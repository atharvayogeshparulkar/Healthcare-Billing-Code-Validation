Healthcare Billing Code Validation & Denial-Risk Analytics

A SQL database and Excel dashboard project that validates whether ICD-10 diagnosis codes and CPT/HCPCS procedure codes on a medical claim form a clinically justifiable pairing, flags likely-to-deny claims before submission using a confidence-tier system, and visualizes denial risk by code, category, and payer.

Core result: claims tagged HIGH confidence denied at ~4.6%; claims with no valid diagnosis-procedure relationship found (NO_MATCH) denied at ~78%. That gradient is the evidence the validation logic works.

Table of Contents
Problem Statement
Solution
Impact
Risk Management
Tech Stack
Repository Contents
How to Run This
Limitations
Problem Statement

Every medical claim submitted to an insurance payer requires two linked pieces of information: a diagnosis code (ICD-10-CM) explaining why the patient was seen, and a procedure/service code (CPT or HCPCS Level II) explaining what was done. Payers evaluate "medical necessity" by checking whether the billed procedure is clinically justified by the stated diagnosis.

In practice, this diagnosis-to-procedure linkage is validated manually or with limited automation in many billing workflows. That gap creates three recurring problems:

Claim denials and payment delays caused by diagnosis/procedure mismatches that are only caught after submission, not before.
No centralized, queryable reference that billing staff or analysts can use to check whether a code pairing is likely to be reimbursed.
No systematic way to flag high-risk pairings before they go out the door, so errors are found reactively rather than proactively, driving rework, delayed cash flow, and administrative cost.

This project builds a relational database and validation layer that addresses that gap directly, using publicly available code sets and a synthetic claims dataset that mirrors real-world billing patterns.

Solution
Database Design

A relational database (MySQL) with six core tables that separate reference data from transactional data from audit output:

Table	Purpose
diagnoses	ICD-10-CM codes, descriptions, and clinical category grouping (25 sample codes across 12 clinical domains)
procedures	CPT and HCPCS-II codes with generic labels and service category (36 sample codes)
code_pairings_reference	Medical-necessity logic: which procedure categories are typically justified by which diagnosis categories, tagged with a confidence tier
claims	Claim-line data: patient, payer, service date, diagnosis code, procedure code, billed amount, status, denial reason (200 sample claims)
claim_flags	Audit trail of validation output: which claims were flagged, at what confidence tier, and how a reviewer resolved the flag
denial_feedback	Aggregated real-world outcomes per diagnosis/procedure pair; the feedback loop described below
Validation Logic

Every claim is evaluated by joining its diagnosis category to its procedure category against the reference table. Instead of a binary valid/invalid outcome, each pairing resolves to one of four confidence tiers, the same triage approach real revenue-cycle-management systems use rather than auto-rejecting everything uncertain:

HIGH — well-established, routinely reimbursed pairing (e.g. diabetes diagnosis + A1c lab test)
MEDIUM — plausible pairing that depends on clinical context and is not automatically approved (e.g. cardiovascular diagnosis + CT imaging)
REVIEW — pairing exists but has historically drawn high payer scrutiny (e.g. chest pain + EKG in the ED)
NO_MATCH — no reference relationship found between the diagnosis and procedure category; highest denial risk

This logic lives in SQL views so it can be queried directly or fed into a BI tool, rather than being recomputed ad hoc every time someone needs an answer.

Dashboard

An Excel workbook presents the validation output: KPI cards for total claims, overall denial rate, and dollars at risk; a denial-rate-by-confidence-tier chart; a denial-rate-by-payer chart; and drill-down tables. KPI cards use live spreadsheet formulas against the raw claims data rather than hardcoded numbers, so the dashboard recalculates if the underlying data changes.

Impact
Confidence Tier	Claims	Denial Rate	Dollars Billed	Dollars Denied
HIGH	109	4.6%	$225,064	$7,553
MEDIUM	50	30.0%	$101,157	$40,870
NO_MATCH	41	78.0%	$95,823	$76,129
Separated claims into risk tiers spanning a 4.6% to 78% denial-rate range, showing the model successfully isolates high-risk billing pairs before submission.
NO_MATCH pairings, roughly 21% of claim volume, accounted for over 39% of all denied dollars in the sample — the highest-leverage segment for pre-submission review.
Denial rate by payer ranged from 7.4% to 42.3% across 7 simulated payers, helping prioritize which payer relationships need the most billing-process attention.

