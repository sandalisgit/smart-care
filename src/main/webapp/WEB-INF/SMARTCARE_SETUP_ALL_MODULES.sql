-- ====================================================================
-- SMARTCARE HOSPITAL ERP — COMPLETE DATABASE SETUP
-- MySQL 8.0  |  Single-file fresh-install script
-- Run: mysql -u root -p < SMARTCARE_SETUP_ALL_MODULES.sql
--
-- Table creation order (57 tables, correct FK dependency chain):
--   1. system_config, audit_log          — no deps
--   2. roles, users, user_sessions       — auth layer
--   3. user_mfa, temp_mfa_tokens         — MFA
--   4. departments, wards, rooms, beds   — location (head_emp FK deferred)
--   5. inventory_categories, suppliers   — inv base (before prescription_items)
--      inventory_items, inventory_batches
--   6. employees                         — HR (deps: users, departments)
--      ALTER departments head_employee_id FK
--      doctors, doctor_schedule, attendance, leave_requests, payroll, shifts
--   7. patients                          — patient base
--      ALTER beds current_patient_id FK
--      patient_sessions, patient_accounts
--   8. admissions                        — deps: patients, wards, rooms, beds, doctors
--   9. appointments, no_show_features    — appointment module
--      appointment_reminders
--  10. medical_records, prescriptions,   — EMR
--      prescription_items, lab_tests
--      drug_interactions, ai_diagnosis_suggestions
--  11. services, bills, bill_items,      — billing
--      payments, insurance_claims
--  12. stock_transactions, medications   — pharmacy
--      dispensing_records, dispensing_log
--  13. purchase_requisitions,            — procurement
--      requisition_items, purchase_orders,
--      po_items, goods_received, grn_items
--  14. inventory_predictions,            — AI / analytics
--      anomaly_detections, ai_reports, kpi_metrics
--      bed_occupancy_history, ward_occupancy_snapshots
--  15. notifications, message_queue      — comms
--  16. bed_transfers                     — bed module addon
--  17. Trigger, Stored Procedures,       — business logic
--      Events, Views
--  18. Essential seed data               — roles, departments, services, demo accounts
-- ====================================================================

DROP DATABASE IF EXISTS hospital_erp;
CREATE DATABASE hospital_erp
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
USE hospital_erp;

SET FOREIGN_KEY_CHECKS = 0;
SET AUTOCOMMIT          = 0;
SET SESSION sql_mode    = 'NO_AUTO_VALUE_ON_ZERO';

-- ====================================================================
-- SECTION 1: SECURITY & SYSTEM (no FK dependencies)
-- ====================================================================

CREATE TABLE system_config (
    config_id    INT           PRIMARY KEY AUTO_INCREMENT,
    config_key   VARCHAR(100)  UNIQUE NOT NULL,
    config_value TEXT,
    config_type  ENUM('string','number','boolean','json') DEFAULT 'string',
    description  TEXT,
    is_active    BOOLEAN       DEFAULT TRUE,
    created_at   TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- user_id intentionally not FK-constrained: allows audit logging before user rows exist
CREATE TABLE audit_log (
    audit_id    BIGINT        PRIMARY KEY AUTO_INCREMENT,
    user_id     INT,
    action_type VARCHAR(50)   NOT NULL,
    table_name  VARCHAR(100),
    record_id   INT,
    old_value   JSON,
    new_value   JSON,
    ip_address  VARCHAR(45),
    user_agent  TEXT,
    entry_hash  VARCHAR(64)   NULL,   -- FR-77: tamper-evident SHA-256 hash chain
    created_at  TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_action  (user_id, action_type),
    INDEX idx_table_record (table_name, record_id),
    INDEX idx_created_at   (created_at)
);

-- ====================================================================
-- SECTION 2: USER AUTHENTICATION & SESSION MANAGEMENT
-- ====================================================================

CREATE TABLE roles (
    role_id     INT           PRIMARY KEY AUTO_INCREMENT,
    role_name   VARCHAR(50)   UNIQUE NOT NULL,
    description TEXT,
    permissions JSON,          -- role permission map
    is_active   BOOLEAN       DEFAULT TRUE,
    created_at  TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE users (
    user_id               INT           PRIMARY KEY AUTO_INCREMENT,
    username              VARCHAR(50)   UNIQUE NOT NULL,
    email                 VARCHAR(100)  UNIQUE NOT NULL,
    password_hash         VARCHAR(255)  NOT NULL,   -- BCrypt cost-12
    role_id               INT,
    is_active             BOOLEAN       DEFAULT TRUE,
    last_login            TIMESTAMP     NULL,
    failed_login_attempts INT           DEFAULT 0,
    account_locked_until  TIMESTAMP     NULL,       -- NFR-07: 30-min lockout
    must_change_password  BOOLEAN       DEFAULT FALSE,
    created_at            TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMP     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (role_id) REFERENCES roles(role_id)
);

-- Staff JWT session store (15-min timeout, NFR-08)
CREATE TABLE user_sessions (
    session_id VARCHAR(100)  PRIMARY KEY,
    user_id    INT           NOT NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    expires_at TIMESTAMP     NOT NULL,
    created_at TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    INDEX idx_user_expires (user_id, expires_at)
);

-- FR-72: TOTP MFA secrets (required for Admin / Doctor / Billing roles)
CREATE TABLE user_mfa (
    user_id     INT           PRIMARY KEY,
    totp_secret VARCHAR(64)   NOT NULL,
    is_enabled  BOOLEAN       DEFAULT FALSE,
    enrolled_at TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Temporary token used during the 2-step MFA login flow
CREATE TABLE temp_mfa_tokens (
    user_id    INT           PRIMARY KEY,
    token      VARCHAR(100)  NOT NULL UNIQUE,
    expires_at TIMESTAMP     NOT NULL,
    created_at TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- ====================================================================
-- SECTION 3: DEPARTMENT & LOCATION
-- NOTE: head_employee_id FK is deferred — added after employees exists
-- ====================================================================

CREATE TABLE departments (
    department_id    INT           PRIMARY KEY AUTO_INCREMENT,
    department_name  VARCHAR(100)  NOT NULL,
    department_code  VARCHAR(20)   UNIQUE NOT NULL,
    department_type  ENUM('Clinical','Administrative','Support','Diagnostic') NOT NULL,
    head_employee_id INT           NULL,   -- FK → employees added after employees table
    location         VARCHAR(100),
    phone            VARCHAR(20),
    email            VARCHAR(100),
    budget_allocated DECIMAL(15,2),
    is_active        BOOLEAN       DEFAULT TRUE,
    created_at       TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE wards (
    ward_id        INT           PRIMARY KEY AUTO_INCREMENT,
    ward_name      VARCHAR(100)  NOT NULL,
    ward_code      VARCHAR(20)   UNIQUE NOT NULL,
    department_id  INT,
    floor_number   INT,
    total_beds     INT           NOT NULL DEFAULT 0,
    available_beds INT           NOT NULL DEFAULT 0,
    ward_type      ENUM('General','ICU','Emergency','Pediatric','Maternity','Surgical','Private') NOT NULL,
    is_active      BOOLEAN       DEFAULT TRUE,
    FOREIGN KEY (department_id) REFERENCES departments(department_id)
);

CREATE TABLE rooms (
    room_id       INT           PRIMARY KEY AUTO_INCREMENT,
    ward_id       INT           NOT NULL,
    room_number   VARCHAR(20)   NOT NULL,
    room_type     ENUM('Single','Double','Triple','ICU','Operation Theatre','Consultation') NOT NULL,
    total_beds    INT           DEFAULT 1,
    occupied_beds INT           DEFAULT 0,
    daily_rate    DECIMAL(10,2),
    is_available  BOOLEAN       DEFAULT TRUE,
    FOREIGN KEY (ward_id) REFERENCES wards(ward_id),
    UNIQUE KEY unique_room (ward_id, room_number)
);

-- current_patient_id FK → patients is deferred (added after patients table)
CREATE TABLE beds (
    bed_id             INT           PRIMARY KEY AUTO_INCREMENT,
    room_id            INT           NOT NULL,
    bed_number         VARCHAR(20)   NOT NULL,
    bed_type           ENUM('Standard','ICU','Pediatric','Bariatric','Examination') NOT NULL,
    is_occupied        BOOLEAN       DEFAULT FALSE,
    current_patient_id INT           NULL,
    last_sanitized     TIMESTAMP     NULL,
    is_operational     BOOLEAN       DEFAULT TRUE,
    FOREIGN KEY (room_id) REFERENCES rooms(room_id),
    UNIQUE KEY unique_bed (room_id, bed_number),
    INDEX idx_beds_occ_ops (is_occupied, is_operational)
);

-- ====================================================================
-- SECTION 4: INVENTORY BASE (created early — prescription_items refs it)
-- ====================================================================

CREATE TABLE inventory_categories (
    category_id   INT           PRIMARY KEY AUTO_INCREMENT,
    category_name VARCHAR(100)  UNIQUE NOT NULL,
    category_type ENUM('Medicine','Medical Equipment','Consumables','Surgical Items','Office Supplies','Other') NOT NULL,
    description   TEXT,
    is_active     BOOLEAN       DEFAULT TRUE
);

CREATE TABLE suppliers (
    supplier_id    INT           PRIMARY KEY AUTO_INCREMENT,
    supplier_code  VARCHAR(20)   UNIQUE NOT NULL,
    supplier_name  VARCHAR(200)  NOT NULL,
    contact_person VARCHAR(100),
    email          VARCHAR(100),
    phone          VARCHAR(20)   NOT NULL,
    address        TEXT,
    city           VARCHAR(50),
    country        VARCHAR(50),
    tax_id         VARCHAR(30),
    payment_terms  VARCHAR(100),
    credit_limit   DECIMAL(12,2),
    rating         DECIMAL(3,2)  DEFAULT 0.00,
    is_active      BOOLEAN       DEFAULT TRUE,
    created_at     TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE inventory_items (
    item_id               INT           PRIMARY KEY AUTO_INCREMENT,
    item_code             VARCHAR(30)   UNIQUE NOT NULL,
    item_name             VARCHAR(200)  NOT NULL,
    category_id           INT           NOT NULL,
    description           TEXT,
    manufacturer          VARCHAR(100),
    unit_of_measure       VARCHAR(20)   NOT NULL,
    reorder_level         INT           NOT NULL DEFAULT 10,
    reorder_quantity      INT           NOT NULL DEFAULT 50,
    minimum_stock_level   INT           DEFAULT 5,
    maximum_stock_level   INT,
    current_stock         INT           DEFAULT 0,
    unit_price            DECIMAL(10,2),
    selling_price         DECIMAL(10,2),
    location              VARCHAR(100),
    expiry_alert_days     INT           DEFAULT 30,
    requires_prescription BOOLEAN       DEFAULT FALSE,
    is_active             BOOLEAN       DEFAULT TRUE,
    created_at            TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMP     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (category_id) REFERENCES inventory_categories(category_id),
    INDEX idx_stock_level (current_stock, reorder_level)
);

CREATE TABLE inventory_batches (
    batch_id           INT           PRIMARY KEY AUTO_INCREMENT,
    item_id            INT           NOT NULL,
    batch_number       VARCHAR(50)   NOT NULL,
    manufacture_date   DATE,
    expiry_date        DATE          NOT NULL,
    quantity           INT           NOT NULL,
    remaining_quantity INT           NOT NULL,
    cost_per_unit      DECIMAL(10,2) NOT NULL,
    supplier_id        INT,
    received_date      DATE          NOT NULL,
    status             ENUM('Active','Expired','Recalled','Depleted') DEFAULT 'Active',
    FOREIGN KEY (item_id)     REFERENCES inventory_items(item_id),
    FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id),
    UNIQUE KEY unique_batch  (item_id, batch_number),
    INDEX idx_expiry_status  (expiry_date, status),
    INDEX idx_batch_fifo     (item_id, status, expiry_date)   -- FIFO dispense ordering
);

-- ====================================================================
-- SECTION 5: HR & STAFF MODULE
-- ====================================================================

CREATE TABLE employees (
    employee_id      INT           PRIMARY KEY AUTO_INCREMENT,
    user_id          INT           UNIQUE,
    employee_code    VARCHAR(20)   UNIQUE NOT NULL,
    first_name       VARCHAR(50)   NOT NULL,
    last_name        VARCHAR(50)   NOT NULL,
    date_of_birth    DATE,
    gender           ENUM('Male','Female','Other') NOT NULL,
    blood_group      VARCHAR(5),
    email            VARCHAR(100),
    phone            VARCHAR(20)   NOT NULL,
    emergency_contact VARCHAR(20),
    address          TEXT,
    city             VARCHAR(50),
    state            VARCHAR(50),
    postal_code      VARCHAR(10),
    country          VARCHAR(50)   DEFAULT 'Sri Lanka',
    national_id      VARCHAR(20)   UNIQUE,
    employee_type    ENUM('Doctor','Nurse','Technician','Administrative','Support','Management') NOT NULL,
    department_id    INT,
    job_title        VARCHAR(100),
    specialization   VARCHAR(100),
    qualification    TEXT,
    license_number   VARCHAR(50),
    hire_date        DATE          NOT NULL,
    employment_type  ENUM('Full-time','Part-time','Contract','Temporary') NOT NULL,
    salary           DECIMAL(12,2),
    bank_account     VARCHAR(50),
    tax_id           VARCHAR(30),
    status           ENUM('Active','On Leave','Suspended','Terminated') DEFAULT 'Active',
    photo_url        VARCHAR(255),
    created_at       TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id)       REFERENCES users(user_id),
    FOREIGN KEY (department_id) REFERENCES departments(department_id)
);

-- Deferred FK: departments.head_employee_id → employees (FIX-2 equivalent)
ALTER TABLE departments
    ADD CONSTRAINT fk_dept_head
    FOREIGN KEY (head_employee_id) REFERENCES employees(employee_id);

CREATE TABLE doctors (
    doctor_id               INT           PRIMARY KEY AUTO_INCREMENT,
    employee_id             INT           UNIQUE NOT NULL,
    specialization          VARCHAR(100)  NOT NULL,
    consultation_fee        DECIMAL(10,2),
    available_for_emergency BOOLEAN       DEFAULT FALSE,
    average_rating          DECIMAL(3,2)  DEFAULT 0.00,
    total_consultations     INT           DEFAULT 0,
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE
);

CREATE TABLE doctor_schedule (
    schedule_id      INT     PRIMARY KEY AUTO_INCREMENT,
    doctor_id        INT     NOT NULL,
    day_of_week      ENUM('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday') NOT NULL,
    start_time       TIME    NOT NULL,
    end_time         TIME    NOT NULL,
    max_appointments INT     DEFAULT 20,
    is_active        BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id) ON DELETE CASCADE
);

CREATE TABLE attendance (
    attendance_id  INT       PRIMARY KEY AUTO_INCREMENT,
    employee_id    INT       NOT NULL,
    date           DATE      NOT NULL,
    check_in_time  TIMESTAMP,
    check_out_time TIMESTAMP,
    status         ENUM('Present','Absent','Late','Half Day','On Leave') NOT NULL,
    remarks        TEXT,
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id),
    UNIQUE KEY unique_attendance (employee_id, date),
    INDEX idx_att_emp_date (employee_id, date)
);

CREATE TABLE leave_requests (
    leave_id    INT       PRIMARY KEY AUTO_INCREMENT,
    employee_id INT       NOT NULL,
    leave_type  ENUM('Sick','Casual','Annual','Maternity','Paternity','Unpaid') NOT NULL,
    start_date  DATE      NOT NULL,
    end_date    DATE      NOT NULL,
    total_days  INT       NOT NULL,
    reason      TEXT,
    status      ENUM('Pending','Approved','Rejected','Cancelled') DEFAULT 'Pending',
    approved_by INT,
    approved_at TIMESTAMP NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id),
    FOREIGN KEY (approved_by) REFERENCES employees(employee_id),
    INDEX idx_leave_status (status, created_at),
    INDEX idx_leave_emp    (employee_id, status)
);

CREATE TABLE payroll (
    payroll_id     INT           PRIMARY KEY AUTO_INCREMENT,
    employee_id    INT           NOT NULL,
    month          INT           NOT NULL,
    year           INT           NOT NULL,
    basic_salary   DECIMAL(12,2) NOT NULL,
    allowances     DECIMAL(12,2) DEFAULT 0.00,
    bonuses        DECIMAL(12,2) DEFAULT 0.00,
    deductions     DECIMAL(12,2) DEFAULT 0.00,
    overtime_hours DECIMAL(5,2)  DEFAULT 0.00,
    overtime_pay   DECIMAL(10,2) DEFAULT 0.00,
    gross_salary   DECIMAL(12,2) NOT NULL,
    tax            DECIMAL(10,2) DEFAULT 0.00,
    net_salary     DECIMAL(12,2) NOT NULL,
    payment_date   DATE,
    payment_method ENUM('Bank Transfer','Cash','Cheque') DEFAULT 'Bank Transfer',
    status         ENUM('Pending','Processed','Paid') DEFAULT 'Pending',
    created_at     TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id),
    UNIQUE KEY unique_payroll (employee_id, month, year)
);

