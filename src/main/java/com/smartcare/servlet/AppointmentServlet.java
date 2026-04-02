package com.smartcare.servlet;

import com.smartcare.ai.NoShowPredictor;
import com.smartcare.dao.AppointmentDAO;
import com.smartcare.dao.StaffDAO;
import com.smartcare.security.AuditService;
import com.smartcare.security.AuthService;
import com.smartcare.util.JsonUtil;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.sql.Date;
import java.sql.Time;
import java.util.*;

/**
 * Appointment & Scheduling REST API.
 * GET  /api/appointments/slots?doctorId=&date=   → available time slots
 * POST /api/appointments                          → book appointment
 * GET  /api/appointments/calendar?doctorId=&year=&month= → calendar view
 * GET  /api/appointments/today?doctorId=          → today's queue
 * PUT  /api/appointments/{id}/status              → update status
 * PUT  /api/appointments/{id}/reschedule          → reschedule
 * GET  /api/appointments/doctors                  → list doctors for booking
 * GET  /api/appointments/stats                    → daily stats for dashboard
 */
@WebServlet("/api/appointments/*")
public class AppointmentServlet extends HttpServlet {

    private final AppointmentDAO apptDAO = new AppointmentDAO();
    private final StaffDAO staffDAO = new StaffDAO();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        String pathInfo = req.getPathInfo();

        try {
            if (pathInfo == null || "/".equals(pathInfo)) {
                // GET /api/appointments (list — filtered by patient or doctor)
                String patientIdStr = req.getParameter("patientId");
                String doctorIdStr = req.getParameter("doctorId");
                if (patientIdStr != null) {
                    int limit = parseIntParam(req.getParameter("limit"), 20);
                    resp.getWriter().write(JsonUtil.success(
                            apptDAO.getByPatient(Integer.parseInt(patientIdStr), limit)));
                } else {
                    resp.getWriter().write(JsonUtil.success(apptDAO.getDailyStats()));
                }
                return;
            }

            // /slots?doctorId=&date=
            if ("/slots".equals(pathInfo)) {
                int doctorId = Integer.parseInt(req.getParameter("doctorId"));
                Date date = Date.valueOf(req.getParameter("date")); // "YYYY-MM-DD"
                List<String> slots = apptDAO.getAvailableSlots(doctorId, date);
                resp.getWriter().write(JsonUtil.success(slots));
                return;
            }

            // /calendar?doctorId=&year=&month=
            if ("/calendar".equals(pathInfo)) {
                int doctorId = Integer.parseInt(req.getParameter("doctorId"));
                int year = Integer.parseInt(req.getParameter("year"));
                int month = Integer.parseInt(req.getParameter("month"));
                resp.getWriter().write(JsonUtil.success(apptDAO.getCalendar(doctorId, year, month)));
                return;
            }

            // /today?doctorId=
            if ("/today".equals(pathInfo)) {
                int doctorId = Integer.parseInt(req.getParameter("doctorId"));
                resp.getWriter().write(JsonUtil.success(apptDAO.getTodayQueue(doctorId)));
                return;
            }

            // /stats
            if ("/stats".equals(pathInfo)) {
                resp.getWriter().write(JsonUtil.success(apptDAO.getDailyStats()));
                return;
            }

            // /doctors?specialization=
            if ("/doctors".equals(pathInfo)) {
                String spec = req.getParameter("specialization");
                resp.getWriter().write(JsonUtil.success(staffDAO.getAllDoctors(spec)));
                return;
            }

            resp.setStatus(404);
            resp.getWriter().write(JsonUtil.error("Endpoint not found"));

        } catch (Exception e) {
            resp.setStatus(500);
            resp.getWriter().write(JsonUtil.error(e.getMessage()));
        }
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        AuthService.SessionInfo session = (AuthService.SessionInfo) req.getAttribute("session");

        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> body = JsonUtil.fromJson(
                    req.getReader().lines().reduce("", String::concat), Map.class);

            int patientId = ((Number) body.get("patientId")).intValue();
            int doctorId = ((Number) body.get("doctorId")).intValue();
            Date date = Date.valueOf((String) body.get("date"));
            Time time = Time.valueOf((String) body.get("time") + ":00");
            String type = (String) body.get("appointmentType");
            String reason = (String) body.get("reason");

