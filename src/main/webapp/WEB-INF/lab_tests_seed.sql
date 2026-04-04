-- ============================================================
-- Lab Tests Seed Data  (lab_tests table)
-- 2-3 realistic orders per patient — 400-600 rows total
-- Idempotent: skips if table already has >= 10 rows
-- Run AFTER: SMARTCARE_COMPLETE_DATABASE.sql, emr_schema_patch.sql
-- ============================================================

-- Ensure the table exists with the correct schema
CREATE TABLE IF NOT EXISTS lab_tests (
    test_id       INT PRIMARY KEY AUTO_INCREMENT,
    patient_id    INT NOT NULL,
    doctor_id     INT NOT NULL,
    record_id     INT NULL,
    test_name     VARCHAR(200) NOT NULL,
    test_type     VARCHAR(100) NOT NULL,
    status        ENUM('Ordered','Sample Collected','In Progress','Completed','Cancelled')
                  DEFAULT 'Ordered',
    urgency       ENUM('Routine','Urgent','STAT') DEFAULT 'Routine',
    test_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    result_date   TIMESTAMP NULL,
    test_result   TEXT NULL,
    normal_range  VARCHAR(200) NULL,
    technician_id INT NULL,
    cost          DECIMAL(10,2) DEFAULT 0.00,
    result_file   VARCHAR(500) NULL,
    CONSTRAINT fk_lt_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
    INDEX idx_lt_patient (patient_id),
    INDEX idx_lt_status  (status),
    INDEX idx_lt_date    (test_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── Seed procedure ───────────────────────────────────────────
DROP PROCEDURE IF EXISTS seed_lab_tests;

DELIMITER //

CREATE PROCEDURE seed_lab_tests()
seed_proc: BEGIN
    DECLARE done         INT DEFAULT FALSE;
    DECLARE p_id         INT;
    DECLARE d_id         INT;
    DECLARE existing_cnt INT;

    DECLARE patient_cur CURSOR FOR
        SELECT patient_id FROM patients ORDER BY patient_id LIMIT 250;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    -- Skip if already seeded
    SELECT COUNT(*) INTO existing_cnt FROM lab_tests;
    IF existing_cnt >= 10 THEN
        LEAVE seed_proc;
    END IF;

    -- Fallback doctor id in case RAND() returns NULL
    SELECT doctor_id INTO d_id FROM doctors ORDER BY doctor_id LIMIT 1;
    IF d_id IS NULL THEN
        LEAVE seed_proc;
    END IF;

    OPEN patient_cur;
    p_loop: LOOP
        FETCH patient_cur INTO p_id;
        IF done THEN LEAVE p_loop; END IF;

        -- Rotate through available doctors for realism
        SELECT doctor_id INTO d_id FROM doctors ORDER BY RAND() LIMIT 1;

        -- ── Test 1: Haematology ───────────────────────────────
        INSERT INTO lab_tests
            (patient_id, doctor_id, test_name, test_type, urgency, status,
             cost, test_date, test_result, normal_range)
        VALUES (
            p_id, d_id,
            CASE (p_id MOD 4)
                WHEN 0 THEN 'Complete Blood Count (CBC)'
                WHEN 1 THEN 'Full Blood Count (FBC)'
                WHEN 2 THEN 'ESR (Erythrocyte Sedimentation Rate)'
                ELSE        'Peripheral Blood Film'
            END,
            'Haematology',
            CASE (p_id MOD 7) WHEN 0 THEN 'STAT' WHEN 1 THEN 'Urgent' ELSE 'Routine' END,
            CASE (p_id MOD 5)
                WHEN 0 THEN 'Ordered'
                WHEN 1 THEN 'Sample Collected'
                WHEN 2 THEN 'In Progress'
                ELSE        'Completed'
            END,
            CASE (p_id MOD 4) WHEN 0 THEN 450.00 WHEN 1 THEN 520.00 WHEN 2 THEN 280.00 ELSE 380.00 END,
            DATE_SUB(CURDATE(), INTERVAL (p_id MOD 90) DAY),
            CASE (p_id MOD 5)
                WHEN 3 THEN 'WBC: 7.2 x10³/µL, Hb: 13.4 g/dL, Plt: 220 x10³/µL — Normal'
                WHEN 4 THEN 'WBC: 11.5 x10³/µL (elevated), Hb: 12.1 g/dL — Possible infection'
                ELSE NULL
            END,
            'WBC: 4.0–11.0, Hb: 12.0–16.0 g/dL'
        );

        -- ── Test 2: Biochemistry ──────────────────────────────
        INSERT INTO lab_tests
            (patient_id, doctor_id, test_name, test_type, urgency, status,
             cost, test_date, test_result, normal_range)
        VALUES (
            p_id, d_id,
            CASE (p_id MOD 8)
                WHEN 0 THEN 'Fasting Blood Sugar (FBS)'
                WHEN 1 THEN 'HbA1c (Glycated Haemoglobin)'
                WHEN 2 THEN 'Lipid Profile'
                WHEN 3 THEN 'Liver Function Test (LFT)'
                WHEN 4 THEN 'Renal Function Test (RFT)'
                WHEN 5 THEN 'Thyroid Panel (TSH, T3, T4)'
                WHEN 6 THEN 'Serum Electrolytes (Na, K, Cl)'
                ELSE        'C-Reactive Protein (CRP)'
            END,
            'Biochemistry',
            CASE (p_id MOD 6) WHEN 0 THEN 'Urgent' WHEN 1 THEN 'STAT' ELSE 'Routine' END,
            CASE (p_id MOD 4)
                WHEN 0 THEN 'Completed'
                WHEN 1 THEN 'Ordered'
                WHEN 2 THEN 'Completed'
                ELSE        'In Progress'
            END,
            CASE (p_id MOD 8)
                WHEN 0 THEN 320.00 WHEN 1 THEN 850.00 WHEN 2 THEN 1200.00 WHEN 3 THEN 1500.00
                WHEN 4 THEN 1800.00 WHEN 5 THEN 2200.00 WHEN 6 THEN 950.00 ELSE 750.00
            END,
            DATE_SUB(CURDATE(), INTERVAL (p_id MOD 60) DAY),
            CASE (p_id MOD 4)
                WHEN 0 THEN 'FBS: 5.8 mmol/L — Normal fasting range'
                WHEN 2 THEN 'HbA1c: 7.2% — Slightly above target; lifestyle modification advised'
                ELSE NULL
            END,
            CASE (p_id MOD 8)
                WHEN 0 THEN '3.9–5.5 mmol/L (fasting)'
                WHEN 1 THEN '< 7.0% (diabetic target)'
                WHEN 2 THEN 'Total cholesterol < 5.0 mmol/L'
                ELSE NULL
            END
        );

        -- ── Test 3: Radiology / Microbiology (alternate patients) ──
        IF (p_id MOD 2) = 0 THEN
            INSERT INTO lab_tests
                (patient_id, doctor_id, test_name, test_type, urgency, status,
                 cost, test_date, test_result)
            VALUES (
                p_id, d_id,
                CASE (p_id MOD 6)
                    WHEN 0 THEN 'Chest X-Ray (PA View)'
                    WHEN 1 THEN 'ECG (12-Lead)'
                    WHEN 2 THEN 'Urine Full Report & Culture'
                    WHEN 3 THEN 'Stool Microscopy & Culture'
                    WHEN 4 THEN 'Ultrasound Abdomen & Pelvis'
                    ELSE        'COVID-19 Antigen Test'
                END,
                CASE (p_id MOD 6)
                    WHEN 0 THEN 'Radiology'   WHEN 1 THEN 'Cardiology'
                    WHEN 2 THEN 'Microbiology' WHEN 3 THEN 'Microbiology'
                    WHEN 4 THEN 'Radiology'   ELSE 'Virology'
                END,
                CASE (p_id MOD 7) WHEN 0 THEN 'STAT' WHEN 1 THEN 'Urgent' ELSE 'Routine' END,
                CASE (p_id MOD 3)
                    WHEN 0 THEN 'Ordered'
                    WHEN 1 THEN 'Completed'
                    ELSE        'In Progress'
                END,
                CASE (p_id MOD 6)
                    WHEN 0 THEN 2500.00 WHEN 1 THEN 1800.00 WHEN 2 THEN 600.00
                    WHEN 3 THEN 550.00  WHEN 4 THEN 3200.00 ELSE 1500.00
                END,
                DATE_SUB(CURDATE(), INTERVAL (p_id MOD 45) DAY),
                CASE (p_id MOD 3) WHEN 1 THEN 'No significant abnormality detected' ELSE NULL END
            );
        END IF;

    END LOOP p_loop;
    CLOSE patient_cur;
END seed_proc //

DELIMITER ;

CALL seed_lab_tests();
DROP PROCEDURE IF EXISTS seed_lab_tests;

SELECT CONCAT('lab_tests seeded: ', COUNT(*), ' rows') AS result FROM lab_tests;
