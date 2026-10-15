-- staging.stg_application
-- Cleaned subset of application_train for segmentation and scorecard work.
-- Fixes two known encoding quirks in the raw table:
--   - DAYS_BIRTH / DAYS_EMPLOYED are stored as negative day counts;
--     converted to positive years for readability.
--   - DAYS_EMPLOYED uses 365243 as a placeholder for "not currently
--     employed" (pensioners, unemployed) rather than a real value —
--     left raw, this badly skews any tenure-based feature. Nulled out
--     here and flagged separately.

CREATE OR REPLACE VIEW staging.stg_application AS
SELECT
    sk_id_curr,
    target,
    name_contract_type,
    code_gender,
    flag_own_car,
    flag_own_realty,
    cnt_children,
    cnt_fam_members,
    amt_income_total,
    amt_credit,
    amt_annuity,
    amt_goods_price,
    name_income_type,
    name_education_type,
    name_family_status,
    name_housing_type,
    occupation_type,
    organization_type,
    region_rating_client,
    ROUND(-days_birth / 365.25, 1)                                   AS age_years,
    CASE WHEN days_employed = 365243 THEN NULL
         ELSE ROUND(-days_employed / 365.25, 1)
    END                                                                AS employment_years,
    (days_employed = 365243)                                          AS is_not_employed,
    ext_source_1,
    ext_source_2,
    ext_source_3
FROM public.application_train;
