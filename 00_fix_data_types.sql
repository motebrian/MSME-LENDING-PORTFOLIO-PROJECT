-- sql/00_fix_data_types.sql
-- Repairs raw tables that were reimported with every column as text.
-- Run each step as its own statement in pgAdmin (select it, then F5).

-- ============================================================
-- STEP 1 - See the damage: all text columns currently in the raw tables
-- ============================================================
SELECT table_name, count(*) AS text_columns
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('application_train','bureau','credit_card_balance',
                     'installments_payments','pos_cash_balance','previous_application')
  AND data_type IN ('text','character varying')
GROUP BY table_name
ORDER BY table_name;

-- ============================================================
-- STEP 2 - OPTIONAL: only if the ALTER in step 3 fails with
-- "cannot alter type of a column used by a view or rule".
-- This drops the staging/metrics views, which you are rebuilding anyway.
-- ============================================================
-- DROP SCHEMA IF EXISTS metrics CASCADE;
-- DROP SCHEMA IF EXISTS staging CASCADE;

-- ============================================================
-- STEP 3 - Convert text columns to numeric (IDs to bigint).
-- A column converts only if every non-empty value looks numeric, so
-- genuine categorical columns stay text and print a KEPT AS TEXT notice
-- (see the Messages tab). Empty strings and 'nan' / 'null' / 'none'
-- become real NULLs. Without this, 'NaN' would cast to a numeric NaN,
-- which Postgres treats as larger than every number.
-- installments_payments has ~13.6M rows, so it can take a few minutes.
-- ============================================================
DO $$
DECLARE
    r        record;
    tgt      text;
    suffix   text;
    bad      bigint;
    tbls     text[] := ARRAY['application_train','bureau','credit_card_balance',
                             'installments_payments','pos_cash_balance','previous_application'];
    id_cols  text[] := ARRAY['sk_id_curr','sk_id_prev','sk_id_bureau'];
    num_re   text   := '^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$';
BEGIN
    FOR r IN
        SELECT table_name, column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = ANY (tbls)
          AND data_type IN ('text','character varying')
        ORDER BY table_name, ordinal_position
    LOOP
        EXECUTE format(
            'SELECT count(*) FROM public.%I WHERE %I IS NOT NULL '
            'AND lower(trim(%I)) NOT IN (%L,%L,%L,%L) AND trim(%I) !~ %L',
            r.table_name, r.column_name, r.column_name,
            '', 'nan', 'null', 'none', r.column_name, num_re
        ) INTO bad;

        IF bad > 0 THEN
            RAISE NOTICE 'KEPT AS TEXT  %.%  (% non-numeric values)', r.table_name, r.column_name, bad;
            CONTINUE;
        END IF;

        IF r.column_name = ANY (id_cols) THEN
            tgt := 'bigint';  suffix := '::numeric::bigint';
        ELSE
            tgt := 'numeric'; suffix := '::numeric';
        END IF;

        EXECUTE format(
            'ALTER TABLE public.%I ALTER COLUMN %I TYPE %s '
            'USING (CASE WHEN lower(trim(%I)) IN (%L,%L,%L,%L) THEN NULL ELSE trim(%I)%s END)',
            r.table_name, r.column_name, tgt, r.column_name,
            '', 'nan', 'null', 'none', r.column_name, suffix
        );
        RAISE NOTICE 'CONVERTED     %.%  ->  %', r.table_name, r.column_name, tgt;
    END LOOP;
END $$;

-- ============================================================
-- STEP 4 - What is still text? Should be categorical columns only.
-- ============================================================
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('application_train','bureau','credit_card_balance',
                     'installments_payments','pos_cash_balance','previous_application')
  AND data_type IN ('text','character varying')
ORDER BY table_name, column_name;

-- ============================================================
-- STEP 5 - Row counts. A reimport after a crash can be partial.
-- Kaggle's documented sizes, as far as I know:
--   application_train 307,511 | bureau 1,716,428 | credit_card_balance 3,840,312
--   installments_payments 13,605,401 | pos_cash_balance 10,001,358
--   previous_application 1,670,214
-- ============================================================
SELECT 'application_train' AS tbl, count(*) FROM public.application_train
UNION ALL SELECT 'bureau', count(*) FROM public.bureau
UNION ALL SELECT 'credit_card_balance', count(*) FROM public.credit_card_balance
UNION ALL SELECT 'installments_payments', count(*) FROM public.installments_payments
UNION ALL SELECT 'pos_cash_balance', count(*) FROM public.pos_cash_balance
UNION ALL SELECT 'previous_application', count(*) FROM public.previous_application;