In a production setting, flagging NO_MATCH and REVIEW-tier claims before submission, rather than after denial, is the mechanism that converts this analysis into reduced rework, faster reimbursement, and lower administrative cost per claim.

Risk Management

Diagnosis-procedure validation can never be a fully solved, static problem: code sets update annually, payer-specific medical necessity rules vary and change, and no reference table can anticipate every legitimate clinical edge case. Rather than treating a rules table as sufficient on its own, the project manages residual risk through five mechanisms:

Confidence tiers instead of binary pass/fail — uncertain pairings (MEDIUM/REVIEW) route to a human reviewer instead of being auto-approved or auto-rejected.
Versioning — every diagnosis/procedure record carries a code_version_year field, since ICD-10-CM, CPT, and HCPCS all release annual updates.
Audit trail — the claim_flags table logs every flag raised and how it was resolved (approved, overridden, pending review).
Feedback loop — the denial_feedback table aggregates real submission/denial outcomes per code pair over time, so reference logic can be improved from actual results.
Escalation, not elimination — the goal is to shrink the pool of claims needing manual review to the smallest, highest-risk subset, not remove human review entirely.
Tech Stack

Database Layer

MySQL (MySQL Workbench) — 6 normalized tables, PK/FK constraints, CHECK constraints for valid code_type/claim_status/confidence_tier values
SQL Views — 4 views (v_claim_validation, v_denial_risk_summary, v_top_risky_pairings, v_payer_denial_summary) encapsulating the validation logic

SQL Techniques

Multi-table joins (INNER JOIN, LEFT JOIN)
COALESCE() for defaulting unmatched pairings to NO_MATCH
INSERT ... SELECT to populate audit/feedback tables directly from view output
Conditional aggregation (SUM(condition), CASE WHEN) inside GROUP BY queries
ROUND(), GROUP BY, HAVING for summary/drill-down views

Data Sources

Code Set	Source	License
ICD-10-CM (diagnoses)	CDC/NCHS	Public domain
HCPCS Level II (procedures)	CMS	Public domain
CPT (procedures)	AMA	Copyrighted — numeric codes + generic labels only, not official descriptor text

Analytics/BI Layer

Excel — dashboard with KPI cards driven by live formulas (COUNTIF, COUNTIFS, SUMIF), not hardcoded numbers
Excel Charts — denial rate by confidence tier, denial rate by payer
CSV exports — structured for direct import into Power BI if a more interactive front end is needed later

Supporting Tools

MySQL Workbench — schema design, script execution, data import
Python — used only in the build phase to generate 200 synthetic claim records with realistic mismatch/denial probability logic
Repository Contents
├── full_project.sql                                  # Complete MySQL schema + sample data + views (run this end-to-end)
├── Healthcare_Billing_Dashboard_2Sheet.xlsx           # Excel dashboard (Dataset sheet + Dashboard sheet, live formulas)
├── Healthcare_Billing_Case_Study.docx                 # Full write-up: problem, solution, impact, risk management
├── Healthcare_Billing_Project_Tech_Stack_Summary.docx # Tech-stack-focused summary
└── README.md
How to Run This
Open MySQL Workbench, connect to your local server
File → Open SQL Script → select full_project.sql
Execute All (lightning bolt icon) — this drops/recreates a healthcare_billing database, builds all 6 tables, loads sample data, creates the 4 validation views, and runs sanity-check queries automatically
Confirm the denial-rate gradient shows up as expected: SELECT * FROM v_denial_risk_summary; should show NO_MATCH with a clearly higher denial rate than HIGH
For the dashboard: open Healthcare_Billing_Dashboard_2Sheet.xlsx in Excel. The Dataset sheet holds the flat claim-level data; the Dashboard sheet's KPIs and charts are all live formulas referencing it — edit a row in Dataset and watch the Dashboard update

Note: MySQL only enforces CHECK constraints from version 8.0.16 onward. Run SELECT VERSION(); first if constraints seem to be ignored.

Limitations
The code_pairings_reference logic is illustrative/synthetic — built to demonstrate the validation approach, not sourced from a specific payer's actual LCD/NCD medical-necessity policy documents. A production system would need to ingest real payer coverage policies.
CPT code descriptions are shown only as short generic labels, not the AMA's official descriptor text, due to CPT licensing restrictions.
The claims dataset (200 rows) is synthetically generated to demonstrate the risk-tiering pattern; it is not real patient or billing data.
