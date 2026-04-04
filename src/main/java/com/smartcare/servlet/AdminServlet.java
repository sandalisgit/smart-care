package com.smartcare.servlet;

import com.smartcare.security.AuthService;
import com.smartcare.util.DBConnection;
import com.smartcare.util.JsonUtil;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.logging.Logger;

/** Admin dashboard API (non-auth logic only; auth enforced by AuthFilter). */
@WebServlet("/api/admin/*")
public class AdminServlet extends HttpServlet {

    private static final Logger log = Logger.getLogger(AdminServlet.class.getName());

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");

        AuthService.SessionInfo session = (AuthService.SessionInfo) req.getAttribute("session");
        if (session == null) {
            resp.setStatus(401);
            resp.getWriter().write(JsonUtil.error("Unauthorized"));
            return;
        }
        if (session.roleName == null || !session.roleName.contains("Admin")) {
            resp.setStatus(403);
            resp.getWriter().write(JsonUtil.error("Access denied - Admin role required"));
            return;
        }

        String path = req.getPathInfo();
        if (!"/dashboard".equals(path)) {
            resp.setStatus(404);
            resp.getWriter().write(JsonUtil.error("Not found"));
            return;
        }

        try {
            resp.getWriter().write(JsonUtil.success(buildDashboard()));
        } catch (Exception e) {
            log.severe("Admin dashboard error: " + e.getMessage());
            resp.setStatus(500);
            resp.getWriter().write(JsonUtil.error("Internal server error"));
        }
    }

    private Map<String, Object> buildDashboard() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("kpi", buildKpi());
        result.put("wards", buildWardOccupancy());
        return result;
    }

    private Map<String, Object> buildKpi() {
        Map<String, Object> kpi = new LinkedHashMap<>();
        kpi.put("patients", queryCount("SELECT COUNT(*) FROM patients WHERE status='Active'"));
        kpi.put("appts", queryCount("SELECT COUNT(*) FROM appointments WHERE DATE(appointment_date)=CURDATE()"));
        kpi.put("beds", queryCount("SELECT COUNT(*) FROM beds WHERE status='Available'"));
        kpi.put("alerts", queryCount("SELECT COUNT(*) FROM anomaly_detections WHERE is_resolved=FALSE"));
        kpi.put("staff", queryCount("SELECT COUNT(DISTINCT employee_id) FROM shifts WHERE shift_date=CURDATE()"));
        kpi.put("revenue", queryRevenue());
        return kpi;
    }

    private List<Map<String, Object>> buildWardOccupancy() {
        List<Map<String, Object>> wards = new ArrayList<>();
        String sql = "SELECT w.ward_name, w.total_beds, " +
                "COUNT(CASE WHEN b.status='Occupied' THEN 1 END) AS occupied " +
                "FROM wards w LEFT JOIN beds b ON w.ward_id=b.ward_id " +
                "GROUP BY w.ward_id, w.ward_name, w.total_beds ORDER BY w.ward_name";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> ward = new LinkedHashMap<>();
                ward.put("name", rs.getString("ward_name"));
                ward.put("total", rs.getInt("total_beds"));
                ward.put("occupied", rs.getInt("occupied"));
                wards.add(ward);
            }
        } catch (Exception e) {
            log.warning("Ward occupancy query failed: " + e.getMessage());
        }
        return wards;
    }

    private int queryCount(String sql) {
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getInt(1) : 0;
        } catch (Exception e) {
            log.warning("Count query failed: " + e.getMessage());
            return 0;
        }
    }

    private String queryRevenue() {
        String sql = "SELECT COALESCE(SUM(paid_amount), 0) FROM bills WHERE DATE(bill_date)=CURDATE()";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                double value = rs.getDouble(1);
                return String.format("%,.0f", value);
            }
        } catch (Exception e) {
            log.warning("Revenue query failed: " + e.getMessage());
        }
        return "0";
    }
}
