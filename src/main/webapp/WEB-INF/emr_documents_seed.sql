-- ============================================================
-- EMR Documents Seed Data  (emr_documents table)
-- 2-3 realistic documents per patient — 400-600 rows total
-- Idempotent: skips if table already has >= 10 rows
-- Run AFTER: SMARTCARE_COMPLETE_DATABASE.sql, emr_schema_patch.sql
-- ============================================================
-- document_type ENUM: 'Lab Result','X-Ray','ECG','Scan',
--                     'Prescription','Referral','Consent','Other'
-- uploaded_by  → users.user_id  (NOT employees.employee_id)
-- ============================================================

CREATE TABLE IF NOT EXISTS emr_documents (
    doc_id        INT PRIMARY KEY AUTO_INCREMENT,
    patient_id    INT NOT NULL,
    uploaded_by   INT NOT NULL,
    record_id     INT NULL,
    document_type ENUM('Lab Result','X-Ray','ECG','Scan','Prescription',
                       'Referral','Consent','Other') NOT NULL,
    file_name     VARCHAR(255) NOT NULL,
    file_path     VARCHAR(500) NOT NULL,
    file_size_kb  INT NULL,
    mime_type     VARCHAR(100) NULL,
    description   VARCHAR(500) NULL,
    upload_date   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_doc_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
    INDEX idx_doc_patient (patient_id),
    INDEX idx_doc_date    (upload_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── Seed procedure ───────────────────────────────────────────
DROP PROCEDURE IF EXISTS seed_emr_documents;

DELIMITER //

CREATE PROCEDURE seed_emr_documents()
seed_proc: BEGIN
    DECLARE done         INT DEFAULT FALSE;
    DECLARE p_id         INT;
    DECLARE u_id         INT;
    DECLARE existing_cnt INT;

    DECLARE patient_cur CURSOR FOR
        SELECT patient_id FROM patients ORDER BY patient_id LIMIT 250;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    -- Skip if already seeded
    SELECT COUNT(*) INTO existing_cnt FROM emr_documents;
    IF existing_cnt >= 10 THEN
        LEAVE seed_proc;
    END IF;

    -- Ensure at least one staff user exists
    SELECT user_id INTO u_id FROM users ORDER BY user_id LIMIT 1;
    IF u_id IS NULL THEN
        LEAVE seed_proc;
    END IF;

    OPEN patient_cur;
    p_loop: LOOP
        FETCH patient_cur INTO p_id;
        IF done THEN LEAVE p_loop; END IF;

        -- Pick a random staff user as uploader
        SELECT user_id INTO u_id FROM users ORDER BY RAND() LIMIT 1;

        -- ── Document 1: Lab result PDF ────────────────────────
        INSERT INTO emr_documents
            (patient_id, uploaded_by, document_type, file_name, file_path,
             file_size_kb, mime_type, description, upload_date)
        VALUES (
            p_id, u_id,
            'Lab Result',
            CASE (p_id MOD 6)
                WHEN 0 THEN CONCAT('CBC_Report_PAT', LPAD(p_id,6,'0'), '.pdf')
                WHEN 1 THEN CONCAT('FBS_HbA1c_PAT', LPAD(p_id,6,'0'), '.pdf')
                WHEN 2 THEN CONCAT('Lipid_Profile_PAT', LPAD(p_id,6,'0'), '.pdf')
                WHEN 3 THEN CONCAT('LFT_RFT_PAT', LPAD(p_id,6,'0'), '.pdf')
                WHEN 4 THEN CONCAT('Thyroid_Panel_PAT', LPAD(p_id,6,'0'), '.pdf')
                ELSE        CONCAT('Blood_Report_PAT', LPAD(p_id,6,'0'), '.pdf')
            END,
            CONCAT('uploads/emr/', p_id, '/',
                CASE (p_id MOD 6)
                    WHEN 0 THEN CONCAT('CBC_Report_PAT', LPAD(p_id,6,'0'), '.pdf')
                    WHEN 1 THEN CONCAT('FBS_HbA1c_PAT', LPAD(p_id,6,'0'), '.pdf')
                    WHEN 2 THEN CONCAT('Lipid_Profile_PAT', LPAD(p_id,6,'0'), '.pdf')
                    WHEN 3 THEN CONCAT('LFT_RFT_PAT', LPAD(p_id,6,'0'), '.pdf')
                    WHEN 4 THEN CONCAT('Thyroid_Panel_PAT', LPAD(p_id,6,'0'), '.pdf')
                    ELSE        CONCAT('Blood_Report_PAT', LPAD(p_id,6,'0'), '.pdf')
                END),
            CASE (p_id MOD 5) WHEN 0 THEN 120 WHEN 1 THEN 245 WHEN 2 THEN 89 WHEN 3 THEN 310 ELSE 175 END,
            'application/pdf',
            CASE (p_id MOD 6)
                WHEN 0 THEN 'Complete Blood Count with differential — haematology panel'
                WHEN 1 THEN 'Fasting Blood Sugar and HbA1c results'
                WHEN 2 THEN 'Full lipid profile including LDL, HDL, triglycerides'
                WHEN 3 THEN 'Liver and renal function test results'
                WHEN 4 THEN 'Thyroid function test — TSH, T3, T4'
                ELSE        'Routine blood test panel'
            END,
            DATE_SUB(CURDATE(), INTERVAL (p_id MOD 90) DAY)
        );

        -- ── Document 2: Imaging or ECG ────────────────────────
        INSERT INTO emr_documents
            (patient_id, uploaded_by, document_type, file_name, file_path,
             file_size_kb, mime_type, description, upload_date)
        VALUES (
            p_id, u_id,
            CASE (p_id MOD 5)
                WHEN 0 THEN 'X-Ray'
                WHEN 1 THEN 'ECG'
                WHEN 2 THEN 'Scan'
                WHEN 3 THEN 'X-Ray'
                ELSE        'Scan'
            END,
            CASE (p_id MOD 5)
                WHEN 0 THEN CONCAT('Chest_Xray_PA_PAT', LPAD(p_id,6,'0'), '.jpg')
                WHEN 1 THEN CONCAT('ECG_12Lead_PAT', LPAD(p_id,6,'0'), '.pdf')
                WHEN 2 THEN CONCAT('Ultrasound_Abdomen_PAT', LPAD(p_id,6,'0'), '.jpg')
                WHEN 3 THEN CONCAT('Lumbosacral_Xray_PAT', LPAD(p_id,6,'0'), '.jpg')
                ELSE        CONCAT('CT_Scan_PAT', LPAD(p_id,6,'0'), '.jpg')
            END,
            CONCAT('uploads/emr/', p_id, '/',
                CASE (p_id MOD 5)
                    WHEN 0 THEN CONCAT('Chest_Xray_PA_PAT', LPAD(p_id,6,'0'), '.jpg')
                    WHEN 1 THEN CONCAT('ECG_12Lead_PAT', LPAD(p_id,6,'0'), '.pdf')
                    WHEN 2 THEN CONCAT('Ultrasound_Abdomen_PAT', LPAD(p_id,6,'0'), '.jpg')
                    WHEN 3 THEN CONCAT('Lumbosacral_Xray_PAT', LPAD(p_id,6,'0'), '.jpg')
                    ELSE        CONCAT('CT_Scan_PAT', LPAD(p_id,6,'0'), '.jpg')
                END),
            CASE (p_id MOD 5)
                WHEN 0 THEN 2840 WHEN 1 THEN 195 WHEN 2 THEN 3120
                WHEN 3 THEN 2650 ELSE 4800
            END,
            CASE (p_id MOD 5) WHEN 1 THEN 'application/pdf' ELSE 'image/jpeg' END,
            CASE (p_id MOD 5)
                WHEN 0 THEN 'PA chest X-ray — reviewed by radiologist'
                WHEN 1 THEN '12-lead ECG — cardiac rhythm assessment'
                WHEN 2 THEN 'Abdominal ultrasound — hepatobiliary system'
                WHEN 3 THEN 'Lumbosacral X-ray — spinal assessment'
                ELSE        'CT scan — detailed cross-sectional imaging'
            END,
            DATE_SUB(CURDATE(), INTERVAL (p_id MOD 75) DAY)
        );

        -- ── Document 3: Prescription/Referral/Consent (every other patient) ──
        IF (p_id MOD 2) = 0 THEN
            INSERT INTO emr_documents
                (patient_id, uploaded_by, document_type, file_name, file_path,
                 file_size_kb, mime_type, description, upload_date)
            VALUES (
                p_id, u_id,
                CASE (p_id MOD 4)
                    WHEN 0 THEN 'Prescription'
                    WHEN 1 THEN 'Referral'
                    WHEN 2 THEN 'Consent'
                    ELSE        'Other'
                END,
                CASE (p_id MOD 4)
                    WHEN 0 THEN CONCAT('Prescription_PAT', LPAD(p_id,6,'0'), '.pdf')
                    WHEN 1 THEN CONCAT('Referral_Letter_PAT', LPAD(p_id,6,'0'), '.pdf')
                    WHEN 2 THEN CONCAT('Consent_Form_PAT', LPAD(p_id,6,'0'), '.pdf')
                    ELSE        CONCAT('Discharge_Summary_PAT', LPAD(p_id,6,'0'), '.pdf')
                END,
                CONCAT('uploads/emr/', p_id, '/',
                    CASE (p_id MOD 4)
                        WHEN 0 THEN CONCAT('Prescription_PAT', LPAD(p_id,6,'0'), '.pdf')
                        WHEN 1 THEN CONCAT('Referral_Letter_PAT', LPAD(p_id,6,'0'), '.pdf')
                        WHEN 2 THEN CONCAT('Consent_Form_PAT', LPAD(p_id,6,'0'), '.pdf')
                        ELSE        CONCAT('Discharge_Summary_PAT', LPAD(p_id,6,'0'), '.pdf')
                    END),
                CASE (p_id MOD 4)
                    WHEN 0 THEN 95 WHEN 1 THEN 140 WHEN 2 THEN 210 ELSE 320
                END,
                'application/pdf',
                CASE (p_id MOD 4)
                    WHEN 0 THEN 'Signed prescription — current medication regimen'
                    WHEN 1 THEN 'Referral letter to specialist consultant'
                    WHEN 2 THEN 'Signed patient consent form for procedure'
                    ELSE        'Discharge summary with follow-up instructions'
                END,
                DATE_SUB(CURDATE(), INTERVAL (p_id MOD 60) DAY)
            );
        END IF;

    END LOOP p_loop;
    CLOSE patient_cur;
END seed_proc //

DELIMITER ;

CALL seed_emr_documents();
DROP PROCEDURE IF EXISTS seed_emr_documents;

SELECT CONCAT('emr_documents seeded: ', COUNT(*), ' rows') AS result FROM emr_documents;
