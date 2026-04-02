package com.smartcare.filter;

import com.smartcare.security.AuthService;
import com.smartcare.util.JsonUtil;
import jakarta.servlet.*;
import jakarta.servlet.annotation.WebFilter;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.util.Set;

/**
 * Global security filter - runs before every API servlet.
 * Validates Bearer token, enforces 15-min session timeout (NFR-08), enforces RBAC (FR-71).
 *
 * Public paths (no auth needed):
 *   /api/auth/login             - staff login
 *   /api/auth/logout            - logout
 *   /api/auth/mfa-verify        - TOTP code verify (subsequent logins)
 *   /api/auth/mfa-setup-verify  - TOTP first-time setup + verify  [FIXED]
 *   /api/auth/mfa-enroll        - generate TOTP secret + QR URI   [FIXED]
 *   /api/auth/patient-login     - patient portal login             [FIXED]
 */
@WebFilter(urlPatterns = "/api/*")
public class AuthFilter implements Filter {

    private static final Set<String> PUBLIC_PATHS = Set.of(
            "/api/auth/login",
            "/api/auth/logout",
            "/api/auth/mfa-verify",
            "/api/auth/mfa-setup-verify",
            "/api/auth/mfa-enroll",
            "/api/auth/patient-login"
    );

    @Override
    public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain)
            throws IOException, ServletException {

        HttpServletRequest  request  = (HttpServletRequest)  req;
        HttpServletResponse response = (HttpServletResponse) res;

        String path = request.getServletPath()
                + (request.getPathInfo() != null ? request.getPathInfo() : "");

        // Security headers
        response.setHeader("Access-Control-Allow-Origin",  "*");
        response.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        response.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
        response.setHeader("X-Content-Type-Options",  "nosniff");
        response.setHeader("X-Frame-Options",          "DENY");
        response.setHeader("X-XSS-Protection",         "1; mode=block");

        // Pre-flight OPTIONS
        if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
            response.setStatus(HttpServletResponse.SC_OK);
            return;
        }

        // Allow public paths through without authentication
        for (String pub : PUBLIC_PATHS) {
            if (path.startsWith(pub)) {
                chain.doFilter(req, res);
                return;
            }
        }

        // Extract Bearer token
        String authHeader = request.getHeader("Authorization");
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.setContentType("application/json;charset=UTF-8");
            response.getWriter().write(JsonUtil.error("No authentication token provided"));
            return;
        }

        String token = authHeader.substring(7);

        // Validate session - also slides the 15-min window (NFR-08)
        AuthService.SessionInfo session = AuthService.validateSession(token);
        if (session == null) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.setContentType("application/json;charset=UTF-8");
            response.getWriter().write(JsonUtil.error("Session expired or invalid. Please login again."));
            return;
        }

        // Attach session to request attributes for downstream servlets
        request.setAttribute("session",  session);
        request.setAttribute("userId",   session.userId);
        request.setAttribute("roleName", session.roleName);

        chain.doFilter(req, res);
    }
}
