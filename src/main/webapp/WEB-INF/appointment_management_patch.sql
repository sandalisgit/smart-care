-- =============================================================================
-- Appointment Management Patch
-- FR-11..FR-20: Scheduling, conflict detection, reminders, no-show prediction
-- Run after SMARTCARE_COMPLETE_DATABASE.sql
-- =============================================================================

USE hospital_erp;

-- ---------------------------------------------------------------------------
-- 1. Extend appointments table with audit + cancellation columns
-- ---------------------------------------------------------------------------
ALTER TABLE appointments
    ADD COLUMN IF NOT EXISTS updated_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS cancelled_by   INT NULL,
    ADD COLUMN IF NOT EXISTS cancellation_reason VARCHAR(500) NULL,
    ADD COLUMN IF NOT EXISTS reminder_sent  TINYINT(1) DEFAULT 0 COMMENT 'FR-16: 1 when 24h reminder queued',
    ADD INDEX  IF NOT EXISTS idx_appt_status        (status),
    ADD INDEX  IF NOT EXISTS idx_appt_date_status   (appointment_date, status),
    ADD INDEX  IF NOT EXISTS idx_appt_type          (appointment_type),
    ADD INDEX  IF NOT EXISTS idx_appt_reminder      (reminder_sent, appointment_date);

-- Foreign key for cancelled_by → users (best-effort; skip if users table differs)
-- ALTER TABLE appointments ADD CONSTRAINT fk_appt_cancelled_by
--     FOREIGN KEY (cancelled_by) REFERENCES users(user_id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- 2. AI no-show prediction results (FR-17 / NoShowPredictor.savePrediction)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS no_show_features (
    id               INT            PRIMARY KEY AUTO_INCREMENT,
    appointment_id   INT            NOT NULL UNIQUE,
    prediction_score DOUBLE         NOT NULL COMMENT '0.0–1.0 probability of no-show',
    model_version    VARCHAR(20)    DEFAULT 'rf-v1',
    predicted_at     TIMESTAMP      DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_nsf_appt FOREIGN KEY (appointment_id)
        REFERENCES appointments(appointment_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 3. Reminder tracking table (FR-16 automated email reminders)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS appointment_reminders (
    reminder_id      INT            PRIMARY KEY AUTO_INCREMENT,
    appointment_id   INT            NOT NULL,
    reminder_type    ENUM('EMAIL','SMS') NOT NULL,
    scheduled_at     TIMESTAMP      NOT NULL COMMENT 'When the reminder should fire',
    sent_at          TIMESTAMP      NULL,
    status           ENUM('Pending','Sent','Failed') DEFAULT 'Pending',
    error_message    VARCHAR(500)   NULL,
    created_at       TIMESTAMP      DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_reminder_appt FOREIGN KEY (appointment_id)
        REFERENCES appointments(appointment_id) ON DELETE CASCADE,
    INDEX idx_reminders_pending  (status, scheduled_at),
    INDEX idx_reminders_appt     (appointment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 4. Calendar view — joins appointments with patient + doctor + risk score
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_appointment_calendar AS
SELECT
    a.appointment_id,
    a.patient_id,
    a.doctor_id,
    a.appointment_date,
    a.appointment_time,
    a.appointment_type,
    a.status,
    a.reason,
    a.consultation_fee,
    a.reminder_sent,
    a.cancellation_reason,
    a.created_at,
    a.updated_at,
    CONCAT(p.first_name, ' ', p.last_name)  AS patient_name,
    p.phone                                  AS patient_phone,
    p.patient_code,
    p.blood_group,
    p.allergies,
    CONCAT(e.first_name, ' ', e.last_name)  AS doctor_name,
    d.specialization,
    nsf.prediction_score                     AS no_show_risk
FROM appointments a
JOIN  patients  p   ON a.patient_id   = p.patient_id
JOIN  doctors   d   ON a.doctor_id    = d.doctor_id
JOIN  employees e   ON d.employee_id  = e.employee_id
LEFT  JOIN no_show_features nsf ON a.appointment_id = nsf.appointment_id;

-- ---------------------------------------------------------------------------
-- 5. Daily stats view
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_appointment_daily_stats AS
SELECT
    appointment_date,
    COUNT(*)                                         AS total,
    SUM(status = 'Scheduled')                        AS scheduled,
    SUM(status = 'Confirmed')                        AS confirmed,
    SUM(status = 'In Progress')                      AS in_progress,
    SUM(status = 'Completed')                        AS completed,
    SUM(status = 'Cancelled')                        AS cancelled,
    SUM(status = 'No Show')                          AS no_show,
    ROUND(AVG(nsf.prediction_score) * 100, 1)        AS avg_no_show_risk_pct
FROM appointments a
LEFT JOIN no_show_features nsf ON a.appointment_id = nsf.appointment_id
GROUP BY appointment_date;
