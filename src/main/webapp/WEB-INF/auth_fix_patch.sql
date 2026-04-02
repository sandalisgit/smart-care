-- ====================================================================
-- SMART CARE -- Auth Fix Patch v1.1
-- Run AFTER SMARTCARE_COMPLETE_DATABASE.sql and db_additions.sql
-- Fixes: patient_sessions table, demo accounts, Receptionist role
-- ====================================================================

USE hospital_erp;

-- 1. Patient sessions table (FR-73 patient portal login)
CREATE TABLE IF NOT EXISTS patient_sessions (
    session_id  VARCHAR(100) PRIMARY KEY,
    patient_id  INT NOT NULL,
    ip_address  VARCHAR(45),
    expires_at  TIMESTAMP NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE,
    INDEX idx_patient_session_exp (expires_at)
);

-- 2. Ensure Receptionist role exists
INSERT IGNORE INTO roles (role_name, description, permissions) VALUES
('Receptionist', 'Front desk access', '{"modules": ["patients", "appointments"]}'),
('Nurse',        'Nursing staff access', '{"modules": ["patients", "beds", "emr"]}');

-- 3. Demo staff accounts with bcrypt cost-12 hashes (generated via jbcrypt 0.4, $2a$ prefix)
--    Passwords: Admin@2026! / Doctor@2026! / Pharm@2026! / Billing@2026! / Recept@2026! / Nurse@2026!
INSERT IGNORE INTO users (username, email, password_hash, role_id, is_active) VALUES
('admin',       'admin@hospital.lk',       '$2a$12$d2gnwl6hCtSX2ScXKFcUnuL94IvkW2lsl1Cg6fKdfsNRX0Npn8hKW', (SELECT role_id FROM roles WHERE role_name='System Admin'   LIMIT 1), TRUE),
('dr.silva',    'dr.silva@hospital.lk',    '$2a$12$O1T.oZbN1NAeD9aVPCky6uh6H0jKFEs/mxaqIlb0bCz8WiXp29/.2', (SELECT role_id FROM roles WHERE role_name='Doctor'          LIMIT 1), TRUE),
('pharmacist',  'pharmacist@hospital.lk',  '$2a$12$0Gmrjy76b2YZUF6c8KgbzedbNdt7vyN5nuXE57Dfvulb8kZjhti/q', (SELECT role_id FROM roles WHERE role_name='Pharmacist'       LIMIT 1), TRUE),
('billing',     'billing@hospital.lk',     '$2a$12$IUoDc3sU55iYNRyZCir6a.2fA6kXupLP1i/uU4UCYp2FFbCqCNG7G', (SELECT role_id FROM roles WHERE role_name='Billing Clerk'    LIMIT 1), TRUE),
('reception',   'reception@hospital.lk',   '$2a$12$lurGqc9b7ZQycglykOfAI.Ke1etC/aafqR2isNYr14F2lWzclOuZ.', (SELECT role_id FROM roles WHERE role_name='Receptionist'     LIMIT 1), TRUE),
('nurse',       'nurse@hospital.lk',       '$2a$12$lurGqc9b7ZQycglykOfAI.Ke1etC/aafqR2isNYr14F2lWzclOuZ.', (SELECT role_id FROM roles WHERE role_name='Nurse'            LIMIT 1), TRUE);
-- ON DUPLICATE KEY: update hashes so re-running the patch fixes any broken installations
UPDATE users SET password_hash='$2a$12$d2gnwl6hCtSX2ScXKFcUnuL94IvkW2lsl1Cg6fKdfsNRX0Npn8hKW', failed_login_attempts=0, account_locked_until=NULL WHERE username='admin';
UPDATE users SET password_hash='$2a$12$O1T.oZbN1NAeD9aVPCky6uh6H0jKFEs/mxaqIlb0bCz8WiXp29/.2', failed_login_attempts=0, account_locked_until=NULL WHERE username='dr.silva';
UPDATE users SET password_hash='$2a$12$0Gmrjy76b2YZUF6c8KgbzedbNdt7vyN5nuXE57Dfvulb8kZjhti/q', failed_login_attempts=0, account_locked_until=NULL WHERE username='pharmacist';
UPDATE users SET password_hash='$2a$12$IUoDc3sU55iYNRyZCir6a.2fA6kXupLP1i/uU4UCYp2FFbCqCNG7G', failed_login_attempts=0, account_locked_until=NULL WHERE username='billing';
UPDATE users SET password_hash='$2a$12$lurGqc9b7ZQycglykOfAI.Ke1etC/aafqR2isNYr14F2lWzclOuZ.', failed_login_attempts=0, account_locked_until=NULL WHERE username='reception';

-- 4. Demo patient accounts (login: Patient ID + Full Name)
INSERT IGNORE INTO patients (patient_code, first_name, last_name, date_of_birth, gender, blood_group, phone, email, address, city, status, registration_date) VALUES
('PAT000001', 'Saman',    'Silva',      '1985-04-12', 'Male',   'O+',  '+94771234567', 'saman.silva@email.com',     '45 Galle Road',    'Colombo', 'Active', NOW()),
('PAT000002', 'Dilini',   'Fernando',   '1992-07-23', 'Female', 'A+',  '+94772345678', 'dilini.fernando@email.com', '12 Kandy Road',    'Kandy',   'Active', NOW()),
('PAT000003', 'Kasun',    'Perera',     '1978-11-05', 'Male',   'B+',  '+94773456789', 'kasun.perera@email.com',    '78 Matara Road',   'Galle',   'Active', NOW()),
('PAT000004', 'Nimali',   'Rajapaksa',  '1995-02-18', 'Female', 'AB+', '+94774567890', 'nimali.r@email.com',        '23 Temple Road',   'Colombo', 'Active', NOW()),
('PAT000005', 'Tharindu', 'Bandara',    '1988-09-30', 'Male',   'O-',  '+94775678901', 'tharindu.b@email.com',      '56 Hospital Road', 'Matara',  'Active', NOW());

-- 5. Auto-cleanup expired patient sessions
DROP EVENT IF EXISTS cleanup_patient_sessions;
CREATE EVENT IF NOT EXISTS cleanup_patient_sessions
  ON SCHEDULE EVERY 1 HOUR DO DELETE FROM patient_sessions WHERE expires_at < NOW();

SELECT 'Auth fix patch applied successfully!' AS Status;
