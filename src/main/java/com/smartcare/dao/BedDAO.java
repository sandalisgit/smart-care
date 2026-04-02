package com.smartcare.dao;

import com.smartcare.util.DBConnection;
import java.sql.*;
import java.util.*;

/**
 * Bed & Ward Management DAO.
 * FR-51: Real-time bed availability
 * FR-52: Admit patient to bed
 * FR-53: Discharge and bed release
 * FR-54: Prevent occupied bed assignment
 * FR-55: Housekeeping status tracking
 * FR-58: Log all bed events
 */
public class BedDAO {

    // =====================================================================
    // WARD OVERVIEW
    // =====================================================================

    public List<Map<String, Object>> getWardOverview() throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT w.ward_id, w.ward_name, w.ward_code, w.ward_type, " +
                "w.total_beds, w.available_beds, " +
                "(w.total_beds - w.available_beds) AS occupied_beds, " +
                "ROUND(((w.total_beds - w.available_beds) / w.total_beds) * 100, 1) AS occupancy_pct, " +
                "d.department_name " +
                "FROM wards w LEFT JOIN departments d ON w.department_id = d.department_id " +
                "WHERE w.is_active = TRUE ORDER BY w.ward_name";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) list.add(rsToMap(rs));
        }
        return list;
    }

    /** Full bed map for a ward — each bed with its status and current patient if occupied */
    public List<Map<String, Object>> getBedMap(int wardId) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT b.bed_id, b.bed_number, b.bed_type, b.is_occupied, " +
                "b.last_sanitized, b.is_operational, " +
                "r.room_number, r.room_type, r.daily_rate, " +
                "CONCAT(p.first_name,' ',p.last_name) AS patient_name, " +
                "p.patient_code, p.blood_group, " +
                "a.admission_id, a.admission_date, a.primary_diagnosis, " +
                "CONCAT(e.first_name,' ',e.last_name) AS admitting_doctor, " +
                "DATEDIFF(NOW(), a.admission_date) AS days_admitted " +
                "FROM beds b " +
                "JOIN rooms r ON b.room_id = r.room_id " +
                "LEFT JOIN patients p ON b.current_patient_id = p.patient_id " +
                "LEFT JOIN admissions a ON a.bed_id = b.bed_id AND a.status = 'Admitted' " +
                "LEFT JOIN doctors d ON a.admitting_doctor_id = d.doctor_id " +
                "LEFT JOIN employees e ON d.employee_id = e.employee_id " +
                "WHERE r.ward_id = ? ORDER BY r.room_number, b.bed_number";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, wardId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(rsToMap(rs));
            }
        }
        return list;
    }

    // =====================================================================
    // ADMIT PATIENT (FR-52, FR-54 — prevent double assignment)
    // =====================================================================

    /**
     * Atomically admit a patient:
     * 1. Verify bed is free (FR-54)
     * 2. INSERT admission record
     * 3. UPDATE beds.is_occupied = TRUE
     * 4. UPDATE rooms.occupied_beds++
     * 5. UPDATE wards.available_beds--
     */
    public int admitPatient(int patientId, int bedId, int doctorId,
                             String admissionType, String primaryDiagnosis,
                             String notes, int performedByUserId) throws SQLException {

        try (Connection conn = DBConnection.getConnection()) {
            conn.setAutoCommit(false);
            try {
                // Step 1: Verify bed is available (FR-54)
                String checkSql = "SELECT b.bed_id, b.is_occupied, b.is_operational, " +
                        "r.room_id, r.ward_id " +
                        "FROM beds b JOIN rooms r ON b.room_id = r.room_id " +
                        "WHERE b.bed_id = ? FOR UPDATE";
                int roomId, wardId;
                try (PreparedStatement ps = conn.prepareStatement(checkSql)) {
                    ps.setInt(1, bedId);
                    try (ResultSet rs = ps.executeQuery()) {
                        if (!rs.next()) throw new SQLException("Bed not found: " + bedId);
                        if (rs.getBoolean("is_occupied"))
                            throw new SQLException("BED_OCCUPIED: Bed " + bedId + " is already occupied");
                        if (!rs.getBoolean("is_operational"))
                            throw new SQLException("BED_NOT_OPERATIONAL: Bed is under maintenance");
                        roomId = rs.getInt("room_id");
                        wardId = rs.getInt("ward_id");
                    }
                }

                // Step 2: Create admission record
                String admSql = "INSERT INTO admissions (patient_id, admission_type, ward_id, room_id, " +
                        "bed_id, admitting_doctor_id, primary_diagnosis, admission_notes, status) " +
                        "VALUES (?,?,?,?,?,?,?,?,'Admitted')";
                int admissionId;
                try (PreparedStatement ps = conn.prepareStatement(admSql, Statement.RETURN_GENERATED_KEYS)) {
                    ps.setInt(1, patientId);
                    ps.setString(2, admissionType);
                    ps.setInt(3, wardId);
                    ps.setInt(4, roomId);
                    ps.setInt(5, bedId);
                    ps.setInt(6, doctorId);
                    ps.setString(7, primaryDiagnosis);
                    ps.setString(8, notes);
                    ps.executeUpdate();
                    try (ResultSet keys = ps.getGeneratedKeys()) {
                        if (keys.next()) admissionId = keys.getInt(1);
                        else throw new SQLException("Admission insert failed");
                    }
                }

                // Step 3: Mark bed as occupied
                try (PreparedStatement ps = conn.prepareStatement(
                        "UPDATE beds SET is_occupied=TRUE, current_patient_id=? WHERE bed_id=?")) {
                    ps.setInt(1, patientId);
                    ps.setInt(2, bedId);
                    ps.executeUpdate();
                }

                // Step 4: Increment room occupied count
                try (PreparedStatement ps = conn.prepareStatement(
                        "UPDATE rooms SET occupied_beds = occupied_beds + 1 WHERE room_id=?")) {
                    ps.setInt(1, roomId);
                    ps.executeUpdate();
                }

                // Step 5: Decrement ward available beds
                try (PreparedStatement ps = conn.prepareStatement(
                        "UPDATE wards SET available_beds = available_beds - 1 WHERE ward_id=?")) {
                    ps.setInt(1, wardId);
                    ps.executeUpdate();
                }

                conn.commit();
                return admissionId;

            } catch (SQLException e) {
                conn.rollback();
                throw e;
            } finally {
                conn.setAutoCommit(true);
            }
        }
    }

    // =====================================================================
    // DISCHARGE PATIENT (FR-53)
    // =====================================================================

    public boolean dischargePatient(int admissionId, String dischargeSummary,
                                     int performedByUserId) throws SQLException {
        try (Connection conn = DBConnection.getConnection()) {
            conn.setAutoCommit(false);
            try {
                // Get admission details
                String getSql = "SELECT bed_id, room_id, ward_id FROM admissions WHERE admission_id=? AND status='Admitted'";
                int bedId, roomId, wardId;
                try (PreparedStatement ps = conn.prepareStatement(getSql)) {
                    ps.setInt(1, admissionId);
                    try (ResultSet rs = ps.executeQuery()) {
                        if (!rs.next()) throw new SQLException("Active admission not found: " + admissionId);
                        bedId = rs.getInt("bed_id");
                        roomId = rs.getInt("room_id");
                        wardId = rs.getInt("ward_id");
                    }
                }

                // Update admission
                try (PreparedStatement ps = conn.prepareStatement(
                        "UPDATE admissions SET discharge_date=NOW(), status='Discharged', " +
                                "discharge_summary=? WHERE admission_id=?")) {
                    ps.setString(1, dischargeSummary);
                    ps.setInt(2, admissionId);
                    ps.executeUpdate();
                }

                // Release bed (mark for sanitization — FR-55)
                try (PreparedStatement ps = conn.prepareStatement(
                        "UPDATE beds SET is_occupied=FALSE, current_patient_id=NULL, " +
                                "last_sanitized=NULL WHERE bed_id=?")) {
                    ps.setInt(1, bedId);
                    ps.executeUpdate();
                }

                // Decrement room occupied count
                try (PreparedStatement ps = conn.prepareStatement(
                        "UPDATE rooms SET occupied_beds = GREATEST(0, occupied_beds - 1) WHERE room_id=?")) {
                    ps.setInt(1, roomId);
                    ps.executeUpdate();
                }

                // Increment ward available beds
                try (PreparedStatement ps = conn.prepareStatement(
                        "UPDATE wards SET available_beds = LEAST(total_beds, available_beds + 1) WHERE ward_id=?")) {
                    ps.setInt(1, wardId);
                    ps.executeUpdate();
                }

                conn.commit();
                return true;

            } catch (SQLException e) {
                conn.rollback();
                throw e;
            } finally {
                conn.setAutoCommit(true);
            }
        }
    }

    // =====================================================================
    // HOUSEKEEPING STATUS (FR-55)
    // =====================================================================

    public boolean markBedSanitized(int bedId) throws SQLException {
        String sql = "UPDATE beds SET last_sanitized=NOW() WHERE bed_id=?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, bedId);
            return ps.executeUpdate() > 0;
        }
    }

    public boolean setBedOperational(int bedId, boolean operational) throws SQLException {
        String sql = "UPDATE beds SET is_operational=? WHERE bed_id=?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setBoolean(1, operational);
            ps.setInt(2, bedId);
            return ps.executeUpdate() > 0;
        }
    }

    // =====================================================================
    // CURRENT ADMISSIONS
    // =====================================================================

    public List<Map<String, Object>> getCurrentAdmissions() throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT * FROM v_current_admissions ORDER BY days_admitted DESC";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) list.add(rsToMap(rs));
        }
        return list;
    }

    public List<Map<String, Object>> getAvailableBeds() throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT b.bed_id, b.bed_number, b.bed_type, " +
                "r.room_number, r.room_type, r.daily_rate, " +
                "w.ward_name, w.ward_type " +
                "FROM beds b JOIN rooms r ON b.room_id=r.room_id JOIN wards w ON r.ward_id=w.ward_id " +
                "WHERE b.is_occupied=FALSE AND b.is_operational=TRUE AND w.is_active=TRUE " +
                "ORDER BY w.ward_name, r.room_number, b.bed_number";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) list.add(rsToMap(rs));
        }
        return list;
    }

    // =====================================================================
    // DAILY SNAPSHOT FOR AI MODEL
    // =====================================================================

    public void saveDailyOccupancySnapshot() throws SQLException {
        String sql = "INSERT INTO bed_occupancy_history (ward_id, record_date, total_beds, occupied_beds) " +
                "SELECT ward_id, CURDATE(), total_beds, (total_beds - available_beds) " +
                "FROM wards WHERE is_active=TRUE " +
                "ON DUPLICATE KEY UPDATE occupied_beds = VALUES(occupied_beds)";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.executeUpdate();
        }
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
