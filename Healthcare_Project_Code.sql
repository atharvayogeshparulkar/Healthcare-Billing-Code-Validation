
-- Healthcare Billing Code Validation Database 



DROP DATABASE IF EXISTS healthcare_billing;
CREATE DATABASE healthcare_billing;
USE healthcare_billing;

-- ---------------------------------------------------------------------
-- 1. TABLES
-- ---------------------------------------------------------------------

CREATE TABLE diagnoses (
    icd10_code        VARCHAR(10) PRIMARY KEY,
    description        VARCHAR(255) NOT NULL,
    chapter            VARCHAR(150),
    category           VARCHAR(100),
    code_version_year  INT NOT NULL DEFAULT 2026
);


CREATE TABLE procedures (
    proc_code          VARCHAR(10) PRIMARY KEY,
    code_type          VARCHAR(20) NOT NULL,
    short_label         VARCHAR(255) NOT NULL,
    category           VARCHAR(100),
    code_version_year  INT NOT NULL DEFAULT 2026,
    CHECK (code_type IN ('CPT', 'HCPCS-II'))
);


CREATE TABLE code_pairings_reference (
    pairing_id          INT AUTO_INCREMENT PRIMARY KEY,
    diagnosis_category  VARCHAR(100) NOT NULL,
    proc_category        VARCHAR(100) NOT NULL,
    confidence_tier      VARCHAR(20) NOT NULL,
    source_note          VARCHAR(255),
    CHECK (confidence_tier IN ('HIGH', 'MEDIUM', 'REVIEW'))
);


CREATE TABLE claims (
    claim_id          INT AUTO_INCREMENT PRIMARY KEY,
    patient_id        VARCHAR(20) NOT NULL,
    payer             VARCHAR(100) NOT NULL,
    service_date      DATE NOT NULL,
    icd10_code        VARCHAR(10) NOT NULL,
    proc_code         VARCHAR(10) NOT NULL,
    billed_amount     DECIMAL(10,2) NOT NULL,
    claim_status      VARCHAR(20) NOT NULL,
    denial_reason     VARCHAR(255),
    CHECK (claim_status IN ('PAID', 'DENIED', 'PENDING')),
    FOREIGN KEY (icd10_code) REFERENCES diagnoses(icd10_code),
    FOREIGN KEY (proc_code) REFERENCES procedures(proc_code)
);


CREATE TABLE claim_flags (
    flag_id            INT AUTO_INCREMENT PRIMARY KEY,
    claim_id           INT NOT NULL,
    confidence_tier    VARCHAR(20) NOT NULL,
    flag_reason        VARCHAR(255),
    flagged_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    reviewer_decision  VARCHAR(20),
    reviewer_notes     VARCHAR(255),
    FOREIGN KEY (claim_id) REFERENCES claims(claim_id)
);


CREATE TABLE denial_feedback (
    feedback_id        INT AUTO_INCREMENT PRIMARY KEY,
    icd10_code         VARCHAR(10) NOT NULL,
    proc_code          VARCHAR(10) NOT NULL,
    times_submitted    INT NOT NULL DEFAULT 0,
    times_denied         INT NOT NULL DEFAULT 0,
    last_updated        DATE,
    FOREIGN KEY (icd10_code) REFERENCES diagnoses(icd10_code),
    FOREIGN KEY (proc_code) REFERENCES procedures(proc_code)
);

-- ---------------------------------------------------------------------
-- 2. DIAGNOSES (ICD-10-CM, public domain)
-- ---------------------------------------------------------------------
INSERT INTO diagnoses (icd10_code, description, chapter, category) VALUES
('E11.9', 'Type 2 diabetes mellitus without complications', 'Endocrine, nutritional and metabolic diseases', 'Diabetes'),
('E11.65', 'Type 2 diabetes mellitus with hyperglycemia', 'Endocrine, nutritional and metabolic diseases', 'Diabetes'),
('I10', 'Essential (primary) hypertension', 'Diseases of the circulatory system', 'Cardiovascular'),
('I25.10', 'Atherosclerotic heart disease of native coronary artery without angina pectoris', 'Diseases of the circulatory system', 'Cardiovascular'),
('J45.909', 'Unspecified asthma, uncomplicated', 'Diseases of the respiratory system', 'Respiratory'),
('J18.9', 'Pneumonia, unspecified organism', 'Diseases of the respiratory system', 'Respiratory'),
('S52.501A', 'Unspecified fracture of the lower end of right radius, initial encounter', 'Injury, poisoning and certain other consequences of external causes', 'Musculoskeletal'),
('M17.11', 'Unilateral primary osteoarthritis, right knee', 'Diseases of the musculoskeletal system and connective tissue', 'Musculoskeletal'),
('M54.50', 'Low back pain, unspecified', 'Diseases of the musculoskeletal system and connective tissue', 'Musculoskeletal'),
('F32.9', 'Major depressive disorder, single episode, unspecified', 'Mental, Behavioral and Neurodevelopmental disorders', 'BehavioralHealth'),
('F41.1', 'Generalized anxiety disorder', 'Mental, Behavioral and Neurodevelopmental disorders', 'BehavioralHealth'),
('O80', 'Encounter for full-term uncomplicated delivery', 'Pregnancy, childbirth and the puerperium', 'Obstetrics'),
('Z34.90', 'Encounter for supervision of normal pregnancy, unspecified trimester', 'Pregnancy, childbirth and the puerperium', 'Obstetrics'),
('N18.3', 'Chronic kidney disease, stage 3', 'Diseases of the genitourinary system', 'Renal'),
('N39.0', 'Urinary tract infection, site not specified', 'Diseases of the genitourinary system', 'Renal'),
('K21.9', 'Gastro-esophageal reflux disease without esophagitis', 'Diseases of the digestive system', 'GI'),
('K35.80', 'Unspecified acute appendicitis', 'Diseases of the digestive system', 'GI'),
('C50.919', 'Malignant neoplasm of unspecified site of unspecified female breast', 'Neoplasms', 'Oncology'),
('C34.90', 'Malignant neoplasm of unspecified part of unspecified bronchus or lung', 'Neoplasms', 'Oncology'),
('Z00.00', 'Encounter for general adult medical examination without abnormal findings', 'Factors influencing health status', 'Preventive'),
('Z23', 'Encounter for immunization', 'Factors influencing health status', 'Preventive'),
('H52.4', 'Presbyopia', 'Diseases of the eye and adnexa', 'Vision'),
('H35.30', 'Unspecified macular degeneration', 'Diseases of the eye and adnexa', 'Vision'),
('R07.9', 'Chest pain, unspecified', 'Symptoms, signs and abnormal clinical findings', 'Symptom'),
('R51.9', 'Headache, unspecified', 'Symptoms, signs and abnormal clinical findings', 'Symptom');

