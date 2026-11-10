-- sql/quality/03_run_on_real_data.sql
--
-- Runs the checks on the real tables (schema public) and reconciles the
-- staging and metrics layers against the raw data.
-- Prerequisites: 01_dq_framework.sql, and the staging and metrics views.
-- Run each numbered block on its own.

-- ============================================================
-- A. Run all 21 checks on the real tables
-- ============================================================
DELETE FROM dq.check_results WHERE run_label = 'real_data';
SELECT dq.run_checks('public', 'real_data') AS real_run_id;

-- ============================================================
-- B. Results: errors and failures first
--    A 'warning' or 'info' failure is not a defect in the pipeline by itself.
--    Expect DQ06 (the 3 income outliers) and DQ18 (prior loans of applicants
--    outside application_train) to fail on the real data. Both are documented.
-- ============================================================
SELECT c.check_id, c.severity, c.table_name, c.description,
       r.status, r.violations, r.error_message
FROM dq.check_results r
JOIN dq.checks c USING (check_id)
WHERE r.run_label = 'real_data'
ORDER BY CASE r.status WHEN 'error' THEN 0 WHEN 'fail' THEN 1 ELSE 2 END,
         CASE c.severity WHEN 'error' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END,
         c.check_id;

-- ============================================================
-- C. Reconciliation: the staging and metrics layers must agree with
--    the raw tables. Every row should read 'pass'.
-- ============================================================
SELECT check_name,
       violations,
       CASE WHEN violations = 0 THEN 'pass' ELSE 'FAIL' END AS verdict
FROM (
    SELECT 'row count: stg_application = application_train' AS check_name,
           abs((SELECT count(*) FROM staging.stg_application) - (SELECT count(*) FROM public.application_train)) AS violations
    UNION ALL
    SELECT 'row count: stg_previous_application = previous_application',
           abs((SELECT count(*) FROM staging.stg_previous_application) - (SELECT count(*) FROM public.previous_application))
    UNION ALL
    SELECT 'row count: stg_installments_payments = installments_payments',
           abs((SELECT count(*) FROM staging.stg_installments_payments) - (SELECT count(*) FROM public.installments_payments))
    UNION ALL
    SELECT 'row count: stg_bureau = bureau',
           abs((SELECT count(*) FROM staging.stg_bureau) - (SELECT count(*) FROM public.bureau))
    UNION ALL
    SELECT 'row count: stg_pos_cash_balance = pos_cash_balance',
           abs((SELECT count(*) FROM staging.stg_pos_cash_balance) - (SELECT count(*) FROM public.pos_cash_balance))
    UNION ALL
    SELECT 'row count: stg_credit_card_balance = credit_card_balance',
           abs((SELECT count(*) FROM staging.stg_credit_card_balance) - (SELECT count(*) FROM public.credit_card_balance))
    UNION ALL
    SELECT 'defaults: staging total = raw total',
           abs((SELECT sum(target) FROM staging.stg_application) - (SELECT sum(target) FROM public.application_train))
    UNION ALL
    SELECT 'placeholder 365243 removed: no employment tenure above 100 years in stg_application',
           (SELECT count(*) FROM staging.stg_application WHERE employment_years > 100)
    UNION ALL
    SELECT 'PAR flags nest: ever 90+ implies ever 60+ implies ever 30+',
           (SELECT count(*) FROM metrics.loan_level_dpd
            WHERE (ever_90_plus AND NOT ever_60_plus) OR (ever_60_plus AND NOT ever_30_plus))
    UNION ALL
    SELECT 'vintage curve never decreases within a cohort',
           (SELECT count(*) FROM metrics.vintage_curve a
            JOIN metrics.vintage_curve b
              ON a.vintage_label = b.vintage_label AND b.seasoning_month = a.seasoning_month - 1
            WHERE a.pct_ever_30_plus < b.pct_ever_30_plus)
) r
ORDER BY check_name;
