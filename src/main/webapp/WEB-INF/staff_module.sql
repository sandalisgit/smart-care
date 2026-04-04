-- =============================================================================
-- SmartCare Staff & Clinical Portal — Supplemental Schema
-- FR-61: Staff profiles  FR-62: Shift scheduling  FR-63: Leave workflow
-- FR-64: Attendance      FR-65: Clinical dashboards
-- Run AFTER SMARTCARE_COMPLETE_DATABASE.sql
-- =============================================================================

USE hospital_erp;

-- =============================================================================
-- SHIFTS TABLE (FR-62: Shift scheduling with conflict detection)
-- =============================================================================
CREATE TABLE IF NOT EXISTS shifts (
    shift_id        INT PRIMARY KEY AUTO_INCREMENT,
    employee_id     INT NOT NULL,
    shift_date      DATE NOT NULL,
    shift_type      ENUM('Day','Evening','Night','On-Call') NOT NULL,
    start_time      TIME NOT NULL,
    end_time        TIME NOT NULL,
    department_id   INT NULL,
    notes           VARCHAR(255),
    created_by      INT,                        -- user_id of scheduler
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (employee_id)   REFERENCES employees(employee_id)   ON DELETE CASCADE,
    FOREIGN KEY (department_id) REFERENCES departments(department_id) ON DELETE SET NULL,
    -- Prevents same employee having same shift type on the same date twice
    UNIQUE KEY uq_emp_date_type (employee_id, shift_date, shift_type)
);

-- =============================================================================
-- VIEWS
-- =============================================================================

-- v_staff_stats: Aggregate KPIs for admin dashboard stat cards (FR-61)
CREATE OR REPLACE VIEW v_staff_stats AS
SELECT
    COUNT(*)                                                      AS total_employees,
    SUM(CASE WHEN status = 'Active'     THEN 1 ELSE 0 END)       AS active_employees,
    SUM(CASE WHEN status = 'On Leave'   THEN 1 ELSE 0 END)       AS on_leave,
    SUM(CASE WHEN employee_type = 'Doctor'  THEN 1 ELSE 0 END)   AS total_doctors,
    SUM(CASE WHEN employee_type = 'Nurse'   THEN 1 ELSE 0 END)   AS total_nurses,
    SUM(CASE WHEN employment_type = 'Full-time'  THEN 1 ELSE 0 END) AS full_time,
    SUM(CASE WHEN employment_type = 'Part-time'  THEN 1 ELSE 0 END) AS part_time
FROM employees;

-- v_shift_schedule: Shift list enriched with employee and department names
CREATE OR REPLACE VIEW v_shift_schedule AS
SELECT
    s.shift_id,
    s.shift_date,
    s.shift_type,
    s.start_time,
    s.end_time,
    s.notes,
    e.employee_id,
    CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
    e.employee_type,
    e.job_title,
    d.department_id,
    d.department_name
FROM shifts s
JOIN  employees   e ON s.employee_id   = e.employee_id
LEFT JOIN departments d ON s.department_id = d.department_id;

-- v_attendance_summary: Current-month attendance rollup per employee
CREATE OR REPLACE VIEW v_attendance_summary AS
SELECT
    e.employee_id,
    CONCAT(e.first_name, ' ', e.last_name)        AS full_name,
    e.employee_type,
    d.department_name,
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

-- =============================================================================
-- PERFORMANCE INDEXES
-- =============================================================================

-- Shifts: common filters
CREATE INDEX IF NOT EXISTS idx_shifts_emp_date
    ON shifts (employee_id, shift_date);
CREATE INDEX IF NOT EXISTS idx_shifts_dept_date
    ON shifts (department_id, shift_date);
CREATE INDEX IF NOT EXISTS idx_shifts_date_type
    ON shifts (shift_date, shift_type);

-- Attendance: date range queries
CREATE INDEX IF NOT EXISTS idx_att_emp_date
    ON attendance (employee_id, date);

-- Leave requests: status queries
CREATE INDEX IF NOT EXISTS idx_leave_status
    ON leave_requests (status, created_at);
CREATE INDEX IF NOT EXISTS idx_leave_emp
    ON leave_requests (employee_id, status);

-- =============================================================================
-- SEED: Sample shift data for current week (idempotent — INSERT IGNORE)
-- Demonstrates FR-62 shift scheduling across roles
-- =============================================================================
DELIMITER $$
CREATE PROCEDURE IF NOT EXISTS seed_weekly_shifts()
BEGIN
    DECLARE today DATE DEFAULT CURDATE();
    DECLARE mon   DATE DEFAULT today - INTERVAL (DAYOFWEEK(today) - 2) DAY;

    -- Day shifts: first 3 active employees (Mon–Fri)
    INSERT IGNORE INTO shifts (employee_id, shift_date, shift_type, start_time, end_time, notes, created_by)
    SELECT e.employee_id, mon + INTERVAL n.n DAY, 'Day', '07:00:00', '15:00:00', 'Day shift', 1
    FROM employees e CROSS JOIN (
        SELECT 0 n UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
    ) n
    WHERE e.status = 'Active'
    LIMIT 15;

    -- Night shifts: next 2 active employees (Mon–Thu)
    INSERT IGNORE INTO shifts (employee_id, shift_date, shift_type, start_time, end_time, notes, created_by)
    SELECT e.employee_id, mon + INTERVAL n.n DAY, 'Night', '23:00:00', '07:00:00', 'Night shift', 1
    FROM employees e CROSS JOIN (
        SELECT 0 n UNION SELECT 1 UNION SELECT 2 UNION SELECT 3
    ) n
    WHERE e.status = 'Active'
    LIMIT 8;
END$$
DELIMITER ;

CALL seed_weekly_shifts();
