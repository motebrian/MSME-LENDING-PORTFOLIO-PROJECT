-- sql/quality/02_inject_errors.sql
--
-- Proves the checks work. A check that never fails proves nothing, so this
-- script:
--   1. copies a 5,000-applicant sample (and all of their related rows) into
--      schema dq_test, leaving the real tables untouched
--   2. runs every check on the clean sample          -> run label 'baseline'
--   3. injects one known error per check             (5 rows each, or 1 flip
--      for the type and missing-rate checks)
--   4. runs every check again                        -> run label 'after_injection'
--   5. compares: each check should rise by exactly the number of injected errors
--
-- Baseline counts are subtracted, so real anomalies already present in the
-- sample do not distort the result.
--
-- Prerequisite: run 01_dq_framework.sql first.
-- Run the numbered blocks in order, each one as a whole. The copy in step 1


-- ============================================================
-- STEP 1. Build the sample copy
-- ============================================================
DROP SCHEMA IF EXISTS dq_test CASCADE;
CREATE SCHEMA dq_test;

CREATE TABLE dq_test.pick AS
SELECT sk_id_curr, row_number() OVER (ORDER BY sk_id_curr) AS rn
FROM (SELECT sk_id_curr FROM public.application_train ORDER BY sk_id_curr LIMIT 5000) s;

CREATE TABLE dq_test.application_train AS
SELECT t.* FROM public.application_train t
WHERE t.sk_id_curr IN (SELECT sk_id_curr FROM dq_test.pick);

-- _rid is a row number used only to target injections
CREATE TABLE dq_test.previous_application AS
SELECT row_number() OVER () AS _rid, t.* FROM public.previous_application t
WHERE t.sk_id_curr IN (SELECT sk_id_curr FROM dq_test.pick);

CREATE TABLE dq_test.installments_payments AS
SELECT row_number() OVER () AS _rid, t.* FROM public.installments_payments t
WHERE t.sk_id_curr IN (SELECT sk_id_curr FROM dq_test.pick);

CREATE TABLE dq_test.bureau AS
SELECT row_number() OVER () AS _rid, t.* FROM public.bureau t
WHERE t.sk_id_curr IN (SELECT sk_id_curr FROM dq_test.pick);

CREATE TABLE dq_test.pos_cash_balance AS
SELECT row_number() OVER () AS _rid, t.* FROM public.pos_cash_balance t
WHERE t.sk_id_curr IN (SELECT sk_id_curr FROM dq_test.pick);

CREATE TABLE dq_test.credit_card_balance AS
SELECT row_number() OVER () AS _rid, t.* FROM public.credit_card_balance t
WHERE t.sk_id_curr IN (SELECT sk_id_curr FROM dq_test.pick);

-- ============================================================
-- STEP 2. Baseline run on the clean sample
-- ============================================================
DELETE FROM dq.check_results WHERE run_label IN ('baseline', 'after_injection');
SELECT dq.run_checks('dq_test', 'baseline') AS baseline_run_id;

-- ============================================================
-- STEP 3. Inject one known error per check.
-- Each injection uses its own rows, so one error cannot trigger another check.
-- Duplicate-key injections come last, so no later update copies or edits them.
-- ============================================================

-- DQ04: target outside {0, 1}                                   (5 rows)
UPDATE dq_test.application_train SET target = 2
WHERE sk_id_curr IN (SELECT sk_id_curr FROM dq_test.pick WHERE rn BETWEEN 6 AND 10);

-- DQ05: non-positive income                                     (5 rows)
UPDATE dq_test.application_train SET amt_income_total = -1000
WHERE sk_id_curr IN (SELECT sk_id_curr FROM dq_test.pick WHERE rn BETWEEN 11 AND 15);

-- DQ06: extreme income                                          (5 rows)
UPDATE dq_test.application_train SET amt_income_total = 999999999
WHERE sk_id_curr IN (SELECT sk_id_curr FROM dq_test.pick WHERE rn BETWEEN 16 AND 20);

-- DQ07: zero credit amount                                      (5 rows)
UPDATE dq_test.application_train SET amt_credit = 0
WHERE sk_id_curr IN (SELECT sk_id_curr FROM dq_test.pick WHERE rn BETWEEN 21 AND 25);

-- DQ08: birth offset with the wrong sign                        (5 rows)
UPDATE dq_test.application_train SET days_birth = 12000
WHERE sk_id_curr IN (SELECT sk_id_curr FROM dq_test.pick WHERE rn BETWEEN 26 AND 30);

-- DQ09: implausible age (about 137 years)                       (5 rows)
UPDATE dq_test.application_train SET days_birth = -50000
WHERE sk_id_curr IN (SELECT sk_id_curr FROM dq_test.pick WHERE rn BETWEEN 31 AND 35);

-- DQ10: invalid gender code                                     (5 rows)
UPDATE dq_test.application_train SET code_gender = 'Z'
WHERE sk_id_curr IN (SELECT sk_id_curr FROM dq_test.pick WHERE rn BETWEEN 36 AND 40);

