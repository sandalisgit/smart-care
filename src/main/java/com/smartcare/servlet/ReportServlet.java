package com.smartcare.servlet;

import com.itextpdf.text.BaseColor;
import com.itextpdf.text.Document;
import com.itextpdf.text.DocumentException;
import com.itextpdf.text.Element;
import com.itextpdf.text.FontFactory;
import com.itextpdf.text.PageSize;
import com.itextpdf.text.Paragraph;
import com.itextpdf.text.Phrase;
import com.itextpdf.text.Chunk;
import com.itextpdf.text.pdf.PdfPCell;
import com.itextpdf.text.pdf.PdfPTable;
import com.itextpdf.text.pdf.PdfWriter;
import com.smartcare.dao.BillingDAO;
import com.smartcare.dao.EmrDAO;
import com.smartcare.dao.PatientDAO;
import com.smartcare.model.Patient;
import com.smartcare.security.AuditService;
import com.smartcare.security.AuthService;
import com.smartcare.util.JsonUtil;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.*;
import java.io.*;
import java.util.List;
import java.util.Map;

/**
 * PDF Reports servlet — FR-04, FR-09, FR-43, FR-46
 * NOTE: Uses com.itextpdf.text.BaseColor (NOT java.awt.Color) to avoid conflicts.
 *       Uses java.util.List explicitly (NOT com.itextpdf.text.List) to avoid ambiguity.
 */
@WebServlet("/api/reports/*")
public class ReportServlet extends HttpServlet {

    private final PatientDAO patientDAO = new PatientDAO();
    private final BillingDAO billingDAO = new BillingDAO();
    private final EmrDAO     emrDAO     = new EmrDAO();

