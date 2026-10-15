-- staging.stg_pos_cash_balance
-- One row per monthly POS/cash loan snapshot. sk_dpd / sk_dpd_def are
-- carried through as-is (already computed in the source); we only add
-- a bucket for aggregation and a flag for the most recent snapshot per
-- loan, since most reporting cares about current status, not history.

CREATE OR REPLACE VIEW staging.stg_pos_cash_balance AS
SELECT
    sk_id_prev,
    sk_id_curr,
    months_balance,
    cnt_installment,
    cnt_instalment_future,
    name_contract_status,
    sk_dpd,
    sk_dpd_def,
    CASE
        WHEN sk_dpd <= 0 THEN 'current'
        WHEN sk_dpd BETWEEN 1  AND 30  THEN '1-30'
        WHEN sk_dpd BETWEEN 31 AND 60  THEN '31-60'
        WHEN sk_dpd BETWEEN 61 AND 90  THEN '61-90'
        ELSE '90+'
    END                                                                AS dpd_bucket,
    (months_balance = MAX(months_balance) OVER (PARTITION BY sk_id_prev)) AS is_latest_snapshot
FROM public.pos_cash_balance;
