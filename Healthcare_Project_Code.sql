-- =====================================================================
-- ICD-10 to CPT/HCPCS Crosswalk & Prior Authorization Decision Engine
-- FULL SCRIPT (MySQL)
--
-- This is a code-level crosswalk (not category-level): each entry maps
-- one specific ICD-10 diagnosis code to one specific CPT/HCPCS procedure
-- code, with a crosswalk confidence grade. Claim decisions are driven by
-- TWO INDEPENDENT factors, kept deliberately separate:
--   1. Crosswalk confidence (is this pairing even a recognized match?)
--      -> MEDIUM / LOW / NO_MATCH always routes to HUMAN_REVIEW
--   2. Prior authorization status (an administrative requirement,
--      independent of whether the pairing itself is valid)
--      -> only checked once crosswalk confidence is HIGH; a missing or
--         denied required authorization is what actually produces DENIED
-- So HUMAN_REVIEW never happens because of prior auth, and DENIED never
-- happens because of low crosswalk confidence -- the two reasons are not
-- conflated, by design.
--
-- Run this entire script in MySQL Workbench (Execute All)
-- =====================================================================

DROP DATABASE IF EXISTS icd_cpt_crosswalk;
CREATE DATABASE icd_cpt_crosswalk;
USE icd_cpt_crosswalk;

-- ---------------------------------------------------------------------
-- 1. TABLES
-- ---------------------------------------------------------------------

CREATE TABLE diagnoses (
    icd10_code        VARCHAR(10) PRIMARY KEY,
    description       VARCHAR(255) NOT NULL,
    category          VARCHAR(100)
);


CREATE TABLE procedures (
    proc_code         VARCHAR(10) PRIMARY KEY,
    code_type         VARCHAR(20) NOT NULL,
    short_label       VARCHAR(255) NOT NULL,
    category          VARCHAR(100),
    requires_prior_auth_default TINYINT(1) NOT NULL DEFAULT 0,
    CHECK (code_type IN ('CPT', 'HCPCS-II'))
);


-- THE CROSSWALK -- the primary artifact of this project. Each row is a
-- specific, individually-graded ICD-10-to-CPT/HCPCS pairing, not a
-- category-level rule. If a diagnosis/procedure pair submitted on a
-- claim has no row here at all, it is treated as NO_MATCH (unrecognized
-- pairing) downstream.
CREATE TABLE crosswalk_reference (
    crosswalk_id         INT AUTO_INCREMENT PRIMARY KEY,
    icd10_code           VARCHAR(10) NOT NULL,
    proc_code            VARCHAR(10) NOT NULL,
    crosswalk_confidence VARCHAR(20) NOT NULL,   -- 'HIGH' / 'MEDIUM' / 'LOW'
    requires_prior_auth  TINYINT(1) NOT NULL DEFAULT 0,
    source_note          VARCHAR(255),
    CHECK (crosswalk_confidence IN ('HIGH', 'MEDIUM', 'LOW')),
    FOREIGN KEY (icd10_code) REFERENCES diagnoses(icd10_code),
    FOREIGN KEY (proc_code) REFERENCES procedures(proc_code),
    UNIQUE KEY uq_crosswalk_pair (icd10_code, proc_code)
);


-- Prior authorization requests -- a separate administrative process from
-- the crosswalk itself. A procedure that requires prior auth needs one
-- of these on file with an APPROVED status for the claim to clear.
CREATE TABLE prior_authorizations (
    auth_id         INT PRIMARY KEY,
    patient_id      VARCHAR(20) NOT NULL,
    proc_code       VARCHAR(10) NOT NULL,
    payer           VARCHAR(100) NOT NULL,
    request_date    DATE NOT NULL,
    decision_date   DATE,
    auth_status     VARCHAR(20) NOT NULL,
    CHECK (auth_status IN ('APPROVED', 'DENIED', 'NOT_OBTAINED')),
    FOREIGN KEY (proc_code) REFERENCES procedures(proc_code)
);


CREATE TABLE claims (
    claim_id         INT PRIMARY KEY,
    patient_id       VARCHAR(20) NOT NULL,
    payer            VARCHAR(100) NOT NULL,
    service_date     DATE NOT NULL,
    icd10_code       VARCHAR(10) NOT NULL,
    proc_code        VARCHAR(10) NOT NULL,
    billed_amount    DECIMAL(10,2) NOT NULL,
    auth_id          INT,                        -- NULL if no prior auth was required/requested
    claim_decision   VARCHAR(20) NOT NULL,        -- 'APPROVED' / 'DENIED' / 'HUMAN_REVIEW'
    decision_reason  VARCHAR(255),
    CHECK (claim_decision IN ('APPROVED', 'DENIED', 'HUMAN_REVIEW')),
    FOREIGN KEY (icd10_code) REFERENCES diagnoses(icd10_code),
    FOREIGN KEY (proc_code) REFERENCES procedures(proc_code),
    FOREIGN KEY (auth_id) REFERENCES prior_authorizations(auth_id)
);


CREATE TABLE claim_decision_flags (
    flag_id            INT AUTO_INCREMENT PRIMARY KEY,
    claim_id           INT NOT NULL,
    crosswalk_confidence VARCHAR(20) NOT NULL,
    claim_decision       VARCHAR(20) NOT NULL,
    flag_reason          VARCHAR(255),
    flagged_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    reviewer_decision     VARCHAR(20),
    reviewer_notes        VARCHAR(255),
    FOREIGN KEY (claim_id) REFERENCES claims(claim_id)
);


CREATE TABLE decision_feedback (
    feedback_id          INT AUTO_INCREMENT PRIMARY KEY,
    icd10_code           VARCHAR(10) NOT NULL,
    proc_code            VARCHAR(10) NOT NULL,
    times_submitted       INT NOT NULL DEFAULT 0,
    times_denied          INT NOT NULL DEFAULT 0,
    times_human_review    INT NOT NULL DEFAULT 0,
    last_updated          DATE,
    FOREIGN KEY (icd10_code) REFERENCES diagnoses(icd10_code),
    FOREIGN KEY (proc_code) REFERENCES procedures(proc_code)
);

-- ---------------------------------------------------------------------
-- 2. DIAGNOSES (ICD-10-CM, public domain)
-- ---------------------------------------------------------------------
INSERT INTO diagnoses (icd10_code, description, category) VALUES
('E11.9', 'Type 2 diabetes mellitus without complications', 'Diabetes'),
('E11.65', 'Type 2 diabetes mellitus with hyperglycemia', 'Diabetes'),
('I10', 'Essential (primary) hypertension', 'Cardiovascular'),
('I25.10', 'Atherosclerotic heart disease of native coronary artery without angina pectoris', 'Cardiovascular'),
('J45.909', 'Unspecified asthma, uncomplicated', 'Respiratory'),
('J18.9', 'Pneumonia, unspecified organism', 'Respiratory'),
('S52.501A', 'Unspecified fracture of the lower end of right radius, initial encounter', 'Musculoskeletal'),
('M17.11', 'Unilateral primary osteoarthritis, right knee', 'Musculoskeletal'),
('M54.50', 'Low back pain, unspecified', 'Musculoskeletal'),
('F32.9', 'Major depressive disorder, single episode, unspecified', 'BehavioralHealth'),
('F41.1', 'Generalized anxiety disorder', 'BehavioralHealth'),
('O80', 'Encounter for full-term uncomplicated delivery', 'Obstetrics'),
('Z34.90', 'Encounter for supervision of normal pregnancy, unspecified trimester', 'Obstetrics'),
('N18.3', 'Chronic kidney disease, stage 3', 'Renal'),
('N39.0', 'Urinary tract infection, site not specified', 'Renal'),
('K21.9', 'Gastro-esophageal reflux disease without esophagitis', 'GI'),
('K35.80', 'Unspecified acute appendicitis', 'GI'),
('C50.919', 'Malignant neoplasm of unspecified site of unspecified female breast', 'Oncology'),
('C34.90', 'Malignant neoplasm of unspecified part of unspecified bronchus or lung', 'Oncology'),
('Z00.00', 'Encounter for general adult medical examination without abnormal findings', 'Preventive'),
('Z23', 'Encounter for immunization', 'Preventive'),
('H52.4', 'Presbyopia', 'Vision'),
('H35.30', 'Unspecified macular degeneration', 'Vision'),
('R07.9', 'Chest pain, unspecified', 'Symptom'),
('R51.9', 'Headache, unspecified', 'Symptom');

