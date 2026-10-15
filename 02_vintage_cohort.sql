-- metrics/02_vintage_cohort.sql
--
-- IMPORTANT: this dataset has no real calendar dates — DAYS_DECISION is a
-- relative offset (days before the current application's reference
-- point). "Cohort" here means "loans that originated roughly N years
-- before the current application," not a true calendar vintage (e.g.
-- "Q1 2019"). State this wherever vintage results are shown.

CREATE SCHEMA IF NOT EXISTS metrics;

-- ============================================================
-- 1. Vintage cohort assignment (one row per previous loan)
-- ============================================================
CREATE OR REPLACE VIEW metrics.vintage_cohort AS
SELECT
    sk_id_prev,
    sk_id_curr,
    days_decision,
    floor(-days_decision / 365.0)::int                               AS vintage_years_ago,
    'Y-' || floor(-days_decision / 365.0)::int                       AS vintage_label
FROM staging.stg_previous_application
WHERE days_decision IS NOT NULL;

-- ============================================================
-- 2. Instalment seasoning (months since loan origination, per instalment)
-- ============================================================
CREATE OR REPLACE VIEW metrics.instalment_seasoning AS
SELECT
    ip.sk_id_prev,
    ip.sk_id_curr,
    vc.vintage_years_ago,
    vc.vintage_label,
    floor((ip.days_instalment - vc.days_decision) / 30.0)::int        AS seasoning_month,
    ip.dpd,
    (ip.dpd > 30)                                                     AS is_30_plus
FROM staging.stg_installments_payments ip
JOIN metrics.vintage_cohort vc
    ON ip.sk_id_prev = vc.sk_id_prev
WHERE ip.days_instalment IS NOT NULL;

-- ============================================================
-- 3. Cumulative "ever 30+ by this seasoning month" per loan
--    (the window function gives each loan a running worst-case flag,
--    ordered by seasoning month — this is what makes it a vintage
--    curve rather than a per-month snapshot)
-- ============================================================
CREATE OR REPLACE VIEW metrics.loan_cumulative_delinquency AS
SELECT
    sk_id_prev,
    sk_id_curr,
    vintage_label,
    seasoning_month,
    bool_or(is_30_plus) OVER (
        PARTITION BY sk_id_prev
        ORDER BY seasoning_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                                  AS ever_30_plus_by_month
FROM metrics.instalment_seasoning;

-- ============================================================
-- 4. The vintage curve itself — cohort x seasoning month,
--    % of loans cumulatively 30+ days late by that point.
--    This is the shape to plot in Power BI: one line per vintage_label,
--    x = seasoning_month, y = pct_ever_30_plus.
-- ============================================================
SELECT
    vintage_label,
    seasoning_month,
    count(DISTINCT sk_id_prev)                                        AS n_loans,
    round(
        count(DISTINCT sk_id_prev) FILTER (WHERE ever_30_plus_by_month) * 100.0
        / count(DISTINCT sk_id_prev), 2
    )                                                                  AS pct_ever_30_plus
FROM metrics.loan_cumulative_delinquency
WHERE seasoning_month BETWEEN 0 AND 24   -- cap at 24 months — most loans season out by then
GROUP BY vintage_label, seasoning_month
ORDER BY vintage_label, seasoning_month;
