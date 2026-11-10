-- sql/quality/01_dq_framework.sql
--
-- A small data quality framework for the six raw Home Credit tables.
--   dq.checks         catalogue of checks; each is a query returning the number
--                     of violations (0 = pass)
--   dq.check_results  one row per check per run
--   dq.run_checks()   runs every check against a schema and logs the results
--
-- Every check is written against {schema}, so the same checks run on the real
-- data (schema public) and on a corrupted test copy (schema dq_test).
-- A check that cannot run (for example because a column has the wrong type)
-- is logged with status 'error' and the database message, not skipped.
--
-- Run this file once, as a whole.

CREATE SCHEMA IF NOT EXISTS dq;

DROP TABLE IF EXISTS dq.check_results;
DROP TABLE IF EXISTS dq.checks;
DROP SEQUENCE IF EXISTS dq.run_seq;

CREATE SEQUENCE dq.run_seq;

CREATE TABLE dq.checks (
    check_id      text PRIMARY KEY,
    category      text NOT NULL,
    table_name    text NOT NULL,
    description   text NOT NULL,
    severity      text NOT NULL CHECK (severity IN ('error', 'warning', 'info')),
    violation_sql text NOT NULL
);

CREATE TABLE dq.check_results (
    run_id        bigint NOT NULL,
    run_label     text   NOT NULL,
    scope_schema  text   NOT NULL,
    check_id      text   NOT NULL REFERENCES dq.checks (check_id),
    violations    bigint,
    status        text   NOT NULL CHECK (status IN ('pass', 'fail', 'error')),
    error_message text,
    run_at        timestamptz NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- Catalogue. {schema} = quoted schema identifier,
--            {schema_lit} = schema name as a quoted literal.
-- ------------------------------------------------------------
INSERT INTO dq.checks (check_id, category, table_name, description, severity, violation_sql) VALUES

('DQ01', 'uniqueness', 'application_train', 'sk_id_curr is unique (counts duplicated keys)', 'error',
 $q$SELECT count(*) FROM (SELECT sk_id_curr FROM {schema}.application_train WHERE sk_id_curr IS NOT NULL GROUP BY 1 HAVING count(*) > 1) t$q$),

('DQ02', 'completeness', 'application_train', 'sk_id_curr is never null', 'error',
 $q$SELECT count(*) FROM {schema}.application_train WHERE sk_id_curr IS NULL$q$),

('DQ03', 'uniqueness', 'previous_application', 'sk_id_prev is unique (counts duplicated keys)', 'error',
 $q$SELECT count(*) FROM (SELECT sk_id_prev FROM {schema}.previous_application WHERE sk_id_prev IS NOT NULL GROUP BY 1 HAVING count(*) > 1) t$q$),

('DQ04', 'validity', 'application_train', 'target is 0 or 1 and never null', 'error',
 $q$SELECT count(*) FROM {schema}.application_train WHERE target IS NULL OR target NOT IN (0, 1)$q$),

('DQ05', 'validity', 'application_train', 'amt_income_total is positive', 'error',
 $q$SELECT count(*) FROM {schema}.application_train WHERE amt_income_total <= 0$q$),

('DQ06', 'validity', 'application_train', 'amt_income_total is at most 10,000,000 (extreme-value screen)', 'warning',
 $q$SELECT count(*) FROM {schema}.application_train WHERE amt_income_total > 10000000$q$),

('DQ07', 'validity', 'application_train', 'amt_credit is positive', 'error',
 $q$SELECT count(*) FROM {schema}.application_train WHERE amt_credit <= 0$q$),

('DQ08', 'validity', 'application_train', 'days_birth is negative (offset before the application)', 'error',
 $q$SELECT count(*) FROM {schema}.application_train WHERE days_birth >= 0$q$),

('DQ09', 'validity', 'application_train', 'age implied by days_birth is between 18 and 100', 'warning',
 $q$SELECT count(*) FROM {schema}.application_train WHERE days_birth < 0 AND (-days_birth / 365.25 < 18 OR -days_birth / 365.25 > 100)$q$),

('DQ10', 'validity', 'application_train', 'code_gender is F, M or XNA when present', 'error',
 $q$SELECT count(*) FROM {schema}.application_train WHERE code_gender IS NOT NULL AND code_gender NOT IN ('F', 'M', 'XNA')$q$),

('DQ11', 'validity', 'installments_payments', 'amt_instalment is not negative', 'error',
 $q$SELECT count(*) FROM {schema}.installments_payments WHERE amt_instalment < 0$q$),

('DQ12', 'validity', 'installments_payments', 'amt_payment is not negative', 'error',
 $q$SELECT count(*) FROM {schema}.installments_payments WHERE amt_payment < 0$q$),

('DQ13', 'validity', 'pos_cash_balance', 'sk_dpd is not negative', 'error',
 $q$SELECT count(*) FROM {schema}.pos_cash_balance WHERE sk_dpd < 0$q$),

('DQ14', 'validity', 'credit_card_balance', 'amt_credit_limit_actual is not negative', 'error',
 $q$SELECT count(*) FROM {schema}.credit_card_balance WHERE amt_credit_limit_actual < 0$q$),

('DQ15', 'validity', 'previous_application', 'days_decision is not positive (offset before the application)', 'error',
 $q$SELECT count(*) FROM {schema}.previous_application WHERE days_decision > 0$q$),

('DQ16', 'validity', 'bureau', 'credit_day_overdue is not negative', 'error',
 $q$SELECT count(*) FROM {schema}.bureau WHERE credit_day_overdue < 0$q$),

('DQ17', 'referential', 'installments_payments', 'every instalment belongs to a loan in previous_application', 'error',
 $q$SELECT count(*) FROM {schema}.installments_payments ip WHERE NOT EXISTS (SELECT 1 FROM {schema}.previous_application pa WHERE pa.sk_id_prev = ip.sk_id_prev)$q$),

('DQ18', 'referential', 'previous_application', 'every prior loan belongs to an applicant in application_train (info: the full dataset includes test-set applicants, so some orphans are expected)', 'info',
 $q$SELECT count(*) FROM {schema}.previous_application pa WHERE NOT EXISTS (SELECT 1 FROM {schema}.application_train a WHERE a.sk_id_curr = pa.sk_id_curr)$q$),

('DQ19', 'consistency', 'installments_payments', 'payment date and payment amount are both present or both missing', 'warning',
 $q$SELECT count(*) FROM {schema}.installments_payments WHERE (days_entry_payment IS NULL) <> (amt_payment IS NULL)$q$),

('DQ20', 'types', 'all six raw tables', 'numeric-looking columns are not stored as text (the reimport failure)', 'error',
 $q$SELECT count(*) FROM information_schema.columns
    WHERE table_schema = {schema_lit}
      AND table_name IN ('application_train', 'previous_application', 'installments_payments', 'bureau', 'pos_cash_balance', 'credit_card_balance')
      AND data_type IN ('text', 'character varying')
      AND (   column_name LIKE 'days\_%' OR column_name LIKE 'amt\_%' OR column_name LIKE 'cnt\_%'
           OR column_name LIKE 'sk\_%'   OR column_name LIKE 'ext\_source\_%' OR column_name LIKE 'flag\_document\_%'
           OR column_name LIKE 'num\_%'  OR column_name LIKE 'hour\_%' OR column_name LIKE 'region\_%'
           OR column_name IN ('months_balance', 'credit_day_overdue', 'target'))$q$),

('DQ21', 'completeness', 'application_train', 'ext_source_2 is missing in at most 5% of rows (returns 1 if the rate is higher)', 'warning',
 $q$SELECT CASE WHEN avg((ext_source_2 IS NULL)::int) > 0.05 THEN 1 ELSE 0 END FROM {schema}.application_train$q$);

-- ------------------------------------------------------------
-- Runner: executes every check against p_schema and logs the results.
-- Returns the run_id.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION dq.run_checks(p_schema text, p_label text)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_run   bigint := nextval('dq.run_seq');
    r       record;
    v_sql   text;
    v_count bigint;
BEGIN
    FOR r IN SELECT check_id, violation_sql FROM dq.checks ORDER BY check_id LOOP
        v_sql := replace(replace(r.violation_sql, '{schema_lit}', quote_literal(p_schema)),
                         '{schema}', quote_ident(p_schema));
        BEGIN
            EXECUTE v_sql INTO v_count;
            INSERT INTO dq.check_results (run_id, run_label, scope_schema, check_id, violations, status)
            VALUES (v_run, p_label, p_schema, r.check_id, v_count,
                    CASE WHEN v_count = 0 THEN 'pass' ELSE 'fail' END);
        EXCEPTION WHEN OTHERS THEN
            INSERT INTO dq.check_results (run_id, run_label, scope_schema, check_id, violations, status, error_message)
            VALUES (v_run, p_label, p_schema, r.check_id, NULL, 'error', SQLERRM);
        END;
    END LOOP;
    RETURN v_run;
END;
$$;