-- ---------------------------------------------------------------------
-- 3. PROCEDURES (CPT numeric + generic label; HCPCS-II public domain)
-- ---------------------------------------------------------------------
INSERT INTO procedures (proc_code, code_type, short_label, category, requires_prior_auth_default) VALUES
('99213', 'CPT', 'Office visit, established patient, low-moderate complexity', 'OfficeVisit', 0),
('99214', 'CPT', 'Office visit, established patient, moderate complexity', 'OfficeVisit', 0),
('99203', 'CPT', 'Office visit, new patient, low complexity', 'OfficeVisit', 0),
('99283', 'CPT', 'Emergency department visit, moderate severity', 'Emergency', 0),
('99284', 'CPT', 'Emergency department visit, high severity', 'Emergency', 0),
('80053', 'CPT', 'Comprehensive metabolic blood panel', 'Lab', 0),
('83036', 'CPT', 'Hemoglobin A1c blood test', 'Lab', 0),
('81002', 'CPT', 'Urinalysis, non-automated, without microscopy', 'Lab', 0),
('71046', 'CPT', 'Chest X-ray, 2 views', 'Imaging', 0),
('73721', 'CPT', 'MRI of lower extremity joint', 'Imaging', 1),
('74176', 'CPT', 'CT scan of abdomen and pelvis', 'Imaging', 1),
('93000', 'CPT', 'Electrocardiogram, routine, with interpretation', 'Cardiology', 0),
('93306', 'CPT', 'Echocardiogram, complete, with Doppler', 'Cardiology', 1),
('29881', 'CPT', 'Knee arthroscopy with meniscectomy', 'Surgery', 1),
('27447', 'CPT', 'Total knee replacement (arthroplasty)', 'Surgery', 1),
('25605', 'CPT', 'Closed treatment of distal radius fracture', 'Surgery', 1),
('59400', 'CPT', 'Routine obstetric care, vaginal delivery, antepartum/postpartum care', 'Obstetrics', 0),
('59510', 'CPT', 'Routine obstetric care, cesarean delivery, antepartum/postpartum care', 'Obstetrics', 1),
('90837', 'CPT', 'Psychotherapy, individual, 60 minutes', 'BehavioralHealth', 0),
('90791', 'CPT', 'Psychiatric diagnostic evaluation', 'BehavioralHealth', 0),
('44970', 'CPT', 'Laparoscopic appendectomy', 'Surgery', 1),
('45378', 'CPT', 'Diagnostic colonoscopy', 'GI', 1),
('77067', 'CPT', 'Screening mammography, bilateral', 'OncologyScreening', 0),
('96413', 'CPT', 'Chemotherapy infusion, initial hour, single drug', 'Oncology', 1),
('92014', 'CPT', 'Comprehensive eye exam, established patient', 'Vision', 0),
('92134', 'CPT', 'Optical coherence tomography, retina', 'Vision', 1),
('90471', 'CPT', 'Immunization administration, one vaccine', 'Preventive', 0),
('99395', 'CPT', 'Periodic preventive medicine exam, established patient', 'Preventive', 0),
('J1100', 'HCPCS-II', 'Injection, dexamethasone sodium phosphate, 1 mg', 'DrugInjection', 0),
('J0696', 'HCPCS-II', 'Injection, ceftriaxone sodium, per 250 mg', 'DrugInjection', 0),
('E0114', 'HCPCS-II', 'Crutches, underarm, other than wood, adjustable or fixed', 'DME', 0),
('E0143', 'HCPCS-II', 'Walker, folding, wheeled, adjustable or fixed height', 'DME', 1),
('A4253', 'HCPCS-II', 'Blood glucose test strips, per 50', 'DiabeticSupplies', 0),
('E0784', 'HCPCS-II', 'External ambulatory insulin infusion pump', 'DiabeticSupplies', 1),
('A0428', 'HCPCS-II', 'Ambulance service, basic life support, non-emergency', 'Ambulance', 0),
('L1832', 'HCPCS-II', 'Knee orthosis, adjustable knee joint, prefabricated', 'Orthotics', 1);

