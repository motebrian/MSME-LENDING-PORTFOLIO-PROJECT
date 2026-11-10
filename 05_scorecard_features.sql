-- metrics/05_scorecard_features.sql
--
-- One row per applicant: the label plus candidate features for the scorecard.
-- Built as a table (a snapshot) so every modelling run sees identical data.
--
-- Prerequisites: staging.stg_application and metrics.borrower_rfm
--                (sql/staging/02 and sql/metrics/04).
--
-- LEAKAGE RULES (features must be known on the application date)
--   * Application columns are application-time attributes.
--   * History from prior loans comes only from loans decided before the
--     application (days_decision <= 0, enforced in metrics.borrower_rfm).
--   * Instalment history counts only payments made on or before the
--     application date (days_entry_payment <= 0).
--   * Bureau history counts only credits opened on or before the
--     application date (days_credit <= 0).
--   * Gender is NOT selected: it should not drive a credit decision.
--
-- Applicants with no prior loans, instalments or bureau record keep NULLs
-- in those columns. The scorecard treats "no record" as its own bin.

DROP TABLE IF EXISTS metrics.scorecard_features;

CREATE TABLE metrics.scorecard_features AS
WITH prior AS (
    SELECT sk_id_curr,
           frequency      AS prior_loans_approved,
           recency_days   AS prior_recency_days,
           monetary       AS prior_total_credit
    FROM metrics.borrower_rfm
),
paid AS (
    SELECT sk_id_curr,
           count(*)                                                         AS prior_instalments_paid,
           avg((days_entry_payment > days_instalment)::int)                 AS prior_late_share,
           max(days_entry_payment - days_instalment)                        AS prior_max_dpd
    FROM public.installments_payments
    WHERE days_entry_payment IS NOT NULL
      AND days_entry_payment <= 0
    GROUP BY sk_id_curr
),
bur AS (
    SELECT sk_id_curr,
           count(*)                                                         AS bureau_n_credits,
           count(*) FILTER (WHERE credit_active = 'Active')                 AS bureau_n_active,
           max(credit_day_overdue)                                          AS bureau_max_overdue_days
    FROM public.bureau
    WHERE days_credit <= 0
    GROUP BY sk_id_curr
)
SELECT
    a.sk_id_curr,
    a.target,

    -- categorical application attributes (no gender)
    a.name_contract_type,
    a.name_income_type,
    a.name_education_type,
    a.name_family_status,
    a.name_housing_type,
    a.occupation_type,
    a.organization_type,
    a.flag_own_car,
    a.flag_own_realty,

    -- external scores
    a.ext_source_1,
    a.ext_source_2,
    a.ext_source_3,

    -- amounts
    a.amt_income_total,
    a.amt_credit,
    a.amt_annuity,
    a.amt_goods_price,

    -- time-based attributes, converted from negative day offsets to years
    s.age_years,
    s.employment_years,                                         -- 365243 placeholder already nulled in staging
    round(-a.days_registration / 365.25, 2)       AS years_since_registration,
    round(-a.days_id_publish / 365.25, 2)         AS years_since_id_change,
    round(-a.days_last_phone_change / 365.25, 2)  AS years_since_phone_change,

    -- household and region
    a.own_car_age,
    a.cnt_children,
    a.cnt_fam_members,
    a.region_population_relative,
    a.region_rating_client_w_city,
    a.obs_30_cnt_social_circle,
    a.def_30_cnt_social_circle,
    a.amt_req_credit_bureau_year,

    -- affordability ratios
    a.amt_credit  / nullif(a.amt_income_total, 0) AS credit_income_ratio,
    a.amt_annuity / nullif(a.amt_income_total, 0) AS annuity_income_ratio,
    a.amt_credit  / nullif(a.amt_annuity, 0)      AS credit_term_months,
    a.amt_credit  / nullif(a.amt_goods_price, 0)  AS credit_goods_ratio,

    -- prior borrowing with Home Credit
    pr.prior_loans_approved,
    pr.prior_recency_days,
    pr.prior_total_credit,
    pd.prior_instalments_paid,
    pd.prior_late_share,
    pd.prior_max_dpd,

    -- external credit bureau history
    b.bureau_n_credits,
    b.bureau_n_active,
    b.bureau_max_overdue_days
FROM public.application_train a
JOIN staging.stg_application s ON s.sk_id_curr = a.sk_id_curr
LEFT JOIN prior pr ON pr.sk_id_curr = a.sk_id_curr
LEFT JOIN paid  pd ON pd.sk_id_curr = a.sk_id_curr
LEFT JOIN bur   b  ON b.sk_id_curr  = a.sk_id_curr;

ALTER TABLE metrics.scorecard_features ADD PRIMARY KEY (sk_id_curr);
ANALYZE metrics.scorecard_features;

-- Checks (run separately):
-- SELECT count(*), round(avg(target) * 100, 2) AS default_rate_pct FROM metrics.scorecard_features;   -- 307,511 rows, 8.07
-- SELECT round(100.0 * count(*) FILTER (WHERE ext_source_1 IS NULL) / count(*), 1) AS ext1_missing_pct,
--        round(100.0 * count(*) FILTER (WHERE prior_late_share IS NULL) / count(*), 1) AS no_paid_history_pct,
--        round(100.0 * count(*) FILTER (WHERE bureau_n_credits IS NULL) / count(*), 1) AS no_bureau_pct
-- FROM metrics.scorecard_features;
