-- staging.stg_bureau
-- One row per external (credit bureau-reported) credit line.
-- amt_credit_sum_debt is intentionally left NULL where the source has
-- it NULL — that's a real gap in bureau reporting, not a placeholder,
-- and coalescing it to 0 would understate debt on affected records.
-- Note this in docs/metrics_definitions.md as a known limitation.

CREATE OR REPLACE VIEW staging.stg_bureau AS
SELECT
    sk_id_curr,
    sk_id_bureau,
    credit_active,
    (credit_active = 'Active')                                        AS is_active,
    credit_currency,
    days_credit,
    credit_day_overdue,
    (credit_day_overdue > 0)                                          AS is_overdue,
    amt_credit_sum,
    amt_credit_sum_debt
FROM public.bureau;
