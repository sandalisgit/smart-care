package com.smartcare.servlet;

import com.smartcare.dao.PharmacyDAO;
import com.smartcare.security.AuditService;
import com.smartcare.security.AuthService;
import com.smartcare.util.JsonUtil;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.sql.Date;
import java.util.*;

/** Pharmacy & Inventory REST API */
@WebServlet("/api/pharmacy/*")
public class PharmacyServlet extends HttpServlet {
    private final PharmacyDAO pharmacyDAO = new PharmacyDAO();

    @Override protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json;charset=UTF-8");
        String path = req.getPathInfo();
        try {
            if ("/dashboard".equals(path))  { resp.getWriter().write(JsonUtil.success(pharmacyDAO.getDashboardStats())); return; }
            if ("/low-stock".equals(path))  { resp.getWriter().write(JsonUtil.success(pharmacyDAO.getLowStockItems())); return; }
            if ("/expiring".equals(path))   { resp.getWriter().write(JsonUtil.success(pharmacyDAO.getExpiringItems())); return; }
            if ("/items".equals(path))      { resp.getWriter().write(JsonUtil.success(pharmacyDAO.getAllItems(req.getParameter("category")))); return; }
            if ("/prescriptions".equals(path)) { resp.getWriter().write(JsonUtil.success(pharmacyDAO.getPendingPrescriptions())); return; }
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

            // POST /api/pharmacy/dispense
            if ("/dispense".equals(path)) {
                int prescriptionId = ((Number) data.get("prescriptionId")).intValue();
                pharmacyDAO.dispensePrescription(prescriptionId, session.userId);
                AuditService.log(session.userId, "DISPENSE_PRESCRIPTION", "prescriptions", prescriptionId, null, null, getClientIp(req));
                resp.getWriter().write(JsonUtil.success("Prescription dispensed", null)); return;
            }

            // POST /api/pharmacy/receive — receive new stock
            if ("/receive".equals(path)) {
                Integer supplierId = data.get("supplierId") != null ? ((Number) data.get("supplierId")).intValue() : null;
                pharmacyDAO.receiveStock(
                        ((Number) data.get("itemId")).intValue(), (String) data.get("batchNumber"),
                        Date.valueOf((String) data.get("expiryDate")),
                        ((Number) data.get("quantity")).intValue(),
                        ((Number) data.get("costPerUnit")).doubleValue(),
                        supplierId, session.userId);
                AuditService.log(session.userId, "RECEIVE_STOCK", "inventory_items", ((Number) data.get("itemId")).intValue(), null, body, getClientIp(req));
                resp.setStatus(201); resp.getWriter().write(JsonUtil.success("Stock received", null)); return;
            }
            resp.setStatus(404); resp.getWriter().write(JsonUtil.error("Not found"));
        } catch (Exception e) {
            if (e.getMessage() != null && e.getMessage().contains("INSUFFICIENT_STOCK")) {
                resp.setStatus(409); resp.getWriter().write(JsonUtil.error(e.getMessage(), "INSUFFICIENT_STOCK"));
            } else { resp.setStatus(500); resp.getWriter().write(JsonUtil.error(e.getMessage())); }
        }
    }

    private String getClientIp(HttpServletRequest req) { String f = req.getHeader("X-Forwarded-For"); return f != null ? f.split(",")[0].trim() : req.getRemoteAddr(); }
}