-- FR-62: Shift scheduling with conflict detection (unique emp+date+type)
CREATE TABLE shifts (
    shift_id      INT           PRIMARY KEY AUTO_INCREMENT,
    employee_id   INT           NOT NULL,
    shift_date    DATE          NOT NULL,
    shift_type    ENUM('Day','Evening','Night','On-Call') NOT NULL,
    start_time    TIME          NOT NULL,
    end_time      TIME          NOT NULL,
    department_id INT           NULL,
    notes         VARCHAR(255),
    created_by    INT,          -- user_id of scheduler
    created_at    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (employee_id)   REFERENCES employees(employee_id)   ON DELETE CASCADE,
    FOREIGN KEY (department_id) REFERENCES departments(department_id) ON DELETE SET NULL,
    UNIQUE KEY uq_emp_date_type (employee_id, shift_date, shift_type),
    INDEX idx_shifts_emp_date   (employee_id, shift_date),
    INDEX idx_shifts_dept_date  (department_id, shift_date),
    INDEX idx_shifts_date_type  (shift_date, shift_type)
);

-- ====================================================================
-- SECTION 6: PATIENT MANAGEMENT
-- ====================================================================

CREATE TABLE patients (
    patient_id              INT           PRIMARY KEY AUTO_INCREMENT,
    patient_code            VARCHAR(20)   UNIQUE NOT NULL,
    first_name              VARCHAR(50)   NOT NULL,
    last_name               VARCHAR(50)   NOT NULL,
    date_of_birth           DATE          NOT NULL,
    gender                  ENUM('Male','Female','Other') NOT NULL,
    blood_group             VARCHAR(5),
    phone                   VARCHAR(20)   NOT NULL,
    email                   VARCHAR(100),
    emergency_contact_name  VARCHAR(100),
    emergency_contact_phone VARCHAR(20),
    address                 TEXT,
    city                    VARCHAR(50),
    state                   VARCHAR(50),
    postal_code             VARCHAR(10),
    country                 VARCHAR(50)   DEFAULT 'Sri Lanka',
    national_id             VARCHAR(20)   UNIQUE,  -- stored AES-256-GCM encrypted
    insurance_provider      VARCHAR(100),
    insurance_policy_number VARCHAR(50),
    allergies               TEXT,                   -- stored AES-256-GCM encrypted
    chronic_conditions      TEXT,
    blood_pressure          VARCHAR(20),
    height                  DECIMAL(5,2),
    weight                  DECIMAL(5,2),
    registration_date       TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    status                  ENUM('Active','Inactive','Deceased') DEFAULT 'Active',
    photo_url               VARCHAR(255),
    created_at              TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_name                 (first_name, last_name),
    INDEX idx_phone                (phone),
    INDEX idx_patients_status      (status),
    INDEX idx_patients_reg_date    (registration_date DESC),
    INDEX idx_patients_gender_blood(gender, blood_group),
    FULLTEXT INDEX idx_patients_fulltext(first_name, last_name)
);

-- Deferred FK: beds.current_patient_id → patients (FIX-2)
ALTER TABLE beds
    ADD CONSTRAINT fk_beds_current_patient
    FOREIGN KEY (current_patient_id) REFERENCES patients(patient_id)
    ON DELETE SET NULL;

-- FR-73: Patient portal session tokens (separate from staff user_sessions)
CREATE TABLE patient_sessions (
    session_id VARCHAR(100)  PRIMARY KEY,
    patient_id INT           NOT NULL,
    ip_address VARCHAR(45),
    expires_at TIMESTAMP     NOT NULL,
    created_at TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE,
    INDEX idx_patient_session_exp (expires_at)
);

-- Patient portal self-registration accounts
CREATE TABLE patient_accounts (
    account_id    INT           AUTO_INCREMENT PRIMARY KEY,
    patient_id    INT           NOT NULL UNIQUE,
    username      VARCHAR(20)   NOT NULL UNIQUE,
    password_hash VARCHAR(255)  NOT NULL,
    created_at    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE,
    INDEX idx_pa_username (username)
);

-- ====================================================================
-- SECTION 7: BED & WARD — ADMISSIONS
-- (depends on patients, wards, rooms, beds, doctors)
-- ====================================================================

CREATE TABLE admissions (
    admission_id        INT           PRIMARY KEY AUTO_INCREMENT,
    patient_id          INT           NOT NULL,
    admission_date      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    discharge_date      TIMESTAMP     NULL,
    admission_type      ENUM('Emergency','Planned','Outpatient','Day Care') NOT NULL,
    ward_id             INT,
    room_id             INT,
    bed_id              INT,
    admitting_doctor_id INT           NOT NULL,
    primary_diagnosis   TEXT,
    secondary_diagnosis TEXT,
    admission_notes     TEXT,
    discharge_summary   TEXT,
    status              ENUM('Admitted','Discharged','Transferred','Deceased') DEFAULT 'Admitted',
    total_bill_amount   DECIMAL(12,2) DEFAULT 0.00,
    FOREIGN KEY (patient_id)          REFERENCES patients(patient_id),
    FOREIGN KEY (ward_id)             REFERENCES wards(ward_id),
    FOREIGN KEY (room_id)             REFERENCES rooms(room_id),
    FOREIGN KEY (bed_id)              REFERENCES beds(bed_id),
    FOREIGN KEY (admitting_doctor_id) REFERENCES doctors(doctor_id),
    INDEX idx_patient_status   (patient_id, status),
    INDEX idx_admission_date   (admission_date),
    INDEX idx_adm_status       (status),
    INDEX idx_adm_patient_stat (patient_id, status)
);

-- ====================================================================
-- SECTION 8: APPOINTMENT MANAGEMENT
-- ====================================================================

CREATE TABLE appointments (
    appointment_id      INT           PRIMARY KEY AUTO_INCREMENT,
    patient_id          INT           NOT NULL,
    doctor_id           INT           NOT NULL,
    appointment_date    DATE          NOT NULL,
    appointment_time    TIME          NOT NULL,
    appointment_type    ENUM('Consultation','Follow-up','Emergency','Routine Check') NOT NULL,
    status              ENUM('Scheduled','Confirmed','In Progress','Completed','Cancelled','No Show') DEFAULT 'Scheduled',
    reason              TEXT,
    notes               TEXT,
    consultation_fee    DECIMAL(10,2),
    cancelled_by        INT           NULL,
    cancellation_reason VARCHAR(500)  NULL,
    reminder_sent       TINYINT(1)    DEFAULT 0,   -- FR-16: 1 when 24h reminder queued
    created_at          TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
    FOREIGN KEY (doctor_id)  REFERENCES doctors(doctor_id),
    INDEX idx_doctor_date      (doctor_id, appointment_date),
    INDEX idx_patient_date     (patient_id, appointment_date),
    INDEX idx_appt_status      (status),
    INDEX idx_appt_date_status (appointment_date, status),
    INDEX idx_appt_type        (appointment_type),
    INDEX idx_appt_reminder    (reminder_sent, appointment_date)
);

-- FR-17: AI no-show prediction training features
CREATE TABLE no_show_features (
    id                       INT           PRIMARY KEY AUTO_INCREMENT,
    appointment_id           INT           NOT NULL UNIQUE,
    patient_age              INT,
    day_of_week              INT,
    hour_of_day              INT,
    days_until_appointment   INT,
    previous_no_shows        INT           DEFAULT 0,
    appointment_type_encoded INT           DEFAULT 0,
    prediction_score         DECIMAL(5,4),
    actual_outcome           ENUM('Showed','No-Show') NULL,
    created_at               TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE
);

-- FR-16: Reminder dispatch tracking
CREATE TABLE appointment_reminders (
    reminder_id    INT           PRIMARY KEY AUTO_INCREMENT,
    appointment_id INT           NOT NULL,
    reminder_type  ENUM('EMAIL','SMS') NOT NULL,
    scheduled_at   TIMESTAMP     NOT NULL,
    sent_at        TIMESTAMP     NULL,
    status         ENUM('Pending','Sent','Failed') DEFAULT 'Pending',
    error_message  VARCHAR(500)  NULL,
    created_at     TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE,
    INDEX idx_reminders_pending (status, scheduled_at),
    INDEX idx_reminders_appt    (appointment_id)
);

-- ====================================================================
-- SECTION 9: ELECTRONIC MEDICAL RECORDS (EMR)
-- ====================================================================

-- Merged definition: base + emr_schema_patch columns combined
CREATE TABLE medical_records (
    record_id       INT           PRIMARY KEY AUTO_INCREMENT,
    patient_id      INT           NOT NULL,
    doctor_id       INT           NOT NULL,
    appointment_id  INT           NULL,
    admission_id    INT           NULL,
    visit_type      ENUM('Consultation','Follow-up','Emergency','Lab Review',
                         'Surgery','Telehealth','Discharge') DEFAULT 'Consultation',
    chief_complaint VARCHAR(500)  NOT NULL,
    symptoms        TEXT,          -- AES-256-GCM encrypted (FR-21)
    diagnosis       TEXT,          -- AES-256-GCM encrypted (FR-21)
    diagnosis_icd10 VARCHAR(20)   NULL,   -- e.g. "I10", "J18.9"
    treatment_plan  TEXT,          -- AES-256-GCM encrypted (FR-21)
    prescriptions   TEXT,          -- free-text summary (structured data in prescriptions table)
    lab_tests_ordered TEXT,        -- free-text summary (structured data in lab_tests table)
    vital_signs     JSON          NULL,   -- {bp, temperature, pulse, o2sat, rr, weight, height}
    notes           TEXT          NULL,
    follow_up_date  DATE          NULL,
    record_date     TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id)     REFERENCES patients(patient_id),
    FOREIGN KEY (doctor_id)      REFERENCES doctors(doctor_id),
    FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id),
    FOREIGN KEY (admission_id)   REFERENCES admissions(admission_id),
    INDEX idx_patient_date (patient_id, record_date),
    INDEX idx_mr_patient   (patient_id),
    INDEX idx_mr_date      (record_date),
    INDEX idx_mr_appt      (appointment_id)
);

-- Merged definition: base + emr_schema_patch (adds dispensed_at/by, status=Dispensed)
CREATE TABLE prescriptions (
    prescription_id   INT           PRIMARY KEY AUTO_INCREMENT,
    patient_id        INT           NOT NULL,
    doctor_id         INT           NOT NULL,
    record_id         INT           NOT NULL,
    prescription_date TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    validity_days     INT           DEFAULT 30,
    notes             TEXT          NULL,
    status            ENUM('Active','Dispensed','Expired','Cancelled') DEFAULT 'Active',
    dispensed_at      TIMESTAMP     NULL,
    dispensed_by      INT           NULL,
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
    FOREIGN KEY (doctor_id)  REFERENCES doctors(doctor_id),
    FOREIGN KEY (record_id)  REFERENCES medical_records(record_id),
    INDEX idx_rx_patient (patient_id),
    INDEX idx_rx_record  (record_id),
    INDEX idx_rx_status  (status)
);

