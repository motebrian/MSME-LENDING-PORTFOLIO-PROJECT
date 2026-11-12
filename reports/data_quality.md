# Data Quality Checks

This project runs 21 data quality checks on the six raw tables, tests that each check works by injecting known errors, and reconciles the staging and metrics layers against the raw data.

## Approach

1. **Checks as queries.** Each check is a SQL query that returns the number of violations. Zero means pass. The checks live in a catalogue table (`dq.checks`), and a runner (`dq.run_checks`) executes them against any schema and logs every result to `dq.check_results`.
2. **Checks that cannot run are logged, not skipped.** If a check fails to execute, for example because a numeric column is stored as text, the runner records an `error` with the database message.
3. **Proof that the checks work.** A check that never fails proves nothing. The injection test copies a 5,000-applicant sample and its related rows into a separate schema, runs every check on the clean copy, injects one known error per check, and runs the checks again. Each check must rise by exactly the number of errors injected. Baseline counts are subtracted, so anomalies already present in the data do not distort the test.
4. **Reconciliation.** Separate queries confirm that the staging views and metrics tables agree with the raw tables.

## Check catalogue

| ID | Table | Category | Rule | Severity |
|---|---|---|---|---|
| DQ01 | application_train | uniqueness | `sk_id_curr` is unique | error |
| DQ02 | application_train | completeness | `sk_id_curr` is never null | error |
| DQ03 | previous_application | uniqueness | `sk_id_prev` is unique | error |
| DQ04 | application_train | validity | `target` is 0 or 1 and never null | error |
| DQ05 | application_train | validity | `amt_income_total` is positive | error |
| DQ06 | application_train | validity | `amt_income_total` is at most 10,000,000 | warning |
| DQ07 | application_train | validity | `amt_credit` is positive | error |
| DQ08 | application_train | validity | `days_birth` is negative | error |
| DQ09 | application_train | validity | age implied by `days_birth` is between 18 and 100 | warning |
| DQ10 | application_train | validity | `code_gender` is F, M or XNA when present | error |
| DQ11 | installments_payments | validity | `amt_instalment` is not negative | error |
| DQ12 | installments_payments | validity | `amt_payment` is not negative | error |
| DQ13 | pos_cash_balance | validity | `sk_dpd` is not negative | error |
| DQ14 | credit_card_balance | validity | `amt_credit_limit_actual` is not negative | error |
| DQ15 | previous_application | validity | `days_decision` is not positive | error |
| DQ16 | bureau | validity | `credit_day_overdue` is not negative | error |
| DQ17 | installments_payments | referential | every instalment belongs to a loan in `previous_application` | error |
| DQ18 | previous_application | referential | every prior loan belongs to an applicant in `application_train` | info |
| DQ19 | installments_payments | consistency | payment date and payment amount are both present or both missing | warning |
| DQ20 | all six raw tables | types | numeric-looking columns are not stored as text | error |
| DQ21 | application_train | completeness | `ext_source_2` is missing in at most 5% of rows | warning |

## Injection test results

All 21 checks caught their injected errors: 19 checks rose by exactly 5 (five corrupted rows or keys each), and the two checks that flip on a condition (DQ20 for a column stored as text, DQ21 for a missing-rate above 5%) rose by exactly 1.

The baseline subtraction mattered in practice. On the clean sample, DQ17 already reported 17,188 violations before any injection. After injecting 5 instalments that point to a non-existent loan, it reported 17,193, so it detected exactly the 5 injected rows without being thrown off by the existing anomaly.

## Results on the real data

18 of the 21 checks pass. The three failures:

| Check | Violations | Reading |
|---|---:|---|
| DQ06 | 3 | Three applicants report income above 10 million. These are the outliers found in the exploratory analysis. Income is capped for clustering and left unchanged for scorecard binning. |
| DQ18 | 256,513 | Prior loans that belong to applicants who are not in `application_train`, about 15% of prior loans. The test set is not loaded, which is consistent with this count. Info level. |
| DQ17 | 1,250,826 | Instalment rows whose loan has no row in `previous_application`. See below. |

### DQ17: instalments without a matching loan

- **Size.** 1,250,826 instalment rows, about 9% of the instalment table. They belong to 38,847 loans, which is 3.89% of the 997,752 loans with instalment history.
- **Not a partial load.** `previous_application` holds 1,670,214 rows, all with distinct `sk_id_prev`, and DQ03 passes.
- **Not a random slice.** The unmatched loans average about 32 instalment rows each, against about 14 for loans overall, so they differ in structure from the rest.
- **Impact.** PAR is built from instalments alone and covers all 997,752 loans. The vintage analysis joins instalments to `previous_application` for the origination date, so it covers the 958,905 loans that appear in both. The 38,847 unmatched loans are in PAR and outside the vintage curves.
- **The unmatched loans are riskier.** PAR by group:

  | Population | Loans | PAR30 | PAR60 | PAR90 |
  |---|---:|---:|---:|---:|
  | In `previous_application` | 958,905 | 2.17% | 0.93% | 0.75% |
  | Not in `previous_application` | 38,847 | 6.04% | 3.17% | 2.60% |
  | All loans (dashboard) | 997,752 | 2.32% | 1.02% | 0.83% |

  The unmatched loans are roughly three times as likely to reach each threshold. They lift the headline PAR by about 0.15 points at 30+ days, 0.09 at 60+ and 0.08 at 90+. The vintage curves describe the lower-risk matched population, so they probably understate delinquency for the whole book.
- **Status.** The cause is not established. The PAR cards stay on the full population, and the vintage page states its narrower scope. The finding is documented as a limitation in `metrics_definitions.md` and the README.

## Reconciliation results

All 10 reconciliation checks pass:

- Staging row counts equal the raw row counts for all six tables.
- Total defaults in `stg_application` equal the raw total.
- No employment tenure above 100 years remains in `stg_application`, so the `365243` placeholder is removed.
- PAR flags nest: every loan ever 90+ days late is also ever 60+, and every loan ever 60+ is also ever 30+.
- No vintage curve decreases within a cohort.

## How to run

1. `sql/quality/01_dataquality.sql` creates the catalogue, the results table and the runner.
2. `sql/quality/02_inject_errors_dataquality.sql` builds the sample copy, injects the errors and prints a verdict for each check.
3. `sql/quality/03_run_on_real_data_dataquality.sql` runs the checks on the real tables and prints the reconciliation table.

## Limitations

- Checks test plausibility, not truth. A value can pass every rule and still be wrong.
- Thresholds (10,000,000 for income, ages 18 to 100, 5% missing for `ext_source_2`) are judgement calls and are stored in the check queries so they are easy to change.
- The injection test uses the first 5,000 applicants by ID, which is deterministic but not a random sample.
- The checks cover the six raw tables. The staging and metrics layers are covered by the reconciliation queries only.
