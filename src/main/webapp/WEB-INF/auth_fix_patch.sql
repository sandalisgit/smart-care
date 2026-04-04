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

-- 3. Demo staff accounts with bcrypt cost-12 hashes
--    Passwords: Admin@2026! / Doctor@2026! / Pharm@2026! / Billing@2026! / Recept@2026!
INSERT IGNORE INTO users (username, email, password_hash, role_id, is_active) VALUES
('admin',       'admin@hospital.lk',       '$2a$12$ExqODWeYvaco1RCwMliZB.nJXtKQThGpH06sF8SgGt5WqfgZTOdt6', (SELECT role_id FROM roles WHERE role_name='System Admin'   LIMIT 1), TRUE),
('dr.silva',    'dr.silva@hospital.lk',    '$2a$12$JS89npX25R6cJQ/badz/m.rSUaqaEO7cVqj5SW/WvbQQ4uFvYqHLa', (SELECT role_id FROM roles WHERE role_name='Doctor'          LIMIT 1), TRUE),
('pharmacist',  'pharmacist@hospital.lk',  '$2a$12$0IuvAgfOupJWL4yCM9PsV.wNy7RyrZ73VRw7raOBRNfFeKTgT1AEi', (SELECT role_id FROM roles WHERE role_name='Pharmacist'       LIMIT 1), TRUE),
('billing',     'billing@hospital.lk',     '$2a$12$darWV9MdNfvu1HJxeLH8seNZicMneEymLgadY3HVjgs/MXpYJ1912', (SELECT role_id FROM roles WHERE role_name='Billing Clerk'    LIMIT 1), TRUE),
('reception',   'reception@hospital.lk',   '$2a$12$Uw3pcUsVvbUlmaX5FFE8yOpsRiBJ99r.nqFmyEN6Fco0xxd2/WqH2', (SELECT role_id FROM roles WHERE role_name='Receptionist'     LIMIT 1), TRUE),
('nurse',       'nurse@hospital.lk',       '$2a$12$zHa13wI1GWrIeOTZF3iixuxzEWb2yX6Hk4XtIEb9p9vfvwCT5rQV6', (SELECT role_id FROM roles WHERE role_name='Nurse'            LIMIT 1), TRUE);

-- NOTE: The hash above is the bcrypt(cost=12) of "Admin@2026!" used as a placeholder.
-- For production, generate individual hashes using AuthService.hashPassword() or:
--   Java: BCrypt.hashpw("YourPassword", BCrypt.gensalt(12))

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

-- 6. Patient portal accounts (username + bcrypt password for self-registered patients)
CREATE TABLE IF NOT EXISTS patient_accounts (
    account_id    INT          AUTO_INCREMENT PRIMARY KEY,
    patient_id    INT          NOT NULL UNIQUE,
    username      VARCHAR(20)  NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE,
    INDEX idx_pa_username (username)
);

SELECT 'Auth fix patch applied successfully!' AS Status;
