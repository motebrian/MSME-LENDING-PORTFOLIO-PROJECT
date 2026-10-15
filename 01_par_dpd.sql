-- metrics/01_par_dpd.sql
--
-- IMPORTANT — read before using these numbers anywhere:
-- Home Credit's installments_payments table has no outstanding-principal
-- field, so "true" point-in-time PAR (% of outstanding balance currently
-- 30+ days overdue, as of a snapshot date) is not computable from this
-- dataset. What follows is a proxy:
--   - "delinquent" here means "this loan/instalment was EVER X+ days late
--     at some point in its history" (not "is currently X+ days late")
--   - "exposure" is approximated using AMT_INSTALMENT (amount due per
--     instalment), not an actual outstanding balance
-- State this explicitly in metrics_definitions.md and anywhere these
-- numbers are shown (README, dashboard).

CREATE SCHEMA IF NOT EXISTS metrics;

-- ============================================================
-- 1. Loan-level DPD summary (one row per previous loan / sk_id_prev)
-- ============================================================
CREATE OR REPLACE VIEW metrics.loan_level_dpd AS
SELECT
    sk_id_prev,
    sk_id_curr,
    count(*)                                                          AS n_instalments,
    sum(amt_instalment)                                               AS total_instalment_amt,
    max(dpd)                                                          AS worst_dpd,   -- MAX ignores NULLs automatically
    bool_or(dpd > 30)                                                 AS ever_30_plus,
    bool_or(dpd > 60)                                                 AS ever_60_plus,
    bool_or(dpd > 90)                                                 AS ever_90_plus,
    CASE
        WHEN max(dpd) IS NULL THEN 'no_payment_recorded'
        WHEN max(dpd) <= 0 THEN 'current'
        WHEN max(dpd) BETWEEN 1  AND 30  THEN '1-30'
        WHEN max(dpd) BETWEEN 31 AND 60  THEN '31-60'
        WHEN max(dpd) BETWEEN 61 AND 90  THEN '61-90'
        ELSE '90+'
    END                                                                AS worst_dpd_bucket
FROM staging.stg_installments_payments
GROUP BY sk_id_prev, sk_id_curr;

-- ============================================================
-- 2. PAR30/60/90 by loan count (simplest version — % of loans that
--    ever crossed each threshold)
-- ============================================================
SELECT
    round(count(*) FILTER (WHERE ever_30_plus) * 100.0 / count(*), 2) AS par30_pct_by_loan_count,
    round(count(*) FILTER (WHERE ever_60_plus) * 100.0 / count(*), 2) AS par60_pct_by_loan_count,
    round(count(*) FILTER (WHERE ever_90_plus) * 100.0 / count(*), 2) AS par90_pct_by_loan_count,
    count(*)                                                          AS total_loans
FROM metrics.loan_level_dpd;

-- ============================================================
-- 3. PAR30/60/90 by amount (estimated exposure — the more standard
--    lender-facing framing, but remember: proxy exposure, not true
--    outstanding balance)
-- ============================================================
SELECT
    round(sum(total_instalment_amt) FILTER (WHERE ever_30_plus) * 100.0 / sum(total_instalment_amt), 2) AS par30_pct_by_amount,
    round(sum(total_instalment_amt) FILTER (WHERE ever_60_plus) * 100.0 / sum(total_instalment_amt), 2) AS par60_pct_by_amount,
    round(sum(total_instalment_amt) FILTER (WHERE ever_90_plus) * 100.0 / sum(total_instalment_amt), 2) AS par90_pct_by_amount,
    sum(total_instalment_amt)                                         AS total_instalment_amt
FROM metrics.loan_level_dpd;

-- ============================================================
-- 4. DPD bucket distribution at instalment level (dashboard-ready —
--    shows the shape of the whole book, not just above/below a threshold)
-- ============================================================
SELECT
    dpd_bucket,
    count(*)              AS n_instalments,
    sum(amt_instalment)    AS total_amt
FROM staging.stg_installments_payments
GROUP BY dpd_bucket
ORDER BY
    CASE dpd_bucket
        WHEN 'current' THEN 1
        WHEN '1-30' THEN 2
        WHEN '31-60' THEN 3
        WHEN '61-90' THEN 4
        WHEN '90+' THEN 5
        WHEN 'unpaid_or_pending' THEN 6
    END;

-- ============================================================
-- 5. Borrower-level rollup (one row per sk_id_curr — a borrower can
--    have multiple previous loans). Feeds segmentation and the
--    scorecard: join to staging.stg_application on sk_id_curr.
-- ============================================================
CREATE OR REPLACE VIEW metrics.borrower_level_dpd AS
SELECT
    sk_id_curr,
    count(DISTINCT sk_id_prev)   AS n_loans,
    max(worst_dpd)               AS worst_dpd_any_loan,
    bool_or(ever_30_plus)        AS ever_30_plus_any_loan,
    bool_or(ever_60_plus)        AS ever_60_plus_any_loan,
    bool_or(ever_90_plus)        AS ever_90_plus_any_loan
FROM metrics.loan_level_dpd
GROUP BY sk_id_curr;