-- ---------------------------------------------------------------------
-- 4. CROSSWALK_REFERENCE (the primary artifact -- synthetic/illustrative
--    code-level ICD-10 to CPT/HCPCS crosswalk with a confidence grade)
-- ---------------------------------------------------------------------
INSERT INTO crosswalk_reference (icd10_code, proc_code, crosswalk_confidence, requires_prior_auth, source_note) VALUES
('E11.9', '83036', 'MEDIUM', 0, 'Illustrative crosswalk entry, Diabetes diagnosis to compatible procedure category'),
('E11.9', '80053', 'HIGH', 0, 'Illustrative crosswalk entry, Diabetes diagnosis to compatible procedure category'),
('E11.65', '99213', 'LOW', 0, 'Illustrative crosswalk entry, Diabetes diagnosis to compatible procedure category'),
('E11.65', 'E0784', 'LOW', 1, 'Illustrative crosswalk entry, Diabetes diagnosis to compatible procedure category'),
('E11.65', '99214', 'HIGH', 0, 'Illustrative crosswalk entry, Diabetes diagnosis to compatible procedure category'),
('E11.65', '83036', 'HIGH', 0, 'Illustrative crosswalk entry, Diabetes diagnosis to compatible procedure category'),
('I10', '93306', 'MEDIUM', 1, 'Illustrative crosswalk entry, Cardiovascular diagnosis to compatible procedure category'),
('I10', '74176', 'HIGH', 1, 'Illustrative crosswalk entry, Cardiovascular diagnosis to compatible procedure category'),
('I25.10', '71046', 'HIGH', 0, 'Illustrative crosswalk entry, Cardiovascular diagnosis to compatible procedure category'),
('I25.10', '93000', 'HIGH', 0, 'Illustrative crosswalk entry, Cardiovascular diagnosis to compatible procedure category'),
('I25.10', '73721', 'HIGH', 1, 'Illustrative crosswalk entry, Cardiovascular diagnosis to compatible procedure category'),
('I25.10', '93306', 'HIGH', 1, 'Illustrative crosswalk entry, Cardiovascular diagnosis to compatible procedure category'),
('J45.909', '99203', 'MEDIUM', 0, 'Illustrative crosswalk entry, Respiratory diagnosis to compatible procedure category'),
('J45.909', '73721', 'HIGH', 1, 'Illustrative crosswalk entry, Respiratory diagnosis to compatible procedure category'),
('J45.909', '74176', 'HIGH', 1, 'Illustrative crosswalk entry, Respiratory diagnosis to compatible procedure category'),
('J18.9', '74176', 'HIGH', 1, 'Illustrative crosswalk entry, Respiratory diagnosis to compatible procedure category'),
('J18.9', '73721', 'HIGH', 1, 'Illustrative crosswalk entry, Respiratory diagnosis to compatible procedure category'),
('J18.9', '99203', 'HIGH', 0, 'Illustrative crosswalk entry, Respiratory diagnosis to compatible procedure category'),
('S52.501A', '73721', 'HIGH', 1, 'Illustrative crosswalk entry, Musculoskeletal diagnosis to compatible procedure category'),
('S52.501A', '74176', 'HIGH', 1, 'Illustrative crosswalk entry, Musculoskeletal diagnosis to compatible procedure category'),
('S52.501A', 'L1832', 'HIGH', 1, 'Illustrative crosswalk entry, Musculoskeletal diagnosis to compatible procedure category'),
('S52.501A', '27447', 'LOW', 1, 'Illustrative crosswalk entry, Musculoskeletal diagnosis to compatible procedure category'),
('M17.11', 'L1832', 'HIGH', 1, 'Illustrative crosswalk entry, Musculoskeletal diagnosis to compatible procedure category'),
('M17.11', 'E0114', 'HIGH', 0, 'Illustrative crosswalk entry, Musculoskeletal diagnosis to compatible procedure category'),
('M54.50', '27447', 'HIGH', 1, 'Illustrative crosswalk entry, Musculoskeletal diagnosis to compatible procedure category'),
('M54.50', 'L1832', 'MEDIUM', 1, 'Illustrative crosswalk entry, Musculoskeletal diagnosis to compatible procedure category'),
('F32.9', '90837', 'HIGH', 0, 'Illustrative crosswalk entry, BehavioralHealth diagnosis to compatible procedure category'),
('F32.9', '90791', 'HIGH', 0, 'Illustrative crosswalk entry, BehavioralHealth diagnosis to compatible procedure category'),
('F41.1', '90791', 'LOW', 0, 'Illustrative crosswalk entry, BehavioralHealth diagnosis to compatible procedure category'),
('F41.1', '90837', 'HIGH', 0, 'Illustrative crosswalk entry, BehavioralHealth diagnosis to compatible procedure category'),
('O80', '73721', 'HIGH', 1, 'Illustrative crosswalk entry, Obstetrics diagnosis to compatible procedure category'),
('O80', '59510', 'HIGH', 1, 'Illustrative crosswalk entry, Obstetrics diagnosis to compatible procedure category'),
('O80', '74176', 'HIGH', 1, 'Illustrative crosswalk entry, Obstetrics diagnosis to compatible procedure category'),
('Z34.90', '73721', 'HIGH', 1, 'Illustrative crosswalk entry, Obstetrics diagnosis to compatible procedure category'),
('Z34.90', '74176', 'HIGH', 1, 'Illustrative crosswalk entry, Obstetrics diagnosis to compatible procedure category'),
('Z34.90', '71046', 'HIGH', 0, 'Illustrative crosswalk entry, Obstetrics diagnosis to compatible procedure category'),
('N18.3', '81002', 'HIGH', 0, 'Illustrative crosswalk entry, Renal diagnosis to compatible procedure category'),
('N18.3', '80053', 'MEDIUM', 0, 'Illustrative crosswalk entry, Renal diagnosis to compatible procedure category'),
('N18.3', 'J1100', 'MEDIUM', 0, 'Illustrative crosswalk entry, Renal diagnosis to compatible procedure category'),
('N18.3', '83036', 'HIGH', 0, 'Illustrative crosswalk entry, Renal diagnosis to compatible procedure category'),
('N39.0', 'J1100', 'LOW', 0, 'Illustrative crosswalk entry, Renal diagnosis to compatible procedure category'),
('N39.0', '80053', 'MEDIUM', 0, 'Illustrative crosswalk entry, Renal diagnosis to compatible procedure category'),
('N39.0', '81002', 'HIGH', 0, 'Illustrative crosswalk entry, Renal diagnosis to compatible procedure category'),
('N39.0', 'J0696', 'HIGH', 0, 'Illustrative crosswalk entry, Renal diagnosis to compatible procedure category'),
('K21.9', '27447', 'MEDIUM', 1, 'Illustrative crosswalk entry, GI diagnosis to compatible procedure category'),
('K21.9', '29881', 'HIGH', 1, 'Illustrative crosswalk entry, GI diagnosis to compatible procedure category'),
('K35.80', '27447', 'LOW', 1, 'Illustrative crosswalk entry, GI diagnosis to compatible procedure category'),
('K35.80', '45378', 'HIGH', 1, 'Illustrative crosswalk entry, GI diagnosis to compatible procedure category'),
('K35.80', '29881', 'HIGH', 1, 'Illustrative crosswalk entry, GI diagnosis to compatible procedure category'),
('K35.80', '44970', 'HIGH', 1, 'Illustrative crosswalk entry, GI diagnosis to compatible procedure category'),
('C50.919', '77067', 'HIGH', 0, 'Illustrative crosswalk entry, Oncology diagnosis to compatible procedure category'),
('C50.919', '96413', 'MEDIUM', 1, 'Illustrative crosswalk entry, Oncology diagnosis to compatible procedure category'),
('C34.90', '77067', 'HIGH', 0, 'Illustrative crosswalk entry, Oncology diagnosis to compatible procedure category'),
('C34.90', '96413', 'HIGH', 1, 'Illustrative crosswalk entry, Oncology diagnosis to compatible procedure category'),
('Z00.00', '99395', 'HIGH', 0, 'Illustrative crosswalk entry, Preventive diagnosis to compatible procedure category'),
('Z00.00', '90471', 'HIGH', 0, 'Illustrative crosswalk entry, Preventive diagnosis to compatible procedure category'),
('Z23', '99395', 'HIGH', 0, 'Illustrative crosswalk entry, Preventive diagnosis to compatible procedure category'),
('Z23', '90471', 'MEDIUM', 0, 'Illustrative crosswalk entry, Preventive diagnosis to compatible procedure category'),
('H52.4', '92014', 'MEDIUM', 0, 'Illustrative crosswalk entry, Vision diagnosis to compatible procedure category'),
('H52.4', '92134', 'HIGH', 1, 'Illustrative crosswalk entry, Vision diagnosis to compatible procedure category'),
('H35.30', '92134', 'HIGH', 1, 'Illustrative crosswalk entry, Vision diagnosis to compatible procedure category'),
('H35.30', '92014', 'HIGH', 0, 'Illustrative crosswalk entry, Vision diagnosis to compatible procedure category'),
('R07.9', '73721', 'HIGH', 1, 'Illustrative crosswalk entry, Symptom diagnosis to compatible procedure category'),
('R07.9', '99284', 'HIGH', 0, 'Illustrative crosswalk entry, Symptom diagnosis to compatible procedure category'),
('R07.9', '99283', 'HIGH', 0, 'Illustrative crosswalk entry, Symptom diagnosis to compatible procedure category'),
('R51.9', '73721', 'MEDIUM', 1, 'Illustrative crosswalk entry, Symptom diagnosis to compatible procedure category'),
('R51.9', '93000', 'HIGH', 0, 'Illustrative crosswalk entry, Symptom diagnosis to compatible procedure category'),
('R51.9', '99284', 'LOW', 0, 'Illustrative crosswalk entry, Symptom diagnosis to compatible procedure category'),
('R51.9', '74176', 'HIGH', 1, 'Illustrative crosswalk entry, Symptom diagnosis to compatible procedure category');

