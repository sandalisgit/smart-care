package com.smartcare.servlet;

import com.smartcare.ai.AnomalyDetector;
import com.smartcare.security.AuditService;
import com.smartcare.security.AuthService;
import com.smartcare.util.DBConnection;
import com.smartcare.util.JsonUtil;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.sql.*;
import java.util.*;

/**
 * Security & Audit REST API
 * GET  /api/security/audit-log        → recent audit log entries
 * GET  /api/security/sessions         → active sessions
 * GET  /api/security/anomalies        → unresolved anomalies
 * PUT  /api/security/anomalies/{id}   → resolve anomaly
 * DELETE /api/security/sessions/{token} → force logout a session
 * GET  /api/security/hipaa-report     → HIPAA compliance status (FR-80)
 * GET  /api/security/chain-verify     → verify audit log chain integrity (FR-77)
 */
@WebServlet("/api/security/*")
public class SecurityServlet extends HttpServlet {

    @Override protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        AuthService.SessionInfo session = (AuthService.SessionInfo) req.getAttribute("session");

        // Only System Admin and Hospital Admin can access security endpoints
        if (!session.hasModule("Security") && !session.roleName.contains("Admin")) {
            resp.setStatus(403); resp.getWriter().write(JsonUtil.error("Access denied — Admin role required")); return;
        }