-- ---------------------------------------------------------------------
-- 3. PROCEDURES (CPT numeric codes + generic labels; HCPCS-II public domain)
-- ---------------------------------------------------------------------
INSERT INTO procedures (proc_code, code_type, short_label, category) VALUES
('99213', 'CPT', 'Office visit, established patient, low-moderate complexity', 'OfficeVisit'),
('99214', 'CPT', 'Office visit, established patient, moderate complexity', 'OfficeVisit'),
('99203', 'CPT', 'Office visit, new patient, low complexity', 'OfficeVisit'),
('99283', 'CPT', 'Emergency department visit, moderate severity', 'Emergency'),
('99284', 'CPT', 'Emergency department visit, high severity', 'Emergency'),
('80053', 'CPT', 'Comprehensive metabolic blood panel', 'Lab'),
('83036', 'CPT', 'Hemoglobin A1c blood test', 'Lab'),
('81002', 'CPT', 'Urinalysis, non-automated, without microscopy', 'Lab'),
('71046', 'CPT', 'Chest X-ray, 2 views', 'Imaging'),
('73721', 'CPT', 'MRI of lower extremity joint', 'Imaging'),
('74176', 'CPT', 'CT scan of abdomen and pelvis', 'Imaging'),
('93000', 'CPT', 'Electrocardiogram, routine, with interpretation', 'Cardiology'),
('93306', 'CPT', 'Echocardiogram, complete, with Doppler', 'Cardiology'),
('29881', 'CPT', 'Knee arthroscopy with meniscectomy', 'Surgery'),
('27447', 'CPT', 'Total knee replacement (arthroplasty)', 'Surgery'),
('25605', 'CPT', 'Closed treatment of distal radius fracture', 'Surgery'),
('59400', 'CPT', 'Routine obstetric care, vaginal delivery, antepartum/postpartum care', 'Obstetrics'),
('59510', 'CPT', 'Routine obstetric care, cesarean delivery, antepartum/postpartum care', 'Obstetrics'),
('90837', 'CPT', 'Psychotherapy, individual, 60 minutes', 'BehavioralHealth'),
('90791', 'CPT', 'Psychiatric diagnostic evaluation', 'BehavioralHealth'),
('44970', 'CPT', 'Laparoscopic appendectomy', 'Surgery'),
('45378', 'CPT', 'Diagnostic colonoscopy', 'GI'),
('77067', 'CPT', 'Screening mammography, bilateral', 'OncologyScreening'),
('96413', 'CPT', 'Chemotherapy infusion, initial hour, single drug', 'Oncology'),
('92014', 'CPT', 'Comprehensive eye exam, established patient', 'Vision'),
('92134', 'CPT', 'Optical coherence tomography, retina', 'Vision'),
('90471', 'CPT', 'Immunization administration, one vaccine', 'Preventive'),
('99395', 'CPT', 'Periodic preventive medicine exam, established patient', 'Preventive'),
('J1100', 'HCPCS-II', 'Injection, dexamethasone sodium phosphate, 1 mg', 'DrugInjection'),
('J0696', 'HCPCS-II', 'Injection, ceftriaxone sodium, per 250 mg', 'DrugInjection'),
('E0114', 'HCPCS-II', 'Crutches, underarm, other than wood, adjustable or fixed', 'DME'),
('E0143', 'HCPCS-II', 'Walker, folding, wheeled, adjustable or fixed height', 'DME'),
('A4253', 'HCPCS-II', 'Blood glucose test strips, per 50', 'DiabeticSupplies'),
('E0784', 'HCPCS-II', 'External ambulatory insulin infusion pump', 'DiabeticSupplies'),
('A0428', 'HCPCS-II', 'Ambulance service, basic life support, non-emergency', 'Ambulance'),
('L1832', 'HCPCS-II', 'Knee orthosis, adjustable knee joint, prefabricated', 'Orthotics');

