package com.smartcare.dao;

import com.smartcare.util.DBConnection;
import java.sql.*;
import java.sql.Date;
import java.util.*;

/**
 * DAO for Appointment & Scheduling module.
 * FR-11: Book appointments
 * FR-13: Prevent double-booking (conflict detection)
 * FR-14: Reschedule with notification
 * FR-15: Cancel appointments
 * FR-19: Daily queue per doctor
 */
public class AppointmentDAO {

    // =====================================================================
    // AVAILABILITY CHECK (FR-13: prevent double-booking)
    // =====================================================================

    /**
     * Get available time slots for a doctor on a specific date.
     * Returns list of time strings like ["09:00", "09:30", "10:00" ...]
     * excluding already-booked slots.
     */
    public List<String> getAvailableSlots(int doctorId, Date date) throws SQLException {
        List<String> allSlots = new ArrayList<>();
        List<String> booked = new ArrayList<>();

        // Step 1: Get doctor's working hours for this day of week
        String dayName = date.toLocalDate().getDayOfWeek()
                .getDisplayName(java.time.format.TextStyle.FULL, java.util.Locale.ENGLISH);

        String scheduleSql = "SELECT start_time, end_time FROM doctor_schedule " +
                "WHERE doctor_id=? AND day_of_week=? AND is_active=TRUE";

        Time startTime = null, endTime = null;
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(scheduleSql)) {
            ps.setInt(1, doctorId);
            ps.setString(2, dayName);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    startTime = rs.getTime("start_time");
                    endTime = rs.getTime("end_time");
                }
            }
        }

        if (startTime == null) return allSlots; // Doctor not working this day

        // Step 2: Generate 30-minute slots between start and end
        java.time.LocalTime slot = startTime.toLocalTime();
        java.time.LocalTime end = endTime.toLocalTime();
        while (slot.isBefore(end)) {
            allSlots.add(slot.toString().substring(0, 5)); // "HH:mm"
            slot = slot.plusMinutes(30);
        }

        // Step 3: Get already-booked times for this doctor+date
        String bookedSql = "SELECT appointment_time FROM appointments " +
                "WHERE doctor_id=? AND appointment_date=? AND status NOT IN ('Cancelled','No Show')";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(bookedSql)) {
            ps.setInt(1, doctorId);
            ps.setDate(2, date);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) booked.add(rs.getTime(1).toString().substring(0, 5));
            }
        }

        // Step 4: Remove booked slots from available
        allSlots.removeAll(booked);
        return allSlots;
    }

    /**
     * Hard conflict check before booking — returns true if slot is free.
     * FR-13: Strict double-booking prevention.
     */
    public boolean isSlotAvailable(int doctorId, Date date, Time time) throws SQLException {
        String sql = "SELECT COUNT(*) FROM appointments WHERE doctor_id=? AND appointment_date=? " +
                "AND appointment_time=? AND status NOT IN ('Cancelled','No Show')";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, doctorId);
            ps.setDate(2, date);
            ps.setTime(3, time);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) == 0;
            }
        }
    }

    // =====================================================================
    // CREATE
    // =====================================================================

    public int create(int patientId, int doctorId, Date date, Time time,
                      String type, String reason, int createdByUserId) throws SQLException {

        // Double-check conflict (defense in depth)
        if (!isSlotAvailable(doctorId, date, time)) {
            throw new SQLException("SLOT_CONFLICT: Doctor is already booked at this time");
        }

        String sql = "INSERT INTO appointments (patient_id, doctor_id, appointment_date, " +
                "appointment_time, appointment_type, status, reason, consultation_fee) " +
                "SELECT ?,?,?,?,?,'Scheduled',?, consultation_fee FROM doctors WHERE doctor_id=?";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ps.setInt(1, patientId);
            ps.setInt(2, doctorId);
            ps.setDate(3, date);
            ps.setTime(4, time);
            ps.setString(5, type);
            ps.setString(6, reason);
            ps.setInt(7, doctorId);
            ps.executeUpdate();
            try (ResultSet keys = ps.getGeneratedKeys()) {
                if (keys.next()) return keys.getInt(1);
            }
        }
        throw new SQLException("Appointment creation failed");
    }

    // =====================================================================
    // READ
    // =====================================================================

    /** Full appointment details with patient + doctor names — for calendar/list views */
    public List<Map<String, Object>> getCalendar(int doctorId, int year, int month) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT a.appointment_id, a.appointment_date, a.appointment_time, " +
                "a.appointment_type, a.status, a.reason, a.consultation_fee, " +
                "CONCAT(p.first_name,' ',p.last_name) AS patient_name, " +
                "p.phone AS patient_phone, p.patient_code, p.blood_group, " +
                "CONCAT(e.first_name,' ',e.last_name) AS doctor_name, " +
                "d.specialization " +
                "FROM appointments a " +
                "JOIN patients p ON a.patient_id = p.patient_id " +
                "JOIN doctors d ON a.doctor_id = d.doctor_id " +
                "JOIN employees e ON d.employee_id = e.employee_id " +
                "WHERE a.doctor_id=? AND YEAR(a.appointment_date)=? AND MONTH(a.appointment_date)=? " +
                "ORDER BY a.appointment_date, a.appointment_time";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, doctorId);
            ps.setInt(2, year);
            ps.setInt(3, month);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(rsToMap(rs));
            }
        }
        return list;
    }

    /** Today's appointment queue for a doctor — sorted by time (FR-19) */
    public List<Map<String, Object>> getTodayQueue(int doctorId) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT a.appointment_id, a.appointment_time, a.appointment_type, a.status, a.reason, " +
                "CONCAT(p.first_name,' ',p.last_name) AS patient_name, p.patient_code, " +
                "p.phone, p.allergies, p.blood_group, a.consultation_fee " +
                "FROM appointments a " +
                "JOIN patients p ON a.patient_id = p.patient_id " +
                "WHERE a.doctor_id=? AND a.appointment_date=CURDATE() " +
                "ORDER BY a.appointment_time";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, doctorId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(rsToMap(rs));
            }
        }
        return list;
    }

    /** All appointments for a patient — for patient profile */
    public List<Map<String, Object>> getByPatient(int patientId, int limit) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT a.appointment_id, a.appointment_date, a.appointment_time, " +
                "a.appointment_type, a.status, a.reason, " +
                "CONCAT(e.first_name,' ',e.last_name) AS doctor_name, d.specialization " +
                "FROM appointments a " +
                "JOIN doctors d ON a.doctor_id = d.doctor_id " +
                "JOIN employees e ON d.employee_id = e.employee_id " +
                "WHERE a.patient_id=? ORDER BY a.appointment_date DESC LIMIT ?";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, patientId);
            ps.setInt(2, limit);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(rsToMap(rs));
            }
        }
        return list;
    }

    /** Get appointments due for reminders tomorrow (FR-16) */
    public List<Map<String, Object>> getTomorrowAppointments() throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT a.appointment_id, a.appointment_date, a.appointment_time, " +
                "a.appointment_type, p.email, p.phone, " +
                "CONCAT(p.first_name,' ',p.last_name) AS patient_name, " +
                "CONCAT(e.first_name,' ',e.last_name) AS doctor_name, d.specialization " +
                "FROM appointments a " +
                "JOIN patients p ON a.patient_id = p.patient_id " +
                "JOIN doctors d ON a.doctor_id = d.doctor_id " +
                "JOIN employees e ON d.employee_id = e.employee_id " +
                "WHERE a.appointment_date = CURDATE() + INTERVAL 1 DAY " +
                "AND a.status IN ('Scheduled','Confirmed')";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) list.add(rsToMap(rs));
        }
        return list;
    }

    // =====================================================================
    // UPDATE
    // =====================================================================

    public boolean updateStatus(int appointmentId, String status) throws SQLException {
        String sql = "UPDATE appointments SET status=? WHERE appointment_id=?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, status);
            ps.setInt(2, appointmentId);
            return ps.executeUpdate() > 0;
        }
    }

    public boolean reschedule(int appointmentId, Date newDate, Time newTime, int doctorId) throws SQLException {
        if (!isSlotAvailable(doctorId, newDate, newTime)) {
            throw new SQLException("SLOT_CONFLICT: New slot is already booked");
        }
        String sql = "UPDATE appointments SET appointment_date=?, appointment_time=?, status='Scheduled' " +
                "WHERE appointment_id=?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setDate(1, newDate);
            ps.setTime(2, newTime);
            ps.setInt(3, appointmentId);
            return ps.executeUpdate() > 0;
        }
    }

    // =====================================================================
    // STATS
    // =====================================================================

    public Map<String, Integer> getDailyStats() throws SQLException {
        Map<String, Integer> stats = new LinkedHashMap<>();
        String sql = "SELECT status, COUNT(*) cnt FROM appointments WHERE appointment_date=CURDATE() GROUP BY status";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) stats.put(rs.getString("status"), rs.getInt("cnt"));
        }
        return stats;
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
