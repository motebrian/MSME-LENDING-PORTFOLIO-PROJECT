# Metrics Definitions

Reference for every metric used in this project — what it means, how it's
calculated, and what its limitations are. Read this before trusting a
number on the dashboard or in a report.

---

## Dataset scope

**Source:** Home Credit Default Risk (Kaggle) — consumer credit, used here
as a proxy for MSME lending analytics. Key limitations that affect every
metric below:

- **Dates are relative offsets**, not calendar dates (e.g. `DAYS_BIRTH`,
  `DAYS_INSTALMENT`). There's no true calendar vintage — cohort analysis
  uses relative application timing, not actual dates.
- **Consumer credit, not MSME.** Borrower and loan patterns won't
  perfectly reflect small-business lending behavior.
- **No outstanding-principal field** for installment loans. This is the
  single biggest constraint — see PAR definitions below.

**Tables excluded from this project:**
- `application_test` — Kaggle competition holdout set, no target column,
  not used.
- `bureau_balance` — optional monthly bureau snapshot table, excluded for
  scope reasons. Scorecard features are drawn from `bureau`,
  `application_train`, and internal repayment history only.

---

## DPD (Days Past Due)

**Definition:** how many days late a scheduled installment was paid,
relative to its due date.

**Formula:** `DAYS_ENTRY_PAYMENT - DAYS_INSTALMENT`
(both fields are relative day-offsets from `installments_payments`)

**Source:** `staging.stg_installments_payments.dpd`

**Interpretation:**
- `dpd <= 0` → paid on time or early
- `dpd > 0` → paid late, by that many days
- `dpd IS NULL` → no entry payment recorded. This can mean the
  installment isn't due yet, **or** it was never paid — the source data
  doesn't distinguish the two. Bucketed separately as
  `unpaid_or_pending` rather than assumed current or defaulted.

---

## DPD buckets

Applied at the instalment level (`stg_installments_payments.dpd_bucket`)
and at the loan level (`metrics.loan_level_dpd.worst_dpd_bucket`, using
the *worst* DPD ever recorded across all of a loan's installments).

| Bucket | Range |
|---|---|
| `current` | dpd ≤ 0 |
| `1-30` | 1–30 days late |
| `31-60` | 31–60 days late |
| `61-90` | 61–90 days late |
| `90+` | 90+ days late |
| `unpaid_or_pending` | no entry payment recorded |

A separate, coarser bucket set (`current` / `1-30` / `31-60` / `61-90` /
`90+`) is also applied directly to `sk_dpd` in `stg_pos_cash_balance` and
`stg_credit_card_balance`, using the source's own pre-computed DPD field
rather than deriving it.

---

## PAR30 / PAR60 / PAR90 (Portfolio At Risk)

**⚠ This is an estimate, not a true point-in-time PAR.** Standard PAR
measures the % of *currently outstanding balance* that is 30/60/90+ days
overdue, as of a snapshot date. This dataset has no outstanding-principal
field for installment loans, so that calculation isn't possible here.

**What's calculated instead:** the % of loans (or loan amount) that were
**ever** 30/60/90+ days late at any point in their history — a
historical/ever-delinquency measure, not a live balance-based one.

**Two versions, both in `sql/metrics/01_par_dpd.sql`:**

1. **By loan count** — simplest version:
   `(# loans ever 30+/60+/90+ days late) / (total loans) × 100`

2. **By amount** — closer to standard lender-facing PAR framing, but
   still a proxy: uses `SUM(AMT_INSTALMENT)` per loan as a stand-in for
   exposure, since no real outstanding balance exists.
   `(sum of instalment amount on ever-delinquent loans) / (total instalment amount) × 100`

**Source view:** `metrics.loan_level_dpd` (one row per `sk_id_prev`),
rolled up to `metrics.borrower_level_dpd` (one row per `sk_id_curr`) for
segmentation/scorecard use.

**When reporting these numbers:** always state "ever-delinquent" and
"amount-proxied" explicitly — don't present as standard point-in-time PAR
without the caveat.

---

## Utilization ratio

**Definition:** how much of a borrower's available credit-card limit is
currently drawn, per monthly snapshot.

**Formula:** `AMT_BALANCE / AMT_CREDIT_LIMIT_ACTUAL`

**Source:** `staging.stg_credit_card_balance.utilization_ratio`

**Handling:** divide-by-zero (accounts with a 0 limit) returns `NULL`
via `NULLIF`, not an error. A ratio above 1.0 is not necessarily an error
— cardholders can exceed their limit.

---

## Derived application fields

From `staging.stg_application`:

- **`age_years`** — `-DAYS_BIRTH / 365.25`, converted from the raw
  negative day-offset to a readable age.
- **`employment_years`** — `-DAYS_EMPLOYED / 365.25`, with one fix:
  Home Credit uses `365243` as a placeholder for "not currently
  employed" (pensioners, unemployed applicants) rather than a real
  value. This is nulled out and flagged separately via
  **`is_not_employed`**, rather than left in as a ~1000-year employment
  tenure.

From `staging.stg_previous_application`:

- **`is_approved`** — `NAME_CONTRACT_STATUS = 'Approved'`.
- The same `365243` placeholder pattern appears across several of this
  table's own `DAYS_*` fields (`DAYS_FIRST_DRAWING`, `DAYS_FIRST_DUE`,
  `DAYS_LAST_DUE_1ST_VERSION`, `DAYS_LAST_DUE`, `DAYS_TERMINATION`) and
  is nulled out the same way.

From `staging.stg_bureau`:

- **`amt_credit_sum_debt`** — left as `NULL` where the source has it
  `NULL`. This is a genuine gap in bureau reporting, not a placeholder —
  **not** coalesced to 0, since doing so would understate debt on
  affected records.

---

## Known limitations summary

- PAR is an ever-delinquency, amount-proxied estimate — not point-in-time.
- No true calendar vintages; cohort analysis uses relative timing only.
- Dataset is consumer credit, used as an MSME-lending proxy.
- `bureau_balance` and `application_test` are out of scope.
- `amt_credit_sum_debt` has real (unfilled) gaps in bureau data.