-- ---------------------------------------------------------------------
-- 4. CODE PAIRING REFERENCE (synthetic medical-necessity logic)
-- ---------------------------------------------------------------------
INSERT INTO code_pairings_reference (diagnosis_category, proc_category, confidence_tier, source_note) VALUES
('Diabetes', 'Lab', 'HIGH', 'A1c/metabolic panels routinely justified by diabetes dx'),
('Diabetes', 'DiabeticSupplies', 'HIGH', 'Glucose monitoring supplies tied to diabetes mgmt'),
('Diabetes', 'OfficeVisit', 'HIGH', 'Routine diabetes management visits'),
('Cardiovascular', 'Cardiology', 'HIGH', 'EKG/echo standard workup for cardiovascular dx'),
('Cardiovascular', 'OfficeVisit', 'HIGH', 'Routine hypertension/CAD management'),
('Cardiovascular', 'Imaging', 'MEDIUM', 'CT/MRI sometimes justified, depends on presentation'),
('Respiratory', 'Imaging', 'HIGH', 'Chest X-ray standard for pneumonia/asthma workup'),
('Respiratory', 'OfficeVisit', 'HIGH', 'Routine respiratory management'),
('Musculoskeletal', 'Imaging', 'HIGH', 'MRI/X-ray standard for fracture/joint injury'),
('Musculoskeletal', 'Surgery', 'MEDIUM', 'Surgery justified only for qualifying severity'),
('Musculoskeletal', 'Orthotics', 'HIGH', 'Bracing/orthosis common post-injury'),
('Musculoskeletal', 'DME', 'MEDIUM', 'Mobility aids depend on severity/mobility limitation'),
('BehavioralHealth', 'BehavioralHealth', 'HIGH', 'Psychotherapy/psych eval matched to behavioral health dx'),
('Obstetrics', 'Obstetrics', 'HIGH', 'Delivery/antepartum codes matched to pregnancy dx'),
('Obstetrics', 'Imaging', 'MEDIUM', 'Ultrasound during pregnancy, context-dependent'),
('Renal', 'Lab', 'HIGH', 'Renal panels standard for CKD/UTI workup'),
('Renal', 'DrugInjection', 'MEDIUM', 'Antibiotic injection depends on UTI severity'),
('GI', 'GI', 'HIGH', 'Colonoscopy standard GI workup'),
('GI', 'Surgery', 'MEDIUM', 'Appendectomy justified only for acute appendicitis'),
('Oncology', 'Oncology', 'HIGH', 'Chemotherapy matched to malignant neoplasm dx'),
('Oncology', 'OncologyScreening', 'HIGH', 'Mammography standard breast cancer screening'),
('Preventive', 'Preventive', 'HIGH', 'Routine wellness visit/immunization matched to preventive dx'),
('Vision', 'Vision', 'HIGH', 'Eye exam/OCT matched to vision dx'),
('Symptom', 'Imaging', 'MEDIUM', 'Chest pain/headache workups vary widely by context'),
('Symptom', 'Emergency', 'MEDIUM', 'ED visit justified depending on acuity, needs review'),
('Symptom', 'Cardiology', 'REVIEW', 'EKG for chest pain often justified but payer scrutiny is high');

