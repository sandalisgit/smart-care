-- ============================================================
-- SmartCare EMR Schema Patch
-- FR-21: AES-256-GCM encrypted clinical data
-- FR-22: EMR entries — diagnosis, prescriptions, lab orders
-- FR-23: Full audit trail on updates
-- FR-24: Document upload and storage
-- FR-27: Drug interaction data store
-- FR-29: RBAC-restricted access
-- ============================================================

-- ── Core Medical Records ────────────────────────────────────

CREATE TABLE IF NOT EXISTS medical_records (
    record_id           INT PRIMARY KEY AUTO_INCREMENT,
    patient_id          INT NOT NULL,
    doctor_id           INT NOT NULL,
    appointment_id      INT NULL,
    admission_id        INT NULL,
    visit_type          ENUM('Consultation','Follow-up','Emergency','Lab Review',
                             'Surgery','Telehealth','Discharge') DEFAULT 'Consultation',
    chief_complaint     VARCHAR(500) NOT NULL,
    symptoms            TEXT,                       -- AES-256-GCM encrypted (FR-21)
    diagnosis           TEXT,                       -- AES-256-GCM encrypted (FR-21)
    diagnosis_icd10     VARCHAR(20) NULL,           -- e.g. "I10", "J18.9"
    treatment_plan      TEXT,                       -- AES-256-GCM encrypted (FR-21)
    vital_signs         JSON NULL,                  -- {bp, temp, pulse, o2sat, rr, weight, height}
    notes               TEXT NULL,                  -- free clinical notes (NOT encrypted — not PII)
    follow_up_date      DATE NULL,
    record_date         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_mr_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
    CONSTRAINT fk_mr_doctor  FOREIGN KEY (doctor_id)  REFERENCES doctors(doctor_id),
    INDEX idx_mr_patient (patient_id),
    INDEX idx_mr_date    (record_date),
    INDEX idx_mr_appt    (appointment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── Prescriptions ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS prescriptions (
    prescription_id INT PRIMARY KEY AUTO_INCREMENT,
    patient_id      INT NOT NULL,
    doctor_id       INT NOT NULL,
    record_id       INT NOT NULL,
    prescription_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    validity_days   INT DEFAULT 30,
    notes           TEXT NULL,
    status          ENUM('Active','Dispensed','Expired','Cancelled') DEFAULT 'Active',
    dispensed_at    TIMESTAMP NULL,
    dispensed_by    INT NULL,
    CONSTRAINT fk_rx_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
    CONSTRAINT fk_rx_record  FOREIGN KEY (record_id)  REFERENCES medical_records(record_id),
    INDEX idx_rx_patient (patient_id),
    INDEX idx_rx_record  (record_id),
    INDEX idx_rx_status  (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS prescription_items (
    item_id           INT PRIMARY KEY AUTO_INCREMENT,
    prescription_id   INT NOT NULL,
    medicine_name     VARCHAR(200) NOT NULL,
    dosage            VARCHAR(100) NOT NULL,        -- e.g. "500mg"
    frequency         VARCHAR(100) NOT NULL,        -- e.g. "Twice daily"
    duration_days     INT NOT NULL,
    quantity          INT NOT NULL,
    instructions      TEXT NULL,                    -- e.g. "Take with food"
    CONSTRAINT fk_pi_rx FOREIGN KEY (prescription_id)
        REFERENCES prescriptions(prescription_id) ON DELETE CASCADE,
    INDEX idx_pi_rx (prescription_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── Lab Tests / Orders ──────────────────────────────────────

CREATE TABLE IF NOT EXISTS lab_tests (
    test_id         INT PRIMARY KEY AUTO_INCREMENT,
    patient_id      INT NOT NULL,
    doctor_id       INT NOT NULL,
    record_id       INT NULL,
    test_name       VARCHAR(200) NOT NULL,
    test_type       VARCHAR(100) NOT NULL,          -- Haematology, Biochemistry, Radiology, etc.
    status          ENUM('Ordered','Sample Collected','In Progress','Completed','Cancelled')
                    DEFAULT 'Ordered',
    urgency         ENUM('Routine','Urgent','STAT') DEFAULT 'Routine',
    test_date       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    result_date     TIMESTAMP NULL,
    test_result     TEXT NULL,
    normal_range    VARCHAR(200) NULL,
    technician_id   INT NULL,
    cost            DECIMAL(10,2) DEFAULT 0.00,
    result_file     VARCHAR(500) NULL,              -- path for uploaded PDF/image result
    CONSTRAINT fk_lt_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
    INDEX idx_lt_patient (patient_id),
    INDEX idx_lt_status  (status),
    INDEX idx_lt_date    (test_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── Clinical Notes ─────────────────────────────────────────
-- Separate from medical_records.notes for granular audit and encryption

CREATE TABLE IF NOT EXISTS clinical_notes (
    note_id         INT PRIMARY KEY AUTO_INCREMENT,
    patient_id      INT NOT NULL,
    staff_id        INT NOT NULL,               -- user_id of author (Doctor or Nurse)
    record_id       INT NULL,
    note_type       ENUM('Progress','SOAP','Nursing','Discharge','Procedure','Other')
                    DEFAULT 'Progress',
    encrypted_content TEXT NOT NULL,            -- AES-256-GCM encrypted (FR-21)
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_cn_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
    INDEX idx_cn_patient (patient_id),
    INDEX idx_cn_staff   (staff_id),
    INDEX idx_cn_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── EMR Documents ──────────────────────────────────────────

CREATE TABLE IF NOT EXISTS emr_documents (
    doc_id          INT PRIMARY KEY AUTO_INCREMENT,
    patient_id      INT NOT NULL,
    uploaded_by     INT NOT NULL,               -- user_id
    record_id       INT NULL,
    document_type   ENUM('Lab Result','X-Ray','ECG','Scan','Prescription',
                         'Referral','Consent','Other') NOT NULL,
    file_name       VARCHAR(255) NOT NULL,
    file_path       VARCHAR(500) NOT NULL,      -- relative path under uploads/emr/
    file_size_kb    INT NULL,
    mime_type       VARCHAR(100) NULL,
    description     VARCHAR(500) NULL,
    upload_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_doc_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
    INDEX idx_doc_patient (patient_id),
    INDEX idx_doc_date    (upload_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── Drug Interactions Knowledge Base ──────────────────────
-- Seeded from DrugBank open data + FDA SPL (public domain, NFR-34)

CREATE TABLE IF NOT EXISTS drug_interactions (
    interaction_id  INT PRIMARY KEY AUTO_INCREMENT,
    drug_a          VARCHAR(200) NOT NULL,
    drug_b          VARCHAR(200) NOT NULL,
    severity        ENUM('Contraindicated','Major','Moderate','Minor') NOT NULL,
    description     TEXT NOT NULL,
    mechanism       VARCHAR(500) NULL,
    management      VARCHAR(500) NULL,
    source          VARCHAR(100) DEFAULT 'DrugBank-Open',
    UNIQUE INDEX uq_drug_pair (drug_a, drug_b),
    INDEX idx_di_drug_a (drug_a),
    INDEX idx_di_drug_b (drug_b)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed common interactions (DrugBank open data subset — NFR-34)
INSERT IGNORE INTO drug_interactions
    (drug_a, drug_b, severity, description, mechanism, management)
VALUES
('Warfarin',    'Aspirin',        'Major',           'Increased bleeding risk (INR elevation)',           'Synergistic anticoagulation + platelet inhibition', 'Monitor INR closely; consider PPI co-prescription'),
('Warfarin',    'Ibuprofen',      'Major',           'Increased risk of GI bleeding and INR elevation',   'CYP2C9 inhibition by ibuprofen',                   'Use paracetamol instead; monitor INR'),
('Warfarin',    'Naproxen',       'Major',           'Enhanced anticoagulant effect and GI bleeding',     'CYP2C9 inhibition',                                'Avoid combination; use paracetamol'),
('Metformin',   'Contrast Dye',   'Contraindicated', 'Risk of contrast-induced nephropathy and lactic acidosis', 'Renal impairment from contrast media',        'Hold Metformin 48h before and after contrast'),
('Simvastatin', 'Amiodarone',     'Contraindicated', 'Severe myopathy and rhabdomyolysis risk',           'CYP3A4 inhibition elevates simvastatin levels',    'Use low-dose statin (max 20mg) or switch to pravastatin'),
('Clopidogrel', 'Omeprazole',     'Moderate',        'Reduced clopidogrel antiplatelet efficacy',         'CYP2C19 inhibition reduces active metabolite',     'Use pantoprazole or famotidine instead'),
('ACE Inhibitor','Potassium',     'Major',           'Severe hyperkalaemia risk',                         'ACE inhibitors reduce aldosterone-mediated K+ excretion', 'Monitor serum potassium closely'),
('Digoxin',     'Amiodarone',     'Major',           'Digoxin toxicity due to elevated levels',           'P-glycoprotein inhibition reduces digoxin clearance', 'Reduce digoxin dose by 50%; monitor levels'),
('SSRIs',       'Tramadol',       'Contraindicated', 'Serotonin syndrome risk',                           'Additive serotonergic activity',                   'Avoid combination; use alternative analgesic'),
('Lithium',     'NSAIDs',         'Major',           'Lithium toxicity due to decreased renal clearance', 'NSAIDs reduce renal prostaglandins; elevated lithium', 'Monitor lithium levels; use paracetamol'),
('Rifampicin',  'Warfarin',       'Major',           'Markedly reduced warfarin effect',                  'CYP2C9 induction accelerates warfarin metabolism', 'Increase warfarin dose; monitor INR every 2-3 days'),
('Ciprofloxacin','Theophylline',  'Major',           'Theophylline toxicity (nausea, seizures)',           'CYP1A2 inhibition reduces theophylline clearance', 'Monitor theophylline levels; reduce dose'),
('Methotrexate','NSAIDs',         'Major',           'Methotrexate toxicity due to reduced renal excretion', 'NSAID-mediated renal competition',              'Avoid NSAIDs; use paracetamol'),
('Azithromycin','QT-prolonging',  'Major',           'Additive QT prolongation and torsades de pointes',  'Additive cardiac K+ channel blockade',             'ECG monitoring; avoid combination if possible'),
('Amlodipine',  'Simvastatin',    'Moderate',        'Increased simvastatin exposure',                    'CYP3A4 inhibition by amlodipine',                  'Limit simvastatin to 20mg/day'),
('Metronidazole','Alcohol',       'Contraindicated', 'Disulfiram-like reaction (flushing, vomiting)',      'Inhibition of acetaldehyde dehydrogenase',         'Abstain from alcohol during and 48h after therapy'),
('Fluconazole',  'Warfarin',      'Contraindicated', 'Severe INR elevation and haemorrhage',              'CYP2C9 potent inhibition',                         'Avoid; use topical antifungal; if systemic needed reduce warfarin 50%');

-- ── ICD-10 Code Reference ──────────────────────────────────
-- Subset of ICD-10-CM 2026 (public domain WHO/CDC data — NFR-34)

CREATE TABLE IF NOT EXISTS icd_codes (
    code        VARCHAR(10) PRIMARY KEY,
    description VARCHAR(300) NOT NULL,
    category    VARCHAR(100) NOT NULL,
    INDEX idx_icd_desc (description(100)),
    INDEX idx_icd_cat  (category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO icd_codes (code, description, category) VALUES
('A01.0','Typhoid fever','Infectious Diseases'),
('A09',  'Other gastroenteritis and colitis of infectious and unspecified origin','Infectious Diseases'),
('A15',  'Respiratory tuberculosis','Infectious Diseases'),
('A41',  'Other sepsis','Infectious Diseases'),
('A90',  'Dengue fever (classical dengue)','Infectious Diseases'),
('B01',  'Varicella (chickenpox)','Infectious Diseases'),
('B20',  'Human immunodeficiency virus (HIV) disease','Infectious Diseases'),
('D64',  'Other anaemias','Blood Disorders'),
('E03',  'Other hypothyroidism','Endocrine'),
('E10',  'Type 1 diabetes mellitus','Endocrine'),
('E11',  'Type 2 diabetes mellitus','Endocrine'),
('E11.9','Type 2 diabetes mellitus without complications','Endocrine'),
('E11.65','Type 2 diabetes mellitus with hyperglycaemia','Endocrine'),
('E66',  'Overweight and obesity','Endocrine'),
('F32',  'Major depressive disorder, single episode','Mental Health'),
('F41',  'Other anxiety disorders','Mental Health'),
('F41.1','Generalised anxiety disorder','Mental Health'),
('G03',  'Meningitis due to other and unspecified causes','Nervous System'),
('G43',  'Migraine','Nervous System'),
('G44.2','Tension-type headache','Nervous System'),
('H81.1','Benign paroxysmal vertigo','Ear / ENT'),
('I10',  'Essential (primary) hypertension','Cardiovascular'),
('I16',  'Hypertensive crisis','Cardiovascular'),
('I20',  'Angina pectoris','Cardiovascular'),
('I21',  'Acute myocardial infarction','Cardiovascular'),
('I25',  'Chronic ischaemic heart disease','Cardiovascular'),
('I26',  'Pulmonary embolism','Cardiovascular'),
('I48',  'Atrial fibrillation and flutter','Cardiovascular'),
('I50',  'Heart failure','Cardiovascular'),
('I82',  'Other venous embolism and thrombosis','Cardiovascular'),
('I95',  'Hypotension','Cardiovascular'),
('J06',  'Acute upper respiratory infections of multiple and unspecified sites','Respiratory'),
('J11',  'Influenza, virus not identified','Respiratory'),
('J18',  'Pneumonia, unspecified organism','Respiratory'),
('J18.9','Pneumonia, unspecified organism','Respiratory'),
('J40',  'Bronchitis, not specified as acute or chronic','Respiratory'),
('J44',  'Chronic obstructive pulmonary disease','Respiratory'),
('J45',  'Asthma','Respiratory'),
('K21',  'Gastro-oesophageal reflux disease','Digestive'),
('K27',  'Peptic ulcer, site unspecified','Digestive'),
('K29',  'Gastritis and duodenitis','Digestive'),
('K35',  'Acute appendicitis','Digestive'),
('K81',  'Cholecystitis','Digestive'),
('L03',  'Cellulitis and acute lymphangitis','Skin'),
('L23',  'Allergic contact dermatitis','Skin'),
('L50',  'Urticaria','Skin'),
('M05',  'Rheumatoid arthritis with rheumatoid factor','Musculoskeletal'),
('M19',  'Other and unspecified arthrosis','Musculoskeletal'),
('M47.8','Other spondylosis','Musculoskeletal'),
('M51.1','Thoracic, thoracolumbar and lumbosacral intervertebral disc degeneration','Musculoskeletal'),
('M54.5','Low back pain','Musculoskeletal'),
('M54.6','Pain in thoracic spine','Musculoskeletal'),
('M79',  'Other and unspecified soft tissue disorders','Musculoskeletal'),
('N20',  'Calculus of kidney and ureter','Genitourinary'),
('N39.0','Urinary tract infection, site not specified','Genitourinary'),
('R50',  'Fever of other and unknown origin','Symptoms/Signs'),
('U07.1','COVID-19, virus identified','COVID-19');

-- ── AI Drug Interaction Model Metadata ────────────────────
-- Tracks DL4J model versions and performance metrics (NFR-33)

CREATE TABLE IF NOT EXISTS ai_drug_interaction_log (
    log_id          INT PRIMARY KEY AUTO_INCREMENT,
    prescription_id INT NULL,
    patient_id      INT NOT NULL,
    doctor_id       INT NOT NULL,
    drugs_checked   TEXT NOT NULL,               -- JSON array of drug names
    interactions_found INT DEFAULT 0,
    has_major       TINYINT(1) DEFAULT 0,
    model_version   VARCHAR(30) DEFAULT 'kb-v1', -- 'dl4j-v1' once DL4J model loaded
    confidence_avg  DOUBLE NULL,
    checked_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    acknowledged_by INT NULL,
    acknowledged_at TIMESTAMP NULL,
    INDEX idx_aidil_patient (patient_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── Uploads directory placeholder ─────────────────────────
-- Actual files stored under: {webapp}/uploads/emr/{patientId}/{filename}
-- Servlet enforces: max 10MB, types: PDF/JPEG/PNG only (FR-24)
