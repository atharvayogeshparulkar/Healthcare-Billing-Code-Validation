# ICD-10 to CPT/HCPCS Crosswalk

A simple SQL database and Excel dashboard project that checks whether a diagnosis code (ICD-10) and a procedure code (CPT/HCPCS) on a medical claim form a recognized, billable pairing — and lets that confidence grade alone decide the outcome.

**Core result:** each crosswalk confidence tier maps to exactly one decision. HIGH is always APPROVED, MEDIUM is always HUMAN_REVIEW, LOW or unmatched is always DENIED. No overlap, no exceptions.

---

## Table of Contents
- [Problem Statement](#problem-statement)
- [Solution](#solution)
- [Impact](#impact)
- [Risk Management](#risk-management)
- [Tech Stack](#tech-stack)
- [Repository Contents](#repository-contents)
- [How to Run This](#how-to-run-this)
- [Limitations](#limitations)

---

## Problem Statement

Billing teams need a quick way to check whether a diagnosis-procedure pairing on a claim is actually recognized before the claim goes out the door. Without a centralized reference, that check is either skipped, done manually, or discovered only after a denial comes back — all of which cost time and money that a simple lookup could avoid.

This project builds a small, clear database that answers one question directly: how confident are we that this pairing is legitimate, and what should happen to the claim as a result?

## Solution

### Database Design
A relational database (MySQL) with four core tables:

| Table | Purpose |
|---|---|
| `diagnoses` | ICD-10-CM codes, descriptions, and category (12 sample codes) |
| `procedures` | CPT and HCPCS-II codes with generic labels and category (15 sample codes) |
| `crosswalk` | Which specific diagnosis-procedure pairs are recognized, graded HIGH/MEDIUM/LOW confidence (25 sample pairings) |
| `claims` | Claim-line data: patient, payer, service date, diagnosis code, procedure code, billed amount (150 sample claims) |

### Validation Logic
Every claim is evaluated with a single `LEFT JOIN` from `claims` to `crosswalk`, so an unrecognized pairing surfaces as `NULL` rather than disappearing from results, then `COALESCE()` labels it `NO_MATCH`. One `CASE` statement maps the resulting tier directly to a decision:

- **APPROVED** — crosswalk confidence is HIGH
- **HUMAN_REVIEW** — crosswalk confidence is MEDIUM
- **DENIED** — crosswalk confidence is LOW, or no crosswalk entry exists at all

This logic lives in one SQL view, `v_claims`, so it can be queried directly or fed into a BI tool.

### Dashboard
An Excel workbook with three tabs: a ReadMe tab with the project overview, a Dataset tab with all 150 claims joined and labeled, and a Dashboard tab with KPI cards and a decision-by-confidence-tier chart. KPI cards use live spreadsheet formulas against the raw claims data rather than hardcoded numbers.

## Impact

| Decision | Claims | Driven By |
|---|---|---|
| APPROVED | 75 | HIGH-confidence crosswalk pairing |
| HUMAN_REVIEW | 18 | MEDIUM-confidence crosswalk pairing |
| DENIED | 57 | LOW-confidence or unrecognized pairing |

- Every claim's decision is fully explained by a single factor: its crosswalk confidence tier. There's no second variable muddying the result.
- Unrecognized pairings (NO_MATCH), 34 of the 57 denials, are the single largest driver of denied claims in the sample — the clearest signal of where the crosswalk itself needs to be expanded.
- That one-to-one mapping is verifiable directly in SQL: `SELECT crosswalk_confidence, claim_decision, COUNT(*) FROM v_claims GROUP BY crosswalk_confidence, claim_decision;`

In a production setting, a DENIED claim always points a coder straight to the crosswalk table — either the pairing needs to be added, or it genuinely isn't billable — with no other explanation to rule out first.

## Risk Management

Diagnosis-procedure recognition can never be a fully solved, static problem — new or rare combinations will always exist that the crosswalk hasn't graded yet. This project manages that risk with one deliberate choice:

1. **Safe default for unknowns** — a pairing with no crosswalk entry at all defaults to `NO_MATCH`, which resolves to DENIED rather than being silently approved. An unrecognized pairing never sneaks through as a false positive.

This version intentionally does not include an audit-trail table or a feedback loop to recalibrate confidence grades from real outcomes over time — that would be the natural next addition if this were extended toward production use. For a portfolio-scale project, keeping the schema to four tables and one view was a deliberate trade-off: easier to read and verify end to end, at the cost of that recalibration capability.

## Tech Stack

**Database Layer**
- MySQL (MySQL Workbench) — 4 tables, one composite primary key (`icd10_code`, `proc_code`) on `crosswalk`
- SQL Views — 1 view (`v_claims`) doing the entire join and decision computation

**SQL Techniques**
- `LEFT JOIN` from claims to the crosswalk table, so unmatched pairings surface instead of disappearing
- `COALESCE()` to label unmatched pairings `NO_MATCH`
- A single `CASE` statement mapping each confidence tier directly to one decision, with no secondary condition to check

**Data Sources**
| Code Set | Source | License |
|---|---|---|
| ICD-10-CM (diagnoses) | CDC/NCHS | Public domain |
| HCPCS Level II (procedures) | CMS | Public domain |
| CPT (procedures) | AMA | Copyrighted — numeric codes + generic labels only, not official descriptor text |

**Analytics/BI Layer**
- Excel — three-tab workbook (ReadMe, Dataset, Dashboard); KPI cards driven by live formulas (`COUNTIF`, `COUNTIFS`), not hardcoded numbers
- Excel Charts — decision outcome by crosswalk confidence tier

**Supporting Tools**
- Python — used only in the build phase to generate 150 synthetic claims with a realistic mix of matched and unmatched pairings
- SQLite — used only in the validation phase to independently confirm the view's output before delivery

## Repository Contents

```
├── crosswalk_project.sql              # Complete MySQL schema + sample data + view (run this end-to-end)
├── crosswalk_dashboard.xlsx           # Excel dashboard (ReadMe, Dataset, Dashboard tabs, live formulas)
├── Crosswalk_Simple_Case_Study.docx   # Full write-up: problem, solution, impact, risk management
├── Crosswalk_Simple_Tech_Stack.docx   # Tech-stack-focused summary
└── README.md
```

## How to Run This

1. Open MySQL Workbench, connect to your local server
2. File → Open SQL Script → select `crosswalk_project.sql`
3. Execute All (lightning bolt icon) — this drops/recreates a `crosswalk_db` database, builds all 4 tables, loads sample data, and creates the `v_claims` view
4. Confirm the decision split: `SELECT * FROM v_claims;` or run the summary query at the bottom of the script
5. For the dashboard: open `crosswalk_dashboard.xlsx` in Excel. The Dataset tab holds the flat claim-level data; the Dashboard tab's KPIs and chart are all live formulas referencing it — edit a row in Dataset and watch the Dashboard update

> Note: MySQL only enforces `CHECK` constraints from version 8.0.16 onward. Run `SELECT VERSION();` first if constraints seem to be ignored.

## Limitations

- Crosswalk confidence grades are illustrative and synthetic, built to demonstrate the approach — not sourced from an actual payer's crosswalk policy.
- The 150-claim dataset is synthetically generated to demonstrate the decision pattern; it is not real patient or billing data.

---

*Built as a self-directed portfolio project applying SQL database design to healthcare diagnosis-procedure crosswalk validation.*
