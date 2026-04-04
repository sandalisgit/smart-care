package com.smartcare.security;

import com.smartcare.util.DBConnection;
import com.warrenstrange.googleauth.GoogleAuthenticator;
import com.warrenstrange.googleauth.GoogleAuthenticatorKey;
import org.mindrot.jbcrypt.BCrypt;

import java.sql.*;
import java.util.*;
import java.util.logging.Logger;

/**
 * Authentication and session management service.
 * FR-71: RBAC enforcement across all 8 roles.
 * FR-72: TOTP MFA via authenticator app (Google/Microsoft/Authy) for Admin, Doctor, Billing Clerk.
 * FR-73: Patient login via Patient ID + Full Name only - no password, no staff bypass.
 * FR-75: bcrypt cost factor 12 for staff passwords.
 * FR-76: Account lock after 5 failed attempts (30 min).
 * NFR-08: 15-minute sliding session timeout.
 */
public class AuthService {

    private static final Logger log = Logger.getLogger(AuthService.class.getName());
    private static final GoogleAuthenticator gAuth = new GoogleAuthenticator();

    private static final Set<String> MFA_REQUIRED_ROLES =
            Set.of("System Admin", "Hospital Admin", "Doctor", "Billing Clerk");

    // =====================================================================
    // LOGIN RESULT DTO
    // =====================================================================
    public static class LoginResult {
        public boolean success;
        public boolean requiresMfa;        // MFA enrolled, go to verify page
        public boolean requiresMfaSetup;   // MFA role, not yet enrolled, go to setup page
        public String sessionToken;
        public String tempToken;
        public int userId;
        public String username;
        public String roleName;
        public String permissions;
        public String errorMessage;
    }

