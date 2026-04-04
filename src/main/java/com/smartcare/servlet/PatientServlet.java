package com.smartcare.servlet;

import com.smartcare.ai.NoShowPredictor;
import com.smartcare.dao.AppointmentDAO;
import com.smartcare.dao.PatientDAO;
import com.smartcare.model.Patient;
import com.smartcare.security.AuditService;
import com.smartcare.security.AuthService;
import com.smartcare.util.JsonUtil;
import com.smartcare.util.DBConnection;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.sql.Date;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.*;

/**
 * Patient Management REST API.
 * GET    /api/patients               → search (q param) or list recent
 * POST   /api/patients               → register new patient
 * GET    /api/patients/{id}          → get patient profile
 * PUT    /api/patients/{id}          → update patient
 * GET    /api/patients/{id}/history  → appointments + medical records
 * GET    /api/patients/count         → total count for dashboard
 */
@WebServlet("/api/patients/*")
public class PatientServlet extends HttpServlet {

    private final PatientDAO patientDAO = new PatientDAO();
    private final AppointmentDAO appointmentDAO = new AppointmentDAO();

    // =====================================================================
    // GET
    // =====================================================================
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        AuthService.SessionInfo session = (AuthService.SessionInfo) req.getAttribute("session");
        String pathInfo = req.getPathInfo(); // null, "/123", "/123/history", "/count"

