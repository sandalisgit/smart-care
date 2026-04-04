-- =============================================================================
-- BILLING & FINANCE MODULE — PATCH
-- FR-41: Auto-generate itemised bills  FR-42: Payment recording
-- FR-43: Payment receipts              FR-44: Insurance claim generation
-- FR-45: Co-payment calculation        FR-47: AI fraud detection
-- FR-48: Audit all billing events      FR-50: Outstanding balance per patient
-- Run AFTER SMARTCARE_COMPLETE_DATABASE.sql
-- =============================================================================

USE hospital_erp;

-- ---------------------------------------------------------------------------
-- Mark overdue bills (bills past due_date with unpaid balance)
-- ---------------------------------------------------------------------------
DROP EVENT IF EXISTS evt_mark_overdue_bills;
CREATE EVENT evt_mark_overdue_bills
    ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP
    DO
        UPDATE bills
        SET status = 'Overdue'
        WHERE status IN ('Pending', 'Partially Paid')
          AND due_date < CURDATE()
          AND balance_amount > 0;

-- ---------------------------------------------------------------------------
-- Enhanced outstanding bills view (adds bill_id for API joins)
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS v_outstanding_bills;
CREATE VIEW v_outstanding_bills AS
SELECT
    b.bill_id,
    b.bill_number,
    b.bill_date,
    b.due_date,
    b.patient_id,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    p.phone                                 AS patient_phone,
    p.insurance_provider,
    b.total_amount,
    b.paid_amount,
    b.balance_amount,
    b.status,
    DATEDIFF(CURDATE(), b.due_date) AS days_overdue
FROM bills b
         JOIN patients p ON b.patient_id = p.patient_id
WHERE b.status IN ('Pending', 'Partially Paid', 'Overdue')
  AND b.balance_amount > 0
ORDER BY
    CASE WHEN b.status = 'Overdue' THEN 1 ELSE 2 END,
    b.due_date ASC;

-- ---------------------------------------------------------------------------
-- Revenue summary view — monthly revenue for reports (FR-46)
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS v_monthly_revenue;
CREATE VIEW v_monthly_revenue AS
SELECT
    DATE_FORMAT(b.bill_date, '%Y-%m')   AS revenue_month,
    COUNT(DISTINCT b.bill_id)           AS total_bills,
    COALESCE(SUM(b.total_amount), 0)    AS gross_revenue,
    COALESCE(SUM(b.paid_amount), 0)     AS collected_revenue,
    COALESCE(SUM(b.balance_amount), 0)  AS outstanding_revenue,
    COALESCE(SUM(b.discount_amount), 0) AS total_discounts
FROM bills b
WHERE b.status != 'Draft'
GROUP BY DATE_FORMAT(b.bill_date, '%Y-%m')
ORDER BY revenue_month DESC;

-- ---------------------------------------------------------------------------
-- Claims summary view — insurance performance (FR-44)
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS v_claims_summary;
CREATE VIEW v_claims_summary AS
SELECT
    ic.claim_id,
    ic.claim_number,
    ic.claim_date,
    ic.insurance_provider,
    ic.policy_number,
    ic.claim_amount,
    COALESCE(ic.approved_amount, 0)     AS approved_amount,
    ic.status,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    b.bill_number,
    b.total_amount                      AS bill_amount,
    DATEDIFF(CURDATE(), ic.claim_date)  AS days_pending
FROM insurance_claims ic
         JOIN patients p ON ic.patient_id = p.patient_id
         JOIN bills b ON ic.bill_id = b.bill_id
ORDER BY ic.claim_date DESC;

-- ---------------------------------------------------------------------------
-- Revenue by service category view — for financial reports
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS v_revenue_by_category;
CREATE VIEW v_revenue_by_category AS
SELECT
    COALESCE(s.service_category, 'Other') AS category,
    COUNT(bi.bill_item_id)                AS item_count,
    COALESCE(SUM(bi.line_total), 0)       AS total_revenue
FROM bill_items bi
         LEFT JOIN services s ON bi.service_id = s.service_id
         JOIN bills b ON bi.bill_id = b.bill_id
WHERE b.status != 'Draft'
  AND DATE(b.bill_date) >= CURDATE() - INTERVAL 30 DAY
GROUP BY COALESCE(s.service_category, 'Other')
ORDER BY total_revenue DESC;

-- ---------------------------------------------------------------------------
-- Seed: ensure services table has standard entries (idempotent)
-- ---------------------------------------------------------------------------
INSERT IGNORE INTO services
    (service_code, service_name, service_category, unit_price, tax_percentage)
VALUES
    ('CONS-GEN',  'General Consultation',       'Consultation',  2000.00, 0.00),
    ('CONS-SPEC', 'Specialist Consultation',     'Consultation',  3500.00, 0.00),
    ('CONS-EMER', 'Emergency Consultation',      'Consultation',  5000.00, 0.00),
    ('LAB-CBC',   'Complete Blood Count',        'Laboratory',    1200.00, 0.00),
    ('LAB-LFT',   'Liver Function Test',         'Laboratory',    2500.00, 0.00),
    ('LAB-RFT',   'Renal Function Test',         'Laboratory',    2200.00, 0.00),
    ('LAB-LPS',   'Lipid Profile',               'Laboratory',    3000.00, 0.00),
    ('RAD-XRAY',  'X-Ray',                       'Radiology',     3500.00, 0.00),
    ('RAD-US',    'Ultrasound Scan',             'Radiology',     6000.00, 0.00),
    ('RAD-CT',    'CT Scan',                     'Radiology',    18000.00, 0.00),
    ('RAD-MRI',   'MRI Scan',                    'Radiology',    35000.00, 0.00),
    ('PROC-ECG',  'Electrocardiogram (ECG)',     'Procedure',     2500.00, 0.00),
    ('PROC-ECHO', 'Echocardiogram',              'Procedure',    12000.00, 0.00),
    ('ROOM-GEN',  'General Ward (per day)',      'Room Charges',  3500.00, 0.00),
    ('ROOM-PRIV', 'Private Room (per day)',      'Room Charges',  8000.00, 0.00),
    ('ROOM-ICU',  'ICU (per day)',               'Room Charges', 25000.00, 0.00);

-- ---------------------------------------------------------------------------
-- Performance indexes (idempotent — DROP before CREATE)
-- ---------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_bills_status_date   ON bills;
DROP INDEX IF EXISTS idx_bills_patient_date  ON bills;
DROP INDEX IF EXISTS idx_payments_method     ON payments;
DROP INDEX IF EXISTS idx_claims_status       ON insurance_claims;

CREATE INDEX idx_bills_status_date   ON bills (status, bill_date DESC);
CREATE INDEX idx_bills_patient_date  ON bills (patient_id, bill_date DESC);
CREATE INDEX idx_payments_method     ON payments (payment_method, payment_date DESC);
CREATE INDEX idx_claims_status       ON insurance_claims (status, claim_date DESC);