    // Brand colors — BaseColor(r,g,b), never java.awt.Color
    private static final BaseColor COL_TEAL  = new BaseColor(24,  174, 186);
    private static final BaseColor COL_LIGHT = new BaseColor(232, 248, 250);

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        AuthService.SessionInfo session =
                (AuthService.SessionInfo) req.getAttribute("session");
        String path = req.getPathInfo();
        try {
            if (path != null && path.matches("/patient/\\d+$")) {
                generatePatientReport(req, resp, Integer.parseInt(path.split("/")[2]), session);
            } else if (path != null && path.matches("/patient/\\d+/qr")) {
                generateQrData(resp, Integer.parseInt(path.split("/")[2]));
            } else if (path != null && path.matches("/receipt/\\d+")) {
                generateReceipt(resp, Integer.parseInt(path.split("/")[2]));
            } else if ("/financial".equals(path)) {
                generateFinancialReport(resp);
            } else {
                resp.setStatus(404);
                resp.setContentType("application/json");
                resp.getWriter().write(JsonUtil.error("Report type not found"));
            }
        } catch (Exception e) {
            resp.setStatus(500);
            resp.setContentType("application/json");
            resp.getWriter().write(JsonUtil.error("Report error: " + e.getMessage()));
        }
    }

    // ── FR-04: Patient Medical Report PDF ─────────────────────────────────
    private void generatePatientReport(HttpServletRequest req, HttpServletResponse resp,
                                        int pid, AuthService.SessionInfo session) throws Exception {
        Patient p = patientDAO.getById(pid);
        if (p == null) { resp.setStatus(404); resp.setContentType("application/json");
            resp.getWriter().write(JsonUtil.error("Patient not found")); return; }

        List<Map<String, Object>> history = emrDAO.getPatientHistory(pid, 20);
        List<Map<String, Object>> labs    = emrDAO.getPatientLabHistory(pid);

        resp.setContentType("application/pdf");
        resp.setHeader("Content-Disposition",
                "attachment; filename=\"report_" + p.getPatientCode() + ".pdf\"");

        Document doc = new Document(PageSize.A4, 40, 40, 60, 40);
        PdfWriter.getInstance(doc, resp.getOutputStream());
        doc.open();

        // Header
        PdfPTable hdr = new PdfPTable(2);
        hdr.setWidthPercentage(100);
        hdr.setWidths(new float[]{3, 1});
        PdfPCell tc = new PdfPCell(new Phrase("SMART CARE — Patient Medical Report",
                FontFactory.getFont(FontFactory.HELVETICA_BOLD, 16, COL_TEAL)));
        tc.setBorder(0); tc.setBackgroundColor(COL_LIGHT); tc.setPadding(10);
        hdr.addCell(tc);
        PdfPCell dc = new PdfPCell(new Phrase("Generated: " + new java.util.Date(),
                FontFactory.getFont(FontFactory.HELVETICA, 9, BaseColor.GRAY)));
        dc.setBorder(0); dc.setBackgroundColor(COL_LIGHT); dc.setPadding(10);
        dc.setHorizontalAlignment(Element.ALIGN_RIGHT);
        hdr.addCell(dc);
        doc.add(hdr);
        doc.add(Chunk.NEWLINE);

        // Patient info
        sectionTitle(doc, "Patient Information");
        PdfPTable pt = new PdfPTable(4);
        pt.setWidthPercentage(100);
        infoRow(pt, "Patient Code", p.getPatientCode(), "Full Name", p.getFullName());
        infoRow(pt, "DOB",     p.getDateOfBirth() != null ? p.getDateOfBirth().toString() : "—",
                    "Gender",  p.getGender()     != null ? p.getGender()                 : "—");
        infoRow(pt, "Blood",   p.getBloodGroup() != null ? p.getBloodGroup()              : "—",
                    "Phone",   p.getPhone()       != null ? p.getPhone()                  : "—");
        infoRow(pt, "Allergies", p.getAllergies() != null ? p.getAllergies()               : "None",
                    "Conditions", p.getChronicConditions() != null ? p.getChronicConditions() : "None");
        doc.add(pt);
        doc.add(Chunk.NEWLINE);

        // Medical history
        if (!history.isEmpty()) {
            sectionTitle(doc, "Medical History (" + history.size() + " records)");
            PdfPTable mt = new PdfPTable(4);
            mt.setWidthPercentage(100);
            tblHdr(mt, "Date", "Doctor", "Diagnosis", "Follow-up");
            for (Map<String, Object> r : history) {
                mt.addCell(cel(s(r,"record_date")));
                mt.addCell(cel(s(r,"doctor_name")));
                String d = s(r,"diagnosis");
                mt.addCell(cel(d.length() > 50 ? d.substring(0,50)+"..." : d));
                mt.addCell(cel(s(r,"follow_up_date")));
            }
            doc.add(mt);
            doc.add(Chunk.NEWLINE);
        }

        // Lab results
        if (!labs.isEmpty()) {
            sectionTitle(doc, "Lab Results (" + labs.size() + " records)");
            PdfPTable lt = new PdfPTable(5);
            lt.setWidthPercentage(100);
            tblHdr(lt, "Date","Test Name","Result","Normal Range","Status");
            for (Map<String, Object> r : labs) {
                lt.addCell(cel(s(r,"test_date")));
                lt.addCell(cel(s(r,"test_name")));
                lt.addCell(cel(s(r,"test_result")));
                lt.addCell(cel(s(r,"normal_range")));
                lt.addCell(cel(s(r,"status")));
            }
            doc.add(lt);
        }

        doc.add(Chunk.NEWLINE);
        doc.add(new Paragraph("CONFIDENTIAL — Smart Care | HIPAA 45 CFR §164.312 | AES-256-GCM",
                FontFactory.getFont(FontFactory.HELVETICA, 8, BaseColor.GRAY)));
        doc.close();

        if (session != null)
            AuditService.log(session.userId,"DOWNLOAD_REPORT","patients",pid,null,"PDF",req.getRemoteAddr());
    }

    // ── FR-09: QR Code data ────────────────────────────────────────────────
    private void generateQrData(HttpServletResponse resp, int pid) throws Exception {
        Patient p = patientDAO.getById(pid);
        if (p == null) { resp.setStatus(404); resp.setContentType("application/json");
            resp.getWriter().write(JsonUtil.error("Patient not found")); return; }
        resp.setContentType("application/json");
        resp.getWriter().write(JsonUtil.success(java.util.Map.of(
                "patientCode", p.getPatientCode(),
                "patientName", p.getFullName(),
                "bloodGroup",  p.getBloodGroup() != null ? p.getBloodGroup() : "",
                "allergies",   p.getAllergies()   != null ? p.getAllergies()   : "None",
                "qrData",      "SMARTCARE:" + p.getPatientCode()
        )));
    }

    // ── FR-43: Payment Receipt PDF ─────────────────────────────────────────
    private void generateReceipt(HttpServletResponse resp, int billId) throws Exception {
        Map<String, Object> bill = billingDAO.getBillWithItems(billId);
        if (bill == null || bill.isEmpty()) {
            resp.setStatus(404); resp.setContentType("application/json");
            resp.getWriter().write(JsonUtil.error("Bill not found")); return;
        }
        resp.setContentType("application/pdf");
        resp.setHeader("Content-Disposition",
                "attachment; filename=\"receipt_" + bill.get("bill_number") + ".pdf\"");

        Document doc = new Document(PageSize.A5, 40, 40, 40, 40);
        PdfWriter.getInstance(doc, resp.getOutputStream());
        doc.open();
        doc.add(new Paragraph("SMART CARE", FontFactory.getFont(FontFactory.HELVETICA_BOLD,20,COL_TEAL)));
        doc.add(new Paragraph("Payment Receipt", FontFactory.getFont(FontFactory.HELVETICA,12)));
        doc.add(Chunk.NEWLINE);
        doc.add(new Paragraph("Bill No: " + bill.getOrDefault("bill_number","—")));
        doc.add(new Paragraph("Patient: " + bill.getOrDefault("patient_name","—")));
        doc.add(new Paragraph("Date: "    + bill.getOrDefault("bill_date","—")));
        doc.add(Chunk.NEWLINE);

        @SuppressWarnings("unchecked")
        java.util.List<Map<String,Object>> items =
                (java.util.List<Map<String,Object>>) bill.getOrDefault("items", java.util.List.of());
        PdfPTable t = new PdfPTable(3);
        t.setWidthPercentage(100);
        tblHdr(t, "Description","Qty","Amount (LKR)");
        for (Map<String,Object> i : items) {
            t.addCell(cel(s(i,"description")));
            t.addCell(cel(s(i,"quantity")));
            t.addCell(cel("LKR " + i.getOrDefault("line_total","0")));
        }
        doc.add(t);
        doc.add(Chunk.NEWLINE);
        doc.add(new Paragraph("Total:   LKR " + bill.getOrDefault("total_amount","0"),
                FontFactory.getFont(FontFactory.HELVETICA_BOLD,12)));
        doc.add(new Paragraph("Paid:    LKR " + bill.getOrDefault("paid_amount","0")));
        doc.add(new Paragraph("Balance: LKR " + bill.getOrDefault("balance_amount","0")));
        doc.add(Chunk.NEWLINE);
        doc.add(new Paragraph("Thank you for choosing Smart Care.",
                FontFactory.getFont(FontFactory.HELVETICA,9,BaseColor.GRAY)));
        doc.close();
    }

    // ── FR-46: Financial Summary PDF ───────────────────────────────────────
    private void generateFinancialReport(HttpServletResponse resp) throws Exception {
        resp.setContentType("application/pdf");
        resp.setHeader("Content-Disposition","attachment; filename=\"financial_report.pdf\"");
        Document doc = new Document(PageSize.A4.rotate(),40,40,40,40);
        PdfWriter.getInstance(doc, resp.getOutputStream());
        doc.open();
        doc.add(new Paragraph("SMART CARE — Financial Summary Report",
                FontFactory.getFont(FontFactory.HELVETICA_BOLD,18,COL_TEAL)));
        doc.add(new Paragraph("Generated: "+new java.util.Date(),
                FontFactory.getFont(FontFactory.HELVETICA,10,BaseColor.GRAY)));
        doc.add(Chunk.NEWLINE);

        Map<String,Object> stats = billingDAO.getDashboardStats();
        PdfPTable kpi = new PdfPTable(4);
        kpi.setWidthPercentage(100);
        tblHdr(kpi,"Metric","Value","Metric","Value");
        kpi.addCell(cel("Today Revenue")); kpi.addCell(cel("LKR "+stats.getOrDefault("revenue_today",0)));
        kpi.addCell(cel("Outstanding"));  kpi.addCell(cel("LKR "+stats.getOrDefault("total_outstanding",0)));
        kpi.addCell(cel("Bills Today"));  kpi.addCell(cel(""+stats.getOrDefault("total_bills_today","0")));
        kpi.addCell(cel("Overdue"));      kpi.addCell(cel(""+stats.getOrDefault("overdue_count","0")));
        doc.add(kpi);
        doc.add(Chunk.NEWLINE);

        java.util.List<Map<String,Object>> outstanding = billingDAO.getOutstandingBills(50);
        if (!outstanding.isEmpty()) {
            sectionTitle(doc,"Outstanding Bills");
            PdfPTable ot = new PdfPTable(5);
            ot.setWidthPercentage(100);
            tblHdr(ot,"Bill No.","Patient","Total","Balance","Status");
            for (Map<String,Object> b : outstanding) {
                ot.addCell(cel(s(b,"bill_number")));
                ot.addCell(cel(s(b,"patient_name")));
                ot.addCell(cel("LKR "+b.getOrDefault("total_amount",0)));
                ot.addCell(cel("LKR "+b.getOrDefault("balance_amount",0)));
                ot.addCell(cel(s(b,"status")));
            }
            doc.add(ot);
        }
        doc.close();
    }

    // ── PDF Helpers ────────────────────────────────────────────────────────
    private void sectionTitle(Document doc, String t) throws DocumentException {
        Paragraph p = new Paragraph(t, FontFactory.getFont(FontFactory.HELVETICA_BOLD,12,COL_TEAL));
        p.setSpacingBefore(10); p.setSpacingAfter(5);
        doc.add(p);
    }
    private void tblHdr(PdfPTable tbl, String... cols) {
        for (String c : cols) {
            PdfPCell cell = new PdfPCell(
                    new Phrase(c, FontFactory.getFont(FontFactory.HELVETICA_BOLD,10,BaseColor.WHITE)));
            cell.setBackgroundColor(COL_TEAL); cell.setPadding(6);
            tbl.addCell(cell);
        }
    }
    private void infoRow(PdfPTable t, String l1,String v1,String l2,String v2) {
        t.addCell(lbl(l1)); t.addCell(cel(v1)); t.addCell(lbl(l2)); t.addCell(cel(v2));
    }
    private PdfPCell cel(String text) {
        PdfPCell c = new PdfPCell(
                new Phrase(text!=null?text:"—", FontFactory.getFont(FontFactory.HELVETICA,10)));
        c.setPadding(5); return c;
    }
    private PdfPCell lbl(String text) {
        PdfPCell c = new PdfPCell(
                new Phrase(text, FontFactory.getFont(FontFactory.HELVETICA_BOLD,10)));
        c.setBackgroundColor(COL_LIGHT); c.setPadding(5); return c;
    }
    private String s(Map<String,Object> m, String k) {
        Object v = m.get(k); return v != null ? v.toString() : "—";
    }
}