-- ---------------------------------------------------------------------
-- 5. CLAIMS (200 synthetic claim lines)
-- ---------------------------------------------------------------------
INSERT INTO claims (patient_id, payer, service_date, icd10_code, proc_code, billed_amount, claim_status, denial_reason) VALUES
('PT10001', 'Medicaid', '2025-05-23', 'E11.65', '99213', 497.79, 'PAID', NULL),
('PT10002', 'UnitedHealthcare', '2025-04-06', 'Z23', '90471', 1034.73, 'PAID', NULL),
('PT10003', 'Humana', '2025-10-12', 'R51.9', '99284', 3660.86, 'DENIED', 'Missing prior authorization for billed service'),
('PT10004', 'Humana', '2025-08-09', 'N39.0', '77067', 1463.45, 'PAID', NULL),
('PT10005', 'Blue Cross Blue Shield', '2025-05-08', 'Z34.90', '99284', 400.05, 'DENIED', 'Missing prior authorization for billed service'),
('PT10006', 'Aetna', '2025-10-24', 'R07.9', '99283', 3603.19, 'DENIED', 'Missing prior authorization for billed service'),
('PT10007', 'UnitedHealthcare', '2025-12-30', 'K35.80', '25605', 2839.47, 'DENIED', 'Missing prior authorization for billed service'),
('PT10008', 'Blue Cross Blue Shield', '2025-06-17', 'I10', '93000', 1640.25, 'PENDING', NULL),
('PT10009', 'Humana', '2025-08-23', 'C50.919', '96413', 207.41, 'PAID', NULL),
('PT10010', 'Blue Cross Blue Shield', '2026-05-27', 'M54.50', 'E0114', 3724.32, 'PAID', NULL),
('PT10011', 'Cigna', '2026-02-13', 'J45.909', '96413', 979.7, 'PENDING', NULL),
('PT10012', 'Humana', '2025-06-13', 'I10', '99213', 2881.99, 'PAID', NULL),
('PT10013', 'Medicaid', '2025-04-28', 'Z23', '90471', 3724.75, 'PAID', NULL),
('PT10014', 'Blue Cross Blue Shield', '2025-06-11', 'O80', '59510', 88.39, 'PAID', NULL),
('PT10015', 'Medicare', '2026-06-04', 'C50.919', '77067', 895.51, 'PAID', NULL),
('PT10016', 'Aetna', '2025-01-20', 'C50.919', '99395', 3907.53, 'PENDING', NULL),
('PT10017', 'Aetna', '2025-03-22', 'F32.9', '90837', 3094.12, 'PAID', NULL),
('PT10018', 'Cigna', '2025-06-19', 'C50.919', '77067', 2251.65, 'PAID', NULL),
('PT10019', 'Blue Cross Blue Shield', '2026-01-18', 'C50.919', '96413', 3785.91, 'PAID', NULL),
('PT10020', 'Medicare', '2025-08-24', 'I25.10', '99203', 983.4, 'PAID', NULL),
('PT10021', 'Medicare', '2025-03-14', 'S52.501A', '73721', 1056.77, 'PAID', NULL),
('PT10022', 'UnitedHealthcare', '2026-02-21', 'J18.9', '77067', 464.09, 'DENIED', 'Missing prior authorization for billed service'),
('PT10023', 'Medicaid', '2026-02-17', 'K21.9', '29881', 1474.62, 'DENIED', 'Missing prior authorization for billed service'),
('PT10024', 'UnitedHealthcare', '2026-03-09', 'M54.50', 'L1832', 1224.0, 'PAID', NULL),
('PT10025', 'Humana', '2025-04-06', 'K21.9', '29881', 3575.87, 'PAID', NULL),
('PT10026', 'Aetna', '2026-01-24', 'M17.11', '71046', 4139.4, 'PAID', NULL),
('PT10027', 'UnitedHealthcare', '2025-06-08', 'K35.80', '45378', 1298.92, 'PENDING', NULL),
('PT10028', 'Medicare', '2025-02-21', 'C50.919', '96413', 2041.75, 'DENIED', 'Missing prior authorization for billed service'),
('PT10029', 'Medicaid', '2025-03-11', 'E11.9', '99213', 3630.0, 'PAID', NULL),
('PT10030', 'Medicaid', '2026-03-06', 'Z00.00', '90471', 2482.65, 'PAID', NULL),
('PT10031', 'Blue Cross Blue Shield', '2025-09-29', 'M54.50', 'E0114', 614.87, 'PAID', NULL),
('PT10032', 'Aetna', '2025-04-13', 'I10', '74176', 2292.74, 'PAID', NULL),
('PT10033', 'UnitedHealthcare', '2025-10-19', 'O80', '77067', 1882.51, 'DENIED', 'Missing prior authorization for billed service'),
('PT10034', 'Cigna', '2025-05-18', 'H52.4', '92014', 551.14, 'PAID', NULL),
('PT10035', 'Medicaid', '2025-07-28', 'F41.1', '90791', 2691.23, 'PAID', NULL),
('PT10036', 'Aetna', '2025-10-11', 'E11.9', 'E0784', 89.63, 'PAID', NULL),
('PT10037', 'Aetna', '2025-01-10', 'F32.9', '90791', 385.38, 'DENIED', 'Missing prior authorization for billed service'),
('PT10038', 'UnitedHealthcare', '2026-03-17', 'C50.919', '96413', 247.54, 'PAID', NULL),
('PT10039', 'Medicaid', '2025-09-13', 'E11.65', '99203', 499.02, 'PAID', NULL),
('PT10040', 'Blue Cross Blue Shield', '2025-07-01', 'N18.3', '80053', 177.24, 'PAID', NULL),
('PT10041', 'Blue Cross Blue Shield', '2025-04-21', 'N18.3', 'J1100', 3672.69, 'DENIED', 'Missing prior authorization for billed service'),
('PT10042', 'Aetna', '2025-08-17', 'K35.80', '45378', 2797.64, 'PAID', NULL),
('PT10043', 'Blue Cross Blue Shield', '2026-06-06', 'I25.10', '74176', 2878.01, 'DENIED', 'Missing prior authorization for billed service'),
('PT10044', 'Aetna', '2025-09-29', 'E11.9', '80053', 522.16, 'PAID', NULL),
('PT10045', 'Cigna', '2025-07-14', 'Z34.90', '73721', 258.09, 'PAID', NULL),
('PT10046', 'Medicaid', '2025-03-13', 'C50.919', '96413', 3873.18, 'PAID', NULL),
('PT10047', 'Cigna', '2026-02-23', 'I25.10', '93306', 1734.9, 'PAID', NULL),
('PT10048', 'Medicare', '2026-02-20', 'N39.0', '59510', 3514.12, 'DENIED', 'Procedure not covered for submitted diagnosis code'),
('PT10049', 'Medicaid', '2026-03-29', 'Z23', '99395', 956.52, 'PAID', NULL),
('PT10050', 'Medicaid', '2026-06-12', 'R07.9', '99284', 2685.88, 'PAID', NULL);
INSERT INTO claims (patient_id, payer, service_date, icd10_code, proc_code, billed_amount, claim_status, denial_reason) VALUES
('PT10051', 'UnitedHealthcare', '2025-07-23', 'M54.50', 'E0114', 175.75, 'PAID', NULL),
('PT10052', 'Medicaid', '2025-07-19', 'I25.10', '74176', 2947.46, 'PAID', NULL),
('PT10053', 'UnitedHealthcare', '2025-08-13', 'H52.4', '92134', 3391.95, 'PAID', NULL),
('PT10054', 'Humana', '2025-05-17', 'C50.919', '77067', 1991.65, 'PAID', NULL),
('PT10055', 'Medicaid', '2025-06-12', 'Z34.90', '59510', 3628.67, 'PAID', NULL),
('PT10056', 'Blue Cross Blue Shield', '2025-10-09', 'H35.30', '92014', 394.62, 'PAID', NULL),
('PT10057', 'Blue Cross Blue Shield', '2025-08-25', 'O80', '71046', 2937.54, 'DENIED', 'Missing prior authorization for billed service'),
('PT10058', 'UnitedHealthcare', '2025-03-05', 'N39.0', 'A0428', 3510.68, 'DENIED', 'Diagnosis does not support medical necessity for procedure billed'),
('PT10059', 'Cigna', '2025-12-27', 'Z23', '90471', 3183.08, 'PAID', NULL),
('PT10060', 'Blue Cross Blue Shield', '2025-10-07', 'N18.3', 'J1100', 2078.27, 'PAID', NULL),
('PT10061', 'Blue Cross Blue Shield', '2025-01-28', 'N18.3', 'J1100', 2516.56, 'DENIED', 'Missing prior authorization for billed service'),
('PT10062', 'Cigna', '2025-02-21', 'N18.3', 'A0428', 1638.8, 'DENIED', 'Missing prior authorization for billed service'),
('PT10063', 'Blue Cross Blue Shield', '2025-03-25', 'N39.0', 'J0696', 154.96, 'PAID', NULL),
('PT10064', 'Humana', '2025-02-11', 'O80', '74176', 203.0, 'PAID', NULL),
('PT10065', 'Medicaid', '2026-04-30', 'Z00.00', '90471', 546.86, 'PENDING', NULL),
('PT10066', 'Cigna', '2025-06-17', 'F41.1', '90837', 520.91, 'PAID', NULL),
('PT10067', 'Medicare', '2025-03-19', 'H35.30', '92014', 2923.78, 'PAID', NULL),
('PT10068', 'Blue Cross Blue Shield', '2026-06-30', 'F32.9', '99284', 2803.78, 'PAID', NULL),
('PT10069', 'Cigna', '2026-03-20', 'E11.65', '80053', 2696.79, 'PAID', NULL),
('PT10070', 'Blue Cross Blue Shield', '2026-04-22', 'N18.3', 'J0696', 3481.16, 'PAID', NULL),
('PT10071', 'Humana', '2025-09-07', 'S52.501A', 'E0143', 1991.92, 'PAID', NULL),
('PT10072', 'UnitedHealthcare', '2026-05-15', 'E11.65', '80053', 1538.65, 'PAID', NULL),
('PT10073', 'UnitedHealthcare', '2025-03-29', 'Z23', '90471', 3045.31, 'PAID', NULL),
('PT10074', 'Aetna', '2025-01-18', 'R51.9', '73721', 1288.72, 'PAID', NULL),
('PT10075', 'Medicaid', '2026-03-12', 'H35.30', '92134', 2345.35, 'PAID', NULL),
('PT10076', 'Cigna', '2025-07-17', 'F41.1', '90837', 568.16, 'PAID', NULL),
('PT10077', 'Cigna', '2026-05-11', 'J45.909', '99203', 3063.91, 'PENDING', NULL),
('PT10078', 'Cigna', '2025-08-21', 'F32.9', '90791', 815.2, 'PAID', NULL),
('PT10079', 'Medicaid', '2025-05-10', 'F32.9', '90791', 3657.4, 'PAID', NULL),
('PT10080', 'Cigna', '2026-03-28', 'Z23', '99395', 835.5, 'PAID', NULL),
('PT10081', 'Aetna', '2026-05-19', 'K21.9', '44970', 2455.21, 'DENIED', 'Missing prior authorization for billed service'),
('PT10082', 'Medicare', '2025-05-02', 'Z23', '80053', 3228.33, 'DENIED', 'Procedure not covered for submitted diagnosis code'),
('PT10083', 'Cigna', '2026-03-16', 'N39.0', 'J0696', 2420.6, 'PAID', NULL),
('PT10084', 'Medicaid', '2025-09-28', 'I10', '93000', 409.9, 'PAID', NULL),
('PT10085', 'Cigna', '2026-04-27', 'J45.909', '73721', 209.64, 'PAID', NULL),
('PT10086', 'Blue Cross Blue Shield', '2025-07-22', 'K21.9', '25605', 548.45, 'PAID', NULL),
('PT10087', 'Humana', '2025-06-19', 'F32.9', '80053', 1343.9, 'DENIED', 'Missing prior authorization for billed service'),
('PT10088', 'Medicare', '2026-05-28', 'K35.80', '45378', 2111.91, 'PAID', NULL),
('PT10089', 'UnitedHealthcare', '2025-04-04', 'N39.0', '77067', 4042.88, 'DENIED', 'Diagnosis does not support medical necessity for procedure billed'),
('PT10090', 'Medicare', '2026-04-27', 'H35.30', '92014', 2762.48, 'DENIED', 'Missing prior authorization for billed service'),
('PT10091', 'Cigna', '2026-04-27', 'Z23', 'A0428', 1759.44, 'DENIED', 'Diagnosis does not support medical necessity for procedure billed'),
('PT10092', 'Humana', '2026-02-15', 'Z34.90', '59510', 3212.06, 'PAID', NULL),
('PT10093', 'Humana', '2026-06-11', 'F41.1', '73721', 4150.99, 'DENIED', 'Diagnosis-procedure combination flagged for manual review'),
('PT10094', 'Humana', '2026-03-29', 'M54.50', 'E0143', 287.9, 'PAID', NULL),
('PT10095', 'Medicaid', '2025-01-30', 'F41.1', 'A0428', 2586.6, 'DENIED', 'Procedure not covered for submitted diagnosis code'),
('PT10096', 'Blue Cross Blue Shield', '2025-04-27', 'E11.65', '99213', 3981.63, 'PAID', NULL),
('PT10097', 'Humana', '2026-03-02', 'R51.9', '92134', 2065.31, 'DENIED', 'Diagnosis-procedure combination flagged for manual review'),
('PT10098', 'Humana', '2025-10-10', 'N18.3', '80053', 3333.78, 'PAID', NULL),
('PT10099', 'Humana', '2025-11-02', 'C34.90', '77067', 2496.12, 'PENDING', NULL),
('PT10100', 'Medicare', '2025-12-07', 'J18.9', '73721', 3221.85, 'PAID', NULL);
INSERT INTO claims (patient_id, payer, service_date, icd10_code, proc_code, billed_amount, claim_status, denial_reason) VALUES
('PT10101', 'Humana', '2025-08-28', 'M54.50', '44970', 3274.12, 'PAID', NULL),
('PT10102', 'Blue Cross Blue Shield', '2025-06-05', 'R51.9', '74176', 4054.9, 'PAID', NULL),
('PT10103', 'Blue Cross Blue Shield', '2026-06-23', 'O80', '59400', 138.31, 'PAID', NULL),
('PT10104', 'Medicare', '2025-12-13', 'J45.909', '73721', 2932.41, 'PAID', NULL),
('PT10105', 'Medicare', '2025-02-06', 'H35.30', '92134', 357.24, 'PAID', NULL),
('PT10106', 'Humana', '2025-04-11', 'M54.50', '73721', 2689.21, 'PAID', NULL),
('PT10107', 'Humana', '2025-11-29', 'R51.9', '99283', 306.49, 'PAID', NULL),
('PT10108', 'UnitedHealthcare', '2025-06-24', 'M54.50', 'L1832', 400.74, 'PAID', NULL),
('PT10109', 'Medicaid', '2026-04-18', 'M17.11', '27447', 1122.66, 'PAID', NULL),
('PT10110', 'Cigna', '2026-03-29', 'K35.80', '59400', 4149.06, 'DENIED', 'Diagnosis-procedure combination flagged for manual review'),
('PT10111', 'Aetna', '2026-05-10', 'K35.80', '44970', 1053.47, 'PAID', NULL),
('PT10112', 'Aetna', '2025-10-09', 'R51.9', '99284', 2409.46, 'DENIED', 'Missing prior authorization for billed service'),
('PT10113', 'UnitedHealthcare', '2025-12-27', 'E11.65', '80053', 2701.05, 'PAID', NULL),
('PT10114', 'Humana', '2025-11-13', 'R07.9', '99283', 1893.4, 'PAID', NULL),
('PT10115', 'UnitedHealthcare', '2026-03-02', 'I25.10', '74176', 903.28, 'DENIED', 'Missing prior authorization for billed service'),
('PT10116', 'Humana', '2026-05-09', 'Z34.90', '73721', 1292.46, 'PENDING', NULL),
('PT10117', 'Humana', '2026-02-11', 'K21.9', '27447', 3393.92, 'PAID', NULL),
('PT10118', 'Cigna', '2026-04-11', 'E11.65', 'A4253', 2850.42, 'PAID', NULL),
('PT10119', 'Aetna', '2026-04-28', 'H35.30', '92014', 2630.63, 'PENDING', NULL),
('PT10120', 'Medicaid', '2025-11-06', 'Z00.00', '99395', 1759.22, 'PAID', NULL),
('PT10121', 'Medicare', '2025-08-29', 'F41.1', '90837', 634.61, 'PAID', NULL),
('PT10122', 'Humana', '2025-04-12', 'R51.9', '99284', 2093.56, 'PAID', NULL),
('PT10123', 'UnitedHealthcare', '2026-04-01', 'E11.65', '99214', 3603.73, 'PAID', NULL),
('PT10124', 'UnitedHealthcare', '2025-10-10', 'C34.90', '77067', 4068.85, 'PENDING', NULL),
('PT10125', 'Humana', '2025-02-21', 'I10', '93000', 1450.73, 'PENDING', NULL),
('PT10126', 'Cigna', '2025-08-27', 'S52.501A', '27447', 3269.27, 'DENIED', 'Missing prior authorization for billed service'),
('PT10127', 'Aetna', '2025-06-28', 'F32.9', '90791', 2801.86, 'PAID', NULL),
('PT10128', 'Cigna', '2025-06-28', 'M54.50', '90837', 291.15, 'DENIED', 'Diagnosis does not support medical necessity for procedure billed'),
('PT10129', 'Medicare', '2026-04-08', 'K35.80', '45378', 988.89, 'PAID', NULL),
('PT10130', 'Blue Cross Blue Shield', '2025-03-04', 'H35.30', '92014', 3570.11, 'PAID', NULL),
('PT10131', 'Medicare', '2025-11-26', 'R51.9', '80053', 686.88, 'PAID', NULL),
('PT10132', 'Medicare', '2026-04-10', 'Z23', '99395', 2572.39, 'PAID', NULL),
('PT10133', 'Blue Cross Blue Shield', '2025-08-22', 'H52.4', '92134', 1473.09, 'PAID', NULL),
('PT10134', 'Cigna', '2025-09-19', 'I25.10', '73721', 4008.57, 'DENIED', 'Missing prior authorization for billed service'),
('PT10135', 'Medicaid', '2025-04-09', 'I10', '99214', 3122.53, 'PAID', NULL),
('PT10136', 'Humana', '2025-12-29', 'Z23', '99395', 2819.53, 'PAID', NULL),
('PT10137', 'Cigna', '2025-11-16', 'R07.9', '74176', 502.35, 'PAID', NULL),
('PT10138', 'Aetna', '2026-01-12', 'K21.9', '73721', 3220.75, 'DENIED', 'Diagnosis-procedure combination flagged for manual review'),
('PT10139', 'Cigna', '2025-07-04', 'Z00.00', '90471', 2973.63, 'PAID', NULL),
('PT10140', 'Aetna', '2026-02-15', 'E11.9', '99203', 660.23, 'PAID', NULL),
('PT10141', 'Cigna', '2026-04-10', 'R07.9', '77067', 724.31, 'DENIED', 'Missing prior authorization for billed service'),
('PT10142', 'Humana', '2025-06-11', 'Z00.00', '90471', 2623.58, 'PAID', NULL),
('PT10143', 'Cigna', '2026-03-01', 'H35.30', '92134', 964.22, 'PAID', NULL),
('PT10144', 'Medicaid', '2026-06-24', 'I25.10', '93306', 1347.23, 'PAID', NULL),
('PT10145', 'Humana', '2025-08-05', 'E11.9', '99214', 641.09, 'PAID', NULL),
('PT10146', 'UnitedHealthcare', '2025-06-29', 'E11.65', 'E0784', 1643.36, 'PAID', NULL),
('PT10147', 'Blue Cross Blue Shield', '2025-02-13', 'H35.30', '92134', 152.31, 'DENIED', 'Missing prior authorization for billed service'),
('PT10148', 'Aetna', '2025-10-24', 'Z23', '99395', 1745.76, 'PENDING', NULL),
('PT10149', 'Humana', '2026-03-24', 'Z23', '92014', 511.69, 'DENIED', 'Diagnosis-procedure combination flagged for manual review'),
('PT10150', 'Humana', '2025-12-08', 'N39.0', 'J1100', 768.55, 'PAID', NULL);
INSERT INTO claims (patient_id, payer, service_date, icd10_code, proc_code, billed_amount, claim_status, denial_reason) VALUES
('PT10151', 'UnitedHealthcare', '2025-06-01', 'C50.919', 'J0696', 499.07, 'DENIED', 'Procedure not covered for submitted diagnosis code'),
('PT10152', 'Humana', '2026-04-21', 'H52.4', '92134', 2400.41, 'PAID', NULL),
('PT10153', 'Aetna', '2026-03-27', 'Z23', '90471', 2009.3, 'PAID', NULL),
('PT10154', 'Blue Cross Blue Shield', '2025-11-14', 'Z00.00', '90471', 1939.14, 'PAID', NULL),
('PT10155', 'Medicare', '2026-04-19', 'I10', '93306', 2361.56, 'PAID', NULL),
('PT10156', 'UnitedHealthcare', '2026-05-29', 'K21.9', '45378', 4025.6, 'PAID', NULL),
('PT10157', 'Medicaid', '2025-09-11', 'O80', '71046', 1880.75, 'PAID', NULL),
('PT10158', 'Blue Cross Blue Shield', '2026-02-01', 'J18.9', '73721', 3269.67, 'PAID', NULL),
('PT10159', 'Medicare', '2025-04-07', 'H35.30', '83036', 2873.31, 'DENIED', 'Procedure not covered for submitted diagnosis code'),
('PT10160', 'UnitedHealthcare', '2026-02-06', 'Z00.00', '99395', 2529.55, 'PENDING', NULL),
('PT10161', 'Aetna', '2026-06-24', 'N39.0', '81002', 2739.85, 'PAID', NULL),
('PT10162', 'Humana', '2025-12-16', 'Z34.90', '71046', 2080.87, 'PAID', NULL),
('PT10163', 'Humana', '2026-06-04', 'I25.10', 'A0428', 2301.55, 'DENIED', 'Diagnosis does not support medical necessity for procedure billed'),
('PT10164', 'UnitedHealthcare', '2025-06-16', 'Z00.00', '90471', 3504.3, 'PAID', NULL),
('PT10165', 'Medicaid', '2026-01-09', 'J18.9', '99214', 3043.29, 'PENDING', NULL),
('PT10166', 'Humana', '2025-11-13', 'R51.9', '99283', 3310.53, 'PENDING', NULL),
('PT10167', 'Medicare', '2026-01-27', 'H35.30', 'E0784', 2250.77, 'PENDING', NULL),
('PT10168', 'Humana', '2026-05-08', 'Z00.00', '90471', 1606.25, 'PENDING', NULL),
('PT10169', 'Cigna', '2025-06-14', 'C50.919', '96413', 1928.44, 'PAID', NULL),
('PT10170', 'Blue Cross Blue Shield', '2025-01-28', 'I10', '73721', 294.68, 'PAID', NULL),
('PT10171', 'Aetna', '2025-11-23', 'I25.10', '99213', 3536.6, 'PAID', NULL),
('PT10172', 'Humana', '2025-05-23', 'J45.909', '73721', 2985.34, 'PAID', NULL),
('PT10173', 'Medicare', '2025-06-03', 'I10', '90837', 3953.43, 'DENIED', 'Diagnosis-procedure combination flagged for manual review'),
('PT10174', 'UnitedHealthcare', '2025-02-18', 'F32.9', '96413', 1806.78, 'DENIED', 'Diagnosis-procedure combination flagged for manual review'),
('PT10175', 'Blue Cross Blue Shield', '2025-10-26', 'K21.9', '77067', 81.45, 'DENIED', 'Diagnosis-procedure combination flagged for manual review'),
('PT10176', 'Medicare', '2025-03-11', 'H52.4', 'L1832', 2319.34, 'DENIED', 'Diagnosis does not support medical necessity for procedure billed'),
('PT10177', 'Medicaid', '2025-09-17', 'K21.9', '45378', 142.0, 'PAID', NULL),
('PT10178', 'Cigna', '2025-02-15', 'R07.9', '71046', 2327.31, 'DENIED', 'Missing prior authorization for billed service'),
('PT10179', 'Aetna', '2025-05-19', 'H35.30', 'A0428', 3028.69, 'PENDING', NULL),
('PT10180', 'Cigna', '2025-02-12', 'S52.501A', 'A4253', 3925.16, 'DENIED', 'Diagnosis-procedure combination flagged for manual review'),
('PT10181', 'Humana', '2025-02-18', 'H52.4', '92134', 2779.89, 'PAID', NULL),
('PT10182', 'UnitedHealthcare', '2025-12-14', 'N39.0', 'J0696', 2121.84, 'PAID', NULL),
('PT10183', 'Blue Cross Blue Shield', '2025-03-22', 'C34.90', '77067', 2560.12, 'PAID', NULL),
('PT10184', 'Cigna', '2025-10-30', 'O80', '73721', 1914.4, 'DENIED', 'Missing prior authorization for billed service'),
('PT10185', 'Medicare', '2025-12-28', 'K35.80', 'A0428', 4192.37, 'DENIED', 'Diagnosis does not support medical necessity for procedure billed'),
('PT10186', 'UnitedHealthcare', '2025-02-01', 'H35.30', '90471', 3575.76, 'DENIED', 'Diagnosis-procedure combination flagged for manual review'),
('PT10187', 'Blue Cross Blue Shield', '2026-01-06', 'I10', 'E0784', 3991.55, 'PAID', NULL),
('PT10188', 'Medicare', '2025-03-20', 'K35.80', 'J0696', 642.99, 'DENIED', 'Missing prior authorization for billed service'),
('PT10189', 'Blue Cross Blue Shield', '2025-07-10', 'S52.501A', '74176', 2210.7, 'DENIED', 'Missing prior authorization for billed service'),
('PT10190', 'UnitedHealthcare', '2026-05-18', 'F41.1', '59510', 580.88, 'PENDING', NULL),
('PT10191', 'Medicaid', '2025-12-22', 'R51.9', '99284', 342.87, 'PAID', NULL),
('PT10192', 'Aetna', '2025-08-18', 'J45.909', '74176', 4138.67, 'PAID', NULL),
('PT10193', 'Humana', '2026-04-24', 'K21.9', '45378', 4129.92, 'PAID', NULL),
('PT10194', 'Medicare', '2026-05-06', 'I25.10', '74176', 1769.53, 'PAID', NULL),
('PT10195', 'Medicaid', '2026-04-23', 'J18.9', '99214', 2209.11, 'PAID', NULL),
('PT10196', 'Humana', '2026-05-30', 'C50.919', '77067', 303.58, 'PAID', NULL),
('PT10197', 'Medicare', '2025-12-21', 'J45.909', '90471', 3766.57, 'DENIED', 'Missing prior authorization for billed service'),
('PT10198', 'Medicare', '2025-04-06', 'C34.90', '93306', 2719.07, 'DENIED', 'Procedure not covered for submitted diagnosis code'),
('PT10199', 'Aetna', '2025-03-25', 'Z23', '99283', 3987.76, 'DENIED', 'Missing prior authorization for billed service'),
('PT10200', 'Medicaid', '2025-10-24', 'Z23', '99395', 4021.18, 'PAID', NULL);

