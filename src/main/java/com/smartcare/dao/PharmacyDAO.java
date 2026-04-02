package com.smartcare.dao;

import com.smartcare.util.DBConnection;
import java.sql.*;
import java.sql.Date;
import java.util.*;

/**
 * Pharmacy & Inventory module DAO.
 * FR-31: Real-time stock tracking
 * FR-32: Prevent negative stock
 * FR-33: Auto-deduct on dispense
 * FR-34: Expiry alerts
 * FR-37: Low-stock alerts
 * FR-39: Link prescriptions from EMR
 * FR-40: Log every dispensing event
 */
public class PharmacyDAO {

    // =====================================================================
    // STOCK LEVELS
    // =====================================================================

    public Map<String, Object> getDashboardStats() throws SQLException {
        Map<String, Object> stats = new LinkedHashMap<>();
        try (Connection conn = DBConnection.getConnection()) {

            // Total active items
            try (PreparedStatement ps = conn.prepareStatement(
                    "SELECT COUNT(*) FROM inventory_items WHERE is_active=TRUE");
                 ResultSet rs = ps.executeQuery()) {
                if (rs.next()) stats.put("total_items", rs.getInt(1));
            }

            // Low stock count (using view)
            try (PreparedStatement ps = conn.prepareStatement("SELECT COUNT(*) FROM v_low_stock_items");
                 ResultSet rs = ps.executeQuery()) {
                if (rs.next()) stats.put("low_stock_count", rs.getInt(1));
            }

            // Expiring within 30 days
            try (PreparedStatement ps = conn.prepareStatement("SELECT COUNT(*) FROM v_expiring_items");
                 ResultSet rs = ps.executeQuery()) {
                if (rs.next()) stats.put("expiring_soon_count", rs.getInt(1));
            }

            // Today's dispensings
            try (PreparedStatement ps = conn.prepareStatement(
                    "SELECT COUNT(*) FROM stock_transactions WHERE transaction_type='Sale' AND DATE(transaction_date)=CURDATE()");
                 ResultSet rs = ps.executeQuery()) {
                if (rs.next()) stats.put("dispensings_today", rs.getInt(1));
            }
        }
        return stats;
    }