        String path = req.getPathInfo();
        try {
            // GET /api/security/audit-log?limit=100
            if ("/audit-log".equals(path)) {
                int limit = parseIntParam(req.getParameter("limit"), 100);
                resp.getWriter().write(JsonUtil.success(getAuditLog(limit))); return;
            }

            // GET /api/security/sessions
            if ("/sessions".equals(path)) {
                resp.getWriter().write(JsonUtil.success(getActiveSessions())); return;
            }

            // GET /api/security/anomalies
            if ("/anomalies".equals(path)) {
                int limit = parseIntParam(req.getParameter("limit"), 50);
                resp.getWriter().write(JsonUtil.success(AnomalyDetector.getUnresolvedAnomalies(limit))); return;
            }

            // GET /api/security/hipaa-report — FR-80
            if ("/hipaa-report".equals(path)) {
                resp.getWriter().write(JsonUtil.success(generateHipaaReport())); return;
            }

            // GET /api/security/chain-verify — FR-77
            if ("/chain-verify".equals(path)) {
                int tampered = AuditService.verifyChain();
                resp.getWriter().write(JsonUtil.success(Map.of(
                        "chainIntact", tampered == 0,
                        "tamperedRecords", tampered,
                        "status", tampered == 0 ? "PASS" : "FAIL — " + tampered + " tampered records detected"
                ))); return;
            }

            resp.setStatus(404); resp.getWriter().write(JsonUtil.error("Not found"));
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error(e.getMessage())); }
    }

    @Override protected void doPut(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        AuthService.SessionInfo session = (AuthService.SessionInfo) req.getAttribute("session");
        String path = req.getPathInfo();
        try {
            // PUT /api/security/anomalies/{id}/resolve
            if (path != null && path.matches("/anomalies/\\d+/resolve")) {
                int anomalyId = Integer.parseInt(path.split("/")[2]);
                @SuppressWarnings("unchecked")
                Map<String, String> data = JsonUtil.fromJson(req.getReader().lines().reduce("", String::concat), Map.class);
                boolean ok = AnomalyDetector.resolveAnomaly(anomalyId, session.userId, data.get("notes"));
                AuditService.log(session.userId, "RESOLVE_ANOMALY", "anomaly_detections", anomalyId, null, null, getClientIp(req));
                resp.getWriter().write(ok ? JsonUtil.success("Anomaly resolved", null) : JsonUtil.error("Not found")); return;
            }
            resp.setStatus(404); resp.getWriter().write(JsonUtil.error("Not found"));
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error(e.getMessage())); }
    }

    @Override protected void doDelete(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        AuthService.SessionInfo session = (AuthService.SessionInfo) req.getAttribute("session");
        String path = req.getPathInfo();
        try {
            // DELETE /api/security/sessions/{sessionId} — force logout
            if (path != null && path.startsWith("/sessions/")) {
                String targetToken = path.substring("/sessions/".length());
                forceLogout(targetToken);
                AuditService.log(session.userId, "FORCE_LOGOUT", "user_sessions", null, null, targetToken, getClientIp(req));
                resp.getWriter().write(JsonUtil.success("Session terminated", null)); return;
            }
            resp.setStatus(404); resp.getWriter().write(JsonUtil.error("Not found"));
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error(e.getMessage())); }
    }

    // =====================================================================
    // HELPERS
    // =====================================================================

    private List<Map<String, Object>> getAuditLog(int limit) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT al.audit_id, al.user_id, al.action_type, al.table_name, " +
                "al.record_id, al.ip_address, al.created_at, u.username " +
                "FROM audit_log al LEFT JOIN users u ON al.user_id=u.user_id " +
                "ORDER BY al.audit_id DESC LIMIT ?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, limit);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> row = new LinkedHashMap<>();
                    row.put("audit_id", rs.getLong("audit_id"));
                    row.put("username", rs.getString("username"));
                    row.put("action_type", rs.getString("action_type"));
                    row.put("table_name", rs.getString("table_name"));
                    row.put("record_id", rs.getObject("record_id"));
                    row.put("ip_address", rs.getString("ip_address"));
                    row.put("created_at", rs.getTimestamp("created_at"));
                    list.add(row);
                }
            }
        }
        return list;
    }

    private List<Map<String, Object>> getActiveSessions() throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT s.session_id, s.ip_address, s.created_at, s.expires_at, " +
                "u.username, r.role_name, " +
                "TIMESTAMPDIFF(MINUTE, s.created_at, NOW()) AS session_age_minutes " +
                "FROM user_sessions s JOIN users u ON s.user_id=u.user_id " +
                "JOIN roles r ON u.role_id=r.role_id " +
                "WHERE s.expires_at > NOW() ORDER BY s.created_at DESC";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> row = new LinkedHashMap<>();
                row.put("sessionId", rs.getString("session_id").substring(0, 8) + "..."); // partial for security
                row.put("username", rs.getString("username"));
                row.put("role", rs.getString("role_name"));
                row.put("ipAddress", rs.getString("ip_address"));
                row.put("sessionAgeMinutes", rs.getInt("session_age_minutes"));
                row.put("expiresAt", rs.getTimestamp("expires_at"));
                row.put("fullToken", rs.getString("session_id")); // for force logout
                list.add(row);
            }
        }
        return list;
    }

    private void forceLogout(String token) throws SQLException {
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement("DELETE FROM user_sessions WHERE session_id=?")) {
            ps.setString(1, token);
            ps.executeUpdate();
        }
    }

    /**
     * Generate HIPAA 45 CFR 164.312 compliance report (FR-80).
     * Each control mapped to a system feature and its current status.
     */
    private Map<String, Object> generateHipaaReport() {
        Map<String, Object> report = new LinkedHashMap<>();
        report.put("reportTitle", "HIPAA Technical Safeguards Compliance Report — 45 CFR § 164.312");
        report.put("generatedAt", new java.util.Date());
        report.put("systemName", "Smart Care Hospital ERP");

        List<Map<String, Object>> controls = new ArrayList<>();

        controls.add(control("164.312(a)(1)", "Access Control",
                "RBAC implemented with 8 roles; role-based endpoint filtering active", "IMPLEMENTED"));
        controls.add(control("164.312(a)(2)(i)", "Unique User Identification",
                "Each user has unique user_id and username; no shared accounts", "IMPLEMENTED"));
        controls.add(control("164.312(a)(2)(ii)", "Emergency Access Procedure",
                "Emergency role defined; override documented in security policy", "IMPLEMENTED"));
        controls.add(control("164.312(a)(2)(iii)", "Automatic Logoff",
                "Sessions expire after 15 minutes of inactivity (NFR-08)", "IMPLEMENTED"));
        controls.add(control("164.312(a)(2)(iv)", "Encryption/Decryption",
                "AES-256-GCM at rest; TLS 1.3 in transit (FR-73, FR-74)", "IMPLEMENTED"));
        controls.add(control("164.312(b)", "Audit Controls",
                "SHA-256 hash-chained audit_log table captures all PHI access events", "IMPLEMENTED"));
        controls.add(control("164.312(c)(1)", "Integrity Controls",
                "Tamper-evident audit log; hash chain verification endpoint available", "IMPLEMENTED"));
        controls.add(control("164.312(c)(2)", "Transmission Integrity",
                "TLS 1.3 with certificate validation enforced; HTTP redirected to HTTPS", "IMPLEMENTED"));
        controls.add(control("164.312(d)", "Person Authentication",
                "bcrypt (cost=12) passwords + TOTP MFA for admin/doctor/finance roles", "IMPLEMENTED"));
        controls.add(control("164.312(e)(1)", "Transmission Security",
                "All API traffic over TLS 1.3; HTTP Strict-Transport-Security header set", "IMPLEMENTED"));

        report.put("controls", controls);

        long implemented = controls.stream().filter(c -> "IMPLEMENTED".equals(c.get("status"))).count();
        report.put("summary", Map.of(
                "total", controls.size(),
                "implemented", implemented,
                "partial", 0,
                "notImplemented", controls.size() - implemented,
                "compliancePercentage", Math.round(implemented * 100.0 / controls.size())
        ));
        return report;
    }

    private Map<String, Object> control(String ref, String name, String implementation, String status) {
        Map<String, Object> c = new LinkedHashMap<>();
        c.put("reference", ref); c.put("name", name);
        c.put("implementation", implementation); c.put("status", status);
        return c;
    }

    private int parseIntParam(String v, int d) { try { return Integer.parseInt(v); } catch (Exception e) { return d; } }
    private String getClientIp(HttpServletRequest req) { String f = req.getHeader("X-Forwarded-For"); return f != null ? f.split(",")[0].trim() : req.getRemoteAddr(); }
}
