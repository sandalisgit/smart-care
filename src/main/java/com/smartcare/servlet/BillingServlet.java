package com.smartcare.servlet;

import com.smartcare.ai.AnomalyDetector;
import com.smartcare.dao.BillingDAO;
import com.smartcare.security.AuditService;
import com.smartcare.security.AuthService;
import com.smartcare.util.JsonUtil;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.util.*;

/** Billing & Finance REST API */
@WebServlet("/api/billing/*")
class BillingServlet extends HttpServlet {
    private final BillingDAO billingDAO = new BillingDAO();

    @Override protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        String path = req.getPathInfo();
        try {
            if ("/dashboard".equals(path)) { resp.getWriter().write(JsonUtil.success(billingDAO.getDashboardStats())); return; }
            if ("/outstanding".equals(path)) { resp.getWriter().write(JsonUtil.success(billingDAO.getOutstandingBills(50))); return; }
            if (path != null && path.startsWith("/patient/")) {
                int pid = Integer.parseInt(path.substring("/patient/".length()));
                resp.getWriter().write(JsonUtil.success(billingDAO.getPatientBills(pid))); return;
            }
            if (path != null && path.matches("/\\d+")) {
                int bid = Integer.parseInt(path.substring(1));
                resp.getWriter().write(JsonUtil.success(billingDAO.getBillWithItems(bid))); return;
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

            // POST /api/billing/bills — create bill
            if ("/bills".equals(path)) {
                int patientId = ((Number) data.get("patientId")).intValue();
                Integer admId = data.get("admissionId") != null ? ((Number) data.get("admissionId")).intValue() : null;
                int billId = billingDAO.createBill(patientId, admId, session.userId);
                // Run anomaly check async after creation
                AnomalyDetector.checkAndFlagBill(billId, session.userId);
                AuditService.log(session.userId, "CREATE_BILL", "bills", billId, null, body, getClientIp(req));
                resp.setStatus(201); resp.getWriter().write(JsonUtil.success("Bill created", Map.of("billId", billId))); return;
            }

            // POST /api/billing/payments — record payment
            if ("/payments".equals(path)) {
                int billId = ((Number) data.get("billId")).intValue();
                double amount = ((Number) data.get("amount")).doubleValue();
                String method = (String) data.get("paymentMethod");
                String ref = (String) data.get("reference");
                int paymentId = billingDAO.recordPayment(billId, amount, method, ref, session.userId);
                AuditService.log(session.userId, "RECORD_PAYMENT", "payments", paymentId, null, body, getClientIp(req));
                resp.setStatus(201); resp.getWriter().write(JsonUtil.success("Payment recorded", Map.of("paymentId", paymentId))); return;
            }

            // POST /api/billing/claims — insurance claim
            if ("/claims".equals(path)) {
                int claimId = billingDAO.createInsuranceClaim(
                        ((Number) data.get("patientId")).intValue(), ((Number) data.get("billId")).intValue(),
                        (String) data.get("provider"), (String) data.get("policyNumber"),
                        ((Number) data.get("claimAmount")).doubleValue());
                resp.setStatus(201); resp.getWriter().write(JsonUtil.success("Claim submitted", Map.of("claimId", claimId))); return;
            }

            resp.setStatus(404); resp.getWriter().write(JsonUtil.error("Not found"));
        } catch (Exception e) { resp.setStatus(500); resp.getWriter().write(JsonUtil.error(e.getMessage())); }
    }

    private String getClientIp(HttpServletRequest req) { String f = req.getHeader("X-Forwarded-For"); return f != null ? f.split(",")[0].trim() : req.getRemoteAddr(); }
}