-- FIX-3: inventory_item_id links prescription to inventory for auto stock deduction
CREATE TABLE prescription_items (
    prescription_item_id INT           PRIMARY KEY AUTO_INCREMENT,
    prescription_id      INT           NOT NULL,
    medicine_name        VARCHAR(200)  NOT NULL,
    dosage               VARCHAR(100)  NOT NULL,
    frequency            VARCHAR(100)  NOT NULL,
    duration_days        INT           NOT NULL,
    quantity             INT           NOT NULL,
    instructions         TEXT          NULL,
    inventory_item_id    INT           NULL,   -- FK-3: auto stock deduct on dispense
    FOREIGN KEY (prescription_id)   REFERENCES prescriptions(prescription_id) ON DELETE CASCADE,
    FOREIGN KEY (inventory_item_id) REFERENCES inventory_items(item_id) ON DELETE SET NULL,
    INDEX idx_pi_rx (prescription_id)
);

CREATE TABLE lab_tests (
    test_id               INT           PRIMARY KEY AUTO_INCREMENT,
    patient_id            INT           NOT NULL,
    doctor_id             INT           NOT NULL,
    record_id             INT           NULL,
    test_name             VARCHAR(200)  NOT NULL,
    test_type             VARCHAR(100)  NOT NULL,
    test_date             TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    sample_collected_date TIMESTAMP,
    result_date           TIMESTAMP,
    test_result           TEXT,
    normal_range          VARCHAR(100),
    status                ENUM('Ordered','Sample Collected','In Progress','Completed','Cancelled') DEFAULT 'Ordered',
    cost                  DECIMAL(10,2),
    technician_id         INT,
    remarks               TEXT,
    FOREIGN KEY (patient_id)    REFERENCES patients(patient_id),
    FOREIGN KEY (doctor_id)     REFERENCES doctors(doctor_id),
    FOREIGN KEY (record_id)     REFERENCES medical_records(record_id),
    FOREIGN KEY (technician_id) REFERENCES employees(employee_id),
    INDEX idx_patient_status (patient_id, status)
);

-- FR-27: Drug interaction reference table (populated from DrugBank Open Data)
CREATE TABLE drug_interactions (
    interaction_id INT           PRIMARY KEY AUTO_INCREMENT,
    drug_a         VARCHAR(200)  NOT NULL,
    drug_b         VARCHAR(200)  NOT NULL,
    severity       ENUM('Minor','Moderate','Major','Contraindicated') NOT NULL,
    description    TEXT,
    source         VARCHAR(100)  DEFAULT 'DrugBank Open Data',
    INDEX idx_drug_a (drug_a(50)),
    INDEX idx_drug_b (drug_b(50))
);

-- FR-69: AI diagnosis suggestion audit log
CREATE TABLE ai_diagnosis_suggestions (
    suggestion_id       INT           AUTO_INCREMENT PRIMARY KEY,
    patient_id          INT           NOT NULL,
    doctor_id           INT           NOT NULL,   -- references users.user_id
    chief_complaint     TEXT,
    suggested_diagnosis VARCHAR(255),
    confidence_score    DECIMAL(5,4),
    created_at          TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
    FOREIGN KEY (doctor_id)  REFERENCES users(user_id)
);

-- ====================================================================
-- SECTION 10: BILLING & FINANCE
-- ====================================================================