        try {
            // GET /api/patients/count
            if ("/count".equals(pathInfo)) {
                resp.getWriter().write(JsonUtil.success(Map.of("count", patientDAO.getTotalCount())));
                return;
            }

            // GET /api/patients?q=search
            if (pathInfo == null || pathInfo.equals("/")) {
                String query = req.getParameter("q");
                int limit = parseIntParam(req.getParameter("limit"), 50);
                List<Patient> patients = (query != null && !query.isBlank())
                        ? patientDAO.search(query, limit)
                        : patientDAO.getRecent(limit);
                AuditService.log(session.userId, "SEARCH_PATIENTS", "patients",
                        null, null, query, getClientIp(req));
                resp.getWriter().write(JsonUtil.success(patients));
                return;
            }

            // Parse ID from path
            String[] parts = pathInfo.split("/");
            int patientId = Integer.parseInt(parts[1]);

            // GET /api/patients/{id}/history
            if (parts.length >= 3 && "history".equals(parts[2])) {
                List<Map<String, Object>> appointments = appointmentDAO.getByPatient(patientId, 20);
                resp.getWriter().write(JsonUtil.success(Map.of("appointments", appointments)));
                AuditService.log(session.userId, "VIEW_PATIENT_HISTORY", "patients",
                        patientId, null, null, getClientIp(req));
                return;
            }

            // GET /api/patients/{id}
            Patient patient = patientDAO.getById(patientId);
            if (patient == null) {
                resp.setStatus(404);
                resp.getWriter().write(JsonUtil.error("Patient not found"));
                return;
            }

            // Build full profile with related data
            Map<String, Object> profile = new LinkedHashMap<>();
            profile.put("patient", patient);
            profile.put("upcomingAppointments", appointmentDAO.getByPatient(patientId, 5));

            AuditService.log(session.userId, "VIEW_PATIENT", "patients",
                    patientId, null, null, getClientIp(req));
            resp.getWriter().write(JsonUtil.success(profile));

        } catch (NumberFormatException e) {
            resp.setStatus(400);
            resp.getWriter().write(JsonUtil.error("Invalid patient ID format"));
        } catch (Exception e) {
            resp.setStatus(500);
            resp.getWriter().write(JsonUtil.error("Server error: " + e.getMessage()));
        }
    }

    // =====================================================================
    // POST — Register new patient
    // =====================================================================
    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        String pathInfo = req.getPathInfo();

        // Public endpoint: POST /api/patients/signup (no staff login required)
        if ("/signup".equals(pathInfo)) {
            handlePublicSignup(req, resp);
            return;
        }

        AuthService.SessionInfo session = (AuthService.SessionInfo) req.getAttribute("session");

        try {
            String body = req.getReader().lines().reduce("", String::concat);
            Patient patient = JsonUtil.fromJson(body, Patient.class);

            // Validation
            if (patient.getFirstName() == null || patient.getFirstName().isBlank()) {
                resp.setStatus(400);
                resp.getWriter().write(JsonUtil.error("First name is required"));
                return;
            }
            if (patient.getPhone() == null || patient.getPhone().isBlank()) {
                resp.setStatus(400);
                resp.getWriter().write(JsonUtil.error("Phone number is required"));
                return;
            }

            int newId = patientDAO.createPatient(patient);
            Patient created = patientDAO.getById(newId);

            AuditService.log(session.userId, "CREATE_PATIENT", "patients",
                    newId, null, JsonUtil.toJson(created), getClientIp(req));

            resp.setStatus(201);
            resp.getWriter().write(JsonUtil.success("Patient registered successfully", Map.of(
                    "patientId", newId,
                    "patientCode", created.getPatientCode()
            )));

        } catch (Exception e) {
            resp.setStatus(500);
            resp.getWriter().write(JsonUtil.error("Registration failed: " + e.getMessage()));
        }
    }

    @SuppressWarnings("unchecked")
    private void handlePublicSignup(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        try {
            String body = req.getReader().lines().reduce("", String::concat);
            Map<String, Object> data = JsonUtil.fromJson(body, Map.class);

            String firstName = str(data.get("firstName"));
            String lastName = str(data.get("lastName"));
            String phone = str(data.get("phone"));
            String username = str(data.get("username"));
            String password = str(data.get("password"));
            String email = str(data.get("email"));
            String nationalId = str(data.get("nationalId"));

            if (isBlank(firstName) || isBlank(lastName) || isBlank(phone)) {
                resp.setStatus(400);
                resp.getWriter().write(JsonUtil.error("First name, last name, and phone are required"));
                return;
            }
            if (isBlank(username) || isBlank(password)) {
                resp.setStatus(400);
                resp.getWriter().write(JsonUtil.error("Username and password are required"));
                return;
            }

            if (!username.matches("^[a-z0-9.]{4,20}$")) {
                resp.setStatus(400);
                resp.getWriter().write(JsonUtil.error("Username must be 4-20 chars: lowercase letters, numbers and dots only."));
                return;
            }
            if (password.length() < 8) {
                resp.setStatus(400);
                resp.getWriter().write(JsonUtil.error("Password must be at least 8 characters."));
                return;
            }

            // Pre-check unique username for patient portal accounts
            try (Connection conn = DBConnection.getConnection();
                 PreparedStatement ps = conn.prepareStatement("SELECT COUNT(*) FROM patient_accounts WHERE username=?")) {
                ps.setString(1, username);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next() && rs.getInt(1) > 0) {
                        resp.setStatus(409);
                        resp.getWriter().write(JsonUtil.error("Username already exists. Please choose another."));
                        return;
                    }
                }
            }

            if (!isBlank(nationalId) && patientDAO.nationalIdExists(nationalId, null)) {
                resp.setStatus(409);
                resp.getWriter().write(JsonUtil.error("NIC/Passport already registered."));
                return;
            }

            Patient patient = new Patient();
            patient.setFirstName(firstName);
            patient.setLastName(lastName);
            patient.setPhone(phone);
            patient.setEmail(email);
            patient.setAddress(str(data.get("address")));
            patient.setGender(str(data.get("gender")));
            patient.setBloodGroup(str(data.get("bloodGroup")));
            patient.setNationalId(nationalId);
            patient.setAllergies(str(data.get("allergies")));
            patient.setChronicConditions(str(data.get("conditions")));

            String dob = str(data.get("dateOfBirth"));
            if (!isBlank(dob)) {
                patient.setDateOfBirth(Date.valueOf(dob));
            }

            String height = str(data.get("height"));
            if (!isBlank(height)) patient.setHeight(Double.parseDouble(height));
            String weight = str(data.get("weight"));
            if (!isBlank(weight)) patient.setWeight(Double.parseDouble(weight));

            int newId = patientDAO.createPatient(patient);

            // Create patient portal account credentials
            try (Connection conn = DBConnection.getConnection();
                 PreparedStatement ps = conn.prepareStatement(
                         "INSERT INTO patient_accounts (patient_id, username, password_hash) VALUES(?,?,?)")) {
                ps.setInt(1, newId);
                ps.setString(2, username);
                ps.setString(3, AuthService.hashPassword(password));
                ps.executeUpdate();
            }

            Patient created = patientDAO.getById(newId);
            resp.setStatus(201);
            resp.getWriter().write(JsonUtil.success("Patient registered successfully", Map.of(
                    "patientId", newId,
                    "patientCode", created.getPatientCode()
            )));
        } catch (IllegalArgumentException e) {
            resp.setStatus(400);
            resp.getWriter().write(JsonUtil.error("Invalid date format. Expected YYYY-MM-DD."));
        } catch (Exception e) {
            resp.setStatus(500);
            resp.getWriter().write(JsonUtil.error("Registration failed: " + e.getMessage()));
        }
    }

    // =====================================================================
    // PUT — Update patient
    // =====================================================================
    @Override
    protected void doPut(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        AuthService.SessionInfo session = (AuthService.SessionInfo) req.getAttribute("session");
        String pathInfo = req.getPathInfo();

        try {
            int patientId = Integer.parseInt(pathInfo.substring(1).split("/")[0]);
            Patient existing = patientDAO.getById(patientId);
            if (existing == null) {
                resp.setStatus(404);
                resp.getWriter().write(JsonUtil.error("Patient not found"));
                return;
            }

            String oldJson = JsonUtil.toJson(existing);
            Patient updated = JsonUtil.fromJson(req.getReader().lines().reduce("", String::concat), Patient.class);
            updated.setPatientId(patientId);

            patientDAO.update(updated);

            AuditService.log(session.userId, "UPDATE_PATIENT", "patients",
                    patientId, oldJson, JsonUtil.toJson(updated), getClientIp(req));

            resp.getWriter().write(JsonUtil.success("Patient updated", patientDAO.getById(patientId)));

        } catch (Exception e) {
            resp.setStatus(500);
            resp.getWriter().write(JsonUtil.error("Update failed: " + e.getMessage()));
        }
    }

    private int parseIntParam(String val, int defaultVal) {
        if (val == null) return defaultVal;
        try { return Integer.parseInt(val); } catch (NumberFormatException e) { return defaultVal; }
    }

    private String getClientIp(HttpServletRequest req) {
        String fwd = req.getHeader("X-Forwarded-For");
        return fwd != null ? fwd.split(",")[0].trim() : req.getRemoteAddr();
    }

    private boolean isBlank(String s) {
        return s == null || s.isBlank();
    }

    private String str(Object o) {
        return o == null ? null : String.valueOf(o).trim();
    }
}
