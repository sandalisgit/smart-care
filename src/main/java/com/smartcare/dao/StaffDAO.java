package com.smartcare.dao;

import com.smartcare.util.DBConnection;
import java.sql.*;
import java.sql.Date;
import java.util.*;

/**
 * Staff & Clinical Portal DAO.
 * FR-61: Staff profiles
 * FR-62: Shift scheduling
 * FR-63: Leave request workflow
 * FR-64: Attendance tracking
 * FR-65: Personalised clinical dashboards
 * FR-66: Patient record access for clinical staff
 * FR-70: Upcoming appointment notifications
 */
public class StaffDAO {

    // =====================================================================
    // EMPLOYEES
    // =====================================================================

    public List<Map<String, Object>> getAllEmployees(String typeFilter, String statusFilter) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        StringBuilder sql = new StringBuilder(
                "SELECT e.employee_id, e.employee_code, CONCAT(e.first_name,' ',e.last_name) AS full_name, " +
                        "e.employee_type, e.job_title, e.phone, e.email, e.status, e.hire_date, " +
                        "d.department_name, r.role_name, " +
                        "CASE WHEN doc.doctor_id IS NOT NULL THEN doc.specialization ELSE NULL END AS specialization " +
                        "FROM employees e " +
                        "LEFT JOIN departments d ON e.department_id = d.department_id " +
                        "LEFT JOIN users u ON e.user_id = u.user_id " +
                        "LEFT JOIN roles r ON u.role_id = r.role_id " +
                        "LEFT JOIN doctors doc ON e.employee_id = doc.employee_id " +
                        "WHERE 1=1 ");

