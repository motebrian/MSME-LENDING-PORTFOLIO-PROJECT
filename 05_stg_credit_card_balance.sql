-- staging.stg_credit_card_balance
-- One row per monthly credit-card snapshot. Adds utilization_ratio, the
-- standard revolving-credit risk metric. NULLIF guards against divide-
-- by-zero on accounts with a 0 credit limit — those return NULL rather
-- than erroring the whole view.

CREATE OR REPLACE VIEW staging.stg_credit_card_balance AS
SELECT
    sk_id_prev,
    sk_id_curr,
    months_balance,
    amt_balance,
    amt_credit_limit_actual,
    amt_balance / NULLIF(amt_credit_limit_actual, 0)                  AS utilization_ratio,
    sk_dpd,
    sk_dpd_def,
    CASE
        WHEN sk_dpd <= 0 THEN 'current'
        WHEN sk_dpd BETWEEN 1  AND 30  THEN '1-30'
        WHEN sk_dpd BETWEEN 31 AND 60  THEN '31-60'
        WHEN sk_dpd BETWEEN 61 AND 90  THEN '61-90'
        ELSE '90+'
    END                                                                AS dpd_bucket
FROM public.credit_card_balance;
