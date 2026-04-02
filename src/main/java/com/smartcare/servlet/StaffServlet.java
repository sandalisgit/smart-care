package com.smartcare.servlet;

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

/** Staff & Clinical Portal REST API */
@WebServlet("/api/staff/*")
public class StaffServlet extends HttpServlet {
    private final StaffDAO staffDAO = new StaffDAO();

    @Override protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        String path = req.getPathInfo();
        try {
            if ("/employees".equals(path))  { resp.getWriter().write(JsonUtil.success(staffDAO.getAllEmployees(req.getParameter("type"), req.getParameter("status")))); return; }
            if ("/doctors".equals(path))    { resp.getWriter().write(JsonUtil.success(staffDAO.getAllDoctors(req.getParameter("specialization")))); return; }
            if ("/leaves/pending".equals(path)) { resp.getWriter().write(JsonUtil.success(staffDAO.getPendingLeaveRequests(null))); return; }
            if (path != null && path.startsWith("/employees/")) {
                int empId = Integer.parseInt(path.substring("/employees/".length()).split("/")[0]);
                String sub = path.substring("/employees/".length());
                if (sub.contains("/schedule")) { resp.getWriter().write(JsonUtil.success(staffDAO.getDoctorSchedule(empId))); return; }
                if (sub.contains("/dashboard")) { resp.getWriter().write(JsonUtil.success(staffDAO.getDoctorDashboard(empId))); return; }
                if (sub.contains("/attendance")) {
                    Date from = Date.valueOf(req.getParameter("from") != null ? req.getParameter("from") : java.time.LocalDate.now().minusDays(30).toString());
                    Date to = Date.valueOf(req.getParameter("to") != null ? req.getParameter("to") : java.time.LocalDate.now().toString());
                    resp.getWriter().write(JsonUtil.success(staffDAO.getAttendanceReport(empId, from, to))); return;
                }
                resp.getWriter().write(JsonUtil.success(staffDAO.getEmployeeProfile(empId))); return;
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

            // POST /api/staff/attendance/check-in
            if ("/attendance/check-in".equals(path)) {
                int empId = ((Number) data.get("employeeId")).intValue();
                staffDAO.checkIn(empId, getClientIp(req));
                AuditService.log(session.userId, "CHECKIN", "attendance", empId, null, null, getClientIp(req));
                resp.getWriter().write(JsonUtil.success("Checked in", null)); return;
            }

            // POST /api/staff/attendance/check-out
            if ("/attendance/check-out".equals(path)) {
                int empId = ((Number) data.get("employeeId")).intValue();
                staffDAO.checkOut(empId);
                AuditService.log(session.userId, "CHECKOUT", "attendance", empId, null, null, getClientIp(req));
                resp.getWriter().write(JsonUtil.success("Checked out", null)); return;
            }

            // POST /api/staff/leaves — submit leave request
            if ("/leaves".equals(path)) {
                int leaveId = staffDAO.submitLeaveRequest(
                        ((Number) data.get("employeeId")).intValue(), (String) data.get("leaveType"),
                        Date.valueOf((String) data.get("startDate")), Date.valueOf((String) data.get("endDate")),
                        (String) data.get("reason"));
                resp.setStatus(201); resp.getWriter().write(JsonUtil.success("Leave request submitted", Map.of("leaveId", leaveId))); return;
            }

            // POST /api/staff/schedule — upsert doctor schedule
            if ("/schedule".equals(path)) {
                int doctorId = ((Number) data.get("doctorId")).intValue();
                staffDAO.upsertDoctorSchedule(doctorId, (String) data.get("dayOfWeek"),
                        Time.valueOf((String) data.get("startTime") + ":00"),
                        Time.valueOf((String) data.get("endTime") + ":00"),
                        ((Number) data.get("maxAppointments")).intValue());
                resp.getWriter().write(JsonUtil.success("Schedule updated", null)); return;
            }

            resp.setStatus(404); resp.getWriter().write(JsonUtil.error("Not found"));
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error(e.getMessage())); }
    }

    @Override protected void doPut(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        AuthService.SessionInfo session = (AuthService.SessionInfo) req.getAttribute("session");
        String path = req.getPathInfo();
        String body = req.getReader().lines().reduce("", String::concat);
        try {
            @SuppressWarnings("unchecked") Map<String, Object> data = JsonUtil.fromJson(body, Map.class);
            // PUT /api/staff/leaves/{id}/approve
            if (path != null && path.matches("/leaves/\\d+/approve")) {
                int leaveId = Integer.parseInt(path.split("/")[2]);
                boolean approved = Boolean.TRUE.equals(data.get("approved"));
                int approverEmpId = ((Number) data.get("approvedByEmployeeId")).intValue();
                staffDAO.approveLeave(leaveId, approverEmpId, approved);
                AuditService.log(session.userId, approved ? "APPROVE_LEAVE" : "REJECT_LEAVE", "leave_requests", leaveId, null, null, getClientIp(req));
                resp.getWriter().write(JsonUtil.success("Leave " + (approved ? "approved" : "rejected"), null)); return;
            }
            resp.setStatus(404); resp.getWriter().write(JsonUtil.error("Not found"));
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error(e.getMessage())); }
    }

    private String getClientIp(HttpServletRequest req) { String f = req.getHeader("X-Forwarded-For"); return f != null ? f.split(",")[0].trim() : req.getRemoteAddr(); }
}
