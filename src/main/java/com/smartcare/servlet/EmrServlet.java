package com.smartcare.servlet;

import com.smartcare.dao.EmrDAO;
import com.smartcare.security.AuditService;
import com.smartcare.security.AuthService;
import com.smartcare.util.JsonUtil;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.sql.Date;
import java.util.*;

/**
 * EMR REST API
 * POST /api/emr/records          → create medical record + prescription + lab orders
 * GET  /api/emr/records/{patientId} → patient medical history
 * POST /api/emr/prescriptions    → create prescription with items
 * POST /api/emr/drug-check       → check drug interactions (FR-27)
 * POST /api/emr/lab-orders       → create lab order
 * PUT  /api/emr/lab-orders/{id}/results → enter lab results
 * GET  /api/emr/lab-orders/pending → pending lab tests for lab technician
 */
@WebServlet("/api/emr/*")
public class EmrServlet extends HttpServlet {
    private final EmrDAO emrDAO = new EmrDAO();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        AuthService.SessionInfo session = (AuthService.SessionInfo) req.getAttribute("session");
        String path = req.getPathInfo();

        try {
            if (path == null) { resp.setStatus(400); resp.getWriter().write(JsonUtil.error("Path required")); return; }

            // GET /api/emr/records/{patientId}
            if (path.startsWith("/records/")) {
                int patientId = Integer.parseInt(path.substring("/records/".length()));
                int limit = parseIntParam(req.getParameter("limit"), 20);
                var history = emrDAO.getPatientHistory(patientId, limit);
                AuditService.log(session.userId, "VIEW_EMR", "medical_records", patientId, null, null, getClientIp(req));
                resp.getWriter().write(JsonUtil.success(history));
                return;
            }

            // GET /api/emr/lab-orders/pending
            if ("/lab-orders/pending".equals(path)) {
                resp.getWriter().write(JsonUtil.success(emrDAO.getPendingLabTests()));
                return;
            }

            // GET /api/emr/lab-orders/{patientId}
            if (path.startsWith("/lab-orders/patient/")) {
                int patientId = Integer.parseInt(path.substring("/lab-orders/patient/".length()));
                resp.getWriter().write(JsonUtil.success(emrDAO.getPatientLabHistory(patientId)));
                return;
            }

            // GET /api/emr/prescriptions/{id}
            if (path.startsWith("/prescriptions/")) {
                int prescriptionId = Integer.parseInt(path.substring("/prescriptions/".length()));
                resp.getWriter().write(JsonUtil.success(emrDAO.getPrescriptionWithItems(prescriptionId)));
                return;
            }

            resp.setStatus(404); resp.getWriter().write(JsonUtil.error("Not found"));
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error(e.getMessage())); }
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        AuthService.SessionInfo session = (AuthService.SessionInfo) req.getAttribute("session");
        String path = req.getPathInfo();
        String body = req.getReader().lines().reduce("", String::concat);

        try {
            // POST /api/emr/drug-check — FR-27
            if ("/drug-check".equals(path)) {
                @SuppressWarnings("unchecked")
                Map<String, Object> req2 = JsonUtil.fromJson(body, Map.class);
                @SuppressWarnings("unchecked")
                List<String> drugs = (List<String>) req2.get("drugs");
                var interactions = emrDAO.checkDrugInteractions(drugs);
                resp.getWriter().write(JsonUtil.success(Map.of(
                        "interactions", interactions,
                        "hasMajorInteractions", interactions.stream().anyMatch(i -> "Major".equals(i.get("severity")) || "Contraindicated".equals(i.get("severity")))
                )));
                return;
            }

            // POST /api/emr/records
            if ("/records".equals(path)) {
                @SuppressWarnings("unchecked")
                Map<String, Object> data = JsonUtil.fromJson(body, Map.class);
                int patientId = ((Number) data.get("patientId")).intValue();
                int doctorId = ((Number) data.get("doctorId")).intValue();
                Integer apptId = data.get("appointmentId") != null ? ((Number) data.get("appointmentId")).intValue() : null;
                Integer admId = data.get("admissionId") != null ? ((Number) data.get("admissionId")).intValue() : null;
                String followUpStr = (String) data.get("followUpDate");

                int recordId = emrDAO.createRecord(patientId, doctorId, apptId, admId,
                        (String) data.get("chiefComplaint"), (String) data.get("symptoms"),
                        (String) data.get("diagnosis"), (String) data.get("treatmentPlan"),
                        (String) data.get("vitalSigns"), (String) data.get("notes"),
                        followUpStr != null ? Date.valueOf(followUpStr) : null);

                AuditService.log(session.userId, "CREATE_MEDICAL_RECORD", "medical_records", recordId, null, body, getClientIp(req));
                resp.setStatus(201);
                resp.getWriter().write(JsonUtil.success("Medical record created", Map.of("recordId", recordId)));
                return;
            }

            // POST /api/emr/prescriptions
            if ("/prescriptions".equals(path)) {
                @SuppressWarnings("unchecked")
                Map<String, Object> data = JsonUtil.fromJson(body, Map.class);
                int patientId = ((Number) data.get("patientId")).intValue();
                int doctorId = ((Number) data.get("doctorId")).intValue();
                int recordId = ((Number) data.get("recordId")).intValue();
                int validity = data.get("validityDays") != null ? ((Number) data.get("validityDays")).intValue() : 30;

                int prescriptionId = emrDAO.createPrescription(patientId, doctorId, recordId, validity, (String) data.get("notes"));

                @SuppressWarnings("unchecked")
                List<Map<String, Object>> items = (List<Map<String, Object>>) data.get("items");
                if (items != null) {
                    for (Map<String, Object> item : items) {
                        emrDAO.addPrescriptionItem(prescriptionId,
                                (String) item.get("medicineName"), (String) item.get("dosage"),
                                (String) item.get("frequency"), ((Number) item.get("durationDays")).intValue(),
                                ((Number) item.get("quantity")).intValue(), (String) item.get("instructions"));
                    }
                }
                AuditService.log(session.userId, "CREATE_PRESCRIPTION", "prescriptions", prescriptionId, null, body, getClientIp(req));
                resp.setStatus(201);
                resp.getWriter().write(JsonUtil.success("Prescription created", Map.of("prescriptionId", prescriptionId)));
                return;
            }

            // POST /api/emr/lab-orders
            if ("/lab-orders".equals(path)) {
                @SuppressWarnings("unchecked")
                Map<String, Object> data = JsonUtil.fromJson(body, Map.class);
                int testId = emrDAO.createLabOrder(
                        ((Number) data.get("patientId")).intValue(),
                        ((Number) data.get("doctorId")).intValue(),
                        data.get("recordId") != null ? ((Number) data.get("recordId")).intValue() : null,
                        (String) data.get("testName"), (String) data.get("testType"),
                        data.get("cost") != null ? ((Number) data.get("cost")).doubleValue() : 0);
                AuditService.log(session.userId, "CREATE_LAB_ORDER", "lab_tests", testId, null, body, getClientIp(req));
                resp.setStatus(201);
                resp.getWriter().write(JsonUtil.success("Lab order created", Map.of("testId", testId)));
                return;
            }

            resp.setStatus(404); resp.getWriter().write(JsonUtil.error("Not found"));
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error(e.getMessage())); }
    }

    @Override
    protected void doPut(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        AuthService.SessionInfo session = (AuthService.SessionInfo) req.getAttribute("session");
        String path = req.getPathInfo();
        String body = req.getReader().lines().reduce("", String::concat);

        try {
            // PUT /api/emr/lab-orders/{id}/results
            if (path != null && path.matches("/lab-orders/\\d+/results")) {
                int testId = Integer.parseInt(path.split("/")[2]);
                @SuppressWarnings("unchecked")
                Map<String, Object> data = JsonUtil.fromJson(body, Map.class);
                boolean ok = emrDAO.updateLabResult(testId, (String) data.get("result"),
                        (String) data.get("normalRange"), ((Number) data.get("technicianId")).intValue());
                AuditService.log(session.userId, "UPDATE_LAB_RESULT", "lab_tests", testId, null, body, getClientIp(req));
                resp.getWriter().write(ok ? JsonUtil.success("Result updated", null) : JsonUtil.error("Not found"));
                return;
            }
            resp.setStatus(404); resp.getWriter().write(JsonUtil.error("Not found"));
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error(e.getMessage())); }
    }

    private int parseIntParam(String v, int d) { try { return Integer.parseInt(v); } catch (Exception e) { return d; } }
    private String getClientIp(HttpServletRequest req) { String f = req.getHeader("X-Forwarded-For"); return f != null ? f.split(",")[0].trim() : req.getRemoteAddr(); }
}