-- DQ11: negative instalment amount                              (5 rows)
UPDATE dq_test.installments_payments SET amt_instalment = -100
WHERE _rid BETWEEN 1 AND 5;

-- DQ17: instalments pointing to a loan that does not exist      (5 rows)
UPDATE dq_test.installments_payments SET sk_id_prev = 999999999
WHERE _rid BETWEEN 11 AND 15;

-- DQ12: negative payment amount (rows that have a payment)      (5 rows)
UPDATE dq_test.installments_payments SET amt_payment = -100
WHERE _rid IN (SELECT _rid FROM dq_test.installments_payments
               WHERE amt_payment IS NOT NULL AND _rid BETWEEN 21 AND 80
               ORDER BY _rid LIMIT 5);

-- DQ19: payment amount present but payment date missing         (5 rows)
UPDATE dq_test.installments_payments SET days_entry_payment = NULL
WHERE _rid IN (SELECT _rid FROM dq_test.installments_payments
               WHERE amt_payment IS NOT NULL AND days_entry_payment IS NOT NULL AND _rid > 1000
               ORDER BY _rid LIMIT 5);

-- DQ13: negative days past due                                  (5 rows)
UPDATE dq_test.pos_cash_balance SET sk_dpd = -5
WHERE _rid BETWEEN 1 AND 5;

-- DQ14: negative credit limit                                   (5 rows)
UPDATE dq_test.credit_card_balance SET amt_credit_limit_actual = -1000
WHERE _rid BETWEEN 1 AND 5;

-- DQ16: negative overdue days                                   (5 rows)
UPDATE dq_test.bureau SET credit_day_overdue = -10
WHERE _rid BETWEEN 1 AND 5;

-- DQ15: decision date after the application                     (5 rows)
UPDATE dq_test.previous_application SET days_decision = 500
WHERE _rid BETWEEN 1 AND 5;

-- DQ18: prior loans belonging to an applicant that does not exist (5 rows)
UPDATE dq_test.previous_application SET sk_id_curr = -1
WHERE _rid BETWEEN 6 AND 10;

-- DQ21: ext_source_2 missing for 40% of applicants              (flips 0 -> 1)
UPDATE dq_test.application_train SET ext_source_2 = NULL
WHERE sk_id_curr IN (SELECT sk_id_curr FROM dq_test.pick WHERE rn BETWEEN 1001 AND 3000);

-- DQ02: rows with a null key                                    (5 rows)
INSERT INTO dq_test.application_train (sk_id_curr, target)
SELECT NULL, 0 FROM generate_series(1, 5);

-- DQ20: a numeric-looking column stored as text                 (flips 0 -> 1)
ALTER TABLE dq_test.application_train ALTER COLUMN amt_goods_price TYPE text;

-- DQ01: duplicated applicant keys (rows untouched by the updates above)  (5 keys)
INSERT INTO dq_test.application_train
SELECT * FROM dq_test.application_train
WHERE sk_id_curr IN (SELECT sk_id_curr FROM dq_test.pick WHERE rn BETWEEN 1 AND 5);

-- DQ03: duplicated loan keys (rows untouched by the updates above)       (5 keys)
INSERT INTO dq_test.previous_application
SELECT * FROM dq_test.previous_application
WHERE sk_id_prev IN (SELECT sk_id_prev FROM dq_test.previous_application
                     WHERE _rid > 1000 ORDER BY sk_id_prev LIMIT 5);

-- ============================================================
-- STEP 4. Run every check again on the corrupted copy
-- ============================================================
SELECT dq.run_checks('dq_test', 'after_injection') AS after_run_id;

-- ============================================================
-- STEP 5. Did every check catch its error?
-- ============================================================
WITH expected(check_id, expected_delta) AS (
    VALUES ('DQ01', 5), ('DQ02', 5), ('DQ03', 5), ('DQ04', 5), ('DQ05', 5), ('DQ06', 5),
           ('DQ07', 5), ('DQ08', 5), ('DQ09', 5), ('DQ10', 5), ('DQ11', 5), ('DQ12', 5),
           ('DQ13', 5), ('DQ14', 5), ('DQ15', 5), ('DQ16', 5), ('DQ17', 5), ('DQ18', 5),
           ('DQ19', 5), ('DQ20', 1), ('DQ21', 1)
)
SELECT c.check_id,
       c.description,
       b.violations                        AS baseline,
       a.violations                        AS after_injection,
       a.violations - b.violations         AS detected,
       e.expected_delta                    AS injected,
       CASE
           WHEN a.status = 'error' OR b.status = 'error' THEN 'ERROR: ' || coalesce(a.error_message, b.error_message)
           WHEN a.violations - b.violations = e.expected_delta THEN 'caught'
           ELSE 'MISSED'
       END                                 AS verdict
FROM dq.checks c
JOIN expected e USING (check_id)
JOIN dq.check_results b ON b.check_id = c.check_id AND b.run_label = 'baseline'
JOIN dq.check_results a ON a.check_id = c.check_id AND a.run_label = 'after_injection'
ORDER BY c.check_id;