-- ---------------------------------------------------------------------
-- 6. VALIDATION VIEWS
-- ---------------------------------------------------------------------

-- Every claim joined to its diagnosis/procedure category, with a
-- confidence tier resolved from the reference table (NO_MATCH if none found)
CREATE OR REPLACE VIEW v_claim_validation AS
SELECT
    c.claim_id, c.patient_id, c.payer, c.service_date,
    c.icd10_code, d.description AS diagnosis_desc, d.category AS diagnosis_category,
    c.proc_code, p.short_label AS procedure_label, p.category AS procedure_category,
    c.billed_amount, c.claim_status, c.denial_reason,
    COALESCE(cpr.confidence_tier, 'NO_MATCH') AS confidence_tier
FROM claims c
JOIN diagnoses d  ON c.icd10_code = d.icd10_code
JOIN procedures p ON c.proc_code  = p.proc_code
LEFT JOIN code_pairings_reference cpr
    ON cpr.diagnosis_category = d.category AND cpr.proc_category = p.category;

-- Denial rate rolled up by confidence tier (your headline "impact" numbers)
CREATE OR REPLACE VIEW v_denial_risk_summary AS
SELECT
    confidence_tier,
    COUNT(*) AS total_claims,
    SUM(claim_status = 'DENIED') AS denied_claims,
    ROUND(100.0 * SUM(claim_status = 'DENIED') / COUNT(*), 1) AS denial_rate_pct,
    ROUND(SUM(billed_amount), 2) AS total_billed,
    ROUND(SUM(CASE WHEN claim_status = 'DENIED' THEN billed_amount ELSE 0 END), 2) AS denied_amount
