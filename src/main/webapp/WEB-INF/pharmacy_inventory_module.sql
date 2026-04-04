-- ====================================================================
-- SmartCare — Pharmacy & Inventory Module — Complete Schema
-- MySQL 8.0 | hospital_erp database
-- Run AFTER: SMARTCARE_COMPLETE_DATABASE.sql, db_additions.sql,
--            pharmacy_schema_patch.sql
--
-- FR-31: Real-time stock management with current_stock column
-- FR-32: Batch-level expiry tracking (30-day warning window)
-- FR-33: Auto stock deduction on prescription dispensing (FIFO)
-- FR-34: Audit every dispensing event in stock_transactions
-- FR-35: Supplier and purchase order management
-- FR-36: AI demand forecasting via medications + dispensing_log
-- FR-37: Low-stock threshold alerts via v_low_stock_items view
-- FR-38: Predictive demand forecasting via DemandForecaster AI
-- FR-39: Link prescriptions from EMR module
-- FR-40: Tamper-evident audit log on every dispensing event
-- ====================================================================

USE hospital_erp;

-- ────────────────────────────────────────────────────────────────────
-- SECTION 1: medications table
-- Required by DemandForecaster (FR-36/FR-38).
-- Links to inventory_items so current_stock is always consistent.
-- ────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS medications (
    medication_id    INT           NOT NULL AUTO_INCREMENT,
    item_id          INT           NOT NULL UNIQUE,   -- FK → inventory_items
    drug_code        VARCHAR(20)   NOT NULL UNIQUE,   -- e.g. DR-0001
    drug_name        VARCHAR(200)  NOT NULL,
    generic_name     VARCHAR(200)  NULL,
    drug_class       VARCHAR(100)  NULL,              -- Antibiotic, Analgesic …
    current_stock    INT           NOT NULL DEFAULT 0,-- denormalised for fast AI reads
    unit_of_measure  VARCHAR(20)   NOT NULL DEFAULT 'Tablet',
    requires_prescription BOOLEAN  NOT NULL DEFAULT FALSE,
    is_active        BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                       ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (medication_id),
    CONSTRAINT fk_med_item FOREIGN KEY (item_id)
        REFERENCES inventory_items (item_id) ON DELETE CASCADE,
    INDEX idx_drug_code  (drug_code),
    INDEX idx_drug_name  (drug_name),
    INDEX idx_is_active  (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='FR-36/FR-38: DemandForecaster medication catalogue, mirrors inventory_items';

-- ────────────────────────────────────────────────────────────────────
-- SECTION 2: Seed medications from existing inventory items
-- Generates DR-XXXX drug codes and links each medicine to its
-- inventory_items row so current_stock stays in sync.
-- ────────────────────────────────────────────────────────────────────

INSERT IGNORE INTO medications
    (item_id, drug_code, drug_name, generic_name, drug_class,
     current_stock, unit_of_measure, requires_prescription, is_active)
SELECT
    i.item_id,
    CONCAT('DR-', LPAD(i.item_id, 4, '0')),   -- DR-0001 … DR-0010
    i.item_name,
    i.item_name,                                -- use item_name as generic fallback
    c.category_name,
    i.current_stock,
    i.unit_of_measure,
    i.requires_prescription,
    i.is_active
FROM inventory_items i
JOIN inventory_categories c ON i.category_id = c.category_id
WHERE c.category_type = 'Medicine';

-- ────────────────────────────────────────────────────────────────────
-- SECTION 3: Trigger — keep medications.current_stock in sync
-- Fires after every UPDATE on inventory_items.current_stock so
-- the DemandForecaster always reads fresh stock levels.
-- FR-31: Real-time stock management.
-- ────────────────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_sync_medication_stock;
DELIMITER //
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

-- ────────────────────────────────────────────────────────────────────
-- SECTION 4: Stored procedure — seed 45 days of dispensing_log
-- Creates synthetic dispense events across the 10 seeded medicines
-- so the WMA-based DemandForecaster has sufficient history.
-- FR-36/FR-38: AI demand forecasting requires ≥ 7 days of history.
-- NFR-34: Synthetic data only — no real patient PII used.
-- ────────────────────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS seed_dispensing_log;
DELIMITER //
CREATE PROCEDURE seed_dispensing_log()
BEGIN
    DECLARE v_day     INT DEFAULT 0;
    DECLARE v_med_id  INT;
    DECLARE v_item_id INT;
    DECLARE v_pat_id  INT DEFAULT 1;    -- synthetic patient anchor
    DECLARE v_user_id INT DEFAULT 1;    -- pharmacist anchor (admin user)
    DECLARE v_qty     INT;
    DECLARE v_stock   INT;
    DECLARE v_disp_ts DATETIME;

    -- Only seed if dispensing_log is empty to avoid duplicate runs
    IF (SELECT COUNT(*) FROM dispensing_log) = 0 THEN
        SET v_day = 0;
        WHILE v_day < 45 DO
            -- Loop over 10 medicines (DR-0001 to DR-0010)
            SET v_med_id = 1;
            WHILE v_med_id <= 10 DO
                SELECT medication_id INTO v_med_id
                  FROM medications WHERE medication_id = v_med_id LIMIT 1;

                SELECT item_id INTO v_item_id
                  FROM medications WHERE medication_id = v_med_id LIMIT 1;

                -- Weekday multiplier: fewer on Sun (day 0) and Sat (day 6)
                SET v_qty = CASE
                    WHEN DAYOFWEEK(DATE_SUB(CURDATE(), INTERVAL v_day DAY)) IN (1,7)
                        THEN FLOOR(3 + RAND() * 5)
                    ELSE FLOOR(8 + RAND() * 15)
                END;

                -- Skip if no stock
                SELECT current_stock INTO v_stock
                  FROM inventory_items WHERE item_id = v_item_id LIMIT 1;

                IF v_stock IS NULL THEN
                    SET v_stock = 0;
                END IF;

                IF v_stock >= v_qty THEN
                    SET v_disp_ts = DATE_SUB(
                        NOW(), INTERVAL (v_day * 1440 - FLOOR(480 + RAND() * 480)) MINUTE
                    );

                    INSERT INTO dispensing_log
                        (prescription_id, medication_id, pharmacist_id, patient_id,
                         quantity, stock_before, stock_after, dispensed_at)
                    VALUES
                        (NULL, v_med_id, v_user_id, v_pat_id,
                         v_qty, v_stock, v_stock - v_qty, v_disp_ts);
                END IF;

                SET v_med_id = v_med_id + 1;
            END WHILE;

            SET v_day = v_day + 1;
        END WHILE;
    END IF;
END //
DELIMITER ;

-- Execute seeding (idempotent — no-op if data already present)
CALL seed_dispensing_log();
DROP PROCEDURE IF EXISTS seed_dispensing_log;

-- ────────────────────────────────────────────────────────────────────
-- SECTION 5: View — v_low_stock_items (recreate with item_id for DAO)
-- FR-37: Low-stock threshold alerts.
-- Adds item_id so PharmacyDAO can link rows back to inventory_items.
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW v_low_stock_items AS
SELECT
    i.item_id,
    i.item_code,
    i.item_name,
    c.category_name,
    i.current_stock,
    i.reorder_level,
    i.minimum_stock_level,
    i.reorder_quantity,
    i.unit_of_measure,
    i.selling_price,
    CASE
        WHEN i.current_stock <= i.minimum_stock_level THEN 'Critical'
        WHEN i.current_stock <= i.reorder_level       THEN 'Low'
        ELSE 'Normal'
    END AS stock_status
FROM  inventory_items i
JOIN  inventory_categories c ON i.category_id = c.category_id
WHERE i.current_stock <= i.reorder_level
  AND i.is_active = TRUE
ORDER BY
    CASE WHEN i.current_stock <= i.minimum_stock_level THEN 1 ELSE 2 END,
    i.current_stock ASC;

-- ────────────────────────────────────────────────────────────────────
-- SECTION 6: View — v_expiring_items (30-day window)
-- FR-32: Expiry date tracking with 30-day warning.
-- Uses per-item expiry_alert_days OR 30 days, whichever is larger.
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW v_expiring_items AS
SELECT
    ib.batch_id,
    i.item_id,
    i.item_code,
    i.item_name,
    ib.batch_number,
    ib.expiry_date,
    ib.remaining_quantity,
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
WHERE ib.status             = 'Active'
  AND ib.remaining_quantity > 0
  AND DATEDIFF(ib.expiry_date, CURDATE()) <= GREATEST(i.expiry_alert_days, 30)
ORDER BY ib.expiry_date ASC;

-- ────────────────────────────────────────────────────────────────────
-- SECTION 7: View — v_dispensing_audit (FR-40 audit trail)
-- Joins stock_transactions (type=Sale) with item and user info
-- for the Dispensing Log tab and audit reporting.
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW v_dispensing_audit AS
SELECT
    t.transaction_id                                      AS log_id,
    t.transaction_date                                    AS dispensed_at,
    CONCAT(u.first_name, ' ', u.last_name)                AS pharmacist_name,
    u.user_id                                             AS pharmacist_id,
    t.reference_id                                        AS prescription_id,
    i.item_name                                           AS drug_name,
    i.item_code                                           AS drug_code,
    t.quantity                                            AS qty_dispensed,
    t.remarks
FROM  stock_transactions t
JOIN  inventory_items    i ON t.item_id       = i.item_id
JOIN  users              u ON t.performed_by  = u.user_id
WHERE t.transaction_type = 'Sale'
ORDER BY t.transaction_date DESC;

-- ────────────────────────────────────────────────────────────────────
-- SECTION 8: View — v_inventory_demand_forecast
-- Computes a simple 14-day rolling average per item from
-- stock_transactions so the dashboard can surface forecast hints
-- without calling the Java AI layer.  Used as a fallback display.
-- FR-38 data feed.
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW v_inventory_demand_forecast AS
SELECT
    i.item_id,
    i.item_code,
    i.item_name,
    i.current_stock,
    i.reorder_level,
    COALESCE(SUM(t.quantity), 0)                           AS units_last_14_days,
    ROUND(COALESCE(SUM(t.quantity), 0) / 14.0, 2)         AS avg_daily_demand,
    ROUND(COALESCE(SUM(t.quantity), 0) / 14.0 * 7, 0)    AS forecast_7_days,
    ROUND(COALESCE(SUM(t.quantity), 0) / 14.0 * 30, 0)   AS forecast_30_days,
    CASE
        WHEN i.current_stock < ROUND(COALESCE(SUM(t.quantity),0)/14.0*7,0) THEN 'Restock Needed'
        ELSE 'Adequate'
    END AS restock_recommendation
FROM  inventory_items    i
LEFT JOIN stock_transactions t
       ON t.item_id          = i.item_id
      AND t.transaction_type = 'Sale'
      AND t.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 14 DAY)
WHERE i.is_active = TRUE
GROUP BY i.item_id, i.item_code, i.item_name, i.current_stock, i.reorder_level
ORDER BY avg_daily_demand DESC;

-- ────────────────────────────────────────────────────────────────────
-- SECTION 9: Additional index for performance
-- FR-31/FR-33: Fast stock-level queries during high dispense volume.
-- ────────────────────────────────────────────────────────────────────

-- Index on stock_transactions for dispensing audit queries
CREATE INDEX IF NOT EXISTS idx_st_type_date
    ON stock_transactions (transaction_type, transaction_date);

-- Index on inventory_batches for FIFO expiry ordering
CREATE INDEX IF NOT EXISTS idx_batch_fifo
    ON inventory_batches (item_id, status, expiry_date);

-- ────────────────────────────────────────────────────────────────────
-- Completion marker
-- ────────────────────────────────────────────────────────────────────

SELECT 'Pharmacy Inventory Module schema applied successfully.' AS result;