        List<Object> params = new ArrayList<>();
        if (typeFilter != null) { sql.append("AND e.employee_type=? "); params.add(typeFilter); }
        if (statusFilter != null) { sql.append("AND e.status=? "); params.add(statusFilter); }
        sql.append("ORDER BY e.first_name, e.last_name");

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            for (int i = 0; i < params.size(); i++) ps.setObject(i + 1, params.get(i));
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(rsToMap(rs));
            }
        }
        return list;
    }

    public Map<String, Object> getEmployeeProfile(int employeeId) throws SQLException {
        String sql = "SELECT e.*, d.department_name, r.role_name, " +
                "doc.specialization, doc.consultation_fee, doc.available_for_emergency " +
                "FROM employees e " +
                "LEFT JOIN departments d ON e.department_id = d.department_id " +
                "LEFT JOIN users u ON e.user_id = u.user_id " +
                "LEFT JOIN roles r ON u.role_id = r.role_id " +
                "LEFT JOIN doctors doc ON e.employee_id = doc.employee_id " +
                "WHERE e.employee_id=?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rsToMap(rs) : null;
            }
        }
    }

    // =====================================================================
    // DOCTOR SCHEDULE (FR-62)
    // =====================================================================

    public List<Map<String, Object>> getDoctorSchedule(int doctorId) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT schedule_id, day_of_week, start_time, end_time, max_appointments, is_active " +
                "FROM doctor_schedule WHERE doctor_id=? ORDER BY FIELD(day_of_week," +
                "'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, doctorId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(rsToMap(rs));
            }
        }
        return list;
    }

    public void upsertDoctorSchedule(int doctorId, String dayOfWeek, Time startTime,
                                      Time endTime, int maxAppointments) throws SQLException {
        String sql = "INSERT INTO doctor_schedule (doctor_id, day_of_week, start_time, end_time, max_appointments) " +
                "VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE " +
                "start_time=VALUES(start_time), end_time=VALUES(end_time), " +
                "max_appointments=VALUES(max_appointments), is_active=TRUE";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, doctorId);
            ps.setString(2, dayOfWeek);
            ps.setTime(3, startTime);
            ps.setTime(4, endTime);
            ps.setInt(5, maxAppointments);
            ps.executeUpdate();
        }
    }

    // =====================================================================
    // ATTENDANCE (FR-64)
    // =====================================================================

    public boolean checkIn(int employeeId, String ipAddress) throws SQLException {
        // Prevent duplicate check-in for today
        String check = "SELECT COUNT(*) FROM attendance WHERE employee_id=? AND date=CURDATE()";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(check)) {
            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next() && rs.getInt(1) > 0)
                    throw new SQLException("Already checked in today");
            }
        }
        String sql = "INSERT INTO attendance (employee_id, date, check_in_time, status) " +
                "VALUES (?, CURDATE(), NOW(), 'Present')";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            return ps.executeUpdate() > 0;
        }
    }

    public boolean checkOut(int employeeId) throws SQLException {
        String sql = "UPDATE attendance SET check_out_time=NOW() " +
                "WHERE employee_id=? AND date=CURDATE() AND check_out_time IS NULL";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            return ps.executeUpdate() > 0;
        }
    }

    public List<Map<String, Object>> getAttendanceReport(int employeeId, Date fromDate, Date toDate) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT date, check_in_time, check_out_time, status, remarks, " +
                "TIMEDIFF(check_out_time, check_in_time) AS hours_worked " +
                "FROM attendance WHERE employee_id=? AND date BETWEEN ? AND ? ORDER BY date DESC";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            ps.setDate(2, fromDate);
            ps.setDate(3, toDate);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(rsToMap(rs));
            }
        }
        return list;
    }

    // =====================================================================
    // LEAVE MANAGEMENT (FR-63)
    // =====================================================================

    public int submitLeaveRequest(int employeeId, String leaveType,
                                   Date startDate, Date endDate, String reason) throws SQLException {
        long days = (endDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24) + 1;
        String sql = "INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, " +
                "total_days, reason, status) VALUES (?,?,?,?,?,?,'Pending')";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ps.setInt(1, employeeId);
            ps.setString(2, leaveType);
            ps.setDate(3, startDate);
            ps.setDate(4, endDate);
            ps.setLong(5, days);
            ps.setString(6, reason);
            ps.executeUpdate();
            try (ResultSet keys = ps.getGeneratedKeys()) {
                if (keys.next()) return keys.getInt(1);
            }
        }
        throw new SQLException("Leave request creation failed");
    }

    public boolean approveLeave(int leaveId, int approvedByEmployeeId, boolean approved) throws SQLException {
        String status = approved ? "Approved" : "Rejected";
        String sql = "UPDATE leave_requests SET status=?, approved_by=?, approved_at=NOW() WHERE leave_id=?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, status);
            ps.setInt(2, approvedByEmployeeId);
            ps.setInt(3, leaveId);
            return ps.executeUpdate() > 0;
        }
    }

    public List<Map<String, Object>> getPendingLeaveRequests(Integer departmentId) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT lr.leave_id, lr.leave_type, lr.start_date, lr.end_date, " +
                "lr.total_days, lr.reason, lr.status, lr.created_at, " +
                "CONCAT(e.first_name,' ',e.last_name) AS employee_name, " +
                "e.job_title, d.department_name " +
                "FROM leave_requests lr JOIN employees e ON lr.employee_id=e.employee_id " +
                "LEFT JOIN departments d ON e.department_id=d.department_id " +
                "WHERE lr.status='Pending' " +
                (departmentId != null ? "AND e.department_id=? " : "") +
                "ORDER BY lr.created_at ASC";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            if (departmentId != null) ps.setInt(1, departmentId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(rsToMap(rs));
            }
        }
        return list;
    }

    // =====================================================================
    // DOCTOR CLINICAL DASHBOARD (FR-65)
    // =====================================================================

    public Map<String, Object> getDoctorDashboard(int doctorId) throws SQLException {
        Map<String, Object> dashboard = new LinkedHashMap<>();

        // Today's appointments count
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT COUNT(*) FROM appointments WHERE doctor_id=? AND appointment_date=CURDATE()")) {
            ps.setInt(1, doctorId);
            try (ResultSet rs = ps.executeQuery()) {
                dashboard.put("appointments_today", rs.next() ? rs.getInt(1) : 0);
            }
        }

        // Current inpatients
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT COUNT(*) FROM admissions WHERE admitting_doctor_id=? AND status='Admitted'")) {
            ps.setInt(1, doctorId);
            try (ResultSet rs = ps.executeQuery()) {
                dashboard.put("current_inpatients", rs.next() ? rs.getInt(1) : 0);
            }
        }

        // Pending lab results
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT COUNT(*) FROM lab_tests WHERE doctor_id=? AND status='Completed' " +
                             "AND result_date >= CURDATE() - INTERVAL 7 DAY")) {
            ps.setInt(1, doctorId);
            try (ResultSet rs = ps.executeQuery()) {
                dashboard.put("recent_lab_results", rs.next() ? rs.getInt(1) : 0);
            }
        }

        return dashboard;
    }

    // =====================================================================
    // ALL DOCTORS LIST (for appointment booking dropdown)
    // =====================================================================

    public List<Map<String, Object>> getAllDoctors(String specialization) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT d.doctor_id, CONCAT(e.first_name,' ',e.last_name) AS doctor_name, " +
                "d.specialization, d.consultation_fee, d.available_for_emergency, " +
                "d.average_rating, e.phone, e.email " +
                "FROM doctors d JOIN employees e ON d.employee_id=e.employee_id " +
                "WHERE e.status='Active' " +
                (specialization != null ? "AND d.specialization=? " : "") +
                "ORDER BY e.first_name";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            if (specialization != null) ps.setString(1, specialization);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(rsToMap(rs));
            }
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
}
