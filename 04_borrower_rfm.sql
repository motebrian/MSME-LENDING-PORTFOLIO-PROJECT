-- metrics/04_borrower_rfm.sql
--
-- RFM features per applicant, adapted for lending, from APPROVED prior loans:
--   frequency     = number of approved prior loans
--   recency_days  = days since the most recent approved prior loan, relative
--                   to the current application (relative offset, not a
--                   calendar date)
--   monetary      = total credit amount across approved prior loans
--
-- Applicants with no approved prior loan get frequency = 0 and NULL
-- recency_days / monetary. The segmentation notebook treats them as a
-- separate rule-based segment instead of clustering them.
--
-- The default flag is deliberately NOT in this view: clustering features
-- stay free of the outcome, and the notebook joins it later for profiling.

CREATE OR REPLACE VIEW metrics.borrower_rfm AS
SELECT
    a.sk_id_curr,
    count(p.sk_id_prev) FILTER (WHERE p.is_approved)                  AS frequency,
    (-1) * max(p.days_decision) FILTER (WHERE p.is_approved)          AS recency_days,
    sum(p.amt_credit) FILTER (WHERE p.is_approved)                    AS monetary
FROM staging.stg_application a
LEFT JOIN staging.stg_previous_application p
       ON p.sk_id_curr = a.sk_id_curr
GROUP BY a.sk_id_curr;

-- Checks (run separately):
-- SELECT count(*) FROM metrics.borrower_rfm;                        -- expect 307,511
-- SELECT count(*) FILTER (WHERE frequency = 0) AS no_approved_history,
--        min(recency_days), max(recency_days), max(frequency)
-- FROM metrics.borrower_rfm;