FROM v_claim_validation
GROUP BY confidence_tier;

-- Which specific diagnosis/procedure pairs deny the most (drill-down table)
CREATE OR REPLACE VIEW v_top_risky_pairings AS
SELECT
    icd10_code, diagnosis_desc, proc_code, procedure_label, confidence_tier,
    COUNT(*) AS submitted_count,
    SUM(claim_status = 'DENIED') AS denied_count,
    ROUND(100.0 * SUM(claim_status = 'DENIED') / COUNT(*), 1) AS denial_rate_pct
FROM v_claim_validation
GROUP BY icd10_code, diagnosis_desc, proc_code, procedure_label, confidence_tier
HAVING COUNT(*) >= 2
ORDER BY denial_rate_pct DESC, submitted_count DESC;

-- Denial rate by payer (which insurance companies deny more of your billing)
CREATE OR REPLACE VIEW v_payer_denial_summary AS
SELECT
    payer,
    COUNT(*) AS total_claims,
    SUM(claim_status = 'DENIED') AS denied_claims,
    ROUND(100.0 * SUM(claim_status = 'DENIED') / COUNT(*), 1) AS denial_rate_pct
FROM claims
GROUP BY payer
ORDER BY denial_rate_pct DESC;

-- ---------------------------------------------------------------------
-- 7. POPULATE claim_flags (the audit trail / risk-handling table)
--    Every claim that is NOT a clean HIGH-confidence match gets flagged.
--    reviewer_decision simulates what actually happened to that claim:
--    APPROVED (it got paid despite the flag), OVERRIDDEN (a coder let
--    it through and it got denied -- the risk that was realized), or
--    PENDING_REVIEW (still awaiting outcome).
-- ---------------------------------------------------------------------
INSERT INTO claim_flags (claim_id, confidence_tier, flag_reason, reviewer_decision)
SELECT
    claim_id,
    confidence_tier,
    CASE
        WHEN confidence_tier = 'NO_MATCH' THEN 'No reference pairing found between diagnosis category and procedure category'
        WHEN confidence_tier = 'REVIEW'   THEN 'Pairing exists but payer scrutiny historically high -- recommend manual review'
        WHEN confidence_tier = 'MEDIUM'   THEN 'Pairing plausible but not automatically approved -- context-dependent'
    END AS flag_reason,
    CASE
        WHEN claim_status = 'PAID'    THEN 'APPROVED'
        WHEN claim_status = 'DENIED'  THEN 'OVERRIDDEN'
        ELSE 'PENDING_REVIEW'
    END AS reviewer_decision
