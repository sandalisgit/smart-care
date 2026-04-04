-- ============================================================
-- Lab Tests Column Patch
-- Adds columns that were in emr_schema_patch.sql but missing
-- from the original SMARTCARE_COMPLETE_DATABASE.sql table.
-- Idempotent — checks INFORMATION_SCHEMA before each ALTER.
-- Run AFTER: SMARTCARE_COMPLETE_DATABASE.sql
-- ============================================================

-- ── Add 'urgency' column if missing ─────────────────────────
SET @db  = DATABASE();
SET @tbl = 'lab_tests';

SET @has_urgency = (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = @db AND TABLE_NAME = @tbl AND COLUMN_NAME = 'urgency'
);
SET @sql_urgency = IF(@has_urgency > 0,
    'SELECT ''urgency column already exists'' AS info',
    'ALTER TABLE lab_tests ADD COLUMN urgency ENUM(''Routine'',''Urgent'',''STAT'') DEFAULT ''Routine'''
);
PREPARE stmt FROM @sql_urgency;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ── Add 'result_file' column if missing ─────────────────────
SET @has_result_file = (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = @db AND TABLE_NAME = @tbl AND COLUMN_NAME = 'result_file'
);
SET @sql_rf = IF(@has_result_file > 0,
    'SELECT ''result_file column already exists'' AS info',
    'ALTER TABLE lab_tests ADD COLUMN result_file VARCHAR(500) NULL'
);
PREPARE stmt FROM @sql_rf;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ── Back-fill urgency values on already-seeded rows ─────────
UPDATE lab_tests
SET urgency = CASE (test_id MOD 7)
    WHEN 0 THEN 'STAT'
    WHEN 1 THEN 'Urgent'
    ELSE        'Routine'
END
WHERE urgency = 'Routine' OR urgency IS NULL;

SELECT
    CONCAT('lab_tests columns patched — urgency sample: ',
           (SELECT GROUP_CONCAT(DISTINCT urgency) FROM lab_tests)) AS result;