            // Book appointment (conflict detection inside DAO — FR-13)
            int appointmentId = apptDAO.create(patientId, doctorId, date, time, type, reason, session.userId);

            // Run AI no-show prediction (FR-17)
            double noShowScore = NoShowPredictor.predict(patientId, doctorId, date, time, type);
            if (noShowScore >= 0) {
                NoShowPredictor.savePrediction(appointmentId, noShowScore);
            }

            AuditService.log(session.userId, "CREATE_APPOINTMENT", "appointments",
                    appointmentId, null, JsonUtil.toJson(body), getClientIp(req));

            resp.setStatus(201);
            resp.getWriter().write(JsonUtil.success("Appointment booked", Map.of(
                    "appointmentId", appointmentId,
                    "noShowRisk", noShowScore >= 0 ? Math.round(noShowScore * 100) + "%" : "N/A",
                    "highRisk", noShowScore > 0.65
            )));

        } catch (Exception e) {
            // Check for slot conflict
            if (e.getMessage() != null && e.getMessage().contains("SLOT_CONFLICT")) {
                resp.setStatus(409);
                resp.getWriter().write(JsonUtil.error("This time slot is already booked. Please select another time.", "SLOT_CONFLICT"));
            } else {
                resp.setStatus(500);
                resp.getWriter().write(JsonUtil.error("Booking failed: " + e.getMessage()));
            }
        }
    }

    @Override
    protected void doPut(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        AuthService.SessionInfo session = (AuthService.SessionInfo) req.getAttribute("session");
        String pathInfo = req.getPathInfo(); // "/{id}/status" or "/{id}/reschedule"

        try {
            String[] parts = pathInfo.split("/");
            int appointmentId = Integer.parseInt(parts[1]);

            @SuppressWarnings("unchecked")
            Map<String, Object> body = JsonUtil.fromJson(
                    req.getReader().lines().reduce("", String::concat), Map.class);

            if (parts.length >= 3 && "status".equals(parts[2])) {
                String newStatus = (String) body.get("status");
                boolean updated = apptDAO.updateStatus(appointmentId, newStatus);

                if (updated) {
                    AuditService.log(session.userId, "UPDATE_APPOINTMENT_STATUS", "appointments",
                            appointmentId, null, newStatus, getClientIp(req));
                    resp.getWriter().write(JsonUtil.success("Status updated to " + newStatus, null));
                } else {
                    resp.setStatus(404);
                    resp.getWriter().write(JsonUtil.error("Appointment not found"));
                }
                return;
            }

            if (parts.length >= 3 && "reschedule".equals(parts[2])) {
                Date newDate = Date.valueOf((String) body.get("date"));
                Time newTime = Time.valueOf((String) body.get("time") + ":00");
                int doctorId = ((Number) body.get("doctorId")).intValue();
                apptDAO.reschedule(appointmentId, newDate, newTime, doctorId);
                AuditService.log(session.userId, "RESCHEDULE_APPOINTMENT", "appointments",
                        appointmentId, null, body.toString(), getClientIp(req));
                resp.getWriter().write(JsonUtil.success("Appointment rescheduled", null));
                return;
            }

            resp.setStatus(404);
            resp.getWriter().write(JsonUtil.error("Sub-resource not found"));

        } catch (Exception e) {
            if (e.getMessage() != null && e.getMessage().contains("SLOT_CONFLICT")) {
                resp.setStatus(409);
                resp.getWriter().write(JsonUtil.error("New slot is already booked", "SLOT_CONFLICT"));
            } else {
                resp.setStatus(500);
                resp.getWriter().write(JsonUtil.error(e.getMessage()));
            }
        }
    }

    private int parseIntParam(String val, int def) {
        if (val == null) return def;
        try { return Integer.parseInt(val); } catch (Exception e) { return def; }
    }

    private String getClientIp(HttpServletRequest req) {
        String fwd = req.getHeader("X-Forwarded-For");
        return fwd != null ? fwd.split(",")[0].trim() : req.getRemoteAddr();
    }
}