FROM v_claim_validation
WHERE confidence_tier != 'HIGH';

-- ---------------------------------------------------------------------
-- 8. POPULATE denial_feedback (the feedback-loop table --
--    aggregates real outcomes per diagnosis/procedure pair so the
--    reference logic can be improved over time)
-- ---------------------------------------------------------------------
INSERT INTO denial_feedback (icd10_code, proc_code, times_submitted, times_denied, last_updated)
SELECT
    icd10_code,
    proc_code,
    COUNT(*) AS times_submitted,
    SUM(claim_status = 'DENIED') AS times_denied,
    MAX(service_date) AS last_updated
FROM claims
GROUP BY icd10_code, proc_code;

-- ---------------------------------------------------------------------
-- 9. SANITY CHECKS -- run these after the script finishes to confirm
--    everything loaded and the risk gradient shows up as expected
-- ---------------------------------------------------------------------
SELECT 'diagnoses' AS tbl, COUNT(*) AS row_count FROM diagnoses
UNION ALL SELECT 'procedures', COUNT(*) FROM procedures
UNION ALL SELECT 'code_pairings_reference', COUNT(*) FROM code_pairings_reference
UNION ALL SELECT 'claims', COUNT(*) FROM claims
UNION ALL SELECT 'claim_flags', COUNT(*) FROM claim_flags
UNION ALL SELECT 'denial_feedback', COUNT(*) FROM denial_feedback;

-- This is the number you want to see trending up: NO_MATCH should have
-- a clearly higher denial_rate_pct than HIGH.
SELECT * FROM v_denial_risk_summary ORDER BY denial_rate_pct DESC;

SELECT * FROM v_payer_denial_summary;

SELECT * FROM v_top_risky_pairings LIMIT 15;