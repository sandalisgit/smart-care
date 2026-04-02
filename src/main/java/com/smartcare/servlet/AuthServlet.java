package com.smartcare.servlet;

import com.smartcare.security.AuthService;
import com.smartcare.util.JsonUtil;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.util.Map;

/**
 * Authentication endpoints - all public (AuthFilter skips /api/auth/*).
 *
 * POST /api/auth/login             - Staff login (username + password)
 * POST /api/auth/mfa-verify        - TOTP code verification (enrolled users)
 * POST /api/auth/mfa-setup-verify  - First-time TOTP setup + verify
 * POST /api/auth/mfa-enroll        - Generate TOTP secret + QR URI
 * POST /api/auth/patient-login     - Patient login (Patient ID + Full Name ONLY)
 * POST /api/auth/logout            - Invalidate session
 *
 * SECURITY: /patient-login only accepts PAT-prefixed IDs.
 * Staff cannot authenticate via /patient-login.
 * Patients cannot authenticate via /login.
 */
@WebServlet("/api/auth/*")
public class AuthServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        resp.setHeader("Access-Control-Allow-Origin", "*");
        String path = req.getPathInfo();
        switch (path != null ? path : "") {
            case "/login"            -> handleLogin(req, resp);
            case "/mfa-verify"       -> handleMfaVerify(req, resp);
            case "/mfa-setup-verify" -> handleMfaSetupVerify(req, resp);
            case "/mfa-enroll"       -> handleMfaEnroll(req, resp);
            case "/patient-login"    -> handlePatientLogin(req, resp);
            case "/logout"           -> handleLogout(req, resp);
            default -> { resp.setStatus(404); resp.getWriter().write(JsonUtil.error("Unknown endpoint: " + path)); }
        }
    }

    @Override
    protected void doOptions(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setHeader("Access-Control-Allow-Origin", "*");
        resp.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
        resp.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
        resp.setStatus(200);
    }

    private void handleLogin(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        try {
            @SuppressWarnings("unchecked")
            Map<String, String> body = JsonUtil.fromJson(readBody(req), Map.class);
            String username = body.get("username");
            String password = body.get("password");
            if (isBlank(username) || isBlank(password)) { resp.setStatus(400); resp.getWriter().write(JsonUtil.error("Username and password required.")); return; }

            AuthService.LoginResult result = AuthService.login(username, password, getClientIp(req));
            if (result.success) {
                resp.setStatus(200);
                resp.getWriter().write(JsonUtil.success("Login successful", Map.of(
                    "token", result.sessionToken, "userId", result.userId,
                    "username", result.username, "role", result.roleName,
                    "permissions", result.permissions != null ? result.permissions : "{}"
                )));
            } else if (result.requiresMfa) {
                resp.setStatus(200);
                resp.getWriter().write(JsonUtil.success("MFA required", Map.of(
                    "requiresMfa", true, "tempToken", result.tempToken,
                    "userId", result.userId, "username", result.username
                )));
            } else if (result.requiresMfaSetup) {
                resp.setStatus(200);
                resp.getWriter().write(JsonUtil.success("MFA setup required", Map.of(
                    "requiresMfaSetup", true, "tempToken", result.tempToken,
                    "userId", result.userId, "username", result.username
                )));
            } else {
                resp.setStatus(401);
                resp.getWriter().write(JsonUtil.error(result.errorMessage));
            }
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error("Login error: " + e.getMessage())); }
    }

    private void handleMfaVerify(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> body = JsonUtil.fromJson(readBody(req), Map.class);
            String tempToken = (String) body.get("tempToken");
            Object codeObj = body.get("code");
            if (isBlank(tempToken) || codeObj == null) { resp.setStatus(400); resp.getWriter().write(JsonUtil.error("tempToken and code required.")); return; }
            int totpCode;
            try { totpCode = ((Number) codeObj).intValue(); } catch (ClassCastException e) { totpCode = Integer.parseInt(codeObj.toString()); }
            AuthService.LoginResult result = AuthService.verifyMfa(tempToken, totpCode, getClientIp(req));
            if (result.success) {
                resp.setStatus(200);
                resp.getWriter().write(JsonUtil.success("MFA verified", Map.of(
                    "token", result.sessionToken, "userId", result.userId,
                    "username", result.username, "role", result.roleName
                )));
            } else { resp.setStatus(401); resp.getWriter().write(JsonUtil.error(result.errorMessage)); }
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error("MFA verify error: " + e.getMessage())); }
    }

    private void handleMfaSetupVerify(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> body = JsonUtil.fromJson(readBody(req), Map.class);
            String tempToken = (String) body.get("tempToken");
            String secret    = (String) body.get("secret");
            Object codeObj   = body.get("code");
            if (isBlank(tempToken) || isBlank(secret) || codeObj == null) { resp.setStatus(400); resp.getWriter().write(JsonUtil.error("tempToken, secret, and code required.")); return; }
            int totpCode;
            try { totpCode = ((Number) codeObj).intValue(); } catch (ClassCastException e) { totpCode = Integer.parseInt(codeObj.toString()); }
            AuthService.LoginResult result = AuthService.setupAndVerifyMfa(tempToken, secret, totpCode, getClientIp(req));
            if (result.success) {
                resp.setStatus(200);
                resp.getWriter().write(JsonUtil.success("MFA setup complete", Map.of(
                    "token", result.sessionToken, "userId", result.userId,
                    "username", result.username, "role", result.roleName
                )));
            } else { resp.setStatus(401); resp.getWriter().write(JsonUtil.error(result.errorMessage)); }
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error("MFA setup error: " + e.getMessage())); }
    }

    private void handleMfaEnroll(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> body = JsonUtil.fromJson(readBody(req), Map.class);
            String tempToken = (String) body.get("tempToken");
            String username  = (String) body.get("username");
            Object userIdRaw = body.getOrDefault("userId", 0);
            int userId = userIdRaw instanceof Number ? ((Number) userIdRaw).intValue() : Integer.parseInt(String.valueOf(userIdRaw));
            if (isBlank(tempToken) || isBlank(username) || userId == 0) { resp.setStatus(400); resp.getWriter().write(JsonUtil.error("tempToken, username, userId required.")); return; }
            String qrUri = AuthService.generateMfaSecret(userId, username);
            String secret = qrUri.replaceAll(".*secret=([A-Z2-7]+).*", "$1");
            resp.setStatus(200);
            resp.getWriter().write(JsonUtil.success("MFA secret generated", Map.of(
                "qrUri", qrUri, "secret", secret, "issuer", "SmartCare", "account", username + "@smartcare"
            )));
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error("MFA enroll error: " + e.getMessage())); }
    }

    private void handlePatientLogin(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        try {
            @SuppressWarnings("unchecked")
            Map<String, String> body = JsonUtil.fromJson(readBody(req), Map.class);
            String patientId = body.get("patientId");
            String fullName  = body.get("fullName");
            if (isBlank(patientId) || isBlank(fullName)) { resp.setStatus(400); resp.getWriter().write(JsonUtil.error("Patient ID and full name required.")); return; }
            if (!patientId.toUpperCase().trim().startsWith("PAT")) {
                resp.setStatus(400);
                resp.getWriter().write(JsonUtil.error("Invalid Patient ID format. Patient IDs start with PAT (e.g. PAT000001)."));
                return;
            }
            AuthService.PatientLoginResult result = AuthService.patientLogin(patientId.trim(), fullName.trim(), getClientIp(req));
            if (result.success) {
                resp.setStatus(200);
                resp.getWriter().write(JsonUtil.success("Patient login successful", Map.of(
                    "token", result.sessionToken, "patientId", result.patientId,
                    "patientCode", result.patientCode, "firstName", result.firstName, "lastName", result.lastName
                )));
            } else { resp.setStatus(401); resp.getWriter().write(JsonUtil.error(result.errorMessage)); }
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error("Patient login error: " + e.getMessage())); }
    }

    private void handleLogout(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        String auth = req.getHeader("Authorization");
        if (auth != null && auth.startsWith("Bearer ")) AuthService.logout(auth.substring(7), getClientIp(req));
        resp.setStatus(200); resp.getWriter().write(JsonUtil.success("Logged out.", null));
    }

    private String readBody(HttpServletRequest req) throws IOException { return req.getReader().lines().reduce("", String::concat); }
    private boolean isBlank(String s) { return s == null || s.isBlank(); }
    private String getClientIp(HttpServletRequest req) { String f = req.getHeader("X-Forwarded-For"); return f != null ? f.split(",")[0].trim() : req.getRemoteAddr(); }
}
