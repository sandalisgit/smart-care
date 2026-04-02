package com.smartcare.util;

import java.sql.*;
import java.util.logging.Logger;

/**
 * Notification service — queues email and SMS messages via message_queue table.
 * FR-16: 24-hour appointment reminders
 * FR-43: Payment receipt email
 * FR-60: Ward occupancy > 90% alert to ward manager
 * FR-70: Appointment reminder 30 minutes before to clinical staff
 *
 * Real email sending would use JavaMail (jakarta.mail) + SMTP server.
 * For this project, messages are queued in message_queue and a background
 * job (ScheduledExecutorService) processes them.
 */
public class NotificationService {

    private static final Logger log = Logger.getLogger(NotificationService.class.getName());

    /**
     * Queue an appointment reminder (FR-16: 24h before, FR-70: 30min before)
     */
    public static void queueAppointmentReminder(String recipientEmail, String recipientPhone,
                                                  String patientName, String doctorName,
                                                  String date, String time) {
        String subject = "Appointment Reminder — Smart Care";
        String body = "Dear " + patientName + ",\n\n" +
                "This is a reminder that you have an appointment with " + doctorName +
                " on " + date + " at " + time + ".\n\n" +
                "Please arrive 10 minutes early. If you need to reschedule, contact us at least 24 hours in advance.\n\n" +
                "Smart Care Hospital ERP";

        if (recipientEmail != null && !recipientEmail.isEmpty()) {
            queueEmail(recipientEmail, subject, body, "Normal");
        }
        if (recipientPhone != null && !recipientPhone.isEmpty()) {
            queueSMS(recipientPhone, "Smart Care Reminder: Appointment with " + doctorName + " on " + date + " at " + time);
        }
    }

    /**
     * Queue payment receipt email (FR-43)
     */
    public static void queuePaymentReceipt(String recipientEmail, String patientName,
                                             String billNumber, double amount, String paymentMethod) {
        String subject = "Payment Receipt — Smart Care | Bill " + billNumber;
        String body = "Dear " + patientName + ",\n\n" +
                "Payment received successfully.\n\n" +
                "Bill Number: " + billNumber + "\n" +
                "Amount Paid: LKR " + String.format("%.2f", amount) + "\n" +
                "Payment Method: " + paymentMethod + "\n\n" +
                "Thank you for choosing Smart Care.\n\n" +
                "Smart Care Hospital ERP";

        if (recipientEmail != null && !recipientEmail.isEmpty()) {
            queueEmail(recipientEmail, subject, body, "High");
        }
    }

    /**
     * Queue ward occupancy alert (FR-60)
     */
    public static void queueWardOccupancyAlert(int wardManagerUserId, String wardName, double occupancyPct) {
        queueInAppNotification(wardManagerUserId,
                "Ward Occupancy Alert",
                wardName + " is at " + String.format("%.0f", occupancyPct) + "% occupancy — above 90% threshold. Consider preparations.",
                "Warning");
    }

    /**
     * Queue 30-min appointment reminder to doctor (FR-70)
     */
    public static void queueDoctorAppointmentAlert(int doctorUserId, String patientName, String time) {
        queueInAppNotification(doctorUserId,
                "Upcoming Appointment",
                "Appointment with " + patientName + " in 30 minutes at " + time,
                "Info");
    }

    /**
     * Queue no-show high-risk alert when prediction > 65%
     */
    public static void queueNoShowRiskAlert(String recipientPhone, String patientName, String time, double riskScore) {
        if (recipientPhone != null) {
            queueSMS(recipientPhone,
                    "Smart Care: Hi " + patientName + ", your appointment at " + time +
                            " is confirmed. Please confirm attendance. Reply YES to confirm.");
        }
    }

    // =====================================================================
    // CORE QUEUE METHODS
    // =====================================================================

    public static void queueEmail(String recipient, String subject, String body, String priority) {
        queue("Email", recipient, subject, body, priority);
    }

    public static void queueSMS(String recipient, String body) {
        queue("SMS", recipient, null, body, "Normal");
    }

    public static void queueInAppNotification(int userId, String title, String message, String type) {
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?,?,?,?)")) {
            ps.setInt(1, userId);
            ps.setString(2, type);
            ps.setString(3, title);
            ps.setString(4, message);
            ps.executeUpdate();
        } catch (Exception e) {
            log.warning("Failed to queue notification: " + e.getMessage());
        }
    }

    private static void queue(String type, String recipient, String subject, String body, String priority) {
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "INSERT INTO message_queue (recipient_type, recipient, subject, message_body, priority, status) " +
                             "VALUES (?,?,?,?,?,'Pending')")) {
            ps.setString(1, type);
            ps.setString(2, recipient);
            ps.setString(3, subject);
            ps.setString(4, body);
            ps.setString(5, priority);
            ps.executeUpdate();
        } catch (Exception e) {
            log.warning("Failed to queue " + type + " to " + recipient + ": " + e.getMessage());
        }
    }

    /**
     * Background scheduler — call this on app startup.
     * Processes pending messages from message_queue every 60 seconds.
     * In production, connects to SMTP/SMS gateway.
     */
    public static void startBackgroundProcessor() {
        java.util.concurrent.Executors.newSingleThreadScheduledExecutor()
                .scheduleAtFixedRate(NotificationService::processQueue, 60, 60,
                        java.util.concurrent.TimeUnit.SECONDS);
        log.info("Notification background processor started.");
    }

    private static void processQueue() {
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT message_id, recipient_type, recipient, subject, message_body " +
                             "FROM message_queue WHERE status='Pending' AND retry_count < max_retries LIMIT 10");
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                int msgId = rs.getInt("message_id");
                String type = rs.getString("recipient_type");
                String recipient = rs.getString("recipient");
                // In production: send via SMTP/Twilio/Firebase
                // For demo: mark as sent
                markSent(conn, msgId);
                log.info("Processed " + type + " notification to " + recipient);
            }
        } catch (Exception e) {
            log.warning("Queue processing error: " + e.getMessage());
        }
    }

    private static void markSent(Connection conn, int msgId) throws SQLException {
        try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE message_queue SET status='Sent', sent_at=NOW() WHERE message_id=?")) {
            ps.setInt(1, msgId);
            ps.executeUpdate();
        }
    }
}
