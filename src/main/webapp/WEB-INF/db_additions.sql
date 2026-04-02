-- ====================================================================
-- SMART CARE — Additional Tables (run after HOSPITAL_DATABASE.sql)
-- These 3 tables extend the existing schema for AI + MFA features
-- ====================================================================

USE hospital_erp;

-- 1. No-show prediction features (AI training data for FR-17)
CREATE TABLE IF NOT EXISTS no_show_features (
    id INT PRIMARY KEY AUTO_INCREMENT,
    appointment_id INT NOT NULL,
    patient_age INT,
    day_of_week INT,
    hour_of_day INT,
    days_until_appointment INT,
    previous_no_shows INT DEFAULT 0,
    appointment_type_encoded INT DEFAULT 0,
    prediction_score DECIMAL(5,4),
    actual_outcome ENUM('Showed','No-Show') NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE,
    UNIQUE KEY unique_appt (appointment_id)
);

-- 2. Daily bed occupancy history (LSTM training data for FR-56)
CREATE TABLE IF NOT EXISTS bed_occupancy_history (
    id INT PRIMARY KEY AUTO_INCREMENT,
    ward_id INT NOT NULL,
    record_date DATE NOT NULL,
    total_beds INT NOT NULL,
    occupied_beds INT NOT NULL,
    predicted_occupied INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (ward_id) REFERENCES wards(ward_id) ON DELETE CASCADE,
    UNIQUE KEY unique_ward_date (ward_id, record_date)
);

-- 3. TOTP MFA secrets per user (FR-72)
CREATE TABLE IF NOT EXISTS user_mfa (
    user_id INT PRIMARY KEY,
    totp_secret VARCHAR(64) NOT NULL,
    is_enabled BOOLEAN DEFAULT FALSE,
    enrolled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- 4. Temporary MFA tokens (used during 2-step login flow)
CREATE TABLE IF NOT EXISTS temp_mfa_tokens (
    user_id INT PRIMARY KEY,
    token VARCHAR(100) NOT NULL UNIQUE,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- 5. Drug interactions reference table (for FR-27 drug interaction check)
--    Populate with DrugBank open data or equivalent open dataset
CREATE TABLE IF NOT EXISTS drug_interactions (
    interaction_id INT PRIMARY KEY AUTO_INCREMENT,
    drug_a VARCHAR(200) NOT NULL,
    drug_b VARCHAR(200) NOT NULL,
    severity ENUM('Minor','Moderate','Major','Contraindicated') NOT NULL,
    description TEXT,
    source VARCHAR(100) DEFAULT 'DrugBank Open Data',
    INDEX idx_drug_a (drug_a(50)),
    INDEX idx_drug_b (drug_b(50))
);

-- 6. Add hash chain column to existing audit_log (FR-77)
-- Using procedure to safely add column only if it doesn't exist
DROP PROCEDURE IF EXISTS add_entry_hash_column;
DELIMITER //
CREATE PROCEDURE add_entry_hash_column()
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = 'hospital_erp'
      AND TABLE_NAME   = 'audit_log'
      AND COLUMN_NAME  = 'entry_hash'
  ) THEN
    ALTER TABLE audit_log ADD COLUMN entry_hash VARCHAR(64) NULL AFTER created_at;
  END IF;
END //
DELIMITER ;
CALL add_entry_hash_column();
DROP PROCEDURE IF EXISTS add_entry_hash_column;

-- 7. Sample drug interactions data (representative subset)
INSERT IGNORE INTO drug_interactions (drug_a, drug_b, severity, description) VALUES
('Warfarin', 'Aspirin', 'Major', 'Increased risk of bleeding when combined'),
('Warfarin', 'Ibuprofen', 'Major', 'NSAIDs inhibit platelet function and may increase anticoagulant effect'),
('Metformin', 'Alcohol', 'Moderate', 'Increased risk of lactic acidosis'),
('Simvastatin', 'Clarithromycin', 'Contraindicated', 'Severe risk of myopathy/rhabdomyolysis'),
('Lisinopril', 'Potassium', 'Moderate', 'Risk of hyperkalemia'),
('Clopidogrel', 'Omeprazole', 'Moderate', 'Omeprazole reduces clopidogrel antiplatelet effect'),
('Fluoxetine', 'Tramadol', 'Major', 'Risk of serotonin syndrome'),
('Digoxin', 'Amiodarone', 'Major', 'Amiodarone increases digoxin levels — risk of toxicity'),
('Ciprofloxacin', 'Antacids', 'Moderate', 'Antacids reduce ciprofloxacin absorption'),
('Methotrexate', 'Ibuprofen', 'Major', 'NSAIDs reduce methotrexate clearance — risk of toxicity'),
('Sildenafil', 'Nitrates', 'Contraindicated', 'Severe hypotension — potentially fatal'),
('Lithium', 'Ibuprofen', 'Major', 'NSAIDs reduce renal lithium clearance — lithium toxicity risk'),
('Atorvastatin', 'Erythromycin', 'Major', 'Increased statin levels — myopathy risk'),
('Theophylline', 'Ciprofloxacin', 'Major', 'Ciprofloxacin inhibits theophylline metabolism — toxicity risk'),
('Phenytoin', 'Fluconazole', 'Major', 'Fluconazole increases phenytoin levels — toxicity risk'),
('Heparin', 'Aspirin', 'Major', 'Combined anticoagulation increases bleeding risk'),
('Insulin', 'Alcohol', 'Moderate', 'Alcohol may mask symptoms of hypoglycaemia'),
('Carbamazepine', 'Erythromycin', 'Major', 'Erythromycin increases carbamazepine levels'),
('ACE Inhibitors', 'Potassium-sparing diuretics', 'Major', 'Risk of severe hyperkalemia'),
('SSRIs', 'MAOIs', 'Contraindicated', 'Serotonin syndrome — potentially fatal');

SELECT 'Smart Care additional schema applied successfully!' AS Status;