-- ---------------------------------------------------------------------
-- 5. PRIOR_AUTHORIZATIONS (78 synthetic auth records)
-- ---------------------------------------------------------------------
INSERT INTO prior_authorizations (auth_id, patient_id, proc_code, payer, request_date, decision_date, auth_status) VALUES
(1, 'PT20000', '92134', 'Medicare', '2026-03-20', '2026-03-28', 'APPROVED'),
(2, 'PT20003', 'L1832', 'Humana', '2025-01-07', '2025-01-11', 'APPROVED'),
(3, 'PT20004', '92134', 'Blue Cross Blue Shield', '2025-11-21', '2025-11-26', 'APPROVED'),
(4, 'PT20005', '73721', 'Medicaid', '2026-04-09', '2026-04-14', 'NOT_OBTAINED'),
(5, 'PT20007', '73721', 'Aetna', '2026-02-12', '2026-02-13', 'APPROVED'),
(6, 'PT20008', '93306', 'Blue Cross Blue Shield', '2026-04-22', '2026-05-02', 'APPROVED'),
(7, 'PT20009', '74176', 'Aetna', '2025-11-25', '2025-11-27', 'APPROVED'),
(8, 'PT20011', '27447', 'Medicare', '2026-03-28', '2026-04-04', 'DENIED'),
(9, 'PT20012', '74176', 'Blue Cross Blue Shield', '2026-01-19', '2026-01-24', 'APPROVED'),
(10, 'PT20016', '59510', 'Medicare', '2025-01-09', '2025-01-19', 'APPROVED'),
(11, 'PT20019', 'L1832', 'Blue Cross Blue Shield', '2026-01-27', '2026-01-29', 'APPROVED'),
(12, 'PT20020', '74176', 'Medicaid', '2025-08-15', '2025-08-20', 'APPROVED'),
(13, 'PT20025', '73721', 'Cigna', '2025-03-23', '2025-04-01', 'APPROVED'),
(14, 'PT20033', '73721', 'Medicaid', '2025-03-18', '2025-03-24', 'APPROVED'),
(15, 'PT20035', '73721', 'Cigna', '2025-01-21', '2025-01-23', 'APPROVED'),
(16, 'PT20036', '73721', 'Aetna', '2025-09-10', '2025-09-19', 'APPROVED'),
(17, 'PT20038', '74176', 'Medicaid', '2025-07-14', '2025-07-18', 'DENIED'),
(18, 'PT20041', '92134', 'UnitedHealthcare', '2025-09-20', '2025-09-28', 'APPROVED'),
(19, 'PT20045', '74176', 'Humana', '2025-08-26', '2025-09-03', 'APPROVED'),
(20, 'PT20046', '74176', 'Aetna', '2025-12-26', '2025-12-31', 'APPROVED'),
(21, 'PT20048', '74176', 'Medicare', '2025-12-13', '2025-12-20', 'APPROVED'),
(22, 'PT20050', '73721', 'Blue Cross Blue Shield', '2026-04-04', '2026-04-11', 'NOT_OBTAINED'),
(23, 'PT20063', 'L1832', 'Medicare', '2026-02-10', '2026-02-11', 'APPROVED'),
(24, 'PT20070', '29881', 'Medicare', '2025-08-18', '2025-08-20', 'APPROVED'),
(25, 'PT20072', '29881', 'Humana', '2026-02-19', '2026-02-28', 'APPROVED'),
(26, 'PT20077', '93306', 'Blue Cross Blue Shield', '2025-09-07', '2025-09-16', 'DENIED'),
(27, 'PT20079', 'L1832', 'Humana', '2025-12-14', '2025-12-20', 'APPROVED'),
(28, 'PT20080', '27447', 'Blue Cross Blue Shield', '2025-02-22', '2025-03-04', 'APPROVED'),
(29, 'PT20082', 'L1832', 'Medicaid', '2025-09-30', '2025-10-02', 'APPROVED'),
(30, 'PT20085', 'L1832', 'Blue Cross Blue Shield', '2025-06-20', '2025-06-24', 'DENIED'),
(31, 'PT20089', '96413', 'Cigna', '2025-05-01', '2025-05-04', 'APPROVED'),
(32, 'PT20092', '74176', 'Cigna', '2025-10-26', '2025-11-04', 'APPROVED'),
(33, 'PT20093', '73721', 'Medicaid', '2026-05-10', '2026-05-20', 'APPROVED'),
(34, 'PT20094', '73721', 'Cigna', '2025-08-22', '2025-08-29', 'APPROVED'),
(35, 'PT20095', '73721', 'Cigna', '2025-08-26', '2025-09-02', 'APPROVED'),
(36, 'PT20102', 'L1832', 'Humana', '2026-02-10', '2026-02-17', 'APPROVED'),
(37, 'PT20105', '92134', 'Humana', '2025-05-24', '2025-06-03', 'DENIED'),
(38, 'PT20106', '74176', 'Humana', '2025-07-22', '2025-07-28', 'APPROVED'),
(39, 'PT20107', '96413', 'Medicare', '2026-03-27', '2026-04-02', 'APPROVED'),
(40, 'PT20109', '74176', 'Cigna', '2026-05-17', '2026-05-22', 'APPROVED'),
(41, 'PT20110', '27447', 'Humana', '2025-09-24', '2025-09-28', 'NOT_OBTAINED'),
(42, 'PT20113', '93306', 'Medicare', '2025-05-27', '2025-06-04', 'NOT_OBTAINED'),
(43, 'PT20117', '74176', 'UnitedHealthcare', '2025-12-31', '2026-01-05', 'NOT_OBTAINED'),
(44, 'PT20120', '73721', 'Cigna', '2026-04-08', '2026-04-12', 'APPROVED'),
(45, 'PT20123', '27447', 'Cigna', '2025-04-20', '2025-04-28', 'APPROVED'),
(46, 'PT20126', '27447', 'Medicare', '2026-01-20', '2026-01-26', 'APPROVED'),
(47, 'PT20137', 'E0784', 'Cigna', '2026-06-05', '2026-06-12', 'DENIED'),
(48, 'PT20141', 'L1832', 'Humana', '2025-03-01', '2025-03-07', 'APPROVED'),
(49, 'PT20143', '92134', 'UnitedHealthcare', '2026-05-21', '2026-05-24', 'NOT_OBTAINED'),
(50, 'PT20149', 'L1832', 'UnitedHealthcare', '2026-02-11', '2026-02-14', 'APPROVED'),
(51, 'PT20150', '74176', 'Medicare', '2026-06-05', '2026-06-06', 'APPROVED'),
(52, 'PT20151', '74176', 'Aetna', '2025-04-23', '2025-04-25', 'APPROVED'),
(53, 'PT20155', 'L1832', 'Cigna', '2025-11-03', '2025-11-11', 'APPROVED'),
(54, 'PT20159', '73721', 'Medicare', '2025-10-19', '2025-10-29', 'DENIED'),
(55, 'PT20160', '29881', 'Cigna', '2025-10-28', '2025-11-02', 'APPROVED'),
(56, 'PT20161', '29881', 'Cigna', '2025-04-05', '2025-04-11', 'APPROVED'),
(57, 'PT20162', '29881', 'Aetna', '2025-03-28', '2025-03-31', 'APPROVED'),
(58, 'PT20166', '73721', 'Blue Cross Blue Shield', '2026-01-28', '2026-02-04', 'APPROVED'),
(59, 'PT20168', '73721', 'UnitedHealthcare', '2025-11-29', '2025-12-08', 'APPROVED'),
(60, 'PT20169', '73721', 'Humana', '2025-11-29', '2025-12-04', 'APPROVED'),
(61, 'PT20171', 'L1832', 'Medicaid', '2026-05-23', '2026-05-24', 'NOT_OBTAINED'),
(62, 'PT20172', 'L1832', 'UnitedHealthcare', '2025-03-14', '2025-03-20', 'APPROVED'),
(63, 'PT20173', '27447', 'Blue Cross Blue Shield', '2025-09-23', '2025-09-27', 'APPROVED'),
(64, 'PT20176', '27447', 'Humana', '2025-08-27', '2025-09-06', 'DENIED'),
(65, 'PT20179', '29881', 'UnitedHealthcare', '2025-01-10', '2025-01-19', 'APPROVED'),
(66, 'PT20180', '96413', 'Cigna', '2025-06-06', '2025-06-12', 'APPROVED'),
(67, 'PT20182', '92134', 'Blue Cross Blue Shield', '2025-11-29', '2025-12-06', 'NOT_OBTAINED'),
(68, 'PT20183', '73721', 'Humana', '2026-04-04', '2026-04-06', 'APPROVED'),
(69, 'PT20185', 'E0784', 'Aetna', '2025-11-09', '2025-11-16', 'APPROVED'),
(70, 'PT20188', '73721', 'Medicaid', '2025-11-05', '2025-11-11', 'APPROVED'),
(71, 'PT20191', '74176', 'Aetna', '2026-04-07', '2026-04-13', 'DENIED'),
(72, 'PT20201', 'L1832', 'UnitedHealthcare', '2025-09-21', '2025-09-26', 'APPROVED'),
(73, 'PT20207', 'E0784', 'Humana', '2025-07-06', '2025-07-16', 'NOT_OBTAINED'),
(74, 'PT20208', '44970', 'Blue Cross Blue Shield', '2024-12-20', '2024-12-26', 'APPROVED'),
(75, 'PT20211', '74176', 'UnitedHealthcare', '2026-03-12', '2026-03-16', 'APPROVED'),
(76, 'PT20213', '93306', 'Humana', '2026-04-02', '2026-04-12', 'APPROVED'),
(77, 'PT20216', '73721', 'Aetna', '2025-05-17', '2025-05-27', 'APPROVED'),
(78, 'PT20217', '73721', 'Aetna', '2026-05-11', '2026-05-16', 'APPROVED');

