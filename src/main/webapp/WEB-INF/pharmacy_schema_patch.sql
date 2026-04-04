-- ============================================================
-- SmartCare Pharmacy Module — Schema Patch
-- SmartCare Hospital ERP | MySQL 8.0 | hospital_erp
-- Run AFTER SMARTCARE_COMPLETE_DATABASE.sql and emr_schema_patch.sql
--   mysql -u root -p hospital_erp < pharmacy_schema_patch.sql
-- ============================================================
-- FR-31: Real-time stock management and deduction on dispensing
-- FR-32: Batch-level expiry tracking with configurable alert window
-- FR-34: Automatic stock deduction on prescription dispensing
-- FR-36: AI-driven demand forecasting feed via inventory_predictions
-- FR-37: Supplier management and purchase order lifecycle
-- FR-38: Predictive demand forecasting and reorder triggers
-- ============================================================

USE hospital_erp;

-- ────────────────────────────────────────────────────────────
-- SECTION 1: DDL — dispensing_records table
-- FR-31, FR-34: Track every dispensing event against a batch
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS dispensing_records (
    dispensing_id     INT           NOT NULL AUTO_INCREMENT,
    prescription_id   INT           NOT NULL,          -- FR-34: links dispensing to EMR prescription
    item_id           INT           NOT NULL,          -- FR-31: inventory item dispensed
    batch_id          INT           NULL,              -- FR-32: specific batch for expiry traceability
    quantity_dispensed INT          NOT NULL,
    unit_price        DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    pharmacist_id     INT           NOT NULL,          -- pharmacist who performed the dispense
    dispensed_at      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes             TEXT          NULL,
    PRIMARY KEY (dispensing_id),
    CONSTRAINT fk_dr_prescription FOREIGN KEY (prescription_id)
        REFERENCES prescriptions (prescription_id) ON DELETE CASCADE,
    CONSTRAINT fk_dr_item         FOREIGN KEY (item_id)
        REFERENCES inventory_items (item_id),
    CONSTRAINT fk_dr_batch        FOREIGN KEY (batch_id)
        REFERENCES inventory_batches (batch_id) ON DELETE SET NULL,
    CONSTRAINT fk_dr_pharmacist   FOREIGN KEY (pharmacist_id)
        REFERENCES users (user_id),
    INDEX idx_prescription  (prescription_id),
    INDEX idx_item_date     (item_id, dispensed_at),
    INDEX idx_pharmacist    (pharmacist_id, dispensed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='FR-31/FR-34: Dispensing events linking prescriptions to inventory batches';

-- ────────────────────────────────────────────────────────────
-- SECTION 2: Seed data — inventory_categories
-- FR-31: Categories cover the full pharmacy formulary
-- ────────────────────────────────────────────────────────────

-- Analgesics
INSERT IGNORE INTO inventory_categories (category_name, category_type, description)
    VALUES ('Analgesics', 'Medicine', 'Pain-relief and antipyretic medications');

-- Antibiotics already seeded by base SQL; IGNORE handles the duplicate

-- Antihypertensives
INSERT IGNORE INTO inventory_categories (category_name, category_type, description)
    VALUES ('Antihypertensives', 'Medicine', 'Blood-pressure lowering agents');

-- Antidiabetics
INSERT IGNORE INTO inventory_categories (category_name, category_type, description)
    VALUES ('Antidiabetics', 'Medicine', 'Oral hypoglycaemic and insulin preparations');

-- Anticoagulants
INSERT IGNORE INTO inventory_categories (category_name, category_type, description)
    VALUES ('Anticoagulants', 'Medicine', 'Anticoagulant and antiplatelet agents');

-- Antihistamines
INSERT IGNORE INTO inventory_categories (category_name, category_type, description)
    VALUES ('Antihistamines', 'Medicine', 'Antihistamine and allergy medications');

-- Gastrointestinals
INSERT IGNORE INTO inventory_categories (category_name, category_type, description)
    VALUES ('Gastrointestinals', 'Medicine', 'GI tract and antacid preparations');

-- Vitamins
INSERT IGNORE INTO inventory_categories (category_name, category_type, description)
    VALUES ('Vitamins', 'Medicine', 'Vitamin and mineral supplement preparations');

-- IV Fluids already seeded by base SQL; IGNORE handles the duplicate

-- Steroids
INSERT IGNORE INTO inventory_categories (category_name, category_type, description)
    VALUES ('Steroids', 'Medicine', 'Corticosteroid anti-inflammatory agents');

-- Syringes / Consumables
INSERT IGNORE INTO inventory_categories (category_name, category_type, description)
    VALUES ('Syringes/Consumables', 'Consumables', 'Syringes, needles and injection consumables');

-- Gloves / Consumables
INSERT IGNORE INTO inventory_categories (category_name, category_type, description)
    VALUES ('Gloves/Consumables', 'Consumables', 'Examination and surgical glove supplies');

-- ────────────────────────────────────────────────────────────
-- SECTION 3: Seed data — suppliers (Sri Lankan pharma)
-- FR-37: Approved supplier registry for procurement workflow
-- ────────────────────────────────────────────────────────────

INSERT IGNORE INTO suppliers
    (supplier_code, supplier_name, contact_person, email, phone,
     address, city, country, tax_id, payment_terms, credit_limit, rating, is_active)
VALUES
    -- SUP001: Lanka Pharmaceuticals Ltd
    ('SUP001',
     'Lanka Pharmaceuticals Ltd',
     'Mr. Roshan Perera',
     'procurement@lankapharma.lk',
     '+94112456789',
     '42 Braybrooke Street, Colombo 02',
     'Colombo', 'Sri Lanka',
     'VAT-LK-20190042',
     'Net 30 days',
     2500000.00, 4.50, TRUE),

    -- SUP002: MedTrade (Pvt) Ltd
    ('SUP002',
     'MedTrade (Pvt) Ltd',
     'Ms. Dilini Jayawardena',
     'orders@medtrade.lk',
     '+94812234567',
     '17 Peradeniya Road, Kandy',
     'Kandy', 'Sri Lanka',
     'VAT-LK-20150088',
     'Net 45 days',
     1800000.00, 4.20, TRUE),

    -- SUP003: Ceylon Medical Supplies
    ('SUP003',
     'Ceylon Medical Supplies',
     'Dr. Nuwan Fernando',
     'sales@ceylonmedsupply.lk',
     '+94912345678',
     '88 Galle Road, Matara',
     'Matara', 'Sri Lanka',
     'VAT-LK-20120031',
     'Net 60 days',
     3200000.00, 4.70, TRUE);

-- ────────────────────────────────────────────────────────────
-- SECTION 4: Seed data — inventory_items (10 medicines)
-- FR-31: Representative formulary with realistic LK stock levels
-- FR-32: expiry_alert_days tuned per clinical risk
-- FR-38: reorder_level thresholds feed the AI demand-forecast model
-- ────────────────────────────────────────────────────────────

-- MED001 — Paracetamol 500mg (Analgesics)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT
    'MED001', 'Paracetamol 500mg',
    c.category_id,
    'Analgesic and antipyretic tablet, 500 mg',
    'Hemas Pharmaceuticals (Pvt) Ltd',
    'Tablet', 200, 500, 100, 2000,
    450,    -- well above reorder level
    5.00, 8.00,
    'Pharmacy Shelf A-01', 90, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Analgesics' LIMIT 1;

-- MED002 — Amoxicillin 250mg (Antibiotics, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT
    'MED002', 'Amoxicillin 250mg',
    c.category_id,
    'Broad-spectrum penicillin antibiotic capsule, 250 mg',
    'CIC Holdings — CIC Pharma',
    'Capsule', 150, 400, 75, 1500,
    320,    -- above reorder level
    18.00, 28.00,
    'Pharmacy Shelf B-02', 60, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antibiotics' LIMIT 1;

-- MED003 — Metformin 500mg (Antidiabetics, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT
    'MED003', 'Metformin 500mg',
    c.category_id,
    'Biguanide oral hypoglycaemic tablet, 500 mg',
    'Aspen Pharmacare Lanka (Pvt) Ltd',
    'Tablet', 100, 300, 50, 1200,
    180,    -- above reorder level
    12.00, 20.00,
    'Pharmacy Shelf C-03', 60, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antidiabetics' LIMIT 1;

-- MED004 — Amlodipine 5mg (Antihypertensives, Rx) — AT REORDER LEVEL
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT
    'MED004', 'Amlodipine 5mg',
    c.category_id,
    'Calcium channel blocker antihypertensive tablet, 5 mg',
    'Pfizer Lanka (Pvt) Ltd',
    'Tablet', 100, 250, 50, 1000,
    95,     -- AT reorder level — triggers reorder alert (FR-38)
    22.00, 35.00,
    'Pharmacy Shelf C-01', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antihypertensives' LIMIT 1;

-- MED005 — Warfarin 5mg (Anticoagulants, Rx) — BELOW REORDER LEVEL
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT
    'MED005', 'Warfarin 5mg',
    c.category_id,
    'Vitamin K antagonist anticoagulant tablet, 5 mg — high-alert medication',
    'Cipla Ltd',
    'Tablet', 50, 150, 25, 500,
    25,     -- BELOW reorder level — critical low stock (FR-31, FR-38)
    65.00, 95.00,
    'Pharmacy Safe Storage D-01', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Anticoagulants' LIMIT 1;

-- MED006 — Omeprazole 20mg (Gastrointestinals, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT
    'MED006', 'Omeprazole 20mg',
    c.category_id,
    'Proton pump inhibitor gastric acid suppressant capsule, 20 mg',
    'AstraZeneca Lanka (Pvt) Ltd',
    'Capsule', 100, 300, 50, 1200,
    280,    -- above reorder level
    28.00, 42.00,
    'Pharmacy Shelf E-01', 60, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Gastrointestinals' LIMIT 1;

-- MED007 — Cetirizine 10mg (Antihistamines)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT
    'MED007', 'Cetirizine 10mg',
    c.category_id,
    'Second-generation antihistamine tablet, 10 mg',
    'GlaxoSmithKline Biologicals Lanka',
    'Tablet', 75, 200, 40, 800,
    160,    -- above reorder level
    10.00, 16.00,
    'Pharmacy Shelf F-02', 90, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antihistamines' LIMIT 1;

-- MED008 — Vitamin C 500mg (Vitamins)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT
    'MED008', 'Vitamin C 500mg',
    c.category_id,
    'Ascorbic acid effervescent / chewable tablet, 500 mg',
    'Hemas Pharmaceuticals (Pvt) Ltd',
    'Tablet', 150, 500, 75, 2500,
    520,    -- well above reorder level
    6.00, 10.00,
    'Pharmacy Shelf G-01', 180, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Vitamins' LIMIT 1;

-- MED009 — Normal Saline 0.9% 500ml (IV Fluids) — BELOW REORDER LEVEL
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT
    'MED009', 'Normal Saline 0.9% 500ml',
    c.category_id,
    'Isotonic sodium chloride intravenous infusion bag, 0.9% 500 ml',
    'B. Braun Lanka (Pvt) Ltd',
    'Bag', 50, 120, 25, 400,
    38,     -- BELOW reorder level — critical IV fluid stock (FR-31, FR-38)
    195.00, 280.00,
    'IV Store Room H-01', 60, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'IV Fluids' LIMIT 1;

-- MED010 — Dexamethasone 4mg (Steroids, Rx) — BELOW REORDER LEVEL
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT
    'MED010', 'Dexamethasone 4mg',
    c.category_id,
    'Synthetic glucocorticoid corticosteroid tablet, 4 mg',
    'Merck (Pvt) Ltd',
    'Tablet', 30, 100, 15, 300,
    22,     -- BELOW reorder level (FR-31, FR-38)
    85.00, 130.00,
    'Pharmacy Safe Storage D-02', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Steroids' LIMIT 1;

-- ────────────────────────────────────────────────────────────
-- SECTION 5: Seed data — inventory_batches
-- FR-32: Batch tracking with expiry dates; one near-expiry batch
--         for MED009 demonstrates expiry alert workflow
-- ────────────────────────────────────────────────────────────

-- BATCH-PC01: Paracetamol 500mg — expires ~18 months from now
INSERT IGNORE INTO inventory_batches
    (item_id, batch_number, manufacture_date, expiry_date,
     quantity, remaining_quantity, cost_per_unit,
     supplier_id, received_date, status)
SELECT
    i.item_id,
    'BATCH-PC01',
    DATE_SUB(CURDATE(), INTERVAL 6 MONTH),
    DATE_ADD(CURDATE(), INTERVAL 18 MONTH),
    500, 450, 4.50,
    s.supplier_id,
    DATE_SUB(CURDATE(), INTERVAL 30 DAY),
    'Active'
FROM inventory_items i, suppliers s
WHERE i.item_code = 'MED001' AND s.supplier_code = 'SUP001'
LIMIT 1;

-- BATCH-AX01: Amoxicillin 250mg — expires ~14 months from now
INSERT IGNORE INTO inventory_batches
    (item_id, batch_number, manufacture_date, expiry_date,
     quantity, remaining_quantity, cost_per_unit,
     supplier_id, received_date, status)
SELECT
    i.item_id,
    'BATCH-AX01',
    DATE_SUB(CURDATE(), INTERVAL 4 MONTH),
    DATE_ADD(CURDATE(), INTERVAL 14 MONTH),
    400, 320, 15.00,
    s.supplier_id,
    DATE_SUB(CURDATE(), INTERVAL 20 DAY),
    'Active'
FROM inventory_items i, suppliers s
WHERE i.item_code = 'MED002' AND s.supplier_code = 'SUP002'
LIMIT 1;

-- BATCH-MF01: Metformin 500mg — expires ~22 months from now
INSERT IGNORE INTO inventory_batches
    (item_id, batch_number, manufacture_date, expiry_date,
     quantity, remaining_quantity, cost_per_unit,
     supplier_id, received_date, status)
SELECT
    i.item_id,
    'BATCH-MF01',
    DATE_SUB(CURDATE(), INTERVAL 2 MONTH),
    DATE_ADD(CURDATE(), INTERVAL 22 MONTH),
    300, 180, 10.00,
    s.supplier_id,
    DATE_SUB(CURDATE(), INTERVAL 15 DAY),
    'Active'
FROM inventory_items i, suppliers s
WHERE i.item_code = 'MED003' AND s.supplier_code = 'SUP001'
LIMIT 1;

-- BATCH-AM01: Amlodipine 5mg — expires ~16 months from now
INSERT IGNORE INTO inventory_batches
    (item_id, batch_number, manufacture_date, expiry_date,
     quantity, remaining_quantity, cost_per_unit,
     supplier_id, received_date, status)
SELECT
    i.item_id,
    'BATCH-AM01',
    DATE_SUB(CURDATE(), INTERVAL 8 MONTH),
    DATE_ADD(CURDATE(), INTERVAL 16 MONTH),
    200, 95, 19.00,
    s.supplier_id,
    DATE_SUB(CURDATE(), INTERVAL 45 DAY),
    'Active'
FROM inventory_items i, suppliers s
WHERE i.item_code = 'MED004' AND s.supplier_code = 'SUP003'
LIMIT 1;

-- BATCH-WF01: Warfarin 5mg — expires ~20 months from now
INSERT IGNORE INTO inventory_batches
    (item_id, batch_number, manufacture_date, expiry_date,
     quantity, remaining_quantity, cost_per_unit,
     supplier_id, received_date, status)
SELECT
    i.item_id,
    'BATCH-WF01',
    DATE_SUB(CURDATE(), INTERVAL 4 MONTH),
    DATE_ADD(CURDATE(), INTERVAL 20 MONTH),
    100, 25, 58.00,
    s.supplier_id,
    DATE_SUB(CURDATE(), INTERVAL 60 DAY),
    'Active'
FROM inventory_items i, suppliers s
WHERE i.item_code = 'MED005' AND s.supplier_code = 'SUP002'
LIMIT 1;

-- BATCH-OM01: Omeprazole 20mg — expires ~12 months from now
INSERT IGNORE INTO inventory_batches
    (item_id, batch_number, manufacture_date, expiry_date,
     quantity, remaining_quantity, cost_per_unit,
     supplier_id, received_date, status)
SELECT
    i.item_id,
    'BATCH-OM01',
    DATE_SUB(CURDATE(), INTERVAL 6 MONTH),
    DATE_ADD(CURDATE(), INTERVAL 12 MONTH),
    350, 280, 24.00,
    s.supplier_id,
    DATE_SUB(CURDATE(), INTERVAL 25 DAY),
    'Active'
FROM inventory_items i, suppliers s
WHERE i.item_code = 'MED006' AND s.supplier_code = 'SUP001'
LIMIT 1;

-- BATCH-CT01: Cetirizine 10mg — expires ~20 months from now
INSERT IGNORE INTO inventory_batches
    (item_id, batch_number, manufacture_date, expiry_date,
     quantity, remaining_quantity, cost_per_unit,
     supplier_id, received_date, status)
SELECT
    i.item_id,
    'BATCH-CT01',
    DATE_SUB(CURDATE(), INTERVAL 3 MONTH),
    DATE_ADD(CURDATE(), INTERVAL 20 MONTH),
    200, 160, 8.50,
    s.supplier_id,
    DATE_SUB(CURDATE(), INTERVAL 10 DAY),
    'Active'
FROM inventory_items i, suppliers s
WHERE i.item_code = 'MED007' AND s.supplier_code = 'SUP002'
LIMIT 1;

-- BATCH-VC01: Vitamin C 500mg — expires ~18 months from now
INSERT IGNORE INTO inventory_batches
    (item_id, batch_number, manufacture_date, expiry_date,
     quantity, remaining_quantity, cost_per_unit,
     supplier_id, received_date, status)
SELECT
    i.item_id,
    'BATCH-VC01',
    DATE_SUB(CURDATE(), INTERVAL 2 MONTH),
    DATE_ADD(CURDATE(), INTERVAL 18 MONTH),
    600, 520, 5.00,
    s.supplier_id,
    DATE_SUB(CURDATE(), INTERVAL 7 DAY),
    'Active'
FROM inventory_items i, suppliers s
WHERE i.item_code = 'MED008' AND s.supplier_code = 'SUP001'
LIMIT 1;

-- BATCH-NS01: Normal Saline 0.9% 500ml — expires ~10 months from now
INSERT IGNORE INTO inventory_batches
    (item_id, batch_number, manufacture_date, expiry_date,
     quantity, remaining_quantity, cost_per_unit,
     supplier_id, received_date, status)
SELECT
    i.item_id,
    'BATCH-NS01',
    DATE_SUB(CURDATE(), INTERVAL 5 MONTH),
    DATE_ADD(CURDATE(), INTERVAL 10 MONTH),
    80, 38, 170.00,
    s.supplier_id,
    DATE_SUB(CURDATE(), INTERVAL 40 DAY),
    'Active'
FROM inventory_items i, suppliers s
WHERE i.item_code = 'MED009' AND s.supplier_code = 'SUP003'
LIMIT 1;

-- BATCH-NS02: Normal Saline 0.9% 500ml — NEAR-EXPIRY (20 days)
-- FR-32: Demonstrates expiry alert trigger — expiry_alert_days=60 will flag this batch
INSERT IGNORE INTO inventory_batches
    (item_id, batch_number, manufacture_date, expiry_date,
     quantity, remaining_quantity, cost_per_unit,
     supplier_id, received_date, status)
SELECT
    i.item_id,
    'BATCH-NS02',
    DATE_SUB(CURDATE(), INTERVAL 17 MONTH),
    DATE_ADD(CURDATE(), INTERVAL 20 DAY),   -- near-expiry: expires in 20 days (FR-32)
    50, 0, 165.00,                           -- remaining_quantity=0: depleted but tracked
    s.supplier_id,
    DATE_SUB(CURDATE(), INTERVAL 17 MONTH),
    'Depleted'                               -- near-expiry, depleted — audit trail intact
FROM inventory_items i, suppliers s
WHERE i.item_code = 'MED009' AND s.supplier_code = 'SUP003'
LIMIT 1;

-- BATCH-DX01: Dexamethasone 4mg — expires ~8 months from now
INSERT IGNORE INTO inventory_batches
    (item_id, batch_number, manufacture_date, expiry_date,
     quantity, remaining_quantity, cost_per_unit,
     supplier_id, received_date, status)
SELECT
    i.item_id,
    'BATCH-DX01',
    DATE_SUB(CURDATE(), INTERVAL 4 MONTH),
    DATE_ADD(CURDATE(), INTERVAL 8 MONTH),
    60, 22, 75.00,
    s.supplier_id,
    DATE_SUB(CURDATE(), INTERVAL 20 DAY),
    'Active'
FROM inventory_items i, suppliers s
WHERE i.item_code = 'MED010' AND s.supplier_code = 'SUP003'
LIMIT 1;

-- ────────────────────────────────────────────────────────────
-- SECTION 6: Sample purchase order for low-stock items
-- FR-37: PO lifecycle — Draft PO raised for MED005 (Warfarin)
--         and MED009 (Normal Saline) which are below reorder level
-- FR-38: Auto-reorder logic produces Draft POs for items below
--         reorder_level thresholds
-- ────────────────────────────────────────────────────────────

-- Draft PO — supplier: Ceylon Medical Supplies (SUP003)
-- Items: Warfarin 5mg (MED005) + Normal Saline 0.9% 500ml (MED009)
-- created_by: user_id=1 (system admin — first user in users table)
INSERT IGNORE INTO purchase_orders
    (po_number, requisition_id, supplier_id,
     order_date, expected_delivery_date, delivery_address,
     status, subtotal, tax_amount, shipping_cost, total_amount,
     payment_terms, created_by, approved_by, approval_date, notes)
SELECT
    'PO-PHARM-2026-001',
    NULL,                           -- no linked requisition for emergency reorder
    s.supplier_id,
    NOW(),
    DATE_ADD(CURDATE(), INTERVAL 7 DAY),
    'SmartCare Hospital — Pharmacy Receiving Bay, Ward Block A',
    'Draft',
    -- subtotal: Warfarin 150 units × 58.00 = 8700 + Normal Saline 120 bags × 170.00 = 20400 → 29100
    29100.00,
    4365.00,                        -- 15% VAT
    500.00,
    33965.00,
    'Net 60 days',
    1,                              -- created_by user_id=1 (admin)
    NULL, NULL,
    'FR-38 auto-reorder: MED005 Warfarin stock 25 (reorder 50); MED009 Normal Saline stock 38 (reorder 50)'
FROM suppliers s
WHERE s.supplier_code = 'SUP003'
LIMIT 1;

-- PO line item 1: Warfarin 5mg
INSERT IGNORE INTO po_items
    (po_id, item_id, description,
     quantity_ordered, quantity_received,
     unit_price, tax_percentage, line_total)
SELECT
    po.po_id,
    i.item_id,
    'Warfarin 5mg tablet — reorder quantity 150 units',
    150, 0,
    58.00, 15.00,
    8700.00
FROM purchase_orders po, inventory_items i
WHERE po.po_number = 'PO-PHARM-2026-001'
  AND i.item_code  = 'MED005'
LIMIT 1;

-- PO line item 2: Normal Saline 0.9% 500ml
INSERT IGNORE INTO po_items
    (po_id, item_id, description,
     quantity_ordered, quantity_received,
     unit_price, tax_percentage, line_total)
SELECT
    po.po_id,
    i.item_id,
    'Normal Saline 0.9% 500ml infusion bag — reorder quantity 120 bags',
    120, 0,
    170.00, 15.00,
    20400.00
FROM purchase_orders po, inventory_items i
WHERE po.po_number = 'PO-PHARM-2026-001'
  AND i.item_code  = 'MED009'
LIMIT 1;

-- ────────────────────────────────────────────────────────────
-- SECTION 7: Additional pharmacy categories
-- ────────────────────────────────────────────────────────────

INSERT IGNORE INTO inventory_categories (category_name, category_type, description)
    VALUES ('Cardiovascular Agents', 'Medicine', 'Cardiac and lipid-lowering medications');
INSERT IGNORE INTO inventory_categories (category_name, category_type, description)
    VALUES ('Respiratory Agents', 'Medicine', 'Bronchodilators and respiratory medications');
INSERT IGNORE INTO inventory_categories (category_name, category_type, description)
    VALUES ('Anticonvulsants', 'Medicine', 'Anti-epileptic and seizure control medications');
INSERT IGNORE INTO inventory_categories (category_name, category_type, description)
    VALUES ('Antifungals', 'Medicine', 'Antifungal and antithrombotic medications');

-- ────────────────────────────────────────────────────────────
-- SECTION 8: Extended drug inventory — MED011 to MED055
-- 45 additional items for a realistic Sri Lankan hospital
-- formulary covering all major therapeutic classes.
-- FR-31: Real-time stock | FR-37: Reorder alerts
-- ────────────────────────────────────────────────────────────

-- MED011 — Aspirin 75mg (Anticoagulants, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED011', 'Aspirin 75mg',
    c.category_id,
    'Low-dose acetylsalicylic acid antiplatelet tablet, 75 mg',
    'Hemas Pharmaceuticals (Pvt) Ltd',
    'Tablet', 200, 500, 100, 2000, 680, 3.50, 6.00,
    'Pharmacy Shelf A-02', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Anticoagulants' LIMIT 1;

-- MED012 — Atorvastatin 10mg (Cardiovascular Agents, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED012', 'Atorvastatin 10mg',
    c.category_id,
    'HMG-CoA reductase inhibitor statin tablet, 10 mg',
    'Pfizer Lanka (Pvt) Ltd',
    'Tablet', 120, 350, 60, 1200, 290, 28.00, 45.00,
    'Pharmacy Shelf C-02', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Cardiovascular Agents' LIMIT 1;

-- MED013 — Lisinopril 5mg (Antihypertensives, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED013', 'Lisinopril 5mg',
    c.category_id,
    'ACE inhibitor antihypertensive tablet, 5 mg',
    'Aspen Pharmacare Lanka (Pvt) Ltd',
    'Tablet', 100, 300, 50, 1000, 210, 15.00, 25.00,
    'Pharmacy Shelf C-04', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antihypertensives' LIMIT 1;

-- MED014 — Losartan 50mg (Antihypertensives, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED014', 'Losartan 50mg',
    c.category_id,
    'Angiotensin II receptor blocker antihypertensive tablet, 50 mg',
    'CIC Holdings — CIC Pharma',
    'Tablet', 100, 300, 50, 1000, 175, 32.00, 52.00,
    'Pharmacy Shelf C-05', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antihypertensives' LIMIT 1;

-- MED015 — Metoprolol 50mg (Antihypertensives, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED015', 'Metoprolol 50mg',
    c.category_id,
    'Beta-1 selective adrenergic blocker tablet, 50 mg',
    'AstraZeneca Lanka (Pvt) Ltd',
    'Tablet', 80, 250, 40, 800, 155, 18.00, 30.00,
    'Pharmacy Shelf C-06', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antihypertensives' LIMIT 1;

-- MED016 — Simvastatin 20mg (Cardiovascular Agents, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED016', 'Simvastatin 20mg',
    c.category_id,
    'HMG-CoA reductase inhibitor statin tablet, 20 mg',
    'Merck (Pvt) Ltd',
    'Tablet', 100, 300, 50, 1000, 42, 22.00, 38.00,
    'Pharmacy Shelf C-07', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Cardiovascular Agents' LIMIT 1;

-- MED017 — Ciprofloxacin 500mg (Antibiotics, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED017', 'Ciprofloxacin 500mg',
    c.category_id,
    'Fluoroquinolone broad-spectrum antibiotic tablet, 500 mg',
    'Cipla Ltd',
    'Tablet', 100, 300, 50, 1000, 240, 35.00, 58.00,
    'Pharmacy Shelf B-03', 60, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antibiotics' LIMIT 1;

-- MED018 — Azithromycin 250mg (Antibiotics, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED018', 'Azithromycin 250mg',
    c.category_id,
    'Macrolide antibiotic capsule, 250 mg',
    'Pfizer Lanka (Pvt) Ltd',
    'Capsule', 80, 200, 40, 800, 185, 45.00, 72.00,
    'Pharmacy Shelf B-04', 60, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antibiotics' LIMIT 1;

-- MED019 — Cephalexin 500mg (Antibiotics, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED019', 'Cephalexin 500mg',
    c.category_id,
    'First-generation cephalosporin antibiotic capsule, 500 mg',
    'GlaxoSmithKline Biologicals Lanka',
    'Capsule', 100, 300, 50, 1000, 310, 28.00, 46.00,
    'Pharmacy Shelf B-05', 60, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antibiotics' LIMIT 1;

-- MED020 — Metronidazole 400mg (Antibiotics, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED020', 'Metronidazole 400mg',
    c.category_id,
    'Nitroimidazole antiprotozoal and antibacterial tablet, 400 mg',
    'CIC Holdings — CIC Pharma',
    'Tablet', 100, 300, 50, 1000, 280, 8.00, 14.00,
    'Pharmacy Shelf B-06', 60, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antibiotics' LIMIT 1;

-- MED021 — Ibuprofen 400mg (Analgesics)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED021', 'Ibuprofen 400mg',
    c.category_id,
    'NSAID anti-inflammatory and analgesic tablet, 400 mg',
    'Hemas Pharmaceuticals (Pvt) Ltd',
    'Tablet', 200, 500, 100, 2000, 520, 7.00, 12.00,
    'Pharmacy Shelf A-03', 90, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Analgesics' LIMIT 1;

-- MED022 — Diclofenac 50mg (Analgesics, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED022', 'Diclofenac 50mg',
    c.category_id,
    'NSAID analgesic and anti-inflammatory tablet, 50 mg',
    'Aspen Pharmacare Lanka (Pvt) Ltd',
    'Tablet', 150, 400, 75, 1500, 340, 12.00, 20.00,
    'Pharmacy Shelf A-04', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Analgesics' LIMIT 1;

-- MED023 — Tramadol 50mg (Analgesics, Rx) — BELOW REORDER LEVEL
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED023', 'Tramadol 50mg',
    c.category_id,
    'Opioid analgesic capsule, 50 mg — controlled substance',
    'Cipla Ltd',
    'Capsule', 60, 150, 30, 600, 45, 55.00, 85.00,
    'Pharmacy Safe Storage D-03', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Analgesics' LIMIT 1;

-- MED024 — Ranitidine 150mg (Gastrointestinals)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED024', 'Ranitidine 150mg',
    c.category_id,
    'H2 receptor antagonist antacid tablet, 150 mg',
    'GlaxoSmithKline Biologicals Lanka',
    'Tablet', 100, 300, 50, 1000, 380, 9.00, 15.00,
    'Pharmacy Shelf E-02', 90, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Gastrointestinals' LIMIT 1;

-- MED025 — Pantoprazole 40mg (Gastrointestinals, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED025', 'Pantoprazole 40mg',
    c.category_id,
    'Proton pump inhibitor gastric acid suppressant tablet, 40 mg',
    'AstraZeneca Lanka (Pvt) Ltd',
    'Tablet', 100, 300, 50, 1000, 270, 30.00, 48.00,
    'Pharmacy Shelf E-03', 60, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Gastrointestinals' LIMIT 1;

-- MED026 — Metoclopramide 10mg (Gastrointestinals, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED026', 'Metoclopramide 10mg',
    c.category_id,
    'Dopamine antagonist antiemetic tablet, 10 mg',
    'Hemas Pharmaceuticals (Pvt) Ltd',
    'Tablet', 80, 250, 40, 800, 190, 6.00, 10.00,
    'Pharmacy Shelf E-04', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Gastrointestinals' LIMIT 1;

-- MED027 — Glibenclamide 5mg (Antidiabetics, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED027', 'Glibenclamide 5mg',
    c.category_id,
    'Sulphonylurea oral hypoglycaemic tablet, 5 mg',
    'Aspen Pharmacare Lanka (Pvt) Ltd',
    'Tablet', 100, 300, 50, 1000, 220, 8.00, 14.00,
    'Pharmacy Shelf C-08', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antidiabetics' LIMIT 1;

-- MED028 — Glimepiride 2mg (Antidiabetics, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED028', 'Glimepiride 2mg',
    c.category_id,
    'Third-generation sulphonylurea oral hypoglycaemic tablet, 2 mg',
    'Cipla Ltd',
    'Tablet', 80, 250, 40, 800, 160, 18.00, 30.00,
    'Pharmacy Shelf C-09', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antidiabetics' LIMIT 1;

-- MED029 — Insulin Glargine 100U/ml 10ml (Antidiabetics, Rx) — CRITICAL STOCK
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED029', 'Insulin Glargine 100U/ml',
    c.category_id,
    'Long-acting basal insulin analogue vial, 100 U/ml, 10 ml — cold chain required',
    'Sanofi Lanka (Pvt) Ltd',
    'Vial', 20, 50, 10, 200, 8, 3200.00, 4800.00,
    'Pharmacy Refrigerator R-01', 30, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antidiabetics' LIMIT 1;

-- MED030 — Salbutamol Inhaler 100mcg (Respiratory Agents, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED030', 'Salbutamol Inhaler 100mcg',
    c.category_id,
    'Short-acting beta-2 agonist bronchodilator pressurised inhaler, 200 doses',
    'GlaxoSmithKline Biologicals Lanka',
    'Unit', 40, 100, 20, 400, 85, 350.00, 550.00,
    'Pharmacy Shelf F-01', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Respiratory Agents' LIMIT 1;

-- MED031 — Enalapril 5mg (Antihypertensives, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED031', 'Enalapril 5mg',
    c.category_id,
    'ACE inhibitor antihypertensive and heart failure tablet, 5 mg',
    'Merck (Pvt) Ltd',
    'Tablet', 80, 250, 40, 800, 190, 12.00, 20.00,
    'Pharmacy Shelf C-10', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antihypertensives' LIMIT 1;

-- MED032 — Furosemide 40mg (Cardiovascular Agents, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED032', 'Furosemide 40mg',
    c.category_id,
    'Loop diuretic tablet, 40 mg',
    'Hemas Pharmaceuticals (Pvt) Ltd',
    'Tablet', 100, 300, 50, 1000, 145, 5.00, 9.00,
    'Pharmacy Shelf C-11', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Cardiovascular Agents' LIMIT 1;

-- MED033 — Spironolactone 25mg (Cardiovascular Agents, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED033', 'Spironolactone 25mg',
    c.category_id,
    'Potassium-sparing diuretic and aldosterone antagonist tablet, 25 mg',
    'Aspen Pharmacare Lanka (Pvt) Ltd',
    'Tablet', 60, 200, 30, 600, 110, 20.00, 34.00,
    'Pharmacy Shelf C-12', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Cardiovascular Agents' LIMIT 1;

-- MED034 — Digoxin 0.25mg (Cardiovascular Agents, Rx) — BELOW REORDER LEVEL
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED034', 'Digoxin 0.25mg',
    c.category_id,
    'Cardiac glycoside antiarrhythmic tablet, 0.25 mg — narrow therapeutic index',
    'GlaxoSmithKline Biologicals Lanka',
    'Tablet', 50, 150, 25, 500, 35, 15.00, 26.00,
    'Pharmacy Safe Storage D-04', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Cardiovascular Agents' LIMIT 1;

-- MED035 — Clopidogrel 75mg (Anticoagulants, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED035', 'Clopidogrel 75mg',
    c.category_id,
    'ADP receptor antagonist antiplatelet tablet, 75 mg',
    'Sanofi Lanka (Pvt) Ltd',
    'Tablet', 100, 300, 50, 1000, 230, 55.00, 88.00,
    'Pharmacy Safe Storage D-05', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Anticoagulants' LIMIT 1;

-- MED036 — Heparin 5000IU/ml Injection (Anticoagulants, Rx) — CRITICAL STOCK
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED036', 'Heparin 5000IU/ml Injection',
    c.category_id,
    'Unfractionated heparin anticoagulant injection, 5000 IU/ml — 1 ml ampoule',
    'B. Braun Lanka (Pvt) Ltd',
    'Ampoule', 30, 80, 15, 300, 12, 280.00, 420.00,
    'Pharmacy Safe Storage D-06', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Anticoagulants' LIMIT 1;

-- MED037 — Loratadine 10mg (Antihistamines)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED037', 'Loratadine 10mg',
    c.category_id,
    'Non-sedating second-generation antihistamine tablet, 10 mg',
    'Hemas Pharmaceuticals (Pvt) Ltd',
    'Tablet', 100, 300, 50, 1000, 420, 8.00, 14.00,
    'Pharmacy Shelf F-03', 90, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antihistamines' LIMIT 1;

-- MED038 — Chlorpheniramine 4mg (Antihistamines)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED038', 'Chlorpheniramine 4mg',
    c.category_id,
    'First-generation antihistamine tablet, 4 mg',
    'CIC Holdings — CIC Pharma',
    'Tablet', 100, 300, 50, 1000, 360, 4.00, 7.00,
    'Pharmacy Shelf F-04', 90, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antihistamines' LIMIT 1;

-- MED039 — Vitamin B Complex (Vitamins)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED039', 'Vitamin B Complex',
    c.category_id,
    'B-vitamin complex tablet (B1, B2, B3, B5, B6, B12)',
    'Hemas Pharmaceuticals (Pvt) Ltd',
    'Tablet', 150, 500, 75, 2000, 580, 5.00, 9.00,
    'Pharmacy Shelf G-02', 180, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Vitamins' LIMIT 1;

-- MED040 — Folic Acid 5mg (Vitamins, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED040', 'Folic Acid 5mg',
    c.category_id,
    'Folate supplement tablet, 5 mg — for anaemia and pregnancy',
    'Aspen Pharmacare Lanka (Pvt) Ltd',
    'Tablet', 100, 300, 50, 1000, 340, 3.50, 6.00,
    'Pharmacy Shelf G-03', 180, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Vitamins' LIMIT 1;

-- MED041 — Ferrous Sulphate 200mg (Vitamins, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED041', 'Ferrous Sulphate 200mg',
    c.category_id,
    'Ferrous iron supplement tablet, 200 mg — for iron deficiency anaemia',
    'CIC Holdings — CIC Pharma',
    'Tablet', 100, 300, 50, 1000, 255, 4.00, 7.00,
    'Pharmacy Shelf G-04', 180, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Vitamins' LIMIT 1;

-- MED042 — Calcium Carbonate 500mg (Vitamins)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED042', 'Calcium Carbonate 500mg',
    c.category_id,
    'Calcium supplement and antacid tablet, 500 mg',
    'Hemas Pharmaceuticals (Pvt) Ltd',
    'Tablet', 150, 400, 75, 1500, 470, 6.00, 10.00,
    'Pharmacy Shelf G-05', 180, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Vitamins' LIMIT 1;

-- MED043 — Multivitamin Tablet (Vitamins)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED043', 'Multivitamin Tablet',
    c.category_id,
    'Multi-micronutrient supplement tablet with A, C, D, E, B-complex, zinc',
    'Hemas Pharmaceuticals (Pvt) Ltd',
    'Tablet', 200, 600, 100, 2500, 780, 8.00, 14.00,
    'Pharmacy Shelf G-06', 180, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Vitamins' LIMIT 1;

-- MED044 — Dextrose 5% 500ml (IV Fluids)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED044', 'Dextrose 5% 500ml',
    c.category_id,
    'Isotonic glucose intravenous infusion bag, 5% dextrose 500 ml',
    'B. Braun Lanka (Pvt) Ltd',
    'Bag', 40, 120, 20, 400, 72, 185.00, 265.00,
    'IV Store Room H-02', 60, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'IV Fluids' LIMIT 1;

-- MED045 — Ringer''s Lactate 500ml (IV Fluids)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED045', "Ringer's Lactate 500ml",
    c.category_id,
    "Isotonic balanced electrolyte intravenous infusion bag (Hartmann's solution), 500 ml",
    'B. Braun Lanka (Pvt) Ltd',
    'Bag', 40, 120, 20, 400, 65, 190.00, 275.00,
    'IV Store Room H-03', 60, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'IV Fluids' LIMIT 1;

-- MED046 — Prednisolone 5mg (Steroids, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED046', 'Prednisolone 5mg',
    c.category_id,
    'Synthetic glucocorticoid corticosteroid tablet, 5 mg — anti-inflammatory',
    'CIC Holdings — CIC Pharma',
    'Tablet', 80, 250, 40, 800, 195, 8.00, 14.00,
    'Pharmacy Safe Storage D-07', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Steroids' LIMIT 1;

-- MED047 — Hydrocortisone Injection 100mg (Steroids, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED047', 'Hydrocortisone Injection 100mg',
    c.category_id,
    'Cortisol IV/IM corticosteroid injection, 100 mg — emergency anaphylaxis management',
    'Pfizer Lanka (Pvt) Ltd',
    'Vial', 20, 60, 10, 200, 38, 650.00, 980.00,
    'Pharmacy Safe Storage D-08', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Steroids' LIMIT 1;

-- MED048 — Methylprednisolone 4mg (Steroids, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED048', 'Methylprednisolone 4mg',
    c.category_id,
    'Synthetic corticosteroid tablet, 4 mg — for severe inflammatory conditions',
    'Merck (Pvt) Ltd',
    'Tablet', 50, 150, 25, 500, 88, 45.00, 72.00,
    'Pharmacy Safe Storage D-09', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Steroids' LIMIT 1;

-- MED049 — Syringes 5ml (Syringes/Consumables)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED049', 'Syringes 5ml',
    c.category_id,
    'Sterile disposable syringe 5 ml with 23G needle — box of 100',
    'Terumo Lanka (Pvt) Ltd',
    'Box', 10, 30, 5, 100, 24, 950.00, 1400.00,
    'Storeroom I-01', 365, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Syringes/Consumables' LIMIT 1;

-- MED050 — Syringes 10ml (Syringes/Consumables)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED050', 'Syringes 10ml',
    c.category_id,
    'Sterile disposable syringe 10 ml with 21G needle — box of 100',
    'Terumo Lanka (Pvt) Ltd',
    'Box', 10, 30, 5, 100, 18, 1200.00, 1750.00,
    'Storeroom I-02', 365, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Syringes/Consumables' LIMIT 1;

-- MED051 — Surgical Gloves Medium (Gloves/Consumables)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED051', 'Surgical Gloves Medium',
    c.category_id,
    'Sterile latex surgical gloves, size Medium — box of 50 pairs',
    'Sri Lanka Rubber Research Institute',
    'Box', 15, 40, 8, 150, 32, 2200.00, 3200.00,
    'Storeroom I-03', 1095, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Gloves/Consumables' LIMIT 1;

-- MED052 — Phenobarbitone 30mg (Anticonvulsants, Rx) — BELOW REORDER LEVEL
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED052', 'Phenobarbitone 30mg',
    c.category_id,
    'Barbiturate anticonvulsant tablet, 30 mg — controlled drug, anti-epileptic',
    'CIC Holdings — CIC Pharma',
    'Tablet', 60, 200, 30, 600, 42, 6.00, 10.00,
    'Pharmacy Safe Storage D-10', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Anticonvulsants' LIMIT 1;

-- MED053 — Atenolol 50mg (Antihypertensives, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED053', 'Atenolol 50mg',
    c.category_id,
    'Cardioselective beta-1 blocker antihypertensive tablet, 50 mg',
    'Aspen Pharmacare Lanka (Pvt) Ltd',
    'Tablet', 100, 300, 50, 1000, 280, 10.00, 17.00,
    'Pharmacy Shelf C-13', 90, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antihypertensives' LIMIT 1;

-- MED054 — Clindamycin 150mg (Antibiotics, Rx)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED054', 'Clindamycin 150mg',
    c.category_id,
    'Lincosamide antibiotic capsule, 150 mg — anaerobic coverage',
    'Cipla Ltd',
    'Capsule', 60, 200, 30, 600, 130, 42.00, 68.00,
    'Pharmacy Shelf B-07', 60, TRUE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antibiotics' LIMIT 1;

-- MED055 — Albendazole 400mg (Antibiotics)
INSERT IGNORE INTO inventory_items
    (item_code, item_name, category_id, description, manufacturer,
     unit_of_measure, reorder_level, reorder_quantity,
     minimum_stock_level, maximum_stock_level,
     current_stock, unit_price, selling_price,
     location, expiry_alert_days, requires_prescription, is_active)
SELECT 'MED055', 'Albendazole 400mg',
    c.category_id,
    'Benzimidazole anthelmintic tablet, 400 mg — for intestinal worm infections',
    'GlaxoSmithKline Biologicals Lanka',
    'Tablet', 100, 300, 50, 1000, 320, 18.00, 30.00,
    'Pharmacy Shelf B-08', 90, FALSE, TRUE
FROM inventory_categories c WHERE c.category_name = 'Antibiotics' LIMIT 1;

-- ────────────────────────────────────────────────────────────
-- SECTION 9: Batches for new drugs — FR-32 expiry tracking
-- ────────────────────────────────────────────────────────────

-- Aspirin 75mg batch
INSERT IGNORE INTO inventory_batches (item_id, batch_number, manufacture_date, expiry_date, quantity, remaining_quantity, cost_per_unit, supplier_id, received_date, status)
SELECT i.item_id, 'BATCH-AS01', DATE_SUB(CURDATE(),INTERVAL 3 MONTH), DATE_ADD(CURDATE(),INTERVAL 24 MONTH), 700, 680, 3.00, s.supplier_id, DATE_SUB(CURDATE(),INTERVAL 10 DAY), 'Active'
FROM inventory_items i, suppliers s WHERE i.item_code='MED011' AND s.supplier_code='SUP001' LIMIT 1;

-- Atorvastatin 10mg batch
INSERT IGNORE INTO inventory_batches (item_id, batch_number, manufacture_date, expiry_date, quantity, remaining_quantity, cost_per_unit, supplier_id, received_date, status)
SELECT i.item_id, 'BATCH-AT01', DATE_SUB(CURDATE(),INTERVAL 4 MONTH), DATE_ADD(CURDATE(),INTERVAL 20 MONTH), 300, 290, 25.00, s.supplier_id, DATE_SUB(CURDATE(),INTERVAL 15 DAY), 'Active'
FROM inventory_items i, suppliers s WHERE i.item_code='MED012' AND s.supplier_code='SUP003' LIMIT 1;

-- Lisinopril 5mg batch
INSERT IGNORE INTO inventory_batches (item_id, batch_number, manufacture_date, expiry_date, quantity, remaining_quantity, cost_per_unit, supplier_id, received_date, status)
SELECT i.item_id, 'BATCH-LP01', DATE_SUB(CURDATE(),INTERVAL 2 MONTH), DATE_ADD(CURDATE(),INTERVAL 22 MONTH), 220, 210, 13.00, s.supplier_id, DATE_SUB(CURDATE(),INTERVAL 8 DAY), 'Active'
FROM inventory_items i, suppliers s WHERE i.item_code='MED013' AND s.supplier_code='SUP001' LIMIT 1;

-- Ibuprofen 400mg batch
INSERT IGNORE INTO inventory_batches (item_id, batch_number, manufacture_date, expiry_date, quantity, remaining_quantity, cost_per_unit, supplier_id, received_date, status)
SELECT i.item_id, 'BATCH-IB01', DATE_SUB(CURDATE(),INTERVAL 5 MONTH), DATE_ADD(CURDATE(),INTERVAL 19 MONTH), 540, 520, 6.00, s.supplier_id, DATE_SUB(CURDATE(),INTERVAL 20 DAY), 'Active'
FROM inventory_items i, suppliers s WHERE i.item_code='MED021' AND s.supplier_code='SUP002' LIMIT 1;

-- Ciprofloxacin 500mg batch
INSERT IGNORE INTO inventory_batches (item_id, batch_number, manufacture_date, expiry_date, quantity, remaining_quantity, cost_per_unit, supplier_id, received_date, status)
SELECT i.item_id, 'BATCH-CP01', DATE_SUB(CURDATE(),INTERVAL 3 MONTH), DATE_ADD(CURDATE(),INTERVAL 21 MONTH), 250, 240, 32.00, s.supplier_id, DATE_SUB(CURDATE(),INTERVAL 12 DAY), 'Active'
FROM inventory_items i, suppliers s WHERE i.item_code='MED017' AND s.supplier_code='SUP002' LIMIT 1;

-- Insulin Glargine batch (refrigerated — near-expiry to demo FR-32)
INSERT IGNORE INTO inventory_batches (item_id, batch_number, manufacture_date, expiry_date, quantity, remaining_quantity, cost_per_unit, supplier_id, received_date, status)
SELECT i.item_id, 'BATCH-IN01', DATE_SUB(CURDATE(),INTERVAL 8 MONTH), DATE_ADD(CURDATE(),INTERVAL 25 DAY), 12, 8, 2900.00, s.supplier_id, DATE_SUB(CURDATE(),INTERVAL 60 DAY), 'Active'
FROM inventory_items i, suppliers s WHERE i.item_code='MED029' AND s.supplier_code='SUP003' LIMIT 1;

-- Dextrose 5% batch
INSERT IGNORE INTO inventory_batches (item_id, batch_number, manufacture_date, expiry_date, quantity, remaining_quantity, cost_per_unit, supplier_id, received_date, status)
SELECT i.item_id, 'BATCH-DX01', DATE_SUB(CURDATE(),INTERVAL 4 MONTH), DATE_ADD(CURDATE(),INTERVAL 14 MONTH), 80, 72, 170.00, s.supplier_id, DATE_SUB(CURDATE(),INTERVAL 18 DAY), 'Active'
FROM inventory_items i, suppliers s WHERE i.item_code='MED044' AND s.supplier_code='SUP003' LIMIT 1;

-- Salbutamol Inhaler batch
INSERT IGNORE INTO inventory_batches (item_id, batch_number, manufacture_date, expiry_date, quantity, remaining_quantity, cost_per_unit, supplier_id, received_date, status)
SELECT i.item_id, 'BATCH-SB01', DATE_SUB(CURDATE(),INTERVAL 2 MONTH), DATE_ADD(CURDATE(),INTERVAL 22 MONTH), 90, 85, 320.00, s.supplier_id, DATE_SUB(CURDATE(),INTERVAL 5 DAY), 'Active'
FROM inventory_items i, suppliers s WHERE i.item_code='MED030' AND s.supplier_code='SUP001' LIMIT 1;

-- Tramadol 50mg batch (below reorder — FR-37 demo)
INSERT IGNORE INTO inventory_batches (item_id, batch_number, manufacture_date, expiry_date, quantity, remaining_quantity, cost_per_unit, supplier_id, received_date, status)
SELECT i.item_id, 'BATCH-TR01', DATE_SUB(CURDATE(),INTERVAL 6 MONTH), DATE_ADD(CURDATE(),INTERVAL 18 MONTH), 60, 45, 50.00, s.supplier_id, DATE_SUB(CURDATE(),INTERVAL 30 DAY), 'Active'
FROM inventory_items i, suppliers s WHERE i.item_code='MED023' AND s.supplier_code='SUP002' LIMIT 1;

-- Digoxin 0.25mg batch (below reorder — FR-37 demo)
INSERT IGNORE INTO inventory_batches (item_id, batch_number, manufacture_date, expiry_date, quantity, remaining_quantity, cost_per_unit, supplier_id, received_date, status)
SELECT i.item_id, 'BATCH-DG01', DATE_SUB(CURDATE(),INTERVAL 5 MONTH), DATE_ADD(CURDATE(),INTERVAL 19 MONTH), 50, 35, 14.00, s.supplier_id, DATE_SUB(CURDATE(),INTERVAL 25 DAY), 'Active'
FROM inventory_items i, suppliers s WHERE i.item_code='MED034' AND s.supplier_code='SUP003' LIMIT 1;

-- ────────────────────────────────────────────────────────────
-- Completion marker
-- ────────────────────────────────────────────────────────────

SELECT CONCAT('Pharmacy schema patch applied — ',
    (SELECT COUNT(*) FROM inventory_items WHERE item_code LIKE 'MED%'),
    ' drugs in inventory.') AS result;
