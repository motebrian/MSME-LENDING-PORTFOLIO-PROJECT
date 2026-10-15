-- staging.stg_installments_payments
-- One row per scheduled installment. Adds:
--   dpd            : days late (positive = late, <=0 = on time/early)
--                    only computable once a payment has actually posted
--   is_late        : dpd > 0
--   is_underpaid   : amount paid < amount due (partial payment)
--   dpd_bucket     : standard PAR-style bucket for aggregation
--
-- Note: dpd is NULL for installments with no recorded entry payment yet
-- (not yet due, or genuinely unpaid/written off — the raw table doesn't
-- distinguish the two). This is part of why PAR from this dataset is an
-- estimate rather than a true point-in-time balance-based figure —
-- flag this in docs/metrics_definitions.md when you write it.

CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE VIEW staging.stg_installments_payments AS
SELECT
    sk_id_prev,
    sk_id_curr,
    num_instalment_version,
    num_instalment_number,
    days_instalment,
    days_entry_payment,
    amt_instalment,
    amt_payment,
    (days_entry_payment - days_instalment)                         AS dpd,
    CASE WHEN days_entry_payment IS NOT NULL
              AND (days_entry_payment - days_instalment) > 0
         THEN TRUE ELSE FALSE END                                  AS is_late,
    CASE WHEN amt_payment IS NOT NULL
              AND amt_payment < amt_instalment
         THEN TRUE ELSE FALSE END                                  AS is_underpaid,
    CASE
        WHEN days_entry_payment IS NULL THEN 'unpaid_or_pending'
        WHEN (days_entry_payment - days_instalment) <= 0 THEN 'current'
        WHEN (days_entry_payment - days_instalment) BETWEEN 1  AND 30  THEN '1-30'
        WHEN (days_entry_payment - days_instalment) BETWEEN 31 AND 60  THEN '31-60'
        WHEN (days_entry_payment - days_instalment) BETWEEN 61 AND 90  THEN '61-90'
        ELSE '90+'
    END                                                              AS dpd_bucket
FROM public.installments_payments;
