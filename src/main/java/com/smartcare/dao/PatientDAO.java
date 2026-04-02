package com.smartcare.dao;

import com.smartcare.model.Patient;
import com.smartcare.security.EncryptionService;
import com.smartcare.util.DBConnection;
import java.sql.*;
import java.util.*;

/**
 * Data Access Object for Patient Management module.
 * FR-01: Register with unique patient ID
 * FR-02: Store personal details
 * FR-07: Update contact info
 * FR-08: Search by name, ID, DOB
 * Sensitive fields (allergies, national_id) encrypted with AES-256-GCM (FR-73)
 */
public class PatientDAO {

    // =====================================================================
    // CREATE
    // =====================================================================

    public int createPatient(Patient p) throws SQLException {
        String sql = "INSERT INTO patients (patient_code, first_name, last_name, date_of_birth, " +
                "gender, blood_group, phone, email, emergency_contact_name, emergency_contact_phone, " +
                "address, city, state, postal_code, country, national_id, " +
                "insurance_provider, insurance_policy_number, allergies, chronic_conditions, " +
                "height, weight, status) " +
                "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {

            // Generate unique patient code: PT-2026-000001
            String code = generatePatientCode(conn);
            p.setPatientCode(code);

            ps.setString(1, code);
            ps.setString(2, p.getFirstName());
            ps.setString(3, p.getLastName());
            ps.setDate(4, p.getDateOfBirth());
            ps.setString(5, p.getGender());
            ps.setString(6, p.getBloodGroup());
            ps.setString(7, p.getPhone());
            ps.setString(8, p.getEmail());
            ps.setString(9, p.getEmergencyContactName());
            ps.setString(10, p.getEmergencyContactPhone());
            ps.setString(11, p.getAddress());
            ps.setString(12, p.getCity());
            ps.setString(13, p.getState());
            ps.setString(14, p.getPostalCode());
            ps.setString(15, p.getCountry() != null ? p.getCountry() : "Sri Lanka");
            // Encrypt sensitive PII fields (FR-73)
            ps.setString(16, EncryptionService.encrypt(p.getNationalId()));
            ps.setString(17, p.getInsuranceProvider());
            ps.setString(18, p.getInsurancePolicyNumber());
            ps.setString(19, EncryptionService.encrypt(p.getAllergies()));  // allergies encrypted
            ps.setString(20, p.getChronicConditions());
            if (p.getHeight() != null) ps.setDouble(21, p.getHeight()); else ps.setNull(21, Types.DECIMAL);
            if (p.getWeight() != null) ps.setDouble(22, p.getWeight()); else ps.setNull(22, Types.DECIMAL);
            ps.setString(23, "Active");

            ps.executeUpdate();

            try (ResultSet keys = ps.getGeneratedKeys()) {
                if (keys.next()) return keys.getInt(1);
            }
        }
        throw new SQLException("Patient creation failed — no ID generated");
    }

    // =====================================================================
    // READ
    // =====================================================================

    public Patient getById(int patientId) throws SQLException {
        String sql = "SELECT * FROM patients WHERE patient_id = ?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, patientId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapRow(rs);
            }
        }
        return null;
    }

    public Patient getByCode(String code) throws SQLException {
        String sql = "SELECT * FROM patients WHERE patient_code = ?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, code);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapRow(rs);
            }
        }
        return null;
    }

    /**
     * Search patients by name, phone, patient_code, national_id, or date of birth.
     * FR-08: Staff view search functionality.
     * Uses MySQL FULLTEXT index on first_name, last_name for performance.
     */
    public List<Patient> search(String query, int limit) throws SQLException {
        List<Patient> results = new ArrayList<>();
        String q = "%" + query.trim() + "%";

        String sql = "SELECT * FROM patients WHERE " +
                "(first_name LIKE ? OR last_name LIKE ? OR " +
                "CONCAT(first_name,' ',last_name) LIKE ? OR " +
                "phone LIKE ? OR patient_code LIKE ? OR " +
                "email LIKE ?) " +
                "AND status != 'Deceased' " +
                "ORDER BY created_at DESC LIMIT ?";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, q); ps.setString(2, q); ps.setString(3, q);
            ps.setString(4, q); ps.setString(5, q); ps.setString(6, q);
            ps.setInt(7, limit);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) results.add(mapRow(rs));
            }
        }
        return results;
    }

    /** Recent registrations for dashboard */
    public List<Patient> getRecent(int limit) throws SQLException {
        List<Patient> results = new ArrayList<>();
        String sql = "SELECT * FROM patients ORDER BY created_at DESC LIMIT ?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, limit);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) results.add(mapRow(rs));
            }
        }
        return results;
    }

    public int getTotalCount() throws SQLException {
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement("SELECT COUNT(*) FROM patients WHERE status='Active'");
             ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getInt(1) : 0;
        }
    }

    /** Check if national_id is already registered (for duplicate prevention) */
    public boolean nationalIdExists(String nationalId, Integer excludePatientId) throws SQLException {
        String sql = "SELECT COUNT(*) FROM patients WHERE national_id = ?" +
                (excludePatientId != null ? " AND patient_id != ?" : "");
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            // We store encrypted national_id — encrypt the input for comparison
            ps.setString(1, EncryptionService.encrypt(nationalId));
            if (excludePatientId != null) ps.setInt(2, excludePatientId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        }
    }

    // =====================================================================
    // UPDATE
    // =====================================================================

    public boolean update(Patient p) throws SQLException {
        String sql = "UPDATE patients SET first_name=?, last_name=?, date_of_birth=?, " +
                "gender=?, blood_group=?, phone=?, email=?, " +
                "emergency_contact_name=?, emergency_contact_phone=?, " +
                "address=?, city=?, state=?, postal_code=?, " +
                "insurance_provider=?, insurance_policy_number=?, " +
                "allergies=?, chronic_conditions=?, height=?, weight=?, " +
                "status=?, updated_at=NOW() " +
                "WHERE patient_id=?";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, p.getFirstName());
            ps.setString(2, p.getLastName());
            ps.setDate(3, p.getDateOfBirth());
            ps.setString(4, p.getGender());
            ps.setString(5, p.getBloodGroup());
            ps.setString(6, p.getPhone());
            ps.setString(7, p.getEmail());
            ps.setString(8, p.getEmergencyContactName());
            ps.setString(9, p.getEmergencyContactPhone());
            ps.setString(10, p.getAddress());
            ps.setString(11, p.getCity());
            ps.setString(12, p.getState());
            ps.setString(13, p.getPostalCode());
            ps.setString(14, p.getInsuranceProvider());
            ps.setString(15, p.getInsurancePolicyNumber());
            ps.setString(16, EncryptionService.encrypt(p.getAllergies()));
            ps.setString(17, p.getChronicConditions());
            if (p.getHeight() != null) ps.setDouble(18, p.getHeight()); else ps.setNull(18, Types.DECIMAL);
            if (p.getWeight() != null) ps.setDouble(19, p.getWeight()); else ps.setNull(19, Types.DECIMAL);
            ps.setString(20, p.getStatus());
            ps.setInt(21, p.getPatientId());
            return ps.executeUpdate() > 0;
        }
    }

    // =====================================================================
    // PRIVATE HELPERS
    // =====================================================================

    private String generatePatientCode(Connection conn) throws SQLException {
        String sql = "SELECT COUNT(*) FROM patients";
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            int count = rs.next() ? rs.getInt(1) : 0;
            int year = java.time.Year.now().getValue();
            return String.format("PT-%d-%06d", year, count + 1);
        }
    }

    /** Map a ResultSet row to a Patient object, decrypting sensitive fields */
    private Patient mapRow(ResultSet rs) throws SQLException {
        Patient p = new Patient();
        p.setPatientId(rs.getInt("patient_id"));
        p.setPatientCode(rs.getString("patient_code"));
        p.setFirstName(rs.getString("first_name"));
        p.setLastName(rs.getString("last_name"));
        p.setDateOfBirth(rs.getDate("date_of_birth"));
        p.setGender(rs.getString("gender"));
        p.setBloodGroup(rs.getString("blood_group"));
        p.setPhone(rs.getString("phone"));
        p.setEmail(rs.getString("email"));
        p.setEmergencyContactName(rs.getString("emergency_contact_name"));
        p.setEmergencyContactPhone(rs.getString("emergency_contact_phone"));
        p.setAddress(rs.getString("address"));
        p.setCity(rs.getString("city"));
        p.setInsuranceProvider(rs.getString("insurance_provider"));
        p.setInsurancePolicyNumber(rs.getString("insurance_policy_number"));
        // Decrypt sensitive fields
        p.setNationalId(EncryptionService.decrypt(rs.getString("national_id")));
        p.setAllergies(EncryptionService.decrypt(rs.getString("allergies")));
        p.setChronicConditions(rs.getString("chronic_conditions"));
        p.setHeight(rs.getObject("height") != null ? rs.getDouble("height") : null);
        p.setWeight(rs.getObject("weight") != null ? rs.getDouble("weight") : null);
        p.setRegistrationDate(rs.getTimestamp("created_at"));
        p.setStatus(rs.getString("status"));
        return p;
    }
}
