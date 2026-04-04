-- =============================================================================
-- BED & WARD MANAGEMENT MODULE — PATCH
-- FR-51: Real-time bed availability    FR-52: Admit patient to bed
-- FR-53: Discharge and bed release     FR-54: Prevent double assignment
-- FR-55: Housekeeping status           FR-56: Occupancy AI forecast
-- FR-57: AI bed assignment             FR-58: Bed event audit logging
-- FR-59: Bed utilisation report        FR-60: Ward occupancy notifications
-- Run AFTER SMARTCARE_COMPLETE_DATABASE.sql and db_additions.sql
-- =============================================================================

USE hospital_erp;

-- ---------------------------------------------------------------------------
-- bed_transfers — record every inter-ward / inter-room transfer (FR-56)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bed_transfers (
    transfer_id    INT PRIMARY KEY AUTO_INCREMENT,
    admission_id   INT NOT NULL,
    from_bed_id    INT NOT NULL,
    from_ward_id   INT NOT NULL,
    to_bed_id      INT NOT NULL,
    to_ward_id     INT NOT NULL,
    transfer_reason TEXT,
    transferred_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    transferred_by  INT NOT NULL,
    FOREIGN KEY (admission_id)  REFERENCES admissions(admission_id),
    FOREIGN KEY (from_bed_id)   REFERENCES beds(bed_id),
    FOREIGN KEY (to_bed_id)     REFERENCES beds(bed_id),
    FOREIGN KEY (transferred_by) REFERENCES users(user_id),
    INDEX idx_admission (admission_id),
    INDEX idx_transferred_at (transferred_at DESC)
);

-- ---------------------------------------------------------------------------
-- v_ward_stats — aggregate KPIs for the dashboard header (FR-51)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_ward_stats AS
SELECT
    COUNT(DISTINCT w.ward_id)                                         AS total_wards,
    COALESCE(SUM(w.total_beds), 0)                                   AS total_beds,
    COALESCE(SUM(w.total_beds - w.available_beds), 0)                AS occupied_beds,
    COALESCE(SUM(w.available_beds), 0)                               AS available_beds,
    ROUND(
        COALESCE(SUM(w.total_beds - w.available_beds), 0)
        / NULLIF(SUM(w.total_beds), 0) * 100, 1)                    AS overall_occupancy_pct,
    COUNT(CASE WHEN (w.total_beds - w.available_beds)
               / NULLIF(w.total_beds, 0) >= 0.85 THEN 1 END)        AS critical_wards,
    (SELECT COUNT(*) FROM admissions WHERE status = 'Admitted')      AS current_patients
FROM wards w
WHERE w.is_active = TRUE;

-- ---------------------------------------------------------------------------
-- v_transfer_history — human-readable transfer log (FR-58)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_transfer_history AS
SELECT
    bt.transfer_id,
    bt.transferred_at,
    bt.transfer_reason,
    bt.admission_id,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    p.patient_code,
    fw.ward_name  AS from_ward,
    fb.bed_number AS from_bed,
    tw.ward_name  AS to_ward,
    tb.bed_number AS to_bed,
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

-- ---------------------------------------------------------------------------
-- v_bed_status_summary — breakdown per ward type (FR-51, FR-59)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_bed_status_summary AS
SELECT
    w.ward_type,
    COUNT(b.bed_id)                                   AS total_beds,
    SUM(CASE WHEN b.is_occupied = TRUE  THEN 1 ELSE 0 END) AS occupied,
    SUM(CASE WHEN b.is_occupied = FALSE
              AND b.is_operational = TRUE THEN 1 ELSE 0 END) AS available,
    SUM(CASE WHEN b.is_operational = FALSE THEN 1 ELSE 0 END) AS maintenance,
    SUM(CASE WHEN b.is_occupied = FALSE
              AND b.last_sanitized IS NULL THEN 1 ELSE 0 END) AS needs_sanitizing
FROM beds b
JOIN rooms r  ON b.room_id  = r.room_id
JOIN wards w  ON r.ward_id  = w.ward_id
WHERE w.is_active = TRUE
GROUP BY w.ward_type
ORDER BY w.ward_type;

-- ---------------------------------------------------------------------------
-- Seed ward_occupancy_snapshots with 8 weeks of synthetic data (NFR-34)
-- so WardOccupancyPredictor has enough history for Holt-Winters
-- Uses INSERT IGNORE to be idempotent
-- ---------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS seed_ward_occupancy;
DELIMITER //
CREATE PROCEDURE seed_ward_occupancy()
BEGIN
    DECLARE done   INT DEFAULT FALSE;
    DECLARE wid    INT;
    DECLARE tbeds  INT;
    DECLARE cur CURSOR FOR SELECT ward_id, total_beds FROM wards WHERE is_active = TRUE;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN cur;
    ward_loop: LOOP
        FETCH cur INTO wid, tbeds;
        IF done THEN LEAVE ward_loop; END IF;

        SET @d = 0;
        WHILE @d < 56 DO
            SET @snap_date = DATE_SUB(CURDATE(), INTERVAL @d DAY);
            -- Weekday occupancy 70-85%, weekend 55-65%
            SET @dow = DAYOFWEEK(@snap_date); -- 1=Sun, 7=Sat
            SET @base = IF(@dow IN (1,7), 0.60, 0.75);
            SET @rate = @base + (RAND() * 0.15 - 0.07);
            SET @rate = GREATEST(0.30, LEAST(0.98, @rate));
            SET @occ  = ROUND(@rate * tbeds);

            INSERT IGNORE INTO ward_occupancy_snapshots
                (ward_id, snap_date, total_beds, occupied_beds)
            VALUES (wid, @snap_date, tbeds, @occ);

            SET @d = @d + 1;
        END WHILE;
    END LOOP;
    CLOSE cur;
END //
DELIMITER ;

CALL seed_ward_occupancy();
DROP PROCEDURE IF EXISTS seed_ward_occupancy;

-- ---------------------------------------------------------------------------
-- Performance indexes (idempotent)
-- ---------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_adm_status       ON admissions;
DROP INDEX IF EXISTS idx_adm_patient_stat ON admissions;
DROP INDEX IF EXISTS idx_beds_occ_ops     ON beds;
DROP INDEX IF EXISTS idx_rooms_ward       ON rooms;

CREATE INDEX idx_adm_status       ON admissions (status);
CREATE INDEX idx_adm_patient_stat ON admissions (patient_id, status);
CREATE INDEX idx_beds_occ_ops     ON beds (is_occupied, is_operational);
CREATE INDEX idx_rooms_ward       ON rooms (ward_id);