-- ---------------------------------------------------------------------
-- 6. CLAIMS (220 synthetic claim lines)
-- ---------------------------------------------------------------------
INSERT INTO claims (claim_id, patient_id, payer, service_date, icd10_code, proc_code, billed_amount, auth_id, claim_decision, decision_reason) VALUES
(1, 'PT20000', 'Medicare', '2026-04-08', 'H52.4', '92134', 3602.06, 1, 'APPROVED', NULL),
(2, 'PT20001', 'Blue Cross Blue Shield', '2025-04-07', 'M17.11', 'E0114', 1326.53, NULL, 'APPROVED', NULL),
(3, 'PT20002', 'Blue Cross Blue Shield', '2026-02-10', 'E11.65', '83036', 2772.43, NULL, 'APPROVED', NULL),
(4, 'PT20003', 'Humana', '2025-01-16', 'S52.501A', 'L1832', 2254.57, 2, 'APPROVED', NULL),
(5, 'PT20004', 'Blue Cross Blue Shield', '2025-12-01', 'H52.4', '92134', 2512.71, 3, 'APPROVED', NULL),
(6, 'PT20005', 'Medicaid', '2026-04-14', 'I25.10', '73721', 1222.42, 4, 'DENIED', 'Prior authorization not obtained for a procedure that requires it'),
(7, 'PT20006', 'Cigna', '2026-06-10', 'F41.1', '90837', 197.73, NULL, 'APPROVED', NULL),
(8, 'PT20007', 'Aetna', '2026-02-15', 'J45.909', '73721', 3567.16, 5, 'APPROVED', NULL),
(9, 'PT20008', 'Blue Cross Blue Shield', '2026-04-27', 'I10', '93306', 4118.98, 6, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(10, 'PT20009', 'Aetna', '2025-12-11', 'Z34.90', '74176', 1358.74, 7, 'APPROVED', NULL),
(11, 'PT20010', 'Aetna', '2025-01-12', 'J45.909', '99203', 1992.88, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(12, 'PT20011', 'Medicare', '2026-04-04', 'M54.50', '27447', 861.57, 8, 'DENIED', 'Prior authorization denied for a procedure that requires it'),
(13, 'PT20012', 'Blue Cross Blue Shield', '2026-02-09', 'J45.909', '74176', 4158.97, 9, 'APPROVED', NULL),
(14, 'PT20013', 'Blue Cross Blue Shield', '2025-07-11', 'E11.9', '29881', 4182.82, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(15, 'PT20014', 'UnitedHealthcare', '2025-02-13', 'J45.909', '99203', 954.63, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(16, 'PT20015', 'Blue Cross Blue Shield', '2025-10-31', 'N39.0', '81002', 377.77, NULL, 'APPROVED', NULL),
(17, 'PT20016', 'Medicare', '2025-01-16', 'O80', '59510', 1595.79, 10, 'APPROVED', NULL),
(18, 'PT20017', 'UnitedHealthcare', '2026-01-31', 'J18.9', '99203', 2662.39, NULL, 'APPROVED', NULL),
(19, 'PT20018', 'Medicaid', '2025-09-13', 'F41.1', '90837', 857.93, NULL, 'APPROVED', NULL),
(20, 'PT20019', 'Blue Cross Blue Shield', '2026-02-02', 'M54.50', 'L1832', 2564.58, 11, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(21, 'PT20020', 'Medicaid', '2025-09-02', 'O80', '74176', 2981.39, 12, 'APPROVED', NULL),
(22, 'PT20021', 'UnitedHealthcare', '2025-05-10', 'I25.10', '71046', 2052.11, NULL, 'APPROVED', NULL),
(23, 'PT20022', 'UnitedHealthcare', '2025-10-14', 'I25.10', '93000', 3859.11, NULL, 'APPROVED', NULL),
(24, 'PT20023', 'Cigna', '2025-03-12', 'E11.65', '99213', 1772.13, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(25, 'PT20024', 'Cigna', '2025-06-30', 'E11.65', '83036', 1596.24, NULL, 'APPROVED', NULL),
(26, 'PT20025', 'Cigna', '2025-04-05', 'J18.9', '73721', 645.93, 13, 'APPROVED', NULL),
(27, 'PT20026', 'Aetna', '2025-02-05', 'J18.9', '99203', 2033.52, NULL, 'APPROVED', NULL),
(28, 'PT20027', 'Aetna', '2025-02-04', 'N18.3', '83036', 2543.29, NULL, 'APPROVED', NULL),
(29, 'PT20028', 'Cigna', '2025-11-15', 'I25.10', '71046', 638.5, NULL, 'APPROVED', NULL),
(30, 'PT20029', 'Medicaid', '2026-01-12', 'Z23', '90471', 258.42, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(31, 'PT20030', 'Cigna', '2025-12-16', 'R07.9', '71046', 425.32, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(32, 'PT20031', 'Humana', '2026-03-04', 'I25.10', '93000', 199.86, NULL, 'APPROVED', NULL),
(33, 'PT20032', 'Blue Cross Blue Shield', '2026-01-27', 'E11.9', '80053', 2478.55, NULL, 'APPROVED', NULL),
(34, 'PT20033', 'Medicaid', '2025-04-03', 'I25.10', '73721', 551.77, 14, 'APPROVED', NULL),
(35, 'PT20034', 'Blue Cross Blue Shield', '2026-03-28', 'H52.4', '92014', 3533.28, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(36, 'PT20035', 'Cigna', '2025-01-31', 'R51.9', '73721', 2555.3, 15, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(37, 'PT20036', 'Aetna', '2025-09-19', 'R07.9', '73721', 1592.8, 16, 'APPROVED', NULL),
(38, 'PT20037', 'Blue Cross Blue Shield', '2026-03-29', 'N39.0', 'J0696', 3753.37, NULL, 'APPROVED', NULL),
(39, 'PT20038', 'Medicaid', '2025-07-23', 'O80', '74176', 1852.44, 17, 'DENIED', 'Prior authorization denied for a procedure that requires it'),
(40, 'PT20039', 'UnitedHealthcare', '2025-08-03', 'N39.0', 'J1100', 630.03, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(41, 'PT20040', 'Cigna', '2025-03-07', 'E11.65', '83036', 3465.16, NULL, 'APPROVED', NULL),
(42, 'PT20041', 'UnitedHealthcare', '2025-10-09', 'H35.30', '92134', 3502.45, 18, 'APPROVED', NULL),
(43, 'PT20042', 'Aetna', '2025-11-25', 'Z23', '90471', 3493.5, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(44, 'PT20043', 'Medicare', '2025-10-15', 'E11.65', '83036', 1536.14, NULL, 'APPROVED', NULL),
(45, 'PT20044', 'Blue Cross Blue Shield', '2025-05-20', 'E11.65', '99213', 1951.18, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(46, 'PT20045', 'Humana', '2025-09-01', 'Z34.90', '74176', 656.11, 19, 'APPROVED', NULL),
(47, 'PT20046', 'Aetna', '2026-01-13', 'R51.9', '74176', 2898.53, 20, 'APPROVED', NULL),
(48, 'PT20047', 'Medicare', '2026-04-29', 'E11.9', '80053', 3020.96, NULL, 'APPROVED', NULL),
(49, 'PT20048', 'Medicare', '2025-12-21', 'Z34.90', '74176', 2951.41, 21, 'APPROVED', NULL),
(50, 'PT20049', 'Blue Cross Blue Shield', '2025-03-31', 'H35.30', '27447', 3921.99, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing');
INSERT INTO claims (claim_id, patient_id, payer, service_date, icd10_code, proc_code, billed_amount, auth_id, claim_decision, decision_reason) VALUES
(51, 'PT20050', 'Blue Cross Blue Shield', '2026-04-07', 'J18.9', '73721', 887.12, 22, 'DENIED', 'Prior authorization not obtained for a procedure that requires it'),
(52, 'PT20051', 'Blue Cross Blue Shield', '2025-12-18', 'R07.9', '99283', 1421.68, NULL, 'APPROVED', NULL),
(53, 'PT20052', 'UnitedHealthcare', '2025-08-07', 'I25.10', '81002', 3787.43, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(54, 'PT20053', 'Cigna', '2025-11-25', 'F32.9', 'A0428', 3828.71, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(55, 'PT20054', 'Aetna', '2025-03-26', 'O80', 'A4253', 1893.72, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(56, 'PT20055', 'Aetna', '2026-05-15', 'Z34.90', '71046', 975.46, NULL, 'APPROVED', NULL),
(57, 'PT20056', 'Medicare', '2025-06-27', 'N18.3', '99203', 1456.89, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(58, 'PT20057', 'Medicare', '2025-06-02', 'J45.909', 'E0114', 3789.84, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(59, 'PT20058', 'Medicare', '2026-05-20', 'Z23', '99395', 3990.26, NULL, 'APPROVED', NULL),
(60, 'PT20059', 'Medicare', '2026-03-26', 'F41.1', '90791', 2379.95, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(61, 'PT20060', 'Medicare', '2026-06-20', 'C50.919', '74176', 3554.95, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(62, 'PT20061', 'Humana', '2026-01-26', 'N18.3', '83036', 3664.04, NULL, 'APPROVED', NULL),
(63, 'PT20062', 'Medicare', '2025-05-25', 'N18.3', 'J1100', 2237.43, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(64, 'PT20063', 'Medicare', '2026-02-25', 'M54.50', 'L1832', 546.41, 23, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(65, 'PT20064', 'Blue Cross Blue Shield', '2026-06-13', 'E11.65', '83036', 2318.99, NULL, 'APPROVED', NULL),
(66, 'PT20065', 'Medicaid', '2025-04-06', 'I25.10', 'E0143', 762.93, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(67, 'PT20066', 'Cigna', '2026-02-18', 'N39.0', '90471', 1090.89, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(68, 'PT20067', 'Humana', '2026-03-21', 'N39.0', 'J0696', 3934.72, NULL, 'APPROVED', NULL),
(69, 'PT20068', 'UnitedHealthcare', '2025-09-24', 'N18.3', '99214', 2971.19, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(70, 'PT20069', 'UnitedHealthcare', '2025-06-09', 'E11.65', '93306', 123.81, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(71, 'PT20070', 'Medicare', '2025-09-08', 'K21.9', '29881', 2132.64, 24, 'APPROVED', NULL),
(72, 'PT20071', 'Medicaid', '2025-07-22', 'Z00.00', '59400', 2262.7, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(73, 'PT20072', 'Humana', '2026-02-28', 'K35.80', '29881', 2258.56, 25, 'APPROVED', NULL),
(74, 'PT20073', 'Humana', '2025-08-10', 'R51.9', '99284', 2314.63, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(75, 'PT20074', 'Medicaid', '2025-08-27', 'J18.9', '99203', 2665.02, NULL, 'APPROVED', NULL),
(76, 'PT20075', 'Medicare', '2025-11-20', 'M17.11', 'E0114', 1374.33, NULL, 'APPROVED', NULL),
(77, 'PT20076', 'UnitedHealthcare', '2025-04-10', 'S52.501A', '93306', 3742.0, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(78, 'PT20077', 'Blue Cross Blue Shield', '2025-09-23', 'I25.10', '93306', 475.19, 26, 'DENIED', 'Prior authorization denied for a procedure that requires it'),
(79, 'PT20078', 'Medicaid', '2026-02-17', 'J45.909', '93306', 2901.51, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(80, 'PT20079', 'Humana', '2026-01-02', 'M54.50', 'L1832', 4069.56, 27, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(81, 'PT20080', 'Blue Cross Blue Shield', '2025-03-14', 'M54.50', '27447', 512.96, 28, 'APPROVED', NULL),
(82, 'PT20081', 'UnitedHealthcare', '2025-05-31', 'H35.30', '92014', 836.21, NULL, 'APPROVED', NULL),
(83, 'PT20082', 'Medicaid', '2025-10-17', 'S52.501A', 'L1832', 467.89, 29, 'APPROVED', NULL),
(84, 'PT20083', 'Blue Cross Blue Shield', '2026-02-05', 'N39.0', '80053', 1834.08, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(85, 'PT20084', 'Aetna', '2026-01-18', 'F32.9', '90837', 2690.28, NULL, 'APPROVED', NULL),
(86, 'PT20085', 'Blue Cross Blue Shield', '2025-07-05', 'M54.50', 'L1832', 1947.55, 30, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(87, 'PT20086', 'Humana', '2026-06-09', 'J45.909', '99203', 138.6, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(88, 'PT20087', 'Medicare', '2026-06-01', 'C34.90', '93306', 4128.56, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(89, 'PT20088', 'Medicaid', '2025-04-30', 'M54.50', '59510', 3139.78, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(90, 'PT20089', 'Cigna', '2025-05-17', 'C50.919', '96413', 3704.35, 31, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(91, 'PT20090', 'Humana', '2025-03-14', 'M17.11', 'E0114', 1484.59, NULL, 'APPROVED', NULL),
(92, 'PT20091', 'Medicaid', '2025-12-31', 'E11.9', '80053', 3798.66, NULL, 'APPROVED', NULL),
(93, 'PT20092', 'Cigna', '2025-11-03', 'Z34.90', '74176', 966.2, 32, 'APPROVED', NULL),
(94, 'PT20093', 'Medicaid', '2026-05-25', 'R51.9', '73721', 954.53, 33, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(95, 'PT20094', 'Cigna', '2025-08-31', 'J45.909', '73721', 1905.04, 34, 'APPROVED', NULL),
(96, 'PT20095', 'Cigna', '2025-09-14', 'Z34.90', '73721', 3810.78, 35, 'APPROVED', NULL),
(97, 'PT20096', 'Humana', '2026-04-01', 'C34.90', '83036', 2734.2, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(98, 'PT20097', 'UnitedHealthcare', '2026-01-31', 'E11.65', '83036', 1666.85, NULL, 'APPROVED', NULL),
(99, 'PT20098', 'Blue Cross Blue Shield', '2025-03-01', 'K21.9', 'A0428', 3974.25, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(100, 'PT20099', 'Medicare', '2026-02-13', 'R51.9', '99284', 1363.63, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision');
INSERT INTO claims (claim_id, patient_id, payer, service_date, icd10_code, proc_code, billed_amount, auth_id, claim_decision, decision_reason) VALUES
(101, 'PT20100', 'Medicare', '2025-10-04', 'H35.30', '92014', 3909.09, NULL, 'APPROVED', NULL),
(102, 'PT20101', 'Aetna', '2025-01-28', 'N18.3', '80053', 3261.51, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(103, 'PT20102', 'Humana', '2026-02-23', 'S52.501A', 'L1832', 2897.86, 36, 'APPROVED', NULL),
(104, 'PT20103', 'Humana', '2025-03-17', 'N39.0', 'J1100', 3810.4, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(105, 'PT20104', 'Humana', '2025-09-14', 'H35.30', '92014', 1080.3, NULL, 'APPROVED', NULL),
(106, 'PT20105', 'Humana', '2025-05-28', 'H52.4', '92134', 1086.38, 37, 'DENIED', 'Prior authorization denied for a procedure that requires it'),
(107, 'PT20106', 'Humana', '2025-07-28', 'J18.9', '74176', 289.73, 38, 'APPROVED', NULL),
(108, 'PT20107', 'Medicare', '2026-04-12', 'C34.90', '96413', 1156.28, 39, 'APPROVED', NULL),
(109, 'PT20108', 'Cigna', '2025-05-21', 'R51.9', '99284', 3103.92, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(110, 'PT20109', 'Cigna', '2026-05-31', 'J45.909', '74176', 3310.27, 40, 'APPROVED', NULL),
(111, 'PT20110', 'Humana', '2025-10-13', 'M54.50', '27447', 1062.67, 41, 'DENIED', 'Prior authorization not obtained for a procedure that requires it'),
(112, 'PT20111', 'Cigna', '2025-01-10', 'E11.65', '99283', 1145.52, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(113, 'PT20112', 'UnitedHealthcare', '2025-04-15', 'E11.65', '99214', 2309.3, NULL, 'APPROVED', NULL),
(114, 'PT20113', 'Medicare', '2025-06-14', 'I25.10', '93306', 1043.36, 42, 'DENIED', 'Prior authorization not obtained for a procedure that requires it'),
(115, 'PT20114', 'Blue Cross Blue Shield', '2025-12-18', 'N39.0', 'J0696', 3147.41, NULL, 'APPROVED', NULL),
(116, 'PT20115', 'Humana', '2026-04-04', 'I10', '81002', 3465.92, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(117, 'PT20116', 'Blue Cross Blue Shield', '2026-04-01', 'R51.9', '29881', 3157.7, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(118, 'PT20117', 'UnitedHealthcare', '2026-01-13', 'S52.501A', '74176', 2771.34, 43, 'DENIED', 'Prior authorization not obtained for a procedure that requires it'),
(119, 'PT20118', 'Medicaid', '2026-03-14', 'M17.11', 'E0114', 1598.2, NULL, 'APPROVED', NULL),
(120, 'PT20119', 'Medicare', '2025-03-22', 'N39.0', '80053', 417.46, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(121, 'PT20120', 'Cigna', '2026-04-20', 'R07.9', '73721', 3471.92, 44, 'APPROVED', NULL),
(122, 'PT20121', 'Blue Cross Blue Shield', '2025-11-08', 'Z00.00', '80053', 3065.61, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(123, 'PT20122', 'UnitedHealthcare', '2025-05-27', 'N18.3', '81002', 1550.93, NULL, 'APPROVED', NULL),
(124, 'PT20123', 'Cigna', '2025-05-01', 'K35.80', '27447', 3000.76, 45, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(125, 'PT20124', 'Cigna', '2026-04-15', 'N18.3', '83036', 987.51, NULL, 'APPROVED', NULL),
(126, 'PT20125', 'Aetna', '2025-09-12', 'R07.9', 'E0784', 1566.99, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(127, 'PT20126', 'Medicare', '2026-02-10', 'K35.80', '27447', 1673.77, 46, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(128, 'PT20127', 'UnitedHealthcare', '2025-07-01', 'C50.919', '73721', 445.18, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(129, 'PT20128', 'UnitedHealthcare', '2025-01-23', 'N18.3', '81002', 2202.02, NULL, 'APPROVED', NULL),
(130, 'PT20129', 'Medicaid', '2025-01-23', 'N18.3', '80053', 3546.96, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(131, 'PT20130', 'Cigna', '2025-03-28', 'N18.3', '83036', 411.9, NULL, 'APPROVED', NULL),
(132, 'PT20131', 'Aetna', '2025-03-28', 'N39.0', 'J1100', 2690.78, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(133, 'PT20132', 'Medicaid', '2025-09-09', 'Z00.00', '99395', 984.36, NULL, 'APPROVED', NULL),
(134, 'PT20133', 'Humana', '2025-12-13', 'R51.9', '93000', 1968.66, NULL, 'APPROVED', NULL),
(135, 'PT20134', 'Blue Cross Blue Shield', '2025-05-20', 'N39.0', '81002', 2088.17, NULL, 'APPROVED', NULL),
(136, 'PT20135', 'Humana', '2026-02-25', 'I10', '99203', 3483.21, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(137, 'PT20136', 'Humana', '2026-01-23', 'E11.9', '83036', 443.17, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(138, 'PT20137', 'Cigna', '2026-06-21', 'E11.65', 'E0784', 3004.11, 47, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(139, 'PT20138', 'Medicaid', '2026-01-20', 'M17.11', '74176', 766.58, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(140, 'PT20139', 'Cigna', '2026-06-26', 'Z00.00', '99395', 1205.42, NULL, 'APPROVED', NULL),
(141, 'PT20140', 'Cigna', '2025-04-28', 'K21.9', '90791', 2747.92, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(142, 'PT20141', 'Humana', '2025-03-05', 'M17.11', 'L1832', 1967.38, 48, 'APPROVED', NULL),
(143, 'PT20142', 'UnitedHealthcare', '2026-01-03', 'M17.11', 'E0114', 2501.95, NULL, 'APPROVED', NULL),
(144, 'PT20143', 'UnitedHealthcare', '2026-06-05', 'H35.30', '92134', 1898.06, 49, 'DENIED', 'Prior authorization not obtained for a procedure that requires it'),
(145, 'PT20144', 'Humana', '2026-05-06', 'F32.9', 'L1832', 1149.42, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(146, 'PT20145', 'Blue Cross Blue Shield', '2025-04-05', 'F41.1', 'L1832', 3633.13, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(147, 'PT20146', 'Humana', '2025-05-18', 'F32.9', '90791', 3367.9, NULL, 'APPROVED', NULL),
(148, 'PT20147', 'Medicaid', '2025-03-01', 'K35.80', '59510', 3887.56, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(149, 'PT20148', 'Humana', '2026-04-06', 'K21.9', '96413', 1092.03, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(150, 'PT20149', 'UnitedHealthcare', '2026-03-02', 'S52.501A', 'L1832', 3259.22, 50, 'APPROVED', NULL);
INSERT INTO claims (claim_id, patient_id, payer, service_date, icd10_code, proc_code, billed_amount, auth_id, claim_decision, decision_reason) VALUES
(151, 'PT20150', 'Medicare', '2026-06-13', 'Z34.90', '74176', 293.38, 51, 'APPROVED', NULL),
(152, 'PT20151', 'Aetna', '2025-05-12', 'S52.501A', '74176', 1525.88, 52, 'APPROVED', NULL),
(153, 'PT20152', 'Medicaid', '2025-03-26', 'H35.30', 'J0696', 2494.86, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(154, 'PT20153', 'Blue Cross Blue Shield', '2025-07-12', 'F32.9', '99214', 871.42, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(155, 'PT20154', 'Aetna', '2025-08-02', 'Z23', '99395', 2316.41, NULL, 'APPROVED', NULL),
(156, 'PT20155', 'Cigna', '2025-11-15', 'S52.501A', 'L1832', 1356.83, 53, 'APPROVED', NULL),
(157, 'PT20156', 'Aetna', '2026-01-04', 'I25.10', '71046', 2909.26, NULL, 'APPROVED', NULL),
(158, 'PT20157', 'Medicaid', '2026-04-18', 'C50.919', '77067', 4063.5, NULL, 'APPROVED', NULL),
(159, 'PT20158', 'Humana', '2025-01-13', 'Z23', 'J1100', 1630.65, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(160, 'PT20159', 'Medicare', '2025-10-28', 'O80', '73721', 542.46, 54, 'DENIED', 'Prior authorization denied for a procedure that requires it'),
(161, 'PT20160', 'Cigna', '2025-11-02', 'K35.80', '29881', 3189.05, 55, 'APPROVED', NULL),
(162, 'PT20161', 'Cigna', '2025-04-23', 'K35.80', '29881', 1352.57, 56, 'APPROVED', NULL),
(163, 'PT20162', 'Aetna', '2025-04-05', 'K35.80', '29881', 655.89, 57, 'APPROVED', NULL),
(164, 'PT20163', 'Medicare', '2026-04-20', 'E11.65', '99214', 2978.74, NULL, 'APPROVED', NULL),
(165, 'PT20164', 'Aetna', '2025-06-10', 'E11.65', '99214', 1864.49, NULL, 'APPROVED', NULL),
(166, 'PT20165', 'Medicare', '2026-03-14', 'N39.0', 'J0696', 648.6, NULL, 'APPROVED', NULL),
(167, 'PT20166', 'Blue Cross Blue Shield', '2026-01-31', 'S52.501A', '73721', 1442.07, 58, 'APPROVED', NULL),
(168, 'PT20167', 'Medicaid', '2025-09-08', 'N39.0', 'J1100', 4140.38, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(169, 'PT20168', 'UnitedHealthcare', '2025-12-05', 'Z34.90', '73721', 1486.73, 59, 'APPROVED', NULL),
(170, 'PT20169', 'Humana', '2025-12-07', 'R51.9', '73721', 1285.59, 60, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(171, 'PT20170', 'Cigna', '2025-08-28', 'N18.3', 'J1100', 2599.55, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(172, 'PT20171', 'Medicaid', '2026-06-13', 'M54.50', 'L1832', 2990.64, 61, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(173, 'PT20172', 'UnitedHealthcare', '2025-03-27', 'M54.50', 'L1832', 1083.97, 62, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(174, 'PT20173', 'Blue Cross Blue Shield', '2025-09-30', 'K35.80', '27447', 3717.31, 63, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(175, 'PT20174', 'Medicare', '2025-03-07', 'C50.919', 'A0428', 3849.75, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(176, 'PT20175', 'Aetna', '2025-05-30', 'N39.0', '81002', 3927.71, NULL, 'APPROVED', NULL),
(177, 'PT20176', 'Humana', '2025-09-04', 'K35.80', '27447', 2441.04, 64, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(178, 'PT20177', 'Aetna', '2026-04-11', 'I25.10', '93000', 1738.98, NULL, 'APPROVED', NULL),
(179, 'PT20178', 'Humana', '2025-11-12', 'H52.4', '71046', 2843.84, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(180, 'PT20179', 'UnitedHealthcare', '2025-01-17', 'K35.80', '29881', 898.08, 65, 'APPROVED', NULL),
(181, 'PT20180', 'Cigna', '2025-06-27', 'C50.919', '96413', 2219.05, 66, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(182, 'PT20181', 'Blue Cross Blue Shield', '2025-05-29', 'E11.65', '99214', 4032.24, NULL, 'APPROVED', NULL),
(183, 'PT20182', 'Blue Cross Blue Shield', '2025-12-20', 'H35.30', '92134', 3773.88, 67, 'DENIED', 'Prior authorization not obtained for a procedure that requires it'),
(184, 'PT20183', 'Humana', '2026-04-20', 'R07.9', '73721', 3809.91, 68, 'APPROVED', NULL),
(185, 'PT20184', 'Medicare', '2025-12-05', 'R51.9', '99284', 2222.79, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(186, 'PT20185', 'Aetna', '2025-11-25', 'E11.65', 'E0784', 1296.19, 69, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(187, 'PT20186', 'UnitedHealthcare', '2025-03-13', 'N18.3', '83036', 588.33, NULL, 'APPROVED', NULL),
(188, 'PT20187', 'Aetna', '2026-02-11', 'R07.9', '99283', 2037.32, NULL, 'APPROVED', NULL),
(189, 'PT20188', 'Medicaid', '2025-11-10', 'O80', '73721', 1706.55, 70, 'APPROVED', NULL),
(190, 'PT20189', 'Medicaid', '2025-08-16', 'N18.3', '74176', 3154.82, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(191, 'PT20190', 'Medicare', '2025-04-11', 'I25.10', '93000', 3343.47, NULL, 'APPROVED', NULL),
(192, 'PT20191', 'Aetna', '2026-04-10', 'R51.9', '74176', 1296.44, 71, 'DENIED', 'Prior authorization denied for a procedure that requires it'),
(193, 'PT20192', 'Humana', '2026-04-06', 'Z23', '99395', 2263.14, NULL, 'APPROVED', NULL),
(194, 'PT20193', 'Cigna', '2025-02-16', 'F41.1', '90837', 203.42, NULL, 'APPROVED', NULL),
(195, 'PT20194', 'UnitedHealthcare', '2026-05-26', 'F32.9', '44970', 3927.49, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(196, 'PT20195', 'UnitedHealthcare', '2025-03-02', 'S52.501A', '90837', 1377.99, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(197, 'PT20196', 'Medicaid', '2025-06-26', 'K21.9', '99214', 3703.83, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(198, 'PT20197', 'UnitedHealthcare', '2025-08-30', 'S52.501A', 'A0428', 3991.52, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(199, 'PT20198', 'Medicaid', '2025-11-10', 'Z23', '83036', 3447.98, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(200, 'PT20199', 'Cigna', '2025-05-19', 'M54.50', '90471', 2945.8, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing');
INSERT INTO claims (claim_id, patient_id, payer, service_date, icd10_code, proc_code, billed_amount, auth_id, claim_decision, decision_reason) VALUES
(201, 'PT20200', 'UnitedHealthcare', '2025-03-22', 'N39.0', '90471', 995.85, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(202, 'PT20201', 'UnitedHealthcare', '2025-10-03', 'M54.50', 'L1832', 3045.6, 72, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(203, 'PT20202', 'Medicare', '2025-04-29', 'R51.9', '99284', 2203.14, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(204, 'PT20203', 'UnitedHealthcare', '2025-10-11', 'J18.9', '27447', 2714.71, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(205, 'PT20204', 'Medicare', '2026-03-27', 'I25.10', '93000', 379.47, NULL, 'APPROVED', NULL),
(206, 'PT20205', 'Blue Cross Blue Shield', '2025-09-14', 'E11.9', '90837', 3388.29, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(207, 'PT20206', 'UnitedHealthcare', '2025-07-14', 'N18.3', '81002', 814.73, NULL, 'APPROVED', NULL),
(208, 'PT20207', 'Humana', '2025-07-10', 'E11.65', 'E0784', 3775.25, 73, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(209, 'PT20208', 'Blue Cross Blue Shield', '2025-01-03', 'K35.80', '44970', 323.4, 74, 'APPROVED', NULL),
(210, 'PT20209', 'Cigna', '2026-06-14', 'E11.65', '99214', 2160.72, NULL, 'APPROVED', NULL),
(211, 'PT20210', 'UnitedHealthcare', '2026-06-29', 'H52.4', 'E0784', 2524.73, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(212, 'PT20211', 'UnitedHealthcare', '2026-03-23', 'J45.909', '74176', 2832.31, 75, 'APPROVED', NULL),
(213, 'PT20212', 'Cigna', '2026-05-26', 'F41.1', '90791', 220.75, NULL, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(214, 'PT20213', 'Humana', '2026-04-05', 'I10', '93306', 3707.67, 76, 'HUMAN_REVIEW', 'Crosswalk pairing confidence too low for automatic decision'),
(215, 'PT20214', 'Blue Cross Blue Shield', '2026-05-31', 'Z00.00', '90471', 3057.95, NULL, 'APPROVED', NULL),
(216, 'PT20215', 'UnitedHealthcare', '2025-04-28', 'E11.9', '99284', 2421.7, NULL, 'HUMAN_REVIEW', 'No crosswalk entry found for this diagnosis-procedure pairing'),
(217, 'PT20216', 'Aetna', '2025-05-30', 'O80', '73721', 1357.91, 77, 'APPROVED', NULL),
(218, 'PT20217', 'Aetna', '2026-05-26', 'Z34.90', '73721', 2756.53, 78, 'APPROVED', NULL),
(219, 'PT20218', 'Aetna', '2026-04-11', 'R07.9', '99284', 1377.66, NULL, 'APPROVED', NULL),
(220, 'PT20219', 'UnitedHealthcare', '2025-02-13', 'F32.9', '90791', 2094.34, NULL, 'APPROVED', NULL);

-- ---------------------------------------------------------------------
-- 7. VALIDATION VIEWS
-- ---------------------------------------------------------------------

-- Every claim joined to its diagnosis/procedure/crosswalk/prior-auth
-- data. Crosswalk confidence defaults to NO_MATCH if no crosswalk entry
-- exists for that exact diagnosis-procedure pair.
CREATE OR REPLACE VIEW v_claim_decision_detail AS
SELECT
    c.claim_id, c.patient_id, c.payer, c.service_date,
    c.icd10_code, d.description AS diagnosis_desc, d.category AS diagnosis_category,
    c.proc_code, p.short_label AS procedure_label, p.category AS procedure_category,
    COALESCE(cw.crosswalk_confidence, 'NO_MATCH') AS crosswalk_confidence,
    COALESCE(cw.requires_prior_auth, 0) AS requires_prior_auth,
    pa.auth_status,
    c.billed_amount, c.claim_decision, c.decision_reason
FROM claims c
JOIN diagnoses d ON c.icd10_code = d.icd10_code
JOIN procedures p ON c.proc_code = p.proc_code
LEFT JOIN crosswalk_reference cw
    ON cw.icd10_code = c.icd10_code AND cw.proc_code = c.proc_code
LEFT JOIN prior_authorizations pa ON pa.auth_id = c.auth_id;

-- Decision outcome rolled up overall (APPROVED / DENIED / HUMAN_REVIEW)
CREATE OR REPLACE VIEW v_decision_summary AS
SELECT
    claim_decision,
    COUNT(*) AS total_claims,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM claims), 1) AS pct_of_claims,
    ROUND(SUM(billed_amount), 2) AS total_billed
FROM claims
GROUP BY claim_decision;

-- Decision outcome broken down BY crosswalk confidence tier -- this is
-- the view that proves human review is driven purely by pairing
-- confidence, never by prior authorization.
CREATE OR REPLACE VIEW v_confidence_tier_decision_summary AS
SELECT
    crosswalk_confidence,
    claim_decision,
    COUNT(*) AS claim_count
FROM v_claim_decision_detail
GROUP BY crosswalk_confidence, claim_decision
ORDER BY crosswalk_confidence, claim_decision;

-- Of the claims that were DENIED, confirms the reason is always a
-- prior-authorization failure, and breaks down which type.
CREATE OR REPLACE VIEW v_denial_reason_breakdown AS
SELECT
    auth_status,
    COUNT(*) AS denied_claim_count,
    ROUND(SUM(billed_amount), 2) AS denied_amount
FROM v_claim_decision_detail
WHERE claim_decision = 'DENIED'
GROUP BY auth_status;

-- Decision outcome by payer
CREATE OR REPLACE VIEW v_payer_decision_summary AS
SELECT
    payer,
    COUNT(*) AS total_claims,
    SUM(claim_decision = 'APPROVED') AS approved,
    SUM(claim_decision = 'DENIED') AS denied,
    SUM(claim_decision = 'HUMAN_REVIEW') AS human_review,
    ROUND(100.0 * SUM(claim_decision = 'HUMAN_REVIEW') / COUNT(*), 1) AS human_review_rate_pct
FROM claims
GROUP BY payer
ORDER BY human_review_rate_pct DESC;

-- ---------------------------------------------------------------------
-- 8. POPULATE claim_decision_flags (audit trail -- every non-APPROVED
--    claim gets a flag record)
-- ---------------------------------------------------------------------
INSERT INTO claim_decision_flags (claim_id, crosswalk_confidence, claim_decision, flag_reason, reviewer_decision)
SELECT
    claim_id,
    crosswalk_confidence,
    claim_decision,
    decision_reason,
    CASE
        WHEN claim_decision = 'DENIED' THEN 'OVERRIDDEN'
        WHEN claim_decision = 'HUMAN_REVIEW' THEN 'PENDING_REVIEW'
        ELSE 'APPROVED'
    END AS reviewer_decision
FROM v_claim_decision_detail
WHERE claim_decision != 'APPROVED';

-- ---------------------------------------------------------------------
-- 9. POPULATE decision_feedback (feedback loop per diagnosis/procedure
--    pair -- lets the crosswalk confidence grades be recalibrated from
--    real outcomes over time)
-- ---------------------------------------------------------------------
INSERT INTO decision_feedback (icd10_code, proc_code, times_submitted, times_denied, times_human_review, last_updated)
SELECT
    icd10_code,
    proc_code,
    COUNT(*) AS times_submitted,
    SUM(claim_decision = 'DENIED') AS times_denied,
    SUM(claim_decision = 'HUMAN_REVIEW') AS times_human_review,
    MAX(service_date) AS last_updated
FROM claims
GROUP BY icd10_code, proc_code;

-- ---------------------------------------------------------------------
-- 10. SANITY CHECKS
-- ---------------------------------------------------------------------
SELECT 'diagnoses' AS tbl, COUNT(*) AS row_count FROM diagnoses
UNION ALL SELECT 'procedures', COUNT(*) FROM procedures
UNION ALL SELECT 'crosswalk_reference', COUNT(*) FROM crosswalk_reference
UNION ALL SELECT 'prior_authorizations', COUNT(*) FROM prior_authorizations
UNION ALL SELECT 'claims', COUNT(*) FROM claims
UNION ALL SELECT 'claim_decision_flags', COUNT(*) FROM claim_decision_flags
UNION ALL SELECT 'decision_feedback', COUNT(*) FROM decision_feedback;

-- Overall decision split
SELECT * FROM v_decision_summary;

-- Proves HUMAN_REVIEW tracks confidence tier only, never auth status
SELECT * FROM v_confidence_tier_decision_summary;

-- Proves DENIED is always a prior-auth failure, never a confidence issue
SELECT * FROM v_denial_reason_breakdown;

SELECT * FROM v_payer_decision_summary;