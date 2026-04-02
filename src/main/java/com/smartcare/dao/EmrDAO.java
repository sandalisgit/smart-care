package com.smartcare.dao;

import com.smartcare.security.EncryptionService;
import com.smartcare.util.DBConnection;
import java.sql.*;
import java.sql.Date;
import java.util.*;

/**
 * Electronic Medical Records DAO.
 * FR-21: AES-256 encrypted clinical data storage
 * FR-22: Create EMR entries (diagnosis, prescriptions, lab orders)
 * FR-23: Update with full audit trail
 * FR-27: Drug interaction check support
 * FR-29: RBAC-restricted access
 * FR-30: Patient read-only view
 */
public class EmrDAO {

    // =====================================================================
    // MEDICAL RECORDS
    // =====================================================================

    public int createRecord(int patientId, int doctorId, Integer appointmentId,
                             Integer admissionId, String chiefComplaint, String symptoms,
                             String diagnosis, String treatmentPlan, String vitalSignsJson,
                             String notes, Date followUpDate) throws SQLException {

        // Encrypt sensitive clinical data (FR-21)
        String encDiagnosis = EncryptionService.encrypt(diagnosis);
        String encSymptoms = EncryptionService.encrypt(symptoms);
        String encTreatmentPlan = EncryptionService.encrypt(treatmentPlan);

        String sql = "INSERT INTO medical_records (patient_id, doctor_id, appointment_id, " +
                "admission_id, chief_complaint, symptoms, diagnosis, treatment_plan, " +
                "vital_signs, notes, follow_up_date) VALUES (?,?,?,?,?,?,?,?,?,?,?)";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ps.setInt(1, patientId);
            ps.setInt(2, doctorId);
            if (appointmentId != null) ps.setInt(3, appointmentId); else ps.setNull(3, Types.INTEGER);
            if (admissionId != null) ps.setInt(4, admissionId); else ps.setNull(4, Types.INTEGER);
            ps.setString(5, chiefComplaint);
            ps.setString(6, encSymptoms);
            ps.setString(7, encDiagnosis);
            ps.setString(8, encTreatmentPlan);
            ps.setString(9, vitalSignsJson); // JSON: {bp, temp, pulse, o2sat, rr}
            ps.setString(10, notes);
            if (followUpDate != null) ps.setDate(11, followUpDate); else ps.setNull(11, Types.DATE);
            ps.executeUpdate();

            // Mark appointment as Completed if linked
            if (appointmentId != null) {
                try (PreparedStatement upd = conn.prepareStatement(
                        "UPDATE appointments SET status='Completed' WHERE appointment_id=?")) {
                    upd.setInt(1, appointmentId);
                    upd.executeUpdate();
                }
            }

            try (ResultSet keys = ps.getGeneratedKeys()) {
                if (keys.next()) return keys.getInt(1);
            }
        }
        throw new SQLException("Medical record creation failed");
    }

    public List<Map<String, Object>> getPatientHistory(int patientId, int limit) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT mr.record_id, mr.record_date, mr.chief_complaint, " +
                "mr.symptoms, mr.diagnosis, mr.treatment_plan, mr.vital_signs, " +
                "mr.notes, mr.follow_up_date, " +
                "CONCAT(e.first_name,' ',e.last_name) AS doctor_name, " +
                "d.specialization " +
                "FROM medical_records mr " +
                "JOIN doctors d ON mr.doctor_id = d.doctor_id " +
                "JOIN employees e ON d.employee_id = e.employee_id " +
                "WHERE mr.patient_id=? ORDER BY mr.record_date DESC LIMIT ?";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, patientId);
            ps.setInt(2, limit);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> row = rsToMap(rs);
                    // Decrypt sensitive fields before returning
                    row.put("symptoms", EncryptionService.decrypt((String) row.get("symptoms")));
                    row.put("diagnosis", EncryptionService.decrypt((String) row.get("diagnosis")));
                    row.put("treatment_plan", EncryptionService.decrypt((String) row.get("treatment_plan")));
                    list.add(row);
                }
            }
        }
        return list;
    }

    // =====================================================================
    // PRESCRIPTIONS
    // =====================================================================

    public int createPrescription(int patientId, int doctorId, int recordId,
                                   int validityDays, String notes) throws SQLException {
        String sql = "INSERT INTO prescriptions (patient_id, doctor_id, record_id, " +
                "validity_days, notes, status) VALUES (?,?,?,?,?,'Active')";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ps.setInt(1, patientId);
            ps.setInt(2, doctorId);
            ps.setInt(3, recordId);
            ps.setInt(4, validityDays);
            ps.setString(5, notes);
            ps.executeUpdate();
            try (ResultSet keys = ps.getGeneratedKeys()) {
                if (keys.next()) return keys.getInt(1);
            }
        }
        throw new SQLException("Prescription creation failed");
    }

    public void addPrescriptionItem(int prescriptionId, String medicineName, String dosage,
                                     String frequency, int durationDays, int quantity,
                                     String instructions) throws SQLException {
        String sql = "INSERT INTO prescription_items (prescription_id, medicine_name, dosage, " +
                "frequency, duration_days, quantity, instructions) VALUES (?,?,?,?,?,?,?)";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, prescriptionId);
            ps.setString(2, medicineName);
            ps.setString(3, dosage);
            ps.setString(4, frequency);
            ps.setInt(5, durationDays);
            ps.setInt(6, quantity);
            ps.setString(7, instructions);
            ps.executeUpdate();
        }
    }

    public List<Map<String, Object>> getPrescriptionWithItems(int prescriptionId) throws SQLException {
        List<Map<String, Object>> items = new ArrayList<>();
        String sql = "SELECT pi.*, p.prescription_date, p.validity_days, p.notes AS prescription_notes, " +
                "p.status AS prescription_status, " +
                "CONCAT(pat.first_name,' ',pat.last_name) AS patient_name, " +
                "CONCAT(e.first_name,' ',e.last_name) AS doctor_name " +
                "FROM prescription_items pi " +
                "JOIN prescriptions p ON pi.prescription_id = p.prescription_id " +
                "JOIN patients pat ON p.patient_id = pat.patient_id " +
                "JOIN doctors d ON p.doctor_id = d.doctor_id " +
                "JOIN employees e ON d.employee_id = e.employee_id " +
                "WHERE pi.prescription_id=?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, prescriptionId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) items.add(rsToMap(rs));
            }
        }
        return items;
    }

    // =====================================================================
    // DRUG INTERACTION CHECK (FR-27)
    // Uses drug_interactions table populated from DrugBank open data
    // =====================================================================

    /**
     * Check a list of drug names for known interactions.
     * Returns list of interactions grouped by severity.
     * Doctor must acknowledge Major/Contraindicated before saving prescription.
     */
    public List<Map<String, Object>> checkDrugInteractions(List<String> drugNames) throws SQLException {
        List<Map<String, Object>> interactions = new ArrayList<>();
        if (drugNames == null || drugNames.size() < 2) return interactions;

        String sql = "SELECT drug_a, drug_b, severity, description " +
                "FROM drug_interactions " +
                "WHERE (LOWER(drug_a) LIKE LOWER(?) AND LOWER(drug_b) LIKE LOWER(?)) " +
                "   OR (LOWER(drug_a) LIKE LOWER(?) AND LOWER(drug_b) LIKE LOWER(?)) " +
                "ORDER BY FIELD(severity,'Contraindicated','Major','Moderate','Minor')";

        try (Connection conn = DBConnection.getConnection()) {
            // Check every pair combination
            for (int i = 0; i < drugNames.size(); i++) {
                for (int j = i + 1; j < drugNames.size(); j++) {
                    String drugA = "%" + drugNames.get(i) + "%";
                    String drugB = "%" + drugNames.get(j) + "%";

                    try (PreparedStatement ps = conn.prepareStatement(sql)) {
                        ps.setString(1, drugA); ps.setString(2, drugB);
                        ps.setString(3, drugB); ps.setString(4, drugA);
                        try (ResultSet rs = ps.executeQuery()) {
                            while (rs.next()) {
                                Map<String, Object> interaction = rsToMap(rs);
                                interaction.put("drug_pair", drugNames.get(i) + " + " + drugNames.get(j));
                                interactions.add(interaction);
                            }
                        }
                    }
                }
            }
        }
        return interactions;
    }

    // =====================================================================
    // LAB TESTS
    // =====================================================================

    public int createLabOrder(int patientId, int doctorId, Integer recordId,
                               String testName, String testType, double cost) throws SQLException {
        String sql = "INSERT INTO lab_tests (patient_id, doctor_id, record_id, " +
                "test_name, test_type, status, cost) VALUES (?,?,?,?,?,'Ordered',?)";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ps.setInt(1, patientId);
            ps.setInt(2, doctorId);
            if (recordId != null) ps.setInt(3, recordId); else ps.setNull(3, Types.INTEGER);
            ps.setString(4, testName);
            ps.setString(5, testType);
            ps.setDouble(6, cost);
            ps.executeUpdate();
            try (ResultSet keys = ps.getGeneratedKeys()) {
                if (keys.next()) return keys.getInt(1);
            }
        }
        throw new SQLException("Lab order creation failed");
    }

    public boolean updateLabResult(int testId, String result, String normalRange,
                                    int technicianId) throws SQLException {
        String sql = "UPDATE lab_tests SET test_result=?, normal_range=?, " +
                "result_date=NOW(), status='Completed', technician_id=? WHERE test_id=?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, result);
            ps.setString(2, normalRange);
            ps.setInt(3, technicianId);
            ps.setInt(4, testId);
            return ps.executeUpdate() > 0;
        }
    }

    public List<Map<String, Object>> getPatientLabHistory(int patientId) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT lt.test_id, lt.test_name, lt.test_type, lt.test_date, " +
                "lt.result_date, lt.test_result, lt.normal_range, lt.status, lt.cost, " +
                "CONCAT(e.first_name,' ',e.last_name) AS ordered_by " +
                "FROM lab_tests lt JOIN doctors d ON lt.doctor_id=d.doctor_id " +
                "JOIN employees e ON d.employee_id=e.employee_id " +
                "WHERE lt.patient_id=? ORDER BY lt.test_date DESC";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, patientId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(rsToMap(rs));
            }
        }
        return list;
    }

    public List<Map<String, Object>> getPendingLabTests() throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT lt.test_id, lt.test_name, lt.test_type, lt.test_date, lt.status, " +
                "CONCAT(p.first_name,' ',p.last_name) AS patient_name, p.patient_code " +
                "FROM lab_tests lt JOIN patients p ON lt.patient_id=p.patient_id " +
                "WHERE lt.status IN ('Ordered','Sample Collected','In Progress') " +
                "ORDER BY lt.test_date ASC";
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

    // FR-24: Upload and storage of medical documents (X-ray, lab results, scans)
    public boolean uploadDocument(int patientId, int staffId, String docType,
                                   String fileName, String filePath, String description) throws SQLException {
        String sql = "INSERT INTO emr_documents (patient_id, uploaded_by, document_type, " +
                     "file_name, file_path, description, upload_date) VALUES (?,?,?,?,?,?,NOW())";
        try (Connection c = DBConnection.getConnection();
             PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setInt(1, patientId); ps.setInt(2, staffId);
            ps.setString(3, docType); ps.setString(4, fileName);
            ps.setString(5, filePath); ps.setString(6, description);
            return ps.executeUpdate() > 0;
        }
    }

    // FR-24: Retrieve all documents for a patient (X-rays, lab results, scans)
    public java.util.List<java.util.Map<String,Object>> getPatientDocuments(int patientId) throws SQLException {
        String sql = "SELECT d.*, s.full_name AS uploaded_by_name FROM emr_documents d " +
                     "LEFT JOIN staff s ON d.uploaded_by = s.id " +
                     "WHERE d.patient_id=? ORDER BY d.upload_date DESC";
        java.util.List<java.util.Map<String,Object>> docs = new java.util.ArrayList<>();
        try (Connection c = DBConnection.getConnection();
             PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setInt(1, patientId);
            try (java.sql.ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    java.util.Map<String,Object> doc = new java.util.LinkedHashMap<>();
                    doc.put("id", rs.getInt("id"));
                    doc.put("documentType", rs.getString("document_type"));
                    doc.put("fileName", rs.getString("file_name"));
                    doc.put("description", rs.getString("description"));
                    doc.put("uploadedBy", rs.getString("uploaded_by_name"));
                    doc.put("uploadDate", rs.getString("upload_date"));
                    docs.add(doc);
                }
            }
        }
        return docs;
    }

}