CREATE TABLE services (
    service_id       INT           PRIMARY KEY AUTO_INCREMENT,
    service_code     VARCHAR(20)   UNIQUE NOT NULL,
    service_name     VARCHAR(200)  NOT NULL,
    service_category ENUM('Consultation','Laboratory','Radiology','Surgery','Procedure',
                          'Room Charges','Pharmacy','Other') NOT NULL,
    description      TEXT,
    unit_price       DECIMAL(10,2) NOT NULL,
    tax_percentage   DECIMAL(5,2)  DEFAULT 0.00,
    is_active        BOOLEAN       DEFAULT TRUE,
    created_at       TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE bills (
    bill_id             INT           PRIMARY KEY AUTO_INCREMENT,
    bill_number         VARCHAR(30)   UNIQUE NOT NULL,
    patient_id          INT           NOT NULL,
    admission_id        INT,
    bill_date           TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    due_date            DATE,
    subtotal            DECIMAL(12,2) NOT NULL,
    discount_percentage DECIMAL(5,2)  DEFAULT 0.00,
    discount_amount     DECIMAL(10,2) DEFAULT 0.00,
    tax_amount          DECIMAL(10,2) DEFAULT 0.00,
    total_amount        DECIMAL(12,2) NOT NULL,
    paid_amount         DECIMAL(12,2) DEFAULT 0.00,
    balance_amount      DECIMAL(12,2) NOT NULL,
    status              ENUM('Draft','Pending','Partially Paid','Paid','Overdue','Cancelled') DEFAULT 'Pending',
    payment_terms       VARCHAR(100),
    notes               TEXT,
    created_by          INT,
    FOREIGN KEY (patient_id)   REFERENCES patients(patient_id),
    FOREIGN KEY (admission_id) REFERENCES admissions(admission_id),
    FOREIGN KEY (created_by)   REFERENCES users(user_id),
    INDEX idx_patient_status     (patient_id, status),
    INDEX idx_bill_date          (bill_date),
    INDEX idx_bills_status_date  (status, bill_date DESC),
    INDEX idx_bills_patient_date (patient_id, bill_date DESC)
);

CREATE TABLE bill_items (
    bill_item_id        INT           PRIMARY KEY AUTO_INCREMENT,
    bill_id             INT           NOT NULL,
    service_id          INT,
    description         VARCHAR(255)  NOT NULL,
    quantity            INT           NOT NULL DEFAULT 1,
    unit_price          DECIMAL(10,2) NOT NULL,
    discount_percentage DECIMAL(5,2)  DEFAULT 0.00,
    tax_percentage      DECIMAL(5,2)  DEFAULT 0.00,
    line_total          DECIMAL(12,2) NOT NULL,
    FOREIGN KEY (bill_id)    REFERENCES bills(bill_id) ON DELETE CASCADE,
    FOREIGN KEY (service_id) REFERENCES services(service_id)
);

CREATE TABLE payments (
    payment_id            INT           PRIMARY KEY AUTO_INCREMENT,
    bill_id               INT           NOT NULL,
    payment_date          TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    amount                DECIMAL(12,2) NOT NULL,
    payment_method        ENUM('Cash','Credit Card','Debit Card','Bank Transfer',
                               'Insurance','Mobile Payment','Cheque') NOT NULL,
    transaction_reference VARCHAR(100),
    card_last_4_digits    VARCHAR(4),
    payment_notes         TEXT,
    received_by           INT,
    status                ENUM('Pending','Completed','Failed','Refunded') DEFAULT 'Completed',
    FOREIGN KEY (bill_id)     REFERENCES bills(bill_id),
    FOREIGN KEY (received_by) REFERENCES users(user_id),
    INDEX idx_bill_date       (bill_id, payment_date),
    INDEX idx_payments_method (payment_method, payment_date DESC)
);

CREATE TABLE insurance_claims (
    claim_id           INT           PRIMARY KEY AUTO_INCREMENT,
    patient_id         INT           NOT NULL,
    bill_id            INT           NOT NULL,
    insurance_provider VARCHAR(100)  NOT NULL,
    policy_number      VARCHAR(50)   NOT NULL,
    claim_number       VARCHAR(50)   UNIQUE NOT NULL,
    claim_date         TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    claim_amount       DECIMAL(12,2) NOT NULL,
    approved_amount    DECIMAL(12,2),
    status             ENUM('Submitted','Under Review','Approved','Rejected',
                            'Partially Approved','Paid') DEFAULT 'Submitted',
    submission_date    DATE,
    approval_date      DATE,
    payment_date       DATE,
    rejection_reason   TEXT,
    notes              TEXT,
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
    FOREIGN KEY (bill_id)    REFERENCES bills(bill_id),
    INDEX idx_status_date   (status, claim_date),
    INDEX idx_claims_status (status, claim_date DESC)
);

-- ====================================================================
-- SECTION 11: PHARMACY & INVENTORY (continued)
-- ====================================================================

CREATE TABLE stock_transactions (
    transaction_id   INT           PRIMARY KEY AUTO_INCREMENT,
    item_id          INT           NOT NULL,
    batch_id         INT,
    transaction_type ENUM('Purchase','Sale','Return','Adjustment','Transfer','Wastage','Expired') NOT NULL,
    quantity         INT           NOT NULL,
    transaction_date TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    reference_type   VARCHAR(50),
    reference_id     INT,
    from_location    VARCHAR(100),
    to_location      VARCHAR(100),
    unit_cost        DECIMAL(10,2),
    total_cost       DECIMAL(12,2),
    performed_by     INT           NOT NULL,
    remarks          TEXT,
    FOREIGN KEY (item_id)      REFERENCES inventory_items(item_id),
    FOREIGN KEY (batch_id)     REFERENCES inventory_batches(batch_id),
    FOREIGN KEY (performed_by) REFERENCES users(user_id),
    INDEX idx_item_date    (item_id, transaction_date),
    INDEX idx_type_date    (transaction_type, transaction_date),
    INDEX idx_st_type_date (transaction_type, transaction_date)
);

-- FR-36/FR-38: Medication catalogue — denormalised mirror of inventory_items
--              DemandForecaster reads current_stock here for speed
CREATE TABLE medications (
    medication_id         INT           NOT NULL AUTO_INCREMENT,
    item_id               INT           NOT NULL UNIQUE,
    drug_code             VARCHAR(20)   NOT NULL UNIQUE,
    drug_name             VARCHAR(200)  NOT NULL,
    generic_name          VARCHAR(200)  NULL,
    drug_class            VARCHAR(100)  NULL,
    current_stock         INT           NOT NULL DEFAULT 0,
    unit_of_measure       VARCHAR(20)   NOT NULL DEFAULT 'Tablet',
    requires_prescription BOOLEAN       NOT NULL DEFAULT FALSE,
    is_active             BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at            TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (medication_id),
    CONSTRAINT fk_med_item FOREIGN KEY (item_id)
        REFERENCES inventory_items(item_id) ON DELETE CASCADE,
    INDEX idx_drug_code (drug_code),
    INDEX idx_drug_name (drug_name),
    INDEX idx_is_active (is_active)
);

-- FR-31/FR-34: Batch-level dispensing events (full traceability per dispense)
CREATE TABLE dispensing_records (
    dispensing_id      INT           NOT NULL AUTO_INCREMENT,
    prescription_id    INT           NOT NULL,
    item_id            INT           NOT NULL,
    batch_id           INT           NULL,
    quantity_dispensed INT           NOT NULL,
    unit_price         DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    pharmacist_id      INT           NOT NULL,
    dispensed_at       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes              TEXT          NULL,
    PRIMARY KEY (dispensing_id),
    CONSTRAINT fk_dr_prescription FOREIGN KEY (prescription_id)
        REFERENCES prescriptions(prescription_id) ON DELETE CASCADE,
    CONSTRAINT fk_dr_item         FOREIGN KEY (item_id)
        REFERENCES inventory_items(item_id),
    CONSTRAINT fk_dr_batch        FOREIGN KEY (batch_id)
        REFERENCES inventory_batches(batch_id) ON DELETE SET NULL,
    CONSTRAINT fk_dr_pharmacist   FOREIGN KEY (pharmacist_id)
        REFERENCES users(user_id),
    INDEX idx_prescription (prescription_id),
    INDEX idx_item_date    (item_id, dispensed_at),
    INDEX idx_pharmacist   (pharmacist_id, dispensed_at)
);

-- FR-36/FR-38: Dispensing history for DemandForecaster AI training
CREATE TABLE dispensing_log (
    log_id          INT           AUTO_INCREMENT PRIMARY KEY,
    prescription_id INT,
    medication_id   INT           NOT NULL,
    pharmacist_id   INT           NOT NULL,
    patient_id      INT           NOT NULL,
    quantity        INT           NOT NULL,
    stock_before    INT           NOT NULL,
    stock_after     INT           NOT NULL,
    dispensed_at    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (medication_id)  REFERENCES medications(medication_id),
    FOREIGN KEY (pharmacist_id)  REFERENCES users(user_id),
    FOREIGN KEY (patient_id)     REFERENCES patients(patient_id)
);

-- ====================================================================
-- SECTION 12: PROCUREMENT
-- ====================================================================

CREATE TABLE purchase_requisitions (
    requisition_id       INT           PRIMARY KEY AUTO_INCREMENT,
    requisition_number   VARCHAR(30)   UNIQUE NOT NULL,
    department_id        INT           NOT NULL,
    requested_by         INT           NOT NULL,
    request_date         TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    required_by_date     DATE,
    priority             ENUM('Low','Medium','High','Urgent') DEFAULT 'Medium',
    justification        TEXT,
    status               ENUM('Draft','Pending Approval','Approved','Rejected',
                               'Converted to PO','Cancelled') DEFAULT 'Draft',
    approved_by          INT,
    approval_date        TIMESTAMP     NULL,
    rejection_reason     TEXT,
    total_estimated_cost DECIMAL(12,2),
    FOREIGN KEY (department_id) REFERENCES departments(department_id),
    FOREIGN KEY (requested_by)  REFERENCES employees(employee_id),
    FOREIGN KEY (approved_by)   REFERENCES employees(employee_id),
    INDEX idx_status_date (status, request_date)
);

CREATE TABLE requisition_items (
    requisition_item_id  INT           PRIMARY KEY AUTO_INCREMENT,
    requisition_id       INT           NOT NULL,
    item_id              INT,
    item_description     VARCHAR(255)  NOT NULL,
    quantity             INT           NOT NULL,
    estimated_unit_price DECIMAL(10,2),
    estimated_total      DECIMAL(12,2),
    specifications       TEXT,
    FOREIGN KEY (requisition_id) REFERENCES purchase_requisitions(requisition_id) ON DELETE CASCADE,
    FOREIGN KEY (item_id)        REFERENCES inventory_items(item_id)
);

CREATE TABLE purchase_orders (
    po_id                  INT           PRIMARY KEY AUTO_INCREMENT,
    po_number              VARCHAR(30)   UNIQUE NOT NULL,
    requisition_id         INT,
    supplier_id            INT           NOT NULL,
    order_date             TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    expected_delivery_date DATE,
    delivery_address       TEXT,
    status                 ENUM('Draft','Sent to Supplier','Confirmed',
                                'Partially Received','Received','Cancelled') DEFAULT 'Draft',
    subtotal               DECIMAL(12,2) NOT NULL,
    tax_amount             DECIMAL(10,2) DEFAULT 0.00,
    shipping_cost          DECIMAL(10,2) DEFAULT 0.00,
    total_amount           DECIMAL(12,2) NOT NULL,
    payment_terms          VARCHAR(100),
    created_by             INT           NOT NULL,
    approved_by            INT,
    approval_date          TIMESTAMP     NULL,
    notes                  TEXT,
    FOREIGN KEY (requisition_id) REFERENCES purchase_requisitions(requisition_id),
    FOREIGN KEY (supplier_id)    REFERENCES suppliers(supplier_id),
    FOREIGN KEY (created_by)     REFERENCES users(user_id),
    FOREIGN KEY (approved_by)    REFERENCES users(user_id),
    INDEX idx_supplier_status (supplier_id, status),
    INDEX idx_order_date      (order_date)
);

CREATE TABLE po_items (
    po_item_id        INT           PRIMARY KEY AUTO_INCREMENT,
    po_id             INT           NOT NULL,
    item_id           INT           NOT NULL,
    description       VARCHAR(255)  NOT NULL,
    quantity_ordered  INT           NOT NULL,
    quantity_received INT           DEFAULT 0,
    unit_price        DECIMAL(10,2) NOT NULL,
    tax_percentage    DECIMAL(5,2)  DEFAULT 0.00,
    line_total        DECIMAL(12,2) NOT NULL,
    received_date     DATE,
    FOREIGN KEY (po_id)   REFERENCES purchase_orders(po_id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES inventory_items(item_id)
);

CREATE TABLE goods_received (
    grn_id                  INT           PRIMARY KEY AUTO_INCREMENT,
    grn_number              VARCHAR(30)   UNIQUE NOT NULL,
    po_id                   INT           NOT NULL,
    received_date           TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    received_by             INT           NOT NULL,
    supplier_invoice_number VARCHAR(50),
    supplier_invoice_date   DATE,
    notes                   TEXT,
    status                  ENUM('Pending Inspection','Accepted','Partially Accepted','Rejected')
                            DEFAULT 'Pending Inspection',
    FOREIGN KEY (po_id)       REFERENCES purchase_orders(po_id),
    FOREIGN KEY (received_by) REFERENCES employees(employee_id)
);

-- FIX-4: batch_id links received goods to batch for full traceability
CREATE TABLE grn_items (
    grn_item_id       INT           PRIMARY KEY AUTO_INCREMENT,
    grn_id            INT           NOT NULL,
    po_item_id        INT           NOT NULL,
    item_id           INT           NOT NULL,
    batch_number      VARCHAR(50),
    quantity_received INT           NOT NULL,
    quantity_accepted INT           NOT NULL,
    quantity_rejected INT           DEFAULT 0,
    expiry_date       DATE,
    inspection_notes  TEXT,
    batch_id          INT           NULL,
    FOREIGN KEY (grn_id)     REFERENCES goods_received(grn_id) ON DELETE CASCADE,
    FOREIGN KEY (po_item_id) REFERENCES po_items(po_item_id),
    FOREIGN KEY (item_id)    REFERENCES inventory_items(item_id),
    FOREIGN KEY (batch_id)   REFERENCES inventory_batches(batch_id) ON DELETE SET NULL
);

-- ====================================================================
-- SECTION 13: AI & ANALYTICS
-- ====================================================================

CREATE TABLE inventory_predictions (
    prediction_id     INT           PRIMARY KEY AUTO_INCREMENT,
    item_id           INT           NOT NULL,
    prediction_date   DATE          NOT NULL,
    predicted_demand  INT           NOT NULL,
    confidence_score  DECIMAL(5,4),
    prediction_period VARCHAR(20),
    model_version     VARCHAR(50),
    actual_demand     INT,
    created_at        TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (item_id) REFERENCES inventory_items(item_id),
    INDEX idx_item_date (item_id, prediction_date)
);

CREATE TABLE anomaly_detections (
    anomaly_id       INT           PRIMARY KEY AUTO_INCREMENT,
    anomaly_type     ENUM('Billing','Inventory','Attendance','Prescription',
                          'Lab Test','Stock Movement') NOT NULL,
    detected_at      TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    entity_type      VARCHAR(50),
    entity_id        INT,
    severity         ENUM('Low','Medium','High','Critical') NOT NULL,
    description      TEXT          NOT NULL,
    anomaly_details  JSON,
    model_version    VARCHAR(50),
    is_resolved      BOOLEAN       DEFAULT FALSE,
    resolved_by      INT,
    resolved_at      TIMESTAMP     NULL,
    resolution_notes TEXT,
    FOREIGN KEY (resolved_by) REFERENCES users(user_id),
    INDEX idx_type_severity (anomaly_type, severity),
    INDEX idx_resolved      (is_resolved, detected_at)
);

CREATE TABLE ai_reports (
    report_id           INT           PRIMARY KEY AUTO_INCREMENT,
    report_type         VARCHAR(100)  NOT NULL,
    report_title        VARCHAR(255)  NOT NULL,
    generated_by        INT,
    generation_date     TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    report_period_start DATE,
    report_period_end   DATE,
    report_data         JSON,
    report_file_url     VARCHAR(255),
    parameters_used     JSON,
    model_version       VARCHAR(50),
    FOREIGN KEY (generated_by) REFERENCES users(user_id),
    INDEX idx_type_date (report_type, generation_date)
);

CREATE TABLE kpi_metrics (
    metric_id         INT           PRIMARY KEY AUTO_INCREMENT,
    metric_name       VARCHAR(100)  NOT NULL,
    metric_category   ENUM('Financial','Operational','Clinical','HR','Inventory') NOT NULL,
    metric_value      DECIMAL(15,2) NOT NULL,
    metric_date       DATE          NOT NULL,
    comparison_period VARCHAR(20),
    target_value      DECIMAL(15,2),
    metadata          JSON,
    created_at        TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_metric    (metric_name, metric_date, comparison_period),
    INDEX idx_category_date     (metric_category, metric_date)
);

-- FR-56: Daily bed occupancy snapshots for LSTM / Holt-Winters training
CREATE TABLE bed_occupancy_history (
    id                 INT           PRIMARY KEY AUTO_INCREMENT,
    ward_id            INT           NOT NULL,
    record_date        DATE          NOT NULL,
    total_beds         INT           NOT NULL,
    occupied_beds      INT           NOT NULL,
    predicted_occupied INT           NULL,
    created_at         TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (ward_id) REFERENCES wards(ward_id) ON DELETE CASCADE,
    UNIQUE KEY unique_ward_date (ward_id, record_date)
);

-- FR-56: WardOccupancyPredictor training snapshots (8+ weeks history)
CREATE TABLE ward_occupancy_snapshots (
    snapshot_id   INT           AUTO_INCREMENT PRIMARY KEY,
    ward_id       INT           NOT NULL,
    snap_date     DATE          NOT NULL,
    total_beds    INT           NOT NULL,
    occupied_beds INT           NOT NULL,
    created_at    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_ward_date (ward_id, snap_date),
    FOREIGN KEY (ward_id) REFERENCES wards(ward_id)
);

-- ====================================================================
-- SECTION 14: NOTIFICATIONS & MESSAGING
-- ====================================================================

CREATE TABLE notifications (
    notification_id   INT           PRIMARY KEY AUTO_INCREMENT,
    user_id           INT,
    notification_type ENUM('Info','Warning','Alert','Success','Error') DEFAULT 'Info',
    title             VARCHAR(255)  NOT NULL,
    message           TEXT          NOT NULL,
    link_url          VARCHAR(255),
    is_read           BOOLEAN       DEFAULT FALSE,
    created_at        TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    read_at           TIMESTAMP     NULL,
    expires_at        TIMESTAMP     NULL,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    INDEX idx_user_read (user_id, is_read),
    INDEX idx_created   (created_at)
);

CREATE TABLE message_queue (
    message_id     INT           PRIMARY KEY AUTO_INCREMENT,
    recipient_type ENUM('Email','SMS','Push') NOT NULL,
    recipient      VARCHAR(255)  NOT NULL,
    subject        VARCHAR(255),
    message_body   TEXT          NOT NULL,
    priority       ENUM('Low','Normal','High') DEFAULT 'Normal',
    status         ENUM('Pending','Sent','Failed','Cancelled') DEFAULT 'Pending',
    scheduled_at   TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    sent_at        TIMESTAMP     NULL,
    error_message  TEXT,
    retry_count    INT           DEFAULT 0,
    max_retries    INT           DEFAULT 3,
    created_at     TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

-- ====================================================================
-- SECTION 15: BED TRANSFERS (depends on admissions, beds, users)
-- ====================================================================

-- FR-56: Inter-ward / inter-room transfer audit log
CREATE TABLE bed_transfers (
    transfer_id     INT           PRIMARY KEY AUTO_INCREMENT,
    admission_id    INT           NOT NULL,
    from_bed_id     INT           NOT NULL,
    from_ward_id    INT           NOT NULL,
    to_bed_id       INT           NOT NULL,
    to_ward_id      INT           NOT NULL,
    transfer_reason TEXT,
    transferred_at  TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    transferred_by  INT           NOT NULL,
    FOREIGN KEY (admission_id)   REFERENCES admissions(admission_id),
    FOREIGN KEY (from_bed_id)    REFERENCES beds(bed_id),
    FOREIGN KEY (to_bed_id)      REFERENCES beds(bed_id),
    FOREIGN KEY (transferred_by) REFERENCES users(user_id),
    INDEX idx_admission      (admission_id),
    INDEX idx_transferred_at (transferred_at DESC)
);

-- ====================================================================
-- RE-ENABLE FK CHECKS AND FLUSH DDL
-- ====================================================================

SET FOREIGN_KEY_CHECKS = 1;
COMMIT;

-- ====================================================================
-- SECTION 16: TRIGGERS
-- ====================================================================

DROP TRIGGER IF EXISTS trg_sync_medication_stock;
DELIMITER //
-- FR-31: Keep medications.current_stock in sync whenever inventory_items changes
CREATE TRIGGER trg_sync_medication_stock
AFTER UPDATE ON inventory_items
FOR EACH ROW
BEGIN
    IF NEW.current_stock <> OLD.current_stock THEN
        UPDATE medications
           SET current_stock = NEW.current_stock,
               updated_at    = CURRENT_TIMESTAMP
         WHERE item_id = NEW.item_id;
    END IF;
END //
DELIMITER ;

-- ====================================================================
-- SECTION 17: STORED PROCEDURES
-- ====================================================================

DELIMITER //

-- Register new patient (generates PAT-prefixed code)
CREATE PROCEDURE sp_register_patient(
    IN  p_first_name VARCHAR(50),
    IN  p_last_name  VARCHAR(50),
    IN  p_dob        DATE,
    IN  p_gender     ENUM('Male','Female','Other'),
    IN  p_phone      VARCHAR(20),
    IN  p_email      VARCHAR(100),
    IN  p_address    TEXT,
    OUT p_patient_id   INT,
    OUT p_patient_code VARCHAR(20)
)
BEGIN
    DECLARE v_code VARCHAR(20);
    SET v_code = CONCAT('PAT', LPAD(
        (SELECT COALESCE(MAX(patient_id), 0) + 1 FROM patients), 6, '0'));
    INSERT INTO patients
        (patient_code, first_name, last_name, date_of_birth, gender, phone, email, address)
    VALUES
        (v_code, p_first_name, p_last_name, p_dob, p_gender, p_phone, p_email, p_address);
    SET p_patient_id   = LAST_INSERT_ID();
    SET p_patient_code = v_code;
END //

-- Create appointment (auto-fetches doctor consultation fee)
CREATE PROCEDURE sp_create_appointment(
    IN  p_patient_id       INT,
    IN  p_doctor_id        INT,
    IN  p_appointment_date DATE,
    IN  p_appointment_time TIME,
    IN  p_appointment_type VARCHAR(50),
    OUT p_appointment_id   INT
)
BEGIN
    DECLARE v_fee DECIMAL(10,2);
    SELECT consultation_fee INTO v_fee FROM doctors WHERE doctor_id = p_doctor_id;
    INSERT INTO appointments
        (patient_id, doctor_id, appointment_date, appointment_time,
         appointment_type, consultation_fee, status)
    VALUES
        (p_patient_id, p_doctor_id, p_appointment_date, p_appointment_time,
         p_appointment_type, v_fee, 'Scheduled');
    SET p_appointment_id = LAST_INSERT_ID();
END //

-- Update inventory stock (transactional — also writes stock_transactions)
CREATE PROCEDURE sp_update_inventory_stock(
    IN p_item_id          INT,
    IN p_batch_id         INT,
    IN p_quantity         INT,
    IN p_transaction_type ENUM('Purchase','Sale','Return','Adjustment','Transfer','Wastage','Expired'),
    IN p_performed_by     INT,
    IN p_remarks          TEXT
)
BEGIN
    START TRANSACTION;
    IF p_transaction_type IN ('Purchase', 'Return') THEN
        UPDATE inventory_items
           SET current_stock = current_stock + p_quantity WHERE item_id = p_item_id;
        IF p_batch_id IS NOT NULL THEN
            UPDATE inventory_batches
               SET remaining_quantity = remaining_quantity + p_quantity
             WHERE batch_id = p_batch_id;
        END IF;
    ELSE
        UPDATE inventory_items
           SET current_stock = current_stock - p_quantity WHERE item_id = p_item_id;
        IF p_batch_id IS NOT NULL THEN
            UPDATE inventory_batches
               SET remaining_quantity = remaining_quantity - p_quantity
             WHERE batch_id = p_batch_id;
        END IF;
    END IF;
    INSERT INTO stock_transactions
        (item_id, batch_id, transaction_type, quantity, performed_by, remarks)
    VALUES
        (p_item_id, p_batch_id, p_transaction_type, p_quantity, p_performed_by, p_remarks);
    COMMIT;
END //

-- Generate bill with auto-numbered bill_number
CREATE PROCEDURE sp_generate_bill(
    IN  p_patient_id   INT,
    IN  p_admission_id INT,
    OUT p_bill_id      INT,
    OUT p_bill_number  VARCHAR(30)
)
BEGIN
    DECLARE v_num VARCHAR(30);
    SET v_num = CONCAT('BILL-', YEAR(NOW()), '-',
        LPAD((SELECT COALESCE(MAX(bill_id), 0) + 1 FROM bills), 6, '0'));
    INSERT INTO bills (bill_number, patient_id, admission_id, subtotal, total_amount, balance_amount)
    VALUES (v_num, p_patient_id, p_admission_id, 0.00, 0.00, 0.00);
    SET p_bill_id     = LAST_INSERT_ID();
    SET p_bill_number = v_num;
END //

DELIMITER ;

-- ====================================================================
-- SECTION 18: SCHEDULED EVENTS
-- ====================================================================

-- FR-73: Expire patient sessions hourly
DROP EVENT IF EXISTS cleanup_patient_sessions;
CREATE EVENT IF NOT EXISTS cleanup_patient_sessions
    ON SCHEDULE EVERY 1 HOUR
    DO DELETE FROM patient_sessions WHERE expires_at < NOW();

-- FR-41: Mark bills overdue daily
DROP EVENT IF EXISTS evt_mark_overdue_bills;
CREATE EVENT evt_mark_overdue_bills
    ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP
    DO UPDATE bills
       SET status = 'Overdue'
       WHERE status IN ('Pending', 'Partially Paid')
         AND due_date < CURDATE()
         AND balance_amount > 0;

-- ====================================================================
-- SECTION 19: VIEWS
-- ====================================================================

-- Current admitted patients (FIX-9: LEFT JOIN so NULL doctor still shows)
CREATE VIEW v_current_admissions AS
SELECT
    a.admission_id,
    a.admission_date,
    p.patient_code,
    CONCAT(p.first_name, ' ', p.last_name)  AS patient_name,
    p.phone                                  AS patient_phone,
    w.ward_name,
    r.room_number,
    b.bed_number,
    CONCAT(e.first_name, ' ', e.last_name)  AS doctor_name,
    a.primary_diagnosis,
    a.status,
    DATEDIFF(CURDATE(), DATE(a.admission_date)) AS days_admitted
FROM admissions a
JOIN  patients  p  ON a.patient_id          = p.patient_id
LEFT JOIN wards w  ON a.ward_id             = w.ward_id
LEFT JOIN rooms r  ON a.room_id             = r.room_id
LEFT JOIN beds  b  ON a.bed_id              = b.bed_id
LEFT JOIN doctors  d  ON a.admitting_doctor_id = d.doctor_id
LEFT JOIN employees e ON d.employee_id         = e.employee_id
WHERE a.status = 'Admitted';

-- Upcoming appointments
CREATE VIEW v_upcoming_appointments AS
SELECT
    a.appointment_id,
    a.appointment_date,
    a.appointment_time,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    p.phone                                 AS patient_phone,
    CONCAT(e.first_name, ' ', e.last_name) AS doctor_name,
    d.specialization,
    a.appointment_type,
    a.status
FROM appointments a
JOIN patients  p ON a.patient_id  = p.patient_id
JOIN doctors   d ON a.doctor_id   = d.doctor_id
JOIN employees e ON d.employee_id = e.employee_id
WHERE a.appointment_date >= CURDATE()
  AND a.status IN ('Scheduled', 'Confirmed')
ORDER BY a.appointment_date, a.appointment_time;

-- Appointment calendar with no-show risk score
CREATE OR REPLACE VIEW v_appointment_calendar AS
SELECT
    a.appointment_id, a.patient_id, a.doctor_id,
    a.appointment_date, a.appointment_time, a.appointment_type,
    a.status, a.reason, a.consultation_fee,
    a.reminder_sent, a.cancellation_reason, a.created_at, a.updated_at,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    p.phone AS patient_phone, p.patient_code, p.blood_group, p.allergies,
    CONCAT(e.first_name, ' ', e.last_name) AS doctor_name,
    d.specialization,
    nsf.prediction_score                   AS no_show_risk
FROM appointments a
JOIN patients   p   ON a.patient_id  = p.patient_id
JOIN doctors    d   ON a.doctor_id   = d.doctor_id
JOIN employees  e   ON d.employee_id = e.employee_id
LEFT JOIN no_show_features nsf ON nsf.appointment_id = a.appointment_id;

-- Patient summary (used by ReportServlet; PII columns decrypted in Java layer)
CREATE OR REPLACE VIEW v_patient_summary AS
SELECT
    p.patient_id, p.patient_code,
    CONCAT(p.first_name, ' ', p.last_name) AS full_name,
    p.first_name, p.last_name, p.date_of_birth,
    TIMESTAMPDIFF(YEAR, p.date_of_birth, CURDATE()) AS age,
    p.gender, p.blood_group, p.phone, p.email,
    p.city, p.state, p.country,
    p.insurance_provider, p.insurance_policy_number,
    p.chronic_conditions, p.height, p.weight, p.status, p.registration_date,
    COUNT(DISTINCT a.appointment_id) AS total_appointments,
    MAX(a.appointment_date)          AS last_appointment_date
FROM patients p
LEFT JOIN appointments a ON a.patient_id = p.patient_id
                        AND a.status NOT IN ('Cancelled')
GROUP BY p.patient_id;

-- Patient stats dashboard widget
CREATE OR REPLACE VIEW v_patient_stats AS
SELECT
    COUNT(*)                                                          AS total_patients,
    SUM(status = 'Active')                                            AS active_patients,
    SUM(status = 'Inactive')                                          AS inactive_patients,
    SUM(status = 'Deceased')                                          AS deceased_patients,
    SUM(gender  = 'Male')                                             AS male_count,
    SUM(gender  = 'Female')                                           AS female_count,
    SUM(DATE(registration_date) = CURDATE())                          AS registered_today,
    SUM(DATE(registration_date) >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)) AS registered_last_30_days
FROM patients;

-- Low stock alert (FR-37)
CREATE OR REPLACE VIEW v_low_stock_items AS
SELECT
    i.item_id, i.item_code, i.item_name,
    c.category_name,
    i.current_stock, i.reorder_level, i.minimum_stock_level, i.reorder_quantity,
    i.unit_of_measure, i.selling_price,
    CASE
        WHEN i.current_stock <= i.minimum_stock_level THEN 'Critical'
        WHEN i.current_stock <= i.reorder_level       THEN 'Low'
        ELSE 'Normal'
    END AS stock_status
FROM  inventory_items      i
JOIN  inventory_categories c ON i.category_id = c.category_id
WHERE i.current_stock <= i.reorder_level AND i.is_active = TRUE
ORDER BY
    CASE WHEN i.current_stock <= i.minimum_stock_level THEN 1 ELSE 2 END,
    i.current_stock ASC;

-- Expiring items — configurable alert window (FR-32)
CREATE OR REPLACE VIEW v_expiring_items AS
SELECT
    ib.batch_id, i.item_id, i.item_code, i.item_name, ib.batch_number,
    ib.expiry_date, ib.remaining_quantity,
    DATEDIFF(ib.expiry_date, CURDATE()) AS days_to_expiry,
    s.supplier_name,
    CASE
        WHEN DATEDIFF(ib.expiry_date, CURDATE()) <= 0  THEN 'Expired'
        WHEN DATEDIFF(ib.expiry_date, CURDATE()) <= 7  THEN 'Critical'
        WHEN DATEDIFF(ib.expiry_date, CURDATE()) <= 30 THEN 'Expiring Soon'
        ELSE 'Watch'
    END AS expiry_status
FROM  inventory_batches ib
JOIN  inventory_items   i  ON ib.item_id     = i.item_id
LEFT JOIN suppliers     s  ON ib.supplier_id = s.supplier_id
WHERE ib.status = 'Active'
  AND ib.remaining_quantity > 0
  AND DATEDIFF(ib.expiry_date, CURDATE()) <= GREATEST(i.expiry_alert_days, 30)
ORDER BY ib.expiry_date ASC;

-- Dispensing audit trail (FR-40)
CREATE OR REPLACE VIEW v_dispensing_audit AS
SELECT
    t.transaction_id                       AS log_id,
    t.transaction_date                     AS dispensed_at,
    CONCAT(u.first_name, ' ', u.last_name) AS pharmacist_name,
    u.user_id                              AS pharmacist_id,
    t.reference_id                         AS prescription_id,
    i.item_name                            AS drug_name,
    i.item_code                            AS drug_code,
    t.quantity                             AS qty_dispensed,
    t.remarks
FROM stock_transactions t
JOIN inventory_items    i ON t.item_id      = i.item_id
JOIN users              u ON t.performed_by = u.user_id
WHERE t.transaction_type = 'Sale'
ORDER BY t.transaction_date DESC;

-- 14-day rolling demand forecast (SQL fallback for dashboard)
CREATE OR REPLACE VIEW v_inventory_demand_forecast AS
SELECT
    i.item_id, i.item_code, i.item_name,
    i.current_stock, i.reorder_level,
    COALESCE(SUM(t.quantity), 0)                         AS units_last_14_days,
    ROUND(COALESCE(SUM(t.quantity), 0) / 14.0, 2)       AS avg_daily_demand,
    ROUND(COALESCE(SUM(t.quantity), 0) / 14.0 * 7, 0)   AS forecast_7_days,
    ROUND(COALESCE(SUM(t.quantity), 0) / 14.0 * 30, 0)  AS forecast_30_days,
    CASE
        WHEN i.current_stock < ROUND(COALESCE(SUM(t.quantity), 0) / 14.0 * 7, 0)
        THEN 'Restock Needed' ELSE 'Adequate'
    END AS restock_recommendation
FROM inventory_items i
LEFT JOIN stock_transactions t
       ON t.item_id          = i.item_id
      AND t.transaction_type = 'Sale'
      AND t.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 14 DAY)
WHERE i.is_active = TRUE
GROUP BY i.item_id, i.item_code, i.item_name, i.current_stock, i.reorder_level
ORDER BY avg_daily_demand DESC;

-- Outstanding bills (FR-50)
CREATE OR REPLACE VIEW v_outstanding_bills AS
SELECT
    b.bill_id, b.bill_number, b.bill_date, b.due_date, b.patient_id,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    p.phone AS patient_phone, p.insurance_provider,
    b.total_amount, b.paid_amount, b.balance_amount, b.status,
    DATEDIFF(CURDATE(), b.due_date) AS days_overdue
FROM bills b
JOIN patients p ON b.patient_id = p.patient_id
WHERE b.status IN ('Pending', 'Partially Paid', 'Overdue')
  AND b.balance_amount > 0
ORDER BY CASE WHEN b.status = 'Overdue' THEN 1 ELSE 2 END, b.due_date ASC;

-- Monthly revenue summary (FR-46)
CREATE OR REPLACE VIEW v_monthly_revenue AS
SELECT
    DATE_FORMAT(b.bill_date, '%Y-%m')  AS revenue_month,
    COUNT(DISTINCT b.bill_id)           AS total_bills,
    COALESCE(SUM(b.total_amount),  0)   AS gross_revenue,
    COALESCE(SUM(b.paid_amount),   0)   AS collected_revenue,
    COALESCE(SUM(b.balance_amount),0)   AS outstanding_revenue,
    COALESCE(SUM(b.discount_amount),0)  AS total_discounts
FROM bills b
WHERE b.status != 'Draft'
GROUP BY DATE_FORMAT(b.bill_date, '%Y-%m')
ORDER BY revenue_month DESC;

-- Revenue by service category — last 30 days
CREATE OR REPLACE VIEW v_revenue_by_category AS
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

-- Insurance claims summary (FR-44)
CREATE OR REPLACE VIEW v_claims_summary AS
SELECT
    ic.claim_id, ic.claim_number, ic.claim_date,
    ic.insurance_provider, ic.policy_number,
    ic.claim_amount, COALESCE(ic.approved_amount, 0) AS approved_amount,
    ic.status,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    b.bill_number, b.total_amount AS bill_amount,
    DATEDIFF(CURDATE(), ic.claim_date) AS days_pending
FROM insurance_claims ic
JOIN patients p ON ic.patient_id = p.patient_id
JOIN bills    b ON ic.bill_id    = b.bill_id
ORDER BY ic.claim_date DESC;

-- Ward occupancy KPIs (FR-51)
CREATE OR REPLACE VIEW v_ward_stats AS
SELECT
    COUNT(DISTINCT w.ward_id)                                             AS total_wards,
    COALESCE(SUM(w.total_beds), 0)                                        AS total_beds,
    COALESCE(SUM(w.total_beds - w.available_beds), 0)                     AS occupied_beds,
    COALESCE(SUM(w.available_beds), 0)                                    AS available_beds,
    ROUND(
        COALESCE(SUM(w.total_beds - w.available_beds), 0)
        / NULLIF(SUM(w.total_beds), 0) * 100, 1)                         AS overall_occupancy_pct,
    COUNT(CASE WHEN (w.total_beds - w.available_beds)
               / NULLIF(w.total_beds, 0) >= 0.85 THEN 1 END)             AS critical_wards,
    (SELECT COUNT(*) FROM admissions WHERE status = 'Admitted')           AS current_patients
FROM wards w WHERE w.is_active = TRUE;

-- Bed status breakdown per ward type (FR-51, FR-59)
CREATE OR REPLACE VIEW v_bed_status_summary AS
SELECT
    w.ward_type,
    COUNT(b.bed_id)                                                     AS total_beds,
    SUM(CASE WHEN b.is_occupied = TRUE  THEN 1 ELSE 0 END)             AS occupied,
    SUM(CASE WHEN b.is_occupied = FALSE AND b.is_operational = TRUE
             THEN 1 ELSE 0 END)                                         AS available,
    SUM(CASE WHEN b.is_operational = FALSE THEN 1 ELSE 0 END)           AS maintenance,
    SUM(CASE WHEN b.is_occupied = FALSE AND b.last_sanitized IS NULL
             THEN 1 ELSE 0 END)                                         AS needs_sanitizing
FROM beds b
JOIN rooms r ON b.room_id = r.room_id
JOIN wards w ON r.ward_id = w.ward_id
WHERE w.is_active = TRUE
GROUP BY w.ward_type ORDER BY w.ward_type;

-- Transfer history (FR-58)
CREATE OR REPLACE VIEW v_transfer_history AS
SELECT
    bt.transfer_id, bt.transferred_at, bt.transfer_reason, bt.admission_id,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name, p.patient_code,
    fw.ward_name AS from_ward, fb.bed_number AS from_bed,
    tw.ward_name AS to_ward,   tb.bed_number AS to_bed,
    CONCAT(u.first_name, ' ', u.last_name) AS transferred_by_name
FROM bed_transfers bt
JOIN admissions a  ON bt.admission_id  = a.admission_id
JOIN patients   p  ON a.patient_id     = p.patient_id
JOIN beds       fb ON bt.from_bed_id   = fb.bed_id
JOIN beds       tb ON bt.to_bed_id     = tb.bed_id
JOIN wards      fw ON bt.from_ward_id  = fw.ward_id
JOIN wards      tw ON bt.to_ward_id    = tw.ward_id
JOIN users      u  ON bt.transferred_by = u.user_id
ORDER BY bt.transferred_at DESC;

-- Staff stats for HR dashboard (FR-61)
CREATE OR REPLACE VIEW v_staff_stats AS
SELECT
    COUNT(*)                                                           AS total_employees,
    SUM(CASE WHEN status = 'Active'          THEN 1 ELSE 0 END)       AS active_employees,
    SUM(CASE WHEN status = 'On Leave'        THEN 1 ELSE 0 END)       AS on_leave,
    SUM(CASE WHEN employee_type = 'Doctor'   THEN 1 ELSE 0 END)       AS total_doctors,
    SUM(CASE WHEN employee_type = 'Nurse'    THEN 1 ELSE 0 END)       AS total_nurses,
    SUM(CASE WHEN employment_type = 'Full-time' THEN 1 ELSE 0 END)    AS full_time,
    SUM(CASE WHEN employment_type = 'Part-time' THEN 1 ELSE 0 END)    AS part_time
FROM employees;

-- Shift schedule enriched with names (FR-62)
CREATE OR REPLACE VIEW v_shift_schedule AS
SELECT
    s.shift_id, s.shift_date, s.shift_type, s.start_time, s.end_time, s.notes,
    e.employee_id,
    CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
    e.employee_type, e.job_title,
    d.department_id, d.department_name
FROM shifts s
JOIN  employees  e ON s.employee_id   = e.employee_id
LEFT JOIN departments d ON s.department_id = d.department_id;

-- Monthly attendance rollup (FR-64)
CREATE OR REPLACE VIEW v_attendance_summary AS
SELECT
    e.employee_id,
    CONCAT(e.first_name, ' ', e.last_name) AS full_name,
    e.employee_type, d.department_name,
    SUM(CASE WHEN a.status = 'Present'  THEN 1 ELSE 0 END) AS present,
    SUM(CASE WHEN a.status = 'Absent'   THEN 1 ELSE 0 END) AS absent,
    SUM(CASE WHEN a.status = 'Late'     THEN 1 ELSE 0 END) AS late,
    SUM(CASE WHEN a.status = 'On Leave' THEN 1 ELSE 0 END) AS on_leave_days
FROM employees e
LEFT JOIN attendance a
       ON  e.employee_id = a.employee_id
       AND YEAR(a.date)  = YEAR(CURDATE())
       AND MONTH(a.date) = MONTH(CURDATE())
LEFT JOIN departments d ON e.department_id = d.department_id
GROUP BY e.employee_id, full_name, e.employee_type, d.department_name;

-- Active employees with role and specialisation
CREATE OR REPLACE VIEW v_employee_summary AS
SELECT
    e.employee_code,
    CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
    e.employee_type, e.job_title, d.department_name,
    e.phone, e.email, e.status, r.role_name,
    CASE WHEN doc.doctor_id IS NOT NULL THEN doc.specialization ELSE NULL END AS specialization
FROM employees e
LEFT JOIN departments d   ON e.department_id = d.department_id
LEFT JOIN users       u   ON e.user_id       = u.user_id
LEFT JOIN roles       r   ON u.role_id       = r.role_id
LEFT JOIN doctors   doc   ON e.employee_id   = doc.employee_id
WHERE e.status = 'Active';

-- ====================================================================
-- SECTION 20: ESSENTIAL SEED DATA
-- ====================================================================

-- Roles (10 roles covering all RBAC requirements)
INSERT INTO roles (role_name, description, permissions) VALUES
('System Admin',      'Full system access',                  '{"all": true}'),
('Hospital Admin',    'Administrative access',               '{"modules": ["patients","billing","hr","inventory"]}'),
('Doctor',            'Medical staff access',                '{"modules": ["patients","appointments","medical_records"]}'),
('Nurse',             'Nursing staff access',                '{"modules": ["patients","admissions","medical_records"]}'),
('Pharmacist',        'Pharmacy management',                 '{"modules": ["inventory","prescriptions"]}'),
('Billing Clerk',     'Billing operations',                  '{"modules": ["billing","payments"]}'),
('HR Manager',        'HR operations',                       '{"modules": ["hr","payroll","attendance"]}'),
('Inventory Manager', 'Inventory & procurement',             '{"modules": ["inventory","procurement"]}'),
('Lab Technician',    'Laboratory operations',               '{"modules": ["lab_tests"]}'),
('Receptionist',      'Front desk operations',               '{"modules": ["appointments","patients"]}');

-- System configuration defaults
INSERT INTO system_config (config_key, config_value, config_type, description) VALUES
('session_timeout_minutes',  '15',                                        'number',  'NFR-08: Staff JWT session timeout'),
('max_login_attempts',       '5',                                         'number',  'NFR-07: Failed logins before lockout'),
('lockout_duration_minutes', '30',                                        'number',  'NFR-07: Lockout window after max attempts'),
('mfa_required_roles',       '["System Admin","Doctor","Billing Clerk"]', 'json',    'Roles requiring TOTP MFA (FR-72)'),
('bcrypt_cost',              '12',                                        'number',  'BCrypt work factor for password hashing'),
('expiry_alert_days',        '30',                                        'number',  'Default days before batch expiry to alert');

-- Hospital departments (12 departments)
INSERT INTO departments (department_name, department_code, department_type, location, phone, budget_allocated) VALUES
('Emergency Medicine',  'EMRG', 'Clinical',        'Ground Floor', '+94112345001', 5000000.00),
('Cardiology',          'CARD', 'Clinical',         '2nd Floor',    '+94112345002', 8000000.00),
('Pediatrics',          'PEDI', 'Clinical',         '3rd Floor',    '+94112345003', 6000000.00),
('General Surgery',     'SURG', 'Clinical',         '4th Floor',    '+94112345004', 10000000.00),
('Radiology',           'RADI', 'Diagnostic',       '1st Floor',    '+94112345005', 7000000.00),
('Laboratory',          'LABO', 'Diagnostic',       '1st Floor',    '+94112345006', 4000000.00),
('Pharmacy',            'PHAR', 'Support',          'Ground Floor', '+94112345007', 3000000.00),
('Administration',      'ADMN', 'Administrative',   '5th Floor',    '+94112345008', 2000000.00),
('Human Resources',     'HRES', 'Administrative',   '5th Floor',    '+94112345009', 1500000.00),
('Finance',             'FINC', 'Administrative',   '5th Floor',    '+94112345010', 2500000.00),
('Obstetrics',          'OBGY', 'Clinical',         '3rd Floor',    '+94112345011', 7500000.00),
('Orthopaedics',        'ORTH', 'Clinical',         '2nd Floor',    '+94112345012', 9000000.00);

-- Services catalogue (18 standard services)
INSERT INTO services (service_code, service_name, service_category, unit_price, tax_percentage) VALUES
('CONS-GEN',  'General Consultation',       'Consultation',   2000.00, 0.00),
('CONS-SPEC', 'Specialist Consultation',    'Consultation',   3500.00, 0.00),
('CONS-EMER', 'Emergency Consultation',     'Consultation',   5000.00, 0.00),
('LAB-CBC',   'Complete Blood Count',       'Laboratory',     1200.00, 0.00),
('LAB-LFT',   'Liver Function Test',        'Laboratory',     2500.00, 0.00),
('LAB-RFT',   'Renal Function Test',        'Laboratory',     2200.00, 0.00),
('LAB-LPS',   'Lipid Profile',              'Laboratory',     3000.00, 0.00),
('RAD-XRAY',  'X-Ray',                      'Radiology',      3500.00, 0.00),
('RAD-US',    'Ultrasound Scan',            'Radiology',      6000.00, 0.00),
('RAD-CT',    'CT Scan',                    'Radiology',     18000.00, 0.00),
('RAD-MRI',   'MRI Scan',                   'Radiology',     35000.00, 0.00),
('PROC-ECG',  'Electrocardiogram (ECG)',    'Procedure',      2500.00, 0.00),
('PROC-ECHO', 'Echocardiogram',             'Procedure',     12000.00, 0.00),
('ROOM-GEN',  'General Ward (per day)',     'Room Charges',   3500.00, 0.00),
('ROOM-PRIV', 'Private Room (per day)',     'Room Charges',   8000.00, 0.00),
('ROOM-ICU',  'ICU (per day)',              'Room Charges',  25000.00, 0.00),
('SURG-MIN',  'Minor Surgery',              'Surgery',       50000.00, 0.00),
('SURG-MAJ',  'Major Surgery',             'Surgery',      200000.00, 0.00);

-- Demo staff accounts
-- All use bcrypt(cost=12) of "Admin@2026!" as placeholder hash.
-- Generate role-specific hashes in production: BCrypt.hashpw("YourPass", BCrypt.gensalt(12))
INSERT INTO users (username, email, password_hash, role_id, is_active) VALUES
('admin',       'admin@hospital.lk',       '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5ztOv7uOVh9Zm',
    (SELECT role_id FROM roles WHERE role_name='System Admin'    LIMIT 1), TRUE),
('dr.silva',    'dr.silva@hospital.lk',    '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5ztOv7uOVh9Zm',
    (SELECT role_id FROM roles WHERE role_name='Doctor'          LIMIT 1), TRUE),
('pharmacist',  'pharmacist@hospital.lk',  '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5ztOv7uOVh9Zm',
    (SELECT role_id FROM roles WHERE role_name='Pharmacist'      LIMIT 1), TRUE),
('billing',     'billing@hospital.lk',     '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5ztOv7uOVh9Zm',
    (SELECT role_id FROM roles WHERE role_name='Billing Clerk'   LIMIT 1), TRUE),
('reception',   'reception@hospital.lk',   '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5ztOv7uOVh9Zm',
    (SELECT role_id FROM roles WHERE role_name='Receptionist'    LIMIT 1), TRUE),
('nurse',       'nurse@hospital.lk',       '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5ztOv7uOVh9Zm',
    (SELECT role_id FROM roles WHERE role_name='Nurse'           LIMIT 1), TRUE);

-- Demo patient accounts (portal login: Patient Code + Full Name)
INSERT INTO patients (patient_code, first_name, last_name, date_of_birth, gender,
                      blood_group, phone, email, address, city, status) VALUES
('PAT000001', 'Saman',    'Silva',     '1985-04-12', 'Male',   'O+',  '+94771234567', 'saman.silva@email.com',     '45 Galle Road',    'Colombo', 'Active'),
('PAT000002', 'Dilini',   'Fernando',  '1992-07-23', 'Female', 'A+',  '+94772345678', 'dilini.fernando@email.com', '12 Kandy Road',    'Kandy',   'Active'),
('PAT000003', 'Kasun',    'Perera',    '1978-11-05', 'Male',   'B+',  '+94773456789', 'kasun.perera@email.com',    '78 Matara Road',   'Galle',   'Active'),
('PAT000004', 'Nimali',   'Rajapaksa', '1995-02-18', 'Female', 'AB+', '+94774567890', 'nimali.r@email.com',        '23 Temple Road',   'Colombo', 'Active'),
('PAT000005', 'Tharindu', 'Bandara',   '1988-09-30', 'Male',   'O-',  '+94775678901', 'tharindu.b@email.com',      '56 Hospital Road', 'Matara',  'Active');

-- Drug interaction reference data (FR-27 — 20 critical pairs)
INSERT INTO drug_interactions (drug_a, drug_b, severity, description) VALUES
('Warfarin',         'Aspirin',                      'Major',           'Increased risk of bleeding when combined'),
('Warfarin',         'Ibuprofen',                    'Major',           'NSAIDs inhibit platelet function and may increase anticoagulant effect'),
('Metformin',        'Alcohol',                      'Moderate',        'Increased risk of lactic acidosis'),
('Simvastatin',      'Clarithromycin',               'Contraindicated', 'Severe risk of myopathy/rhabdomyolysis'),
('Lisinopril',       'Potassium',                    'Moderate',        'Risk of hyperkalemia'),
('Clopidogrel',      'Omeprazole',                   'Moderate',        'Omeprazole reduces clopidogrel antiplatelet effect'),
('Fluoxetine',       'Tramadol',                     'Major',           'Risk of serotonin syndrome'),
('Digoxin',          'Amiodarone',                   'Major',           'Amiodarone increases digoxin levels — risk of toxicity'),
('Ciprofloxacin',    'Antacids',                     'Moderate',        'Antacids reduce ciprofloxacin absorption'),
('Methotrexate',     'Ibuprofen',                    'Major',           'NSAIDs reduce methotrexate clearance — risk of toxicity'),
('Sildenafil',       'Nitrates',                     'Contraindicated', 'Severe hypotension — potentially fatal'),
('Lithium',          'Ibuprofen',                    'Major',           'NSAIDs reduce renal lithium clearance — lithium toxicity risk'),
('Atorvastatin',     'Erythromycin',                 'Major',           'Increased statin levels — myopathy risk'),
('Theophylline',     'Ciprofloxacin',                'Major',           'Ciprofloxacin inhibits theophylline metabolism — toxicity risk'),
('Phenytoin',        'Fluconazole',                  'Major',           'Fluconazole increases phenytoin levels — toxicity risk'),
('Heparin',          'Aspirin',                      'Major',           'Combined anticoagulation increases bleeding risk'),
('Insulin',          'Alcohol',                      'Moderate',        'Alcohol may mask symptoms of hypoglycaemia'),
('Carbamazepine',    'Erythromycin',                 'Major',           'Erythromycin increases carbamazepine levels'),
('ACE Inhibitors',   'Potassium-sparing diuretics',  'Major',           'Risk of severe hyperkalemia'),
('SSRIs',            'MAOIs',                        'Contraindicated', 'Serotonin syndrome — potentially fatal');

-- ====================================================================
-- SECTION 21: PHARMACY INVENTORY SEED DATA
-- 55 drugs covering all major therapeutic classes used in
-- Sri Lankan hospitals — realistic LKR prices and stock levels.
-- FR-31: Real-time stock | FR-32: Expiry batches | FR-37: Reorder alerts
-- ====================================================================

-- ── Pharmacy Inventory Categories ────────────────────────────────────
INSERT IGNORE INTO inventory_categories (category_name, category_type, description) VALUES
('Analgesics',            'Medicine',    'Pain-relief and antipyretic medications'),
('Antibiotics',           'Medicine',    'Broad-spectrum and narrow-spectrum antibiotics'),
('Antihypertensives',     'Medicine',    'Blood-pressure lowering agents'),
('Antidiabetics',         'Medicine',    'Oral hypoglycaemic and insulin preparations'),
('Anticoagulants',        'Medicine',    'Anticoagulant and antiplatelet agents'),
('Antihistamines',        'Medicine',    'Antihistamine and allergy medications'),
('Gastrointestinals',     'Medicine',    'GI tract and antacid preparations'),
('Vitamins',              'Medicine',    'Vitamin and mineral supplement preparations'),
('IV Fluids',             'Medicine',    'Intravenous fluids and solutions'),
('Steroids',              'Medicine',    'Corticosteroid anti-inflammatory agents'),
('Cardiovascular Agents', 'Medicine',    'Cardiac and lipid-lowering medications'),
('Respiratory Agents',    'Medicine',    'Bronchodilators and respiratory medications'),
('Anticonvulsants',       'Medicine',    'Anti-epileptic and seizure control medications'),
('Antifungals',           'Medicine',    'Antifungal medications'),
('Syringes/Consumables',  'Consumables', 'Syringes, needles and injection consumables'),
('Gloves/Consumables',    'Consumables', 'Examination and surgical glove supplies');

-- ── Approved Pharmaceutical Suppliers ────────────────────────────────
INSERT IGNORE INTO suppliers (supplier_code, supplier_name, contact_person, email, phone, address, city, country, tax_id, payment_terms, credit_limit, rating, is_active) VALUES
('SUP001', 'Lanka Pharmaceuticals Ltd',   'Mr. Roshan Perera',    'procurement@lankapharma.lk',   '+94112456789', '42 Braybrooke Street, Colombo 02', 'Colombo', 'Sri Lanka', 'VAT-LK-20190042', 'Net 30 days', 2500000.00, 4.50, TRUE),
('SUP002', 'MedTrade (Pvt) Ltd',          'Ms. Dilini Jayawardena','orders@medtrade.lk',           '+94812234567', '17 Peradeniya Road, Kandy',        'Kandy',   'Sri Lanka', 'VAT-LK-20150088', 'Net 45 days', 1800000.00, 4.20, TRUE),
('SUP003', 'Ceylon Medical Supplies',      'Dr. Nuwan Fernando',   'sales@ceylonmedsupply.lk',     '+94912345678', '88 Galle Road, Matara',            'Matara',  'Sri Lanka', 'VAT-LK-20120031', 'Net 60 days', 3200000.00, 4.70, TRUE);

-- ── Drug Inventory — 55 items (MED001–MED055) ────────────────────────

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED001','Paracetamol 500mg',c.category_id,'Analgesic and antipyretic tablet, 500 mg','Hemas Pharmaceuticals (Pvt) Ltd','Tablet',200,500,100,2000,450,5.00,8.00,'Pharmacy Shelf A-01',90,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='Analgesics' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED002','Amoxicillin 250mg',c.category_id,'Broad-spectrum penicillin antibiotic capsule, 250 mg','CIC Holdings — CIC Pharma','Capsule',150,400,75,1500,320,18.00,28.00,'Pharmacy Shelf B-02',60,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antibiotics' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED003','Metformin 500mg',c.category_id,'Biguanide oral hypoglycaemic tablet, 500 mg','Aspen Pharmacare Lanka (Pvt) Ltd','Tablet',100,300,50,1200,180,12.00,20.00,'Pharmacy Shelf C-03',60,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antidiabetics' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED004','Amlodipine 5mg',c.category_id,'Calcium channel blocker antihypertensive tablet, 5 mg','Pfizer Lanka (Pvt) Ltd','Tablet',100,250,50,1000,95,22.00,35.00,'Pharmacy Shelf C-01',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antihypertensives' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED005','Warfarin 5mg',c.category_id,'Vitamin K antagonist anticoagulant tablet, 5 mg — high-alert medication','Cipla Ltd','Tablet',50,150,25,500,25,65.00,95.00,'Pharmacy Safe Storage D-01',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Anticoagulants' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED006','Omeprazole 20mg',c.category_id,'Proton pump inhibitor gastric acid suppressant capsule, 20 mg','AstraZeneca Lanka (Pvt) Ltd','Capsule',100,300,50,1200,280,28.00,42.00,'Pharmacy Shelf E-01',60,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Gastrointestinals' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED007','Cetirizine 10mg',c.category_id,'Second-generation antihistamine tablet, 10 mg','GlaxoSmithKline Biologicals Lanka','Tablet',75,200,40,800,160,10.00,16.00,'Pharmacy Shelf F-02',90,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='Antihistamines' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED008','Vitamin C 500mg',c.category_id,'Ascorbic acid effervescent tablet, 500 mg','Hemas Pharmaceuticals (Pvt) Ltd','Tablet',150,500,75,2500,520,6.00,10.00,'Pharmacy Shelf G-01',180,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='Vitamins' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED009','Normal Saline 0.9% 500ml',c.category_id,'Isotonic sodium chloride IV infusion bag, 0.9% 500 ml','B. Braun Lanka (Pvt) Ltd','Bag',50,120,25,400,38,195.00,280.00,'IV Store Room H-01',60,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='IV Fluids' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED010','Dexamethasone 4mg',c.category_id,'Synthetic glucocorticoid corticosteroid tablet, 4 mg','Merck (Pvt) Ltd','Tablet',30,100,15,300,22,85.00,130.00,'Pharmacy Safe Storage D-02',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Steroids' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED011','Aspirin 75mg',c.category_id,'Low-dose acetylsalicylic acid antiplatelet tablet, 75 mg','Hemas Pharmaceuticals (Pvt) Ltd','Tablet',200,500,100,2000,680,3.50,6.00,'Pharmacy Shelf A-02',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Anticoagulants' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED012','Atorvastatin 10mg',c.category_id,'HMG-CoA reductase inhibitor statin tablet, 10 mg','Pfizer Lanka (Pvt) Ltd','Tablet',120,350,60,1200,290,28.00,45.00,'Pharmacy Shelf C-02',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Cardiovascular Agents' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED013','Lisinopril 5mg',c.category_id,'ACE inhibitor antihypertensive tablet, 5 mg','Aspen Pharmacare Lanka (Pvt) Ltd','Tablet',100,300,50,1000,210,15.00,25.00,'Pharmacy Shelf C-04',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antihypertensives' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED014','Losartan 50mg',c.category_id,'Angiotensin II receptor blocker antihypertensive tablet, 50 mg','CIC Holdings — CIC Pharma','Tablet',100,300,50,1000,175,32.00,52.00,'Pharmacy Shelf C-05',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antihypertensives' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED015','Metoprolol 50mg',c.category_id,'Beta-1 selective adrenergic blocker tablet, 50 mg','AstraZeneca Lanka (Pvt) Ltd','Tablet',80,250,40,800,155,18.00,30.00,'Pharmacy Shelf C-06',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antihypertensives' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED016','Simvastatin 20mg',c.category_id,'HMG-CoA reductase inhibitor statin tablet, 20 mg','Merck (Pvt) Ltd','Tablet',100,300,50,1000,42,22.00,38.00,'Pharmacy Shelf C-07',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Cardiovascular Agents' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED017','Ciprofloxacin 500mg',c.category_id,'Fluoroquinolone broad-spectrum antibiotic tablet, 500 mg','Cipla Ltd','Tablet',100,300,50,1000,240,35.00,58.00,'Pharmacy Shelf B-03',60,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antibiotics' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED018','Azithromycin 250mg',c.category_id,'Macrolide antibiotic capsule, 250 mg','Pfizer Lanka (Pvt) Ltd','Capsule',80,200,40,800,185,45.00,72.00,'Pharmacy Shelf B-04',60,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antibiotics' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED019','Cephalexin 500mg',c.category_id,'First-generation cephalosporin antibiotic capsule, 500 mg','GlaxoSmithKline Biologicals Lanka','Capsule',100,300,50,1000,310,28.00,46.00,'Pharmacy Shelf B-05',60,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antibiotics' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED020','Metronidazole 400mg',c.category_id,'Nitroimidazole antiprotozoal and antibacterial tablet, 400 mg','CIC Holdings — CIC Pharma','Tablet',100,300,50,1000,280,8.00,14.00,'Pharmacy Shelf B-06',60,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antibiotics' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED021','Ibuprofen 400mg',c.category_id,'NSAID anti-inflammatory and analgesic tablet, 400 mg','Hemas Pharmaceuticals (Pvt) Ltd','Tablet',200,500,100,2000,520,7.00,12.00,'Pharmacy Shelf A-03',90,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='Analgesics' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED022','Diclofenac 50mg',c.category_id,'NSAID analgesic and anti-inflammatory tablet, 50 mg','Aspen Pharmacare Lanka (Pvt) Ltd','Tablet',150,400,75,1500,340,12.00,20.00,'Pharmacy Shelf A-04',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Analgesics' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED023','Tramadol 50mg',c.category_id,'Opioid analgesic capsule, 50 mg — controlled substance','Cipla Ltd','Capsule',60,150,30,600,45,55.00,85.00,'Pharmacy Safe Storage D-03',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Analgesics' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED024','Ranitidine 150mg',c.category_id,'H2 receptor antagonist antacid tablet, 150 mg','GlaxoSmithKline Biologicals Lanka','Tablet',100,300,50,1000,380,9.00,15.00,'Pharmacy Shelf E-02',90,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='Gastrointestinals' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED025','Pantoprazole 40mg',c.category_id,'Proton pump inhibitor gastric acid suppressant tablet, 40 mg','AstraZeneca Lanka (Pvt) Ltd','Tablet',100,300,50,1000,270,30.00,48.00,'Pharmacy Shelf E-03',60,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Gastrointestinals' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED026','Metoclopramide 10mg',c.category_id,'Dopamine antagonist antiemetic tablet, 10 mg','Hemas Pharmaceuticals (Pvt) Ltd','Tablet',80,250,40,800,190,6.00,10.00,'Pharmacy Shelf E-04',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Gastrointestinals' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED027','Glibenclamide 5mg',c.category_id,'Sulphonylurea oral hypoglycaemic tablet, 5 mg','Aspen Pharmacare Lanka (Pvt) Ltd','Tablet',100,300,50,1000,220,8.00,14.00,'Pharmacy Shelf C-08',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antidiabetics' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED028','Glimepiride 2mg',c.category_id,'Third-generation sulphonylurea oral hypoglycaemic tablet, 2 mg','Cipla Ltd','Tablet',80,250,40,800,160,18.00,30.00,'Pharmacy Shelf C-09',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antidiabetics' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED029','Insulin Glargine 100U/ml',c.category_id,'Long-acting basal insulin analogue vial, 100 U/ml 10 ml — cold chain required','Sanofi Lanka (Pvt) Ltd','Vial',20,50,10,200,8,3200.00,4800.00,'Pharmacy Refrigerator R-01',30,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antidiabetics' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED030','Salbutamol Inhaler 100mcg',c.category_id,'Short-acting beta-2 agonist bronchodilator pressurised inhaler, 200 doses','GlaxoSmithKline Biologicals Lanka','Unit',40,100,20,400,85,350.00,550.00,'Pharmacy Shelf F-01',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Respiratory Agents' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED031','Enalapril 5mg',c.category_id,'ACE inhibitor antihypertensive and heart failure tablet, 5 mg','Merck (Pvt) Ltd','Tablet',80,250,40,800,190,12.00,20.00,'Pharmacy Shelf C-10',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antihypertensives' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED032','Furosemide 40mg',c.category_id,'Loop diuretic tablet, 40 mg','Hemas Pharmaceuticals (Pvt) Ltd','Tablet',100,300,50,1000,145,5.00,9.00,'Pharmacy Shelf C-11',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Cardiovascular Agents' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED033','Spironolactone 25mg',c.category_id,'Potassium-sparing diuretic and aldosterone antagonist tablet, 25 mg','Aspen Pharmacare Lanka (Pvt) Ltd','Tablet',60,200,30,600,110,20.00,34.00,'Pharmacy Shelf C-12',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Cardiovascular Agents' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED034','Digoxin 0.25mg',c.category_id,'Cardiac glycoside antiarrhythmic tablet, 0.25 mg — narrow therapeutic index','GlaxoSmithKline Biologicals Lanka','Tablet',50,150,25,500,35,15.00,26.00,'Pharmacy Safe Storage D-04',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Cardiovascular Agents' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED035','Clopidogrel 75mg',c.category_id,'ADP receptor antagonist antiplatelet tablet, 75 mg','Sanofi Lanka (Pvt) Ltd','Tablet',100,300,50,1000,230,55.00,88.00,'Pharmacy Safe Storage D-05',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Anticoagulants' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED036','Heparin 5000IU/ml Injection',c.category_id,'Unfractionated heparin anticoagulant injection, 5000 IU/ml — 1 ml ampoule','B. Braun Lanka (Pvt) Ltd','Ampoule',30,80,15,300,12,280.00,420.00,'Pharmacy Safe Storage D-06',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Anticoagulants' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED037','Loratadine 10mg',c.category_id,'Non-sedating second-generation antihistamine tablet, 10 mg','Hemas Pharmaceuticals (Pvt) Ltd','Tablet',100,300,50,1000,420,8.00,14.00,'Pharmacy Shelf F-03',90,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='Antihistamines' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED038','Chlorpheniramine 4mg',c.category_id,'First-generation antihistamine tablet, 4 mg','CIC Holdings — CIC Pharma','Tablet',100,300,50,1000,360,4.00,7.00,'Pharmacy Shelf F-04',90,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='Antihistamines' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED039','Vitamin B Complex',c.category_id,'B-vitamin complex tablet (B1, B2, B3, B5, B6, B12)','Hemas Pharmaceuticals (Pvt) Ltd','Tablet',150,500,75,2000,580,5.00,9.00,'Pharmacy Shelf G-02',180,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='Vitamins' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED040','Folic Acid 5mg',c.category_id,'Folate supplement tablet, 5 mg — for anaemia and pregnancy','Aspen Pharmacare Lanka (Pvt) Ltd','Tablet',100,300,50,1000,340,3.50,6.00,'Pharmacy Shelf G-03',180,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Vitamins' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED041','Ferrous Sulphate 200mg',c.category_id,'Ferrous iron supplement tablet, 200 mg — for iron deficiency anaemia','CIC Holdings — CIC Pharma','Tablet',100,300,50,1000,255,4.00,7.00,'Pharmacy Shelf G-04',180,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Vitamins' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED042','Calcium Carbonate 500mg',c.category_id,'Calcium supplement and antacid tablet, 500 mg','Hemas Pharmaceuticals (Pvt) Ltd','Tablet',150,400,75,1500,470,6.00,10.00,'Pharmacy Shelf G-05',180,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='Vitamins' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED043','Multivitamin Tablet',c.category_id,'Multi-micronutrient supplement tablet with A, C, D, E, B-complex, zinc','Hemas Pharmaceuticals (Pvt) Ltd','Tablet',200,600,100,2500,780,8.00,14.00,'Pharmacy Shelf G-06',180,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='Vitamins' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED044','Dextrose 5% 500ml',c.category_id,'Isotonic glucose intravenous infusion bag, 5% dextrose 500 ml','B. Braun Lanka (Pvt) Ltd','Bag',40,120,20,400,72,185.00,265.00,'IV Store Room H-02',60,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='IV Fluids' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED045',"Ringer's Lactate 500ml",c.category_id,"Isotonic balanced electrolyte IV infusion bag (Hartmann's solution), 500 ml",'B. Braun Lanka (Pvt) Ltd','Bag',40,120,20,400,65,190.00,275.00,'IV Store Room H-03',60,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='IV Fluids' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED046','Prednisolone 5mg',c.category_id,'Synthetic glucocorticoid corticosteroid tablet, 5 mg — anti-inflammatory','CIC Holdings — CIC Pharma','Tablet',80,250,40,800,195,8.00,14.00,'Pharmacy Safe Storage D-07',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Steroids' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED047','Hydrocortisone Injection 100mg',c.category_id,'Cortisol IV/IM corticosteroid injection, 100 mg — emergency anaphylaxis','Pfizer Lanka (Pvt) Ltd','Vial',20,60,10,200,38,650.00,980.00,'Pharmacy Safe Storage D-08',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Steroids' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED048','Methylprednisolone 4mg',c.category_id,'Synthetic corticosteroid tablet, 4 mg — for severe inflammatory conditions','Merck (Pvt) Ltd','Tablet',50,150,25,500,88,45.00,72.00,'Pharmacy Safe Storage D-09',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Steroids' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED049','Syringes 5ml',c.category_id,'Sterile disposable syringe 5 ml with 23G needle — box of 100','Terumo Lanka (Pvt) Ltd','Box',10,30,5,100,24,950.00,1400.00,'Storeroom I-01',365,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='Syringes/Consumables' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED050','Syringes 10ml',c.category_id,'Sterile disposable syringe 10 ml with 21G needle — box of 100','Terumo Lanka (Pvt) Ltd','Box',10,30,5,100,18,1200.00,1750.00,'Storeroom I-02',365,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='Syringes/Consumables' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED051','Surgical Gloves Medium',c.category_id,'Sterile latex surgical gloves, size Medium — box of 50 pairs','Sri Lanka Rubber Research Institute','Box',15,40,8,150,32,2200.00,3200.00,'Storeroom I-03',1095,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='Gloves/Consumables' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED052','Phenobarbitone 30mg',c.category_id,'Barbiturate anticonvulsant tablet, 30 mg — controlled drug, anti-epileptic','CIC Holdings — CIC Pharma','Tablet',60,200,30,600,42,6.00,10.00,'Pharmacy Safe Storage D-10',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Anticonvulsants' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED053','Atenolol 50mg',c.category_id,'Cardioselective beta-1 blocker antihypertensive tablet, 50 mg','Aspen Pharmacare Lanka (Pvt) Ltd','Tablet',100,300,50,1000,280,10.00,17.00,'Pharmacy Shelf C-13',90,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antihypertensives' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED054','Clindamycin 150mg',c.category_id,'Lincosamide antibiotic capsule, 150 mg — anaerobic coverage','Cipla Ltd','Capsule',60,200,30,600,130,42.00,68.00,'Pharmacy Shelf B-07',60,TRUE,TRUE FROM inventory_categories c WHERE c.category_name='Antibiotics' LIMIT 1;

INSERT IGNORE INTO inventory_items (item_code,item_name,category_id,description,manufacturer,unit_of_measure,reorder_level,reorder_quantity,minimum_stock_level,maximum_stock_level,current_stock,unit_price,selling_price,location,expiry_alert_days,requires_prescription,is_active)
SELECT 'MED055','Albendazole 400mg',c.category_id,'Benzimidazole anthelmintic tablet, 400 mg — for intestinal worm infections','GlaxoSmithKline Biologicals Lanka','Tablet',100,300,50,1000,320,18.00,30.00,'Pharmacy Shelf B-08',90,FALSE,TRUE FROM inventory_categories c WHERE c.category_name='Antibiotics' LIMIT 1;

-- ── Seed inventory batches for key drugs — FR-32 expiry tracking ─────
INSERT IGNORE INTO inventory_batches (item_id,batch_number,manufacture_date,expiry_date,quantity,remaining_quantity,cost_per_unit,supplier_id,received_date,status)
SELECT i.item_id,'BATCH-PC01',DATE_SUB(CURDATE(),INTERVAL 6 MONTH),DATE_ADD(CURDATE(),INTERVAL 18 MONTH),500,450,4.50,s.supplier_id,DATE_SUB(CURDATE(),INTERVAL 30 DAY),'Active'
FROM inventory_items i,suppliers s WHERE i.item_code='MED001' AND s.supplier_code='SUP001' LIMIT 1;

INSERT IGNORE INTO inventory_batches (item_id,batch_number,manufacture_date,expiry_date,quantity,remaining_quantity,cost_per_unit,supplier_id,received_date,status)
SELECT i.item_id,'BATCH-AX01',DATE_SUB(CURDATE(),INTERVAL 4 MONTH),DATE_ADD(CURDATE(),INTERVAL 14 MONTH),400,320,15.00,s.supplier_id,DATE_SUB(CURDATE(),INTERVAL 20 DAY),'Active'
FROM inventory_items i,suppliers s WHERE i.item_code='MED002' AND s.supplier_code='SUP002' LIMIT 1;

INSERT IGNORE INTO inventory_batches (item_id,batch_number,manufacture_date,expiry_date,quantity,remaining_quantity,cost_per_unit,supplier_id,received_date,status)
SELECT i.item_id,'BATCH-MF01',DATE_SUB(CURDATE(),INTERVAL 2 MONTH),DATE_ADD(CURDATE(),INTERVAL 22 MONTH),300,180,10.00,s.supplier_id,DATE_SUB(CURDATE(),INTERVAL 15 DAY),'Active'
FROM inventory_items i,suppliers s WHERE i.item_code='MED003' AND s.supplier_code='SUP001' LIMIT 1;

INSERT IGNORE INTO inventory_batches (item_id,batch_number,manufacture_date,expiry_date,quantity,remaining_quantity,cost_per_unit,supplier_id,received_date,status)
SELECT i.item_id,'BATCH-AM01',DATE_SUB(CURDATE(),INTERVAL 8 MONTH),DATE_ADD(CURDATE(),INTERVAL 16 MONTH),200,95,19.00,s.supplier_id,DATE_SUB(CURDATE(),INTERVAL 45 DAY),'Active'
FROM inventory_items i,suppliers s WHERE i.item_code='MED004' AND s.supplier_code='SUP003' LIMIT 1;

INSERT IGNORE INTO inventory_batches (item_id,batch_number,manufacture_date,expiry_date,quantity,remaining_quantity,cost_per_unit,supplier_id,received_date,status)
SELECT i.item_id,'BATCH-WF01',DATE_SUB(CURDATE(),INTERVAL 4 MONTH),DATE_ADD(CURDATE(),INTERVAL 20 MONTH),100,25,58.00,s.supplier_id,DATE_SUB(CURDATE(),INTERVAL 60 DAY),'Active'
FROM inventory_items i,suppliers s WHERE i.item_code='MED005' AND s.supplier_code='SUP002' LIMIT 1;

-- Near-expiry batch for MED009 (Normal Saline) — demonstrates FR-32 alert
INSERT IGNORE INTO inventory_batches (item_id,batch_number,manufacture_date,expiry_date,quantity,remaining_quantity,cost_per_unit,supplier_id,received_date,status)
SELECT i.item_id,'BATCH-NS01',DATE_SUB(CURDATE(),INTERVAL 5 MONTH),DATE_ADD(CURDATE(),INTERVAL 10 MONTH),80,38,170.00,s.supplier_id,DATE_SUB(CURDATE(),INTERVAL 40 DAY),'Active'
FROM inventory_items i,suppliers s WHERE i.item_code='MED009' AND s.supplier_code='SUP003' LIMIT 1;

-- Insulin Glargine batch expiring in 25 days — FR-32 refrigerator alert
INSERT IGNORE INTO inventory_batches (item_id,batch_number,manufacture_date,expiry_date,quantity,remaining_quantity,cost_per_unit,supplier_id,received_date,status)
SELECT i.item_id,'BATCH-IN01',DATE_SUB(CURDATE(),INTERVAL 8 MONTH),DATE_ADD(CURDATE(),INTERVAL 25 DAY),12,8,2900.00,s.supplier_id,DATE_SUB(CURDATE(),INTERVAL 60 DAY),'Active'
FROM inventory_items i,suppliers s WHERE i.item_code='MED029' AND s.supplier_code='SUP003' LIMIT 1;

-- ── Seed medications table from inventory (for DemandForecaster FR-38) ──
INSERT IGNORE INTO medications (item_id,drug_code,drug_name,generic_name,drug_class,current_stock,unit_of_measure,requires_prescription,is_active)
SELECT i.item_id, CONCAT('DR-',LPAD(i.item_id,4,'0')), i.item_name, i.item_name, c.category_name,
       i.current_stock, i.unit_of_measure, i.requires_prescription, i.is_active
FROM inventory_items i
JOIN inventory_categories c ON i.category_id=c.category_id
WHERE i.item_code LIKE 'MED%' AND c.category_type='Medicine';

COMMIT;

SELECT CONCAT(
    'SmartCare Hospital ERP — All modules schema applied. ',
    (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'hospital_erp' AND TABLE_TYPE='BASE TABLE'),
    ' tables | ',
    (SELECT COUNT(*) FROM inventory_items WHERE item_code LIKE 'MED%'),
    ' drugs seeded.'
) AS Status;
