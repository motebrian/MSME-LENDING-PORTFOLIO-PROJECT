-- staging.stg_previous_application
-- One row per prior Home Credit application. Nulls out the same
-- 365243 placeholder trick found on DAYS_EMPLOYED in application_train —
-- here it shows up across several DAYS_* columns tied to loans that
-- never drew down or never had a final due date.

CREATE OR REPLACE VIEW staging.stg_previous_application AS
SELECT
    sk_id_prev,
    sk_id_curr,
    name_contract_type,
    amt_application,
    amt_credit,
    name_contract_status,
    (name_contract_status = 'Approved')                              AS is_approved,
    CASE WHEN days_first_drawing = 365243 THEN NULL ELSE days_first_drawing END        AS days_first_drawing,
    CASE WHEN days_first_due = 365243 THEN NULL ELSE days_first_due END                AS days_first_due,
    CASE WHEN days_last_due_1st_version = 365243 THEN NULL ELSE days_last_due_1st_version END AS days_last_due_1st_version,
    CASE WHEN days_last_due = 365243 THEN NULL ELSE days_last_due END                  AS days_last_due,
    CASE WHEN days_termination = 365243 THEN NULL ELSE days_termination END            AS days_termination,
    days_decision                                                     -- loan origination, relative days before current application — needed for vintage cohorts
FROM public.previous_application;
