-- ============================================================
-- EMR Data Patch
-- FIX 1: Populate test_result for completed lab tests
-- FIX 2: Populate treatment_plan and notes for medical records
-- Idempotent — only updates NULL / empty rows
-- Run AFTER: lab_tests_seed.sql, SMARTCARE_COMPLETE_DATABASE.sql
-- ============================================================

-- ── FIX 1: lab_tests.test_result ────────────────────────────
-- Completed tests should have a result; pending ones stay NULL

UPDATE lab_tests
SET
    test_result = CASE (test_id MOD 8)
        WHEN 0 THEN 'All values within normal reference range'
        WHEN 1 THEN 'WBC: 7.4, Hb: 13.8, Platelets: 224 — Normal'
        WHEN 2 THEN 'FBS: 5.2 mmol/L — Normal fasting range'
        WHEN 3 THEN 'Cholesterol: 4.8, LDL: 2.9, HDL: 1.4 — Acceptable'
        WHEN 4 THEN 'No significant radiological abnormality detected'
        WHEN 5 THEN 'Sinus rhythm, HR 76 bpm — Normal ECG'
        WHEN 6 THEN 'Culture: No growth after 48h — Negative'
        ELSE        'Results reviewed; within expected clinical limits'
    END,
    normal_range = CASE (test_id MOD 6)
        WHEN 0 THEN 'WBC 4.0–11.0 × 10³/µL; Hb 12–16 g/dL'
        WHEN 1 THEN '3.9–5.5 mmol/L (fasting)'
        WHEN 2 THEN 'Total cholesterol < 5.0 mmol/L'
        WHEN 3 THEN 'TSH 0.4–4.0 mIU/L; T4 9–25 pmol/L'
        WHEN 4 THEN 'Creatinine 62–106 µmol/L (female); 80–115 µmol/L (male)'
        ELSE        'Refer to laboratory reference range'
    END,
    result_date = DATE_ADD(test_date, INTERVAL (1 + (test_id MOD 3)) DAY)
WHERE status = 'Completed'
  AND (test_result IS NULL OR test_result = '');

-- ── FIX 2a: medical_records.notes ───────────────────────────
-- notes is NOT encrypted — plain text update is safe

UPDATE medical_records
SET notes = CASE (record_id MOD 7)
    WHEN 0 THEN 'Patient counselled on lifestyle modifications. Follow-up in 2 weeks.'
    WHEN 1 THEN 'Vital signs stable. Patient responding well to current treatment plan.'
    WHEN 2 THEN 'Advised rest and adequate hydration. Review if symptoms worsen after 48 h.'
    WHEN 3 THEN 'Patient educated on medication compliance. Annual review scheduled.'
    WHEN 4 THEN 'No acute distress noted on examination. Discharged with written instructions.'
    WHEN 5 THEN 'Referred to physiotherapy. Ice packs and analgesics for 5 days.'
    ELSE        'Patient advised to follow up with specialist if no improvement within 7 days.'
END
WHERE notes IS NULL OR notes = '';

-- ── FIX 2b: medical_records.treatment_plan ──────────────────
-- treatment_plan is AES-256-GCM encrypted at the Java layer.
-- EncryptionService.decrypt() gracefully returns plain text
-- as-is when the value does not match the IV:ciphertext format,
-- so inserting plain text here is safe for demo/seed data.

UPDATE medical_records
SET treatment_plan = CASE (record_id MOD 8)
    WHEN 0 THEN 'Prescribed medication regimen; rest and oral hydration. Avoid strenuous activity for 1 week.'
    WHEN 1 THEN 'Continue current antihypertensive medications. Low-sodium diet. BP monitoring twice weekly.'
    WHEN 2 THEN 'Antibiotic course for 7 days. Paracetamol 500 mg TDS for fever. Adequate fluid intake.'
    WHEN 3 THEN 'Physiotherapy referral for 6 sessions. Anti-inflammatory NSAID. Ice packs to affected area.'
    WHEN 4 THEN 'Metformin 500 mg BD. HbA1c review in 3 months. Dietary counselling with nutritionist.'
    WHEN 5 THEN 'Nebulisation with salbutamol. Prednisolone 5-day course. Inhaler technique reviewed.'
    WHEN 6 THEN 'IV fluids for rehydration. Anti-emetics and antispasmodics. Soft diet until symptoms resolve.'
    ELSE        'Watchful waiting with symptomatic treatment. Review in 1 week; escalate if no improvement.'
END
WHERE treatment_plan IS NULL OR treatment_plan = '';

-- ── Verify ──────────────────────────────────────────────────
SELECT
    (SELECT COUNT(*) FROM lab_tests  WHERE status='Completed' AND test_result IS NOT NULL) AS lab_results_filled,
    (SELECT COUNT(*) FROM lab_tests  WHERE status='Completed' AND test_result IS NULL)     AS lab_results_still_null,
    (SELECT COUNT(*) FROM medical_records WHERE notes IS NOT NULL AND notes != '')          AS records_with_notes,
    (SELECT COUNT(*) FROM medical_records WHERE treatment_plan IS NOT NULL
                                             AND treatment_plan != '')                      AS records_with_treatment_plan;