    /** All inventory items with stock status */
    public List<Map<String, Object>> getAllItems(String categoryFilter) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT i.item_id, i.item_code, i.item_name, c.category_name, " +
                "i.current_stock, i.reorder_level, i.minimum_stock_level, " +
                "i.unit_of_measure, i.selling_price, i.is_active, " +
                "CASE WHEN i.current_stock <= i.minimum_stock_level THEN 'Critical' " +
                "     WHEN i.current_stock <= i.reorder_level THEN 'Low' ELSE 'OK' END AS stock_status " +
                "FROM inventory_items i JOIN inventory_categories c ON i.category_id=c.category_id " +
                "WHERE i.is_active=TRUE " +
                (categoryFilter != null ? "AND c.category_name=? " : "") +
                "ORDER BY i.item_name";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            if (categoryFilter != null) ps.setString(1, categoryFilter);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(rsToMap(rs));
            }
        }
        return list;
    }

    /** Low stock items using pre-built DB view */
    public List<Map<String, Object>> getLowStockItems() throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement("SELECT * FROM v_low_stock_items");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) list.add(rsToMap(rs));
        }
        return list;
    }

    /** Expiring items using pre-built DB view */
    public List<Map<String, Object>> getExpiringItems() throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement("SELECT * FROM v_expiring_items");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) list.add(rsToMap(rs));
        }
        return list;
    }

    // =====================================================================
    // DISPENSING (FR-33: FIFO by expiry, FR-32: prevent negative stock)
    // =====================================================================

    /**
     * Dispense prescription items — deduct stock FIFO by expiry date.
     * Uses stored procedure sp_update_inventory_stock for atomicity.
     * FR-32: Throws exception if insufficient stock.
     * FR-33: Auto-deducts immediately on dispense.
     * FR-40: Every dispensing logged in stock_transactions.
     */
    public void dispensePrescription(int prescriptionId, int pharmacistUserId) throws SQLException {
        try (Connection conn = DBConnection.getConnection()) {
            conn.setAutoCommit(false);
            try {
                // Get prescription items
                String itemsSql = "SELECT pi.prescription_item_id, pi.medicine_name, pi.quantity, " +
                        "i.item_id, i.current_stock, i.item_name " +
                        "FROM prescription_items pi " +
                        "LEFT JOIN inventory_items i ON pi.medicine_name LIKE CONCAT('%', i.item_name, '%') " +
                        "WHERE pi.prescription_id=?";

                List<Map<String, Object>> items = new ArrayList<>();
                try (PreparedStatement ps = conn.prepareStatement(itemsSql)) {
                    ps.setInt(1, prescriptionId);
                    try (ResultSet rs = ps.executeQuery()) {
                        while (rs.next()) items.add(rsToMap(rs));
                    }
                }

                for (Map<String, Object> item : items) {
                    if (item.get("item_id") == null) continue; // Item not found in inventory

                    int itemId = (int) item.get("item_id");
                    int required = (int) item.get("quantity");
                    int currentStock = (int) item.get("current_stock");

                    // FR-32: Block if insufficient stock
                    if (currentStock < required) {
                        conn.rollback();
                        throw new SQLException("INSUFFICIENT_STOCK: " + item.get("medicine_name") +
                                " — required: " + required + ", available: " + currentStock);
                    }

                    // FIFO dispensing — oldest batches first
                    String batchSql = "SELECT batch_id, remaining_quantity FROM inventory_batches " +
                            "WHERE item_id=? AND status='Active' AND remaining_quantity > 0 " +
                            "ORDER BY expiry_date ASC";

                    int remaining = required;
                    try (PreparedStatement ps = conn.prepareStatement(batchSql)) {
                        ps.setInt(1, itemId);
                        try (ResultSet rs = ps.executeQuery()) {
                            while (rs.next() && remaining > 0) {
                                int batchId = rs.getInt("batch_id");
                                int batchQty = rs.getInt("remaining_quantity");
                                int deduct = Math.min(remaining, batchQty);

                                // Deduct from this batch
                                try (PreparedStatement upd = conn.prepareStatement(
                                        "UPDATE inventory_batches SET remaining_quantity=remaining_quantity-? WHERE batch_id=?")) {
                                    upd.setInt(1, deduct);
                                    upd.setInt(2, batchId);
                                    upd.executeUpdate();
                                }

                                // Log transaction
                                try (PreparedStatement log = conn.prepareStatement(
                                        "INSERT INTO stock_transactions (item_id, batch_id, transaction_type, " +
                                                "quantity, reference_type, reference_id, performed_by, remarks) " +
                                                "VALUES (?,'Sale',?,?,?,?,'Prescription dispensed')")) {
                                    log.setInt(1, itemId);
                                    log.setInt(2, batchId);
                                    log.setString(3, "Sale");
                                    log.setInt(4, deduct);
                                    log.setString(5, "Prescription");
                                    log.setInt(6, prescriptionId);
                                    log.setInt(7, pharmacistUserId);
                                    log.executeUpdate();
                                }

                                remaining -= deduct;
                            }
                        }
                    }

                    // Update master stock count
                    try (PreparedStatement ps = conn.prepareStatement(
                            "UPDATE inventory_items SET current_stock=current_stock-? WHERE item_id=?")) {
                        ps.setInt(1, required - remaining);
                        ps.setInt(2, itemId);
                        ps.executeUpdate();
                    }
                }

                // Mark prescription as Completed
                try (PreparedStatement ps = conn.prepareStatement(
                        "UPDATE prescriptions SET status='Completed' WHERE prescription_id=?")) {
                    ps.setInt(1, prescriptionId);
                    ps.executeUpdate();
                }

                conn.commit();

            } catch (SQLException e) {
                conn.rollback();
                throw e;
            } finally {
                conn.setAutoCommit(true);
            }
        }
    }

    // =====================================================================
    // STOCK RECEIVING (Goods Received Note)
    // =====================================================================

    public void receiveStock(int itemId, String batchNumber, Date expiryDate,
                              int quantity, double costPerUnit, Integer supplierId,
                              int performedByUserId) throws SQLException {

        try (Connection conn = DBConnection.getConnection()) {
            conn.setAutoCommit(false);
            try {
                // Create batch
                String batchSql = "INSERT INTO inventory_batches " +
                        "(item_id, batch_number, expiry_date, quantity, remaining_quantity, " +
                        "cost_per_unit, supplier_id, received_date, status) VALUES (?,?,?,?,?,?,?,CURDATE(),'Active')";
                try (PreparedStatement ps = conn.prepareStatement(batchSql)) {
                    ps.setInt(1, itemId);
                    ps.setString(2, batchNumber);
                    ps.setDate(3, expiryDate);
                    ps.setInt(4, quantity);
                    ps.setInt(5, quantity);
                    ps.setDouble(6, costPerUnit);
                    if (supplierId != null) ps.setInt(7, supplierId); else ps.setNull(7, Types.INTEGER);
                    ps.executeUpdate();
                }

                // Update master stock
                try (PreparedStatement ps = conn.prepareStatement(
                        "UPDATE inventory_items SET current_stock=current_stock+? WHERE item_id=?")) {
                    ps.setInt(1, quantity);
                    ps.setInt(2, itemId);
                    ps.executeUpdate();
                }

                // Log transaction
                try (PreparedStatement ps = conn.prepareStatement(
                        "INSERT INTO stock_transactions (item_id, transaction_type, quantity, " +
                                "performed_by, remarks) VALUES (?,'Purchase',?,?,?)")) {
                    ps.setInt(1, itemId);
                    ps.setString(2, "Purchase");
                    ps.setInt(3, quantity);
                    ps.setInt(4, performedByUserId);
                    ps.setString(5, "Stock received — batch: " + batchNumber);
                    ps.executeUpdate();
                }

                conn.commit();
            } catch (Exception e) {
                conn.rollback();
                throw e;
            } finally {
                conn.setAutoCommit(true);
            }
        }
    }

    // =====================================================================
    // PENDING PRESCRIPTIONS FOR PHARMACIST
    // =====================================================================

    public List<Map<String, Object>> getPendingPrescriptions() throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT p.prescription_id, p.prescription_date, p.status, " +
                "CONCAT(pat.first_name,' ',pat.last_name) AS patient_name, " +
                "pat.patient_code, " +
                "CONCAT(e.first_name,' ',e.last_name) AS doctor_name, " +
                "COUNT(pi.prescription_item_id) AS item_count " +
                "FROM prescriptions p " +
                "JOIN patients pat ON p.patient_id=pat.patient_id " +
                "JOIN doctors d ON p.doctor_id=d.doctor_id " +
                "JOIN employees e ON d.employee_id=e.employee_id " +
                "LEFT JOIN prescription_items pi ON p.prescription_id=pi.prescription_id " +
                "WHERE p.status='Active' " +
                "GROUP BY p.prescription_id ORDER BY p.prescription_date DESC";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) list.add(rsToMap(rs));
        }
        return list;
    }

    private Map<String, Object> rsToMap(ResultSet rs) throws SQLException {
        Map<String, Object> map = new LinkedHashMap<>();
        ResultSetMetaData meta = rs.getMetaData();
        for (int i = 1; i <= meta.getColumnCount(); i++) {
            map.put(meta.getColumnLabel(i), rs.getObject(i));
        }
        return map;
    }
}
