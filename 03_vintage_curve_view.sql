-- metrics/03_vintage_curve_view.sql  (v2 — replaces the first version)
--
-- Vintage curve: % of loans cumulatively 30+ days late, by cohort and
-- months since origination (0-12).
--
-- Method:
--   * Eligible loans: originated at least 365 days before the reference
--     date (days_decision <= -365), so every loan has had time to season
--     12 months. Eligibility depends on origination timing, NOT on
--     payment behaviour — conditioning on continued payment would drop
--     early defaulters and bias the curve downward.
--   * Loans with no payment history (refused / cancelled applications)
--     are excluded.
--   * Each loan's first 30+ DPD month is found once; a loan counts as
--     "ever 30+" at month m if that first month <= m. The denominator is
--     fixed per cohort, so the curve cannot decrease.
--   * Y-0 cohort (originated < 1 year before reference) has too little
--     history, so the 365-day rule excludes it entirely.
--
-- Cohorts are relative (years before application), not calendar years.

CREATE OR REPLACE VIEW metrics.vintage_curve AS
WITH eligible AS (
    SELECT vc.sk_id_prev, vc.vintage_label
    FROM metrics.vintage_cohort vc
    WHERE vc.days_decision <= -365
      AND EXISTS (
          SELECT 1 FROM metrics.instalment_seasoning s
          WHERE s.sk_id_prev = vc.sk_id_prev
      )
),
first_late AS (
    SELECT sk_id_prev, min(seasoning_month) AS first_30_plus_month
    FROM metrics.instalment_seasoning
    WHERE is_30_plus AND seasoning_month >= 0
    GROUP BY sk_id_prev
),
months AS (
    SELECT generate_series(0, 12) AS seasoning_month
)
SELECT
    e.vintage_label,
    m.seasoning_month,
    count(*)                                                           AS n_loans,
    round(
        count(*) FILTER (WHERE f.first_30_plus_month <= m.seasoning_month) * 100.0
        / count(*), 2
    )                                                                   AS pct_ever_30_plus
FROM eligible e
LEFT JOIN first_late f ON f.sk_id_prev = e.sk_id_prev
CROSS JOIN months m
GROUP BY e.vintage_label, m.seasoning_month
ORDER BY e.vintage_label, m.seasoning_month;

-- Validation (should return 0 rows — any row means the curve decreased):
-- SELECT a.vintage_label, a.seasoning_month
-- FROM metrics.vintage_curve a
-- JOIN metrics.vintage_curve b
--   ON a.vintage_label = b.vintage_label
--  AND b.seasoning_month = a.seasoning_month - 1
-- WHERE a.pct_ever_30_plus < b.pct_ever_30_plus;
