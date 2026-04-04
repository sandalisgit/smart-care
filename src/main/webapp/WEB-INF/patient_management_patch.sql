-- ====================================================================
-- Patient Management Module — Schema Patch
-- SmartCare Hospital ERP | CSG3101 Group 21
-- Run AFTER SMARTCARE_COMPLETE_DATABASE.sql
--   mysql -u root -p hospital_erp < patient_management_patch.sql
-- ====================================================================
-- Adds performance indexes, a reporting view, and an audit helper
-- view for the Patient Management module (FR-01..FR-08, FR-77/78).
-- ====================================================================

USE hospital_erp;

-- ── Performance indexes (NFR-38: indexes on high-volume query columns) ──

-- Status filter index (for GET /api/patients?status=Active queries)
CREATE INDEX IF NOT EXISTS idx_patients_status
    ON patients (status);

-- Registration date index (for recent patients query, dashboard)
CREATE INDEX IF NOT EXISTS idx_patients_reg_date
    ON patients (registration_date DESC);

-- Composite index for gender + blood_group filter queries
CREATE INDEX IF NOT EXISTS idx_patients_gender_blood
    ON patients (gender, blood_group);

-- Full-text index for fast LIKE-based name / code search (FR-08)
-- Improves search() and searchWithFilters() query performance
CREATE FULLTEXT INDEX IF NOT EXISTS idx_patients_fulltext
    ON patients (first_name, last_name);

-- ── Reporting view (FR-04, FR-46, FR-59, FR-66) ────────────────────

-- Patient summary view — used by ReportServlet for PDF/CSV export
-- Note: national_id and allergies are stored AES-256-GCM encrypted;
-- they are decrypted in the Java layer by EncryptionService, never here.
CREATE OR REPLACE VIEW v_patient_summary AS
SELECT
    p.patient_id,
    p.patient_code,
    CONCAT(p.first_name, ' ', p.last_name)   AS full_name,
    p.first_name,
    p.last_name,
    p.date_of_birth,
    TIMESTAMPDIFF(YEAR, p.date_of_birth, CURDATE()) AS age,
    p.gender,
    p.blood_group,
    p.phone,
    p.email,
    p.city,
    p.state,
    p.country,
    p.insurance_provider,
    p.insurance_policy_number,
    p.chronic_conditions,
    p.height,
    p.weight,
    p.status,
    p.registration_date,
    COUNT(DISTINCT a.appointment_id)          AS total_appointments,
    MAX(a.appointment_date)                   AS last_appointment_date
FROM patients p
LEFT JOIN appointments a
    ON  a.patient_id = p.patient_id
    AND a.status NOT IN ('Cancelled')
GROUP BY p.patient_id;

-- ── Patient stats view for dashboard widget (FR-66, FR-68) ─────────

CREATE OR REPLACE VIEW v_patient_stats AS
SELECT
    COUNT(*)                                      AS total_patients,
    SUM(status = 'Active')                        AS active_patients,
    SUM(status = 'Inactive')                      AS inactive_patients,
    SUM(status = 'Deceased')                      AS deceased_patients,
    SUM(gender  = 'Male')                         AS male_count,
    SUM(gender  = 'Female')                       AS female_count,
    SUM(DATE(registration_date) = CURDATE())      AS registered_today,
    SUM(DATE(registration_date) >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)) AS registered_last_30_days
FROM patients;

-- ====================================================================
-- END OF PATCH
-- ====================================================================
