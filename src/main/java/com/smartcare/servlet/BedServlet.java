package com.smartcare.servlet;

import com.smartcare.dao.BedDAO;
import com.smartcare.security.AuditService;
import com.smartcare.security.AuthService;
import com.smartcare.util.JsonUtil;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.util.*;

/** Bed & Ward Management REST API */
@WebServlet("/api/beds/*")
public class BedServlet extends HttpServlet {
    private final BedDAO bedDAO = new BedDAO();

    @Override protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        String path = req.getPathInfo();
        try {
            if ("/wards".equals(path))      { resp.getWriter().write(JsonUtil.success(bedDAO.getWardOverview())); return; }
            if ("/available".equals(path))  { resp.getWriter().write(JsonUtil.success(bedDAO.getAvailableBeds())); return; }
            if ("/admissions".equals(path)) { resp.getWriter().write(JsonUtil.success(bedDAO.getCurrentAdmissions())); return; }
            if (path != null && path.startsWith("/map/")) {
                int wardId = Integer.parseInt(path.substring("/map/".length()));
                resp.getWriter().write(JsonUtil.success(bedDAO.getBedMap(wardId))); return;
            }
            resp.setStatus(404); resp.getWriter().write(JsonUtil.error("Not found"));
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error(e.getMessage())); }
    }

    @Override protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        AuthService.SessionInfo session = (AuthService.SessionInfo) req.getAttribute("session");
        String path = req.getPathInfo();
        String body = req.getReader().lines().reduce("", String::concat);
        try {
            @SuppressWarnings("unchecked") Map<String, Object> data = JsonUtil.fromJson(body, Map.class);
            // POST /api/beds/admit
            if ("/admit".equals(path)) {
                int admId = bedDAO.admitPatient(
                        ((Number) data.get("patientId")).intValue(),
                        ((Number) data.get("bedId")).intValue(),
                        ((Number) data.get("doctorId")).intValue(),
                        (String) data.get("admissionType"),
                        (String) data.get("primaryDiagnosis"),
                        (String) data.get("notes"), session.userId);
                AuditService.log(session.userId, "ADMIT_PATIENT", "admissions", admId, null, body, getClientIp(req));
                resp.setStatus(201); resp.getWriter().write(JsonUtil.success("Patient admitted", Map.of("admissionId", admId))); return;
            }
            resp.setStatus(404); resp.getWriter().write(JsonUtil.error("Not found"));
        } catch (Exception e) {
            if (e.getMessage() != null && e.getMessage().contains("BED_OCCUPIED")) {
                resp.setStatus(409); resp.getWriter().write(JsonUtil.error("Bed is already occupied", "BED_OCCUPIED"));
            } else { resp.setStatus(500); resp.getWriter().write(JsonUtil.error(e.getMessage())); }
        }
    }

    @Override protected void doPut(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        AuthService.SessionInfo session = (AuthService.SessionInfo) req.getAttribute("session");
        String path = req.getPathInfo();
        String body = req.getReader().lines().reduce("", String::concat);
        try {
            @SuppressWarnings("unchecked") Map<String, Object> data = JsonUtil.fromJson(body, Map.class);
            // PUT /api/beds/discharge/{admissionId}
            if (path != null && path.startsWith("/discharge/")) {
                int admissionId = Integer.parseInt(path.substring("/discharge/".length()));
                boolean ok = bedDAO.dischargePatient(admissionId, (String) data.get("dischargeSummary"), session.userId);
                AuditService.log(session.userId, "DISCHARGE_PATIENT", "admissions", admissionId, null, null, getClientIp(req));
                resp.getWriter().write(ok ? JsonUtil.success("Patient discharged", null) : JsonUtil.error("Admission not found")); return;
            }
            // PUT /api/beds/sanitize/{bedId}
            if (path != null && path.startsWith("/sanitize/")) {
                int bedId = Integer.parseInt(path.substring("/sanitize/".length()));
                bedDAO.markBedSanitized(bedId);
                resp.getWriter().write(JsonUtil.success("Bed marked as sanitized", null)); return;
            }
            resp.setStatus(404); resp.getWriter().write(JsonUtil.error("Not found"));
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error(e.getMessage())); }
    }

    private String getClientIp(HttpServletRequest req) { String f = req.getHeader("X-Forwarded-For"); return f != null ? f.split(",")[0].trim() : req.getRemoteAddr(); }
}
