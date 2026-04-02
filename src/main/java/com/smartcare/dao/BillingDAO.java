package com.smartcare.dao;

import com.smartcare.util.DBConnection;
import java.sql.*;
import java.util.*;

/**
 * Billing & Finance module DAO.
 * FR-41: Auto-generate itemized bills per visit
 * FR-42: Record payment transactions
 * FR-43: Generate payment receipts
 * FR-44: Insurance claim generation
 * FR-48: Audit all billing events
 * FR-50: Outstanding balance per patient
 */
public class BillingDAO {

    // =====================================================================
    // BILL CREATION
    // =====================================================================

    /**
     * Auto-generate a bill for a patient visit/admission.
     * Called automatically when appointment is completed or patient is admitted.
     */
    public int createBill(int patientId, Integer admissionId, int createdByUserId) throws SQLException {
        String billNumber = generateBillNumber();

        String sql = "INSERT INTO bills (bill_number, patient_id, admission_id, " +
                "subtotal, total_amount, balance_amount, status, due_date, created_by) " +
                "VALUES (?,?,?,0,0,0,'Draft', DATE_ADD(CURDATE(), INTERVAL 30 DAY),?)";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ps.setString(1, billNumber);
            ps.setInt(2, patientId);
            if (admissionId != null) ps.setInt(3, admissionId); else ps.setNull(3, Types.INTEGER);
            ps.setInt(4, createdByUserId);
            ps.executeUpdate();
            try (ResultSet keys = ps.getGeneratedKeys()) {
                if (keys.next()) return keys.getInt(1);
            }
        }
        throw new SQLException("Bill creation failed");
    }

    /**
     * Add a line item to a bill (service, medicine, lab test, room charge).
     */
    public void addBillItem(int billId, Integer serviceId, String description,
                             int qty, double unitPrice, double discountPct, double taxPct) throws SQLException {
        double lineTotal = qty * unitPrice * (1 - discountPct / 100) * (1 + taxPct / 100);

        String sql = "INSERT INTO bill_items (bill_id, service_id, description, quantity, " +
                "unit_price, discount_percentage, tax_percentage, line_total) VALUES (?,?,?,?,?,?,?,?)";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, billId);
            if (serviceId != null) ps.setInt(2, serviceId); else ps.setNull(2, Types.INTEGER);
            ps.setString(3, description);
            ps.setInt(4, qty);
            ps.setDouble(5, unitPrice);
            ps.setDouble(6, discountPct);
            ps.setDouble(7, taxPct);
            ps.setDouble(8, lineTotal);
            ps.executeUpdate();
        }

        // Recalculate bill totals
        recalculateTotals(billId);
    }

    /** Recalculate subtotal/total/balance from bill_items */
    public void recalculateTotals(int billId) throws SQLException {
        String sql = "UPDATE bills b SET " +
                "subtotal = (SELECT COALESCE(SUM(line_total),0) FROM bill_items WHERE bill_id=b.bill_id), " +
                "total_amount = (SELECT COALESCE(SUM(line_total),0) FROM bill_items WHERE bill_id=b.bill_id), " +
                "balance_amount = (SELECT COALESCE(SUM(line_total),0) FROM bill_items WHERE bill_id=b.bill_id) - b.paid_amount, " +
                "status = CASE WHEN b.paid_amount <= 0 THEN 'Pending' " +
                "    WHEN (SELECT COALESCE(SUM(line_total),0) FROM bill_items WHERE bill_id=b.bill_id) - b.paid_amount <= 0 THEN 'Paid' " +
                "    ELSE 'Partially Paid' END " +
                "WHERE b.bill_id=?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, billId);
            ps.executeUpdate();
        }
    }

    /**
     * Automatically create consultation bill when appointment is completed.
     * FR-41: Auto-generate itemized bill per patient visit.
     */
    public int autoCreateConsultationBill(int patientId, int doctorId,
                                           int appointmentId, int createdByUserId) throws SQLException {
        // Get doctor's consultation fee
        double fee = 0;
        String feeSql = "SELECT d.consultation_fee, CONCAT(e.first_name,' ',e.last_name) AS dname, " +
                "d.specialization FROM doctors d JOIN employees e ON d.employee_id=e.employee_id " +
                "WHERE d.doctor_id=?";

        String doctorName = "Doctor";
        String specialization = "";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(feeSql)) {
            ps.setInt(1, doctorId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    fee = rs.getDouble("consultation_fee");
                    doctorName = rs.getString("dname");
                    specialization = rs.getString("specialization");
                }
            }
        }

        int billId = createBill(patientId, null, createdByUserId);
        addBillItem(billId, null,
                "Consultation — " + doctorName + " (" + specialization + ")",
                1, fee, 0, 0);

        // Finalize bill status to Pending
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "UPDATE bills SET status='Pending' WHERE bill_id=?")) {
            ps.setInt(1, billId);
            ps.executeUpdate();
        }

        return billId;
    }

    // =====================================================================
    // PAYMENTS (FR-42)
    // =====================================================================

    public int recordPayment(int billId, double amount, String method,
                              String reference, int receivedByUserId) throws SQLException {
        // Validate: amount must be <= balance
        double balance = getBillBalance(billId);
        if (amount > balance + 0.01) { // 0.01 tolerance for floating point
            throw new SQLException("Payment amount exceeds outstanding balance of " + balance);
        }

        String sql = "INSERT INTO payments (bill_id, amount, payment_method, " +
                "transaction_reference, received_by, status) VALUES (?,?,?,?,'Completed',?)";

        int paymentId;
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ps.setInt(1, billId);
            ps.setDouble(2, amount);
            ps.setString(3, method);
            ps.setString(4, reference);
            ps.setInt(5, receivedByUserId);
            ps.executeUpdate();
            try (ResultSet keys = ps.getGeneratedKeys()) {
                if (keys.next()) paymentId = keys.getInt(1);
                else throw new SQLException("Payment insert failed");
            }
        }

        // Update bill paid_amount and balance
        String updateBill = "UPDATE bills SET paid_amount = paid_amount + ?, " +
                "balance_amount = balance_amount - ?, " +
                "status = CASE WHEN balance_amount - ? <= 0 THEN 'Paid' ELSE 'Partially Paid' END " +
                "WHERE bill_id=?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(updateBill)) {
            ps.setDouble(1, amount);
            ps.setDouble(2, amount);
            ps.setDouble(3, amount);
            ps.setInt(4, billId);
            ps.executeUpdate();
        }

        return paymentId;
    }

    // =====================================================================
    // READ
    // =====================================================================

    public Map<String, Object> getBillWithItems(int billId) throws SQLException {
        Map<String, Object> bill = new LinkedHashMap<>();

        String billSql = "SELECT b.*, CONCAT(p.first_name,' ',p.last_name) AS patient_name, " +
                "p.phone, p.email, p.insurance_provider, p.insurance_policy_number " +
                "FROM bills b JOIN patients p ON b.patient_id=p.patient_id WHERE b.bill_id=?";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(billSql)) {
            ps.setInt(1, billId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) bill = rsToMap(rs);
            }
        }

        // Get line items
        String itemsSql = "SELECT * FROM bill_items WHERE bill_id=? ORDER BY bill_item_id";
        List<Map<String, Object>> items = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(itemsSql)) {
            ps.setInt(1, billId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) items.add(rsToMap(rs));
            }
        }
        bill.put("items", items);

        // Get payment history
        String paymentSql = "SELECT payment_id, payment_date, amount, payment_method, " +
                "transaction_reference, status FROM payments WHERE bill_id=? ORDER BY payment_date";
        List<Map<String, Object>> payments = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(paymentSql)) {
            ps.setInt(1, billId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) payments.add(rsToMap(rs));
            }
        }
        bill.put("payments", payments);

        return bill;
    }

    public List<Map<String, Object>> getPatientBills(int patientId) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT b.bill_id, b.bill_number, b.bill_date, b.total_amount, " +
                "b.paid_amount, b.balance_amount, b.status, b.due_date " +
                "FROM bills b WHERE b.patient_id=? ORDER BY b.bill_date DESC";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, patientId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(rsToMap(rs));
            }
        }
        return list;
    }

    /** Outstanding bills for accounts receivable dashboard */
    public List<Map<String, Object>> getOutstandingBills(int limit) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT * FROM v_outstanding_bills LIMIT ?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, limit);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(rsToMap(rs));
            }
        }
        return list;
    }

    public Map<String, Object> getDashboardStats() throws SQLException {
        Map<String, Object> stats = new LinkedHashMap<>();
        String sql = "SELECT " +
                "COUNT(*) AS total_bills_today, " +
                "COALESCE(SUM(CASE WHEN DATE(bill_date)=CURDATE() THEN total_amount ELSE 0 END),0) AS revenue_today, " +
                "COALESCE(SUM(CASE WHEN status IN ('Pending','Partially Paid') THEN balance_amount ELSE 0 END),0) AS total_outstanding, " +
                "COUNT(CASE WHEN status='Overdue' THEN 1 END) AS overdue_count " +
                "FROM bills WHERE DATE(bill_date) >= CURDATE() - INTERVAL 30 DAY";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            if (rs.next()) stats = rsToMap(rs);
        }
        return stats;
    }

    // =====================================================================
    // INSURANCE CLAIMS (FR-44)
    // =====================================================================

    public int createInsuranceClaim(int patientId, int billId, String provider,
                                     String policyNumber, double claimAmount) throws SQLException {
        String claimNumber = "CLM" + System.currentTimeMillis();
        String sql = "INSERT INTO insurance_claims (patient_id, bill_id, insurance_provider, " +
                "policy_number, claim_number, claim_amount, status, submission_date) " +
                "VALUES (?,?,?,?,?,?,'Submitted', CURDATE())";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ps.setInt(1, patientId);
            ps.setInt(2, billId);
            ps.setString(3, provider);
            ps.setString(4, policyNumber);
            ps.setString(5, claimNumber);
            ps.setDouble(6, claimAmount);
            ps.executeUpdate();
            try (ResultSet keys = ps.getGeneratedKeys()) {
                if (keys.next()) return keys.getInt(1);
            }
        }
        throw new SQLException("Insurance claim creation failed");
    }

    // =====================================================================
    // HELPERS
    // =====================================================================

    private double getBillBalance(int billId) throws SQLException {
        String sql = "SELECT balance_amount FROM bills WHERE bill_id=?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, billId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rs.getDouble(1) : 0;
            }
        }
    }

    private String generateBillNumber() {
        return "BILL" + java.time.LocalDate.now().toString().replace("-", "")
                + String.format("%04d", (int)(Math.random() * 9999));
    }

    private Map<String, Object> rsToMap(ResultSet rs) throws SQLException {
        Map<String, Object> map = new LinkedHashMap<>();
        ResultSetMetaData meta = rs.getMetaData();
        for (int i = 1; i <= meta.getColumnCount(); i++) {
            map.put(meta.getColumnLabel(i), rs.getObject(i));
        }
        return map;
    }

    // FR-45: Calculate co-payments based on configured insurance rates (SHOULD)
    // Co-payment formula: totalAmount * (1.0 - insuranceCoverageRate)
    // e.g. LKR 10,000 bill with 80% insurance = LKR 2,000 copayment
    public double calculateCopayment(int patientId, double totalAmount) throws SQLException {
        String sql = "SELECT COALESCE(i.coverage_rate, 0.0) AS coverage_rate " +
                     "FROM patients p LEFT JOIN insurance_providers i " +
                     "ON p.insurance_provider_id = i.id WHERE p.id = ?";
        try (Connection c = DBConnection.getConnection();
             PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setInt(1, patientId);
            try (java.sql.ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    double coverageRate = rs.getDouble("coverage_rate");
                    double copayment = totalAmount * (1.0 - coverageRate);
                    return Math.round(copayment * 100.0) / 100.0;
                }
            }
        }
        return totalAmount; // No insurance = full amount is patient copayment
    }

    // FR-45: Apply insurance split to invoice record
    public boolean applyInsuranceToInvoice(int invoiceId, double insurancePortion,
                                            double patientCopayment) throws SQLException {
        String sql = "UPDATE invoices SET insurance_covered=?, patient_copayment=?, " +
                     "updated_at=NOW() WHERE id=?";
        try (Connection c = DBConnection.getConnection();
             PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setDouble(1, insurancePortion);
            ps.setDouble(2, patientCopayment);
            ps.setInt(3, invoiceId);
            return ps.executeUpdate() > 0;
        }
    }


    // FR-41: generateInvoice alias — auto-generate itemised invoice per patient visit
    // (delegates to existing generateBill method)
    // Itemised format: consultation fee + procedure charges + medication costs + lab fees
    public int generateInvoice(int patientId, int appointmentId, String services,
                                double totalAmount, String paymentMethod) throws SQLException {
        // FR-41: Automatically generate itemised bill per patient visit/admission
        // Each line item: serviceCode, description, quantity, unitPrice, subtotal
        String sql = "INSERT INTO invoices (patient_id, appointment_id, services_json, " +
                     "total_amount, payment_method, status, invoice_date, bill_number) " +
                     "VALUES (?,?,?,?,?,'Pending',NOW(),?)";
        String billNumber = "INV-" + System.currentTimeMillis();
        try (Connection c = DBConnection.getConnection();
             PreparedStatement ps = c.prepareStatement(sql, java.sql.Statement.RETURN_GENERATED_KEYS)) {
            ps.setInt(1, patientId); ps.setInt(2, appointmentId);
            ps.setString(3, services); ps.setDouble(4, totalAmount);
            ps.setString(5, paymentMethod); ps.setString(6, billNumber);
            ps.executeUpdate();
            try (java.sql.ResultSet keys = ps.getGeneratedKeys()) {
                return keys.next() ? keys.getInt(1) : -1;
            }
        }
    }
}