    // =====================================================================
    // STAFF LOGIN: Step 1 - username + password
    // =====================================================================
    public static LoginResult login(String username, String password, String ipAddress) {
        LoginResult result = new LoginResult();
        try (Connection conn = DBConnection.getConnection()) {
            String sql =
                "SELECT u.user_id, u.username, u.password_hash, u.is_active, " +
                "u.failed_login_attempts, u.account_locked_until, " +
                "r.role_name, r.permissions, " +
                "COALESCE(m.is_enabled, FALSE) AS mfa_enabled, m.totp_secret " +
                "FROM users u " +
                "JOIN roles r ON u.role_id = r.role_id " +
                "LEFT JOIN user_mfa m ON u.user_id = m.user_id " +
                "WHERE u.username = ?";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, username);
                try (ResultSet rs = ps.executeQuery()) {
                    if (!rs.next()) {
                        result.errorMessage = "Invalid credentials.";
                        AuditService.log(0, "LOGIN_FAIL_NOT_FOUND", "users", null, null, username, ipAddress);
                        return result;
                    }
                    int userId = rs.getInt("user_id");
                    String storedHash = rs.getString("password_hash");
                    boolean isActive = rs.getBoolean("is_active");
                    int failedAttempts = rs.getInt("failed_login_attempts");
                    Timestamp locked = rs.getTimestamp("account_locked_until");
                    String roleName = rs.getString("role_name");
                    String permissions = rs.getString("permissions");
                    boolean mfaEnabled = rs.getBoolean("mfa_enabled");
                    String totpSecret = rs.getString("totp_secret");

                    if (!isActive) { result.errorMessage = "Account is deactivated. Contact administrator."; return result; }

                    if (locked != null && locked.after(new Timestamp(System.currentTimeMillis()))) {
                        result.errorMessage = "Account locked until " + locked + ". Too many failed attempts.";
                        AuditService.log(userId, "LOGIN_BLOCKED_LOCKED", "users", userId, null, null, ipAddress);
                        return result;
                    }

                    if (!BCrypt.checkpw(password, storedHash)) {
                        int newAttempts = failedAttempts + 1;
                        if (newAttempts >= 5) {
                            lockAccount(conn, userId);
                            result.errorMessage = "Too many failed attempts. Account locked for 30 minutes.";
                            AuditService.log(userId, "ACCOUNT_LOCKED", "users", userId, null, null, ipAddress);
                        } else {
                            incrementFailedAttempts(conn, userId, newAttempts);
                            result.errorMessage = "Invalid credentials. " + (5 - newAttempts) + " attempt(s) remaining.";
                            AuditService.log(userId, "LOGIN_FAIL_WRONG_PW", "users", userId, null, null, ipAddress);
                        }
                        return result;
                    }
                    resetFailedAttempts(conn, userId);

                    boolean roleRequiresMfa = MFA_REQUIRED_ROLES.contains(roleName);
                    if (roleRequiresMfa) {
                        String tempToken = UUID.randomUUID().toString();
                        storeTempToken(conn, userId, tempToken);
                        result.tempToken = tempToken;
                        result.userId = userId;
                        result.username = username;
                        result.roleName = roleName;
                        if (mfaEnabled && totpSecret != null) {
                            result.requiresMfa = true;      // go to verify
                        } else {
                            result.requiresMfaSetup = true; // go to setup first
                        }
                        return result;
                    }
                    result = createSession(conn, userId, username, roleName, permissions, ipAddress);
                    AuditService.log(userId, "LOGIN_SUCCESS", "users", userId, null, null, ipAddress);
                    return result;
                }
            }
        } catch (Exception e) { log.severe("Login error: " + e.getMessage()); result.errorMessage = "Internal error."; return result; }
    }

    // =====================================================================
    // MFA STEP 2a: First-time setup - enroll + verify first code
    // =====================================================================
    public static LoginResult setupAndVerifyMfa(String tempToken, String totpSecret, int totpCode, String ipAddress) {
        LoginResult result = new LoginResult();
        try (Connection conn = DBConnection.getConnection()) {
            String sql =
                "SELECT t.user_id, u.username, r.role_name, r.permissions " +
                "FROM temp_mfa_tokens t JOIN users u ON t.user_id=u.user_id " +
                "JOIN roles r ON u.role_id=r.role_id WHERE t.token=? AND t.expires_at>NOW()";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, tempToken);
                try (ResultSet rs = ps.executeQuery()) {
                    if (!rs.next()) { result.errorMessage = "Setup session expired. Please log in again."; return result; }
                    int userId = rs.getInt("user_id");
                    String uname = rs.getString("username");
                    String role = rs.getString("role_name");
                    String perms = rs.getString("permissions");
                    if (!gAuth.authorize(totpSecret, totpCode)) {
                        result.errorMessage = "Invalid code. Make sure you scanned the correct QR code.";
                        AuditService.log(userId, "MFA_SETUP_FAIL", "users", userId, null, null, ipAddress);
                        return result;
                    }
                    enrollSecret(conn, userId, totpSecret);
                    deleteTempToken(conn, tempToken);
                    result = createSession(conn, userId, uname, role, perms, ipAddress);
                    AuditService.log(userId, "MFA_SETUP_SUCCESS", "users", userId, null, null, ipAddress);
                    return result;
                }
            }
        } catch (Exception e) { log.severe("MFA setup error: " + e.getMessage()); result.errorMessage = "MFA setup failed."; return result; }
    }

    // =====================================================================
    // MFA STEP 2b: Verify TOTP code for subsequent logins
    // =====================================================================
    public static LoginResult verifyMfa(String tempToken, int totpCode, String ipAddress) {
        LoginResult result = new LoginResult();
        try (Connection conn = DBConnection.getConnection()) {
            String sql =
                "SELECT t.user_id, u.username, r.role_name, r.permissions, m.totp_secret " +
                "FROM temp_mfa_tokens t JOIN users u ON t.user_id=u.user_id " +
                "JOIN roles r ON u.role_id=r.role_id JOIN user_mfa m ON t.user_id=m.user_id " +
                "WHERE t.token=? AND t.expires_at>NOW()";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, tempToken);
                try (ResultSet rs = ps.executeQuery()) {
                    if (!rs.next()) { result.errorMessage = "MFA session expired. Please log in again."; return result; }
                    int userId = rs.getInt("user_id");
                    String uname = rs.getString("username");
                    String role = rs.getString("role_name");
                    String perms = rs.getString("permissions");
                    String secret = rs.getString("totp_secret");
                    if (!gAuth.authorize(secret, totpCode)) {
                        result.errorMessage = "Invalid authenticator code. Please try again.";
                        AuditService.log(userId, "MFA_FAIL", "users", userId, null, null, ipAddress);
                        return result;
                    }
                    deleteTempToken(conn, tempToken);
                    result = createSession(conn, userId, uname, role, perms, ipAddress);
                    AuditService.log(userId, "LOGIN_MFA_SUCCESS", "users", userId, null, null, ipAddress);
                    return result;
                }
            }
        } catch (Exception e) { log.severe("MFA verify error: " + e.getMessage()); result.errorMessage = "MFA verification failed."; return result; }
    }

    // =====================================================================
    // PATIENT LOGIN: Patient ID + Full Name only (FR-73)
    // Staff credentials are rejected - patients have no password.
    // =====================================================================
    public static class PatientLoginResult {
        public boolean success;
        public String sessionToken;
        public int patientId;
        public String patientCode;
        public String firstName;
        public String lastName;
        public String errorMessage;
    }

    public static PatientLoginResult patientLogin(String patientCode, String fullName, String ipAddress) {
        PatientLoginResult result = new PatientLoginResult();
        String normalizedPatientCode = patientCode.toUpperCase().trim();
        if (!(normalizedPatientCode.startsWith("PAT") || normalizedPatientCode.startsWith("PT"))) {
            result.errorMessage = "Invalid Patient ID. Use PAT000001 or PT-2026-000001 format.";
            return result;
        }
        try (Connection conn = DBConnection.getConnection()) {
            String sql = "SELECT patient_id, patient_code, first_name, last_name, status FROM patients WHERE patient_code=? AND status='Active'";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, normalizedPatientCode);
                try (ResultSet rs = ps.executeQuery()) {
                    if (!rs.next()) { result.errorMessage = "Patient ID not found or account is inactive."; return result; }
                    int pid = rs.getInt("patient_id");
                    String dbFirst = rs.getString("first_name");
                    String dbLast  = rs.getString("last_name");
                    String dbFull  = (dbFirst + " " + dbLast).trim();
                    if (!dbFull.equalsIgnoreCase(fullName.trim())) {
                        result.errorMessage = "Name does not match our records. Please enter your full name exactly as registered.";
                        AuditService.log(pid, "PATIENT_LOGIN_NAME_MISMATCH", "patients", pid, null, null, ipAddress);
                        return result;
                    }
                    String token = "PT-" + UUID.randomUUID().toString().replace("-", "");
                    try (PreparedStatement ps2 = conn.prepareStatement(
                            "INSERT INTO patient_sessions (session_id, patient_id, ip_address, expires_at) VALUES(?,?,?,DATE_ADD(NOW(),INTERVAL 15 MINUTE)) ON DUPLICATE KEY UPDATE expires_at=DATE_ADD(NOW(),INTERVAL 15 MINUTE)")) {
                        ps2.setString(1, token); ps2.setInt(2, pid); ps2.setString(3, ipAddress); ps2.executeUpdate();
                    } catch (SQLException se) { log.warning("patient_sessions: " + se.getMessage()); }
                    result.success = true; result.sessionToken = token; result.patientId = pid;
                    result.patientCode = normalizedPatientCode;
                    result.firstName = dbFirst; result.lastName = dbLast;
                    AuditService.log(0, "PATIENT_LOGIN_SUCCESS", "patients", pid, null, null, ipAddress);
                    return result;
                }
            }
        } catch (Exception e) { log.severe("Patient login error: " + e.getMessage()); result.errorMessage = "Internal error."; return result; }
    }

    // =====================================================================
    // MFA ENROLLMENT: Generate TOTP secret + otpauth URI for QR generation
    // =====================================================================
    public static String generateMfaSecret(int userId, String username) {
        GoogleAuthenticatorKey key = gAuth.createCredentials();
        String secret = key.getKey();
        return "otpauth://totp/SmartCare%3A" + username + "?secret=" + secret + "&issuer=SmartCare&algorithm=SHA1&digits=6&period=30";
    }

    // =====================================================================
    // SESSION MANAGEMENT
    // =====================================================================
    public static SessionInfo validateSession(String token) {
        if (token == null || token.isBlank() || token.startsWith("PT-") || token.startsWith("demo-")) return null;
        try (Connection conn = DBConnection.getConnection()) {
            String sql = "SELECT s.user_id, u.username, r.role_name, r.role_id, r.permissions FROM user_sessions s JOIN users u ON s.user_id=u.user_id JOIN roles r ON u.role_id=r.role_id WHERE s.session_id=? AND s.expires_at>NOW() AND u.is_active=TRUE";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, token);
                try (ResultSet rs = ps.executeQuery()) {
                    if (!rs.next()) return null;
                    int uid = rs.getInt("user_id"); String uname = rs.getString("username");
                    String role = rs.getString("role_name"); int roleId = rs.getInt("role_id"); String perms = rs.getString("permissions");
                    slideSession(conn, token);
                    return new SessionInfo(uid, uname, roleId, role, perms, token);
                }
            }
        } catch (Exception e) { log.warning("Session validate error: " + e.getMessage()); return null; }
    }

    public static void logout(String token, String ipAddress) {
        try (Connection conn = DBConnection.getConnection()) {
            int uid = 0;
            try (PreparedStatement ps = conn.prepareStatement("SELECT user_id FROM user_sessions WHERE session_id=?")) {
                ps.setString(1, token); try (ResultSet rs = ps.executeQuery()) { if (rs.next()) uid = rs.getInt("user_id"); }
            }
            try (PreparedStatement ps = conn.prepareStatement("DELETE FROM user_sessions WHERE session_id=?")) { ps.setString(1, token); ps.executeUpdate(); }
            if (uid > 0) AuditService.log(uid, "LOGOUT", "user_sessions", null, null, null, ipAddress);
        } catch (Exception e) { log.warning("Logout error: " + e.getMessage()); }
    }

    public static String hashPassword(String plain) { return BCrypt.hashpw(plain, BCrypt.gensalt(12)); }
    public static boolean verifyPassword(String plain, String hash) { return BCrypt.checkpw(plain, hash); }

    // =====================================================================
    // INTERNAL HELPERS
    // =====================================================================
    private static LoginResult createSession(Connection conn, int userId, String username, String roleName, String permissions, String ipAddress) throws SQLException {
        String token = UUID.randomUUID().toString().replace("-", "");
        try (PreparedStatement ps = conn.prepareStatement("INSERT INTO user_sessions (session_id, user_id, ip_address, expires_at) VALUES(?,?,?,DATE_ADD(NOW(),INTERVAL 15 MINUTE))")) {
            ps.setString(1, token); ps.setInt(2, userId); ps.setString(3, ipAddress); ps.executeUpdate();
        }
        try (PreparedStatement ps = conn.prepareStatement("UPDATE users SET last_login=NOW() WHERE user_id=?")) { ps.setInt(1, userId); ps.executeUpdate(); }
        LoginResult r = new LoginResult(); r.success = true; r.sessionToken = token; r.userId = userId; r.username = username; r.roleName = roleName; r.permissions = permissions; return r;
    }
    private static void slideSession(Connection conn, String token) throws SQLException {
        try (PreparedStatement ps = conn.prepareStatement("UPDATE user_sessions SET expires_at=DATE_ADD(NOW(),INTERVAL 15 MINUTE) WHERE session_id=?")) { ps.setString(1, token); ps.executeUpdate(); }
    }
    private static void enrollSecret(Connection conn, int userId, String secret) throws SQLException {
        try (PreparedStatement ps = conn.prepareStatement("INSERT INTO user_mfa (user_id, totp_secret, is_enabled) VALUES(?,?,TRUE) ON DUPLICATE KEY UPDATE totp_secret=?, is_enabled=TRUE")) {
            ps.setInt(1, userId); ps.setString(2, secret); ps.setString(3, secret); ps.executeUpdate();
        }
    }
    private static void lockAccount(Connection conn, int userId) throws SQLException {
        try (PreparedStatement ps = conn.prepareStatement("UPDATE users SET account_locked_until=DATE_ADD(NOW(),INTERVAL 30 MINUTE),failed_login_attempts=5 WHERE user_id=?")) { ps.setInt(1, userId); ps.executeUpdate(); }
    }
    private static void incrementFailedAttempts(Connection conn, int userId, int count) throws SQLException {
        try (PreparedStatement ps = conn.prepareStatement("UPDATE users SET failed_login_attempts=? WHERE user_id=?")) { ps.setInt(1, count); ps.setInt(2, userId); ps.executeUpdate(); }
    }
    private static void resetFailedAttempts(Connection conn, int userId) throws SQLException {
        try (PreparedStatement ps = conn.prepareStatement("UPDATE users SET failed_login_attempts=0,account_locked_until=NULL WHERE user_id=?")) { ps.setInt(1, userId); ps.executeUpdate(); }
    }
    private static void storeTempToken(Connection conn, int userId, String token) throws SQLException {
        try (PreparedStatement ps = conn.prepareStatement("INSERT INTO temp_mfa_tokens (user_id, token, expires_at) VALUES(?,?,DATE_ADD(NOW(),INTERVAL 5 MINUTE)) ON DUPLICATE KEY UPDATE token=?,expires_at=DATE_ADD(NOW(),INTERVAL 5 MINUTE)")) {
            ps.setInt(1, userId); ps.setString(2, token); ps.setString(3, token); ps.executeUpdate();
        }
    }
    private static void deleteTempToken(Connection conn, String token) throws SQLException {
        try (PreparedStatement ps = conn.prepareStatement("DELETE FROM temp_mfa_tokens WHERE token=?")) { ps.setString(1, token); ps.executeUpdate(); }
    }

    public static class SessionInfo {
        public final int userId; public final String username; public final int roleId;
        public final String roleName; public final String permissions; public final String token;
        public SessionInfo(int userId, String username, int roleId, String roleName, String permissions, String token) {
            this.userId=userId; this.username=username; this.roleId=roleId; this.roleName=roleName; this.permissions=permissions; this.token=token;
        }
        public boolean hasModule(String module) { return permissions!=null && (permissions.contains("\"all\": true") || permissions.contains(module)); }
    }
}
