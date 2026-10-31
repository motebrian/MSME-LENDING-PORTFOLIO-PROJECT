# MSME Lending Portfolio Analytics: Credit Risk Report

**By Mote the Analyst** | October 2026 |

---

## 1. Summary

I built an end-to-end credit risk analysis on 307,511 loan applicants from the Home Credit Default Risk dataset. The work runs from raw relational tables in PostgreSQL, through a SQL staging and metrics layer, to a three-page Power BI dashboard, with every metric defined in writing.

Headline results:

- **8.07%** of applicants defaulted, a 92/8 class split.
- **Portfolio at risk** (loans ever late, by count) is **2.32%** at 30+ days, **1.02%** at 60+ and **0.83%** at 90+.
- **Delinquency builds with loan age**, and the cohort originated five years before the reference date performs worst, reaching 5.45% ever-30+ by month 12.
- **Default rates vary sharply by borrower profile**: from 10.93% for applicants with lower secondary education to 1.83% for those with an academic degree.

The data is consumer credit standing in for MSME lending, and PAR is an ever-delinquent estimate. Section 7 covers these limits.

## 2. Business question

A lender running a loan book needs three answers:

1. How much of the book is paying late, and how late?
2. How does delinquency develop as loans age, and do newer loans behave differently from older ones?
3. Which borrower groups carry the most risk?

The dashboard answers one question per page.

## 3. Data and why I chose it

I used Home Credit Default Risk (Kaggle), with Lending Club and Kiva as the alternatives. Home Credit won for five reasons:

- **It is relational.** Seven linked tables mirror how a lender's data sits across applications, bureau records and repayment history, so the SQL layer does real joins.
- **DPD can be derived.** Instalment due dates and payment dates let me compute days past due myself instead of reading a pre-built status.
- **It has a default label**, which the scorecard stage needs.
- **It has volume**: 307,511 applicants and about 13.6 million instalments, enough for stable segment-level rates.
- **It is a public benchmark**, so anyone can check my numbers against other work.

The trade-off is that it describes consumer credit, not small-business lending. I used six tables: `application_train`, `previous_application`, `installments_payments`, `pos_cash_balance`, `credit_card_balance` and `bureau`. I excluded `application_test` (no target label) and `bureau_balance` (not needed for the metrics here).

## 4. What I built

**Pipeline:** raw tables in PostgreSQL, then six staging views (`staging.stg_*`), then a metrics layer (`metrics.*`), then Power BI.

**Data preparation**
- Corrected the schema of each raw table: missing columns, undersized text fields, integer columns that held missing values, and column-name typos. After a reimport left every column as text, I wrote a script that restores numeric types and keeps genuine categoricals as text.
- Cleaned encoding quirks in the staging views. Home Credit uses `365243` as a placeholder for "not currently employed" (and in several date fields of `previous_application`). I set it to missing and flagged it separately, because left in place it reads as a 1,000-year employment tenure.
- Converted day offsets into age and employment years.

**Metrics layer**
- Days past due per instalment (payment day minus due day), with buckets: current, 1-30, 31-60, 61-90, 90+, and unpaid or pending.
- Loan-level and borrower-level delinquency rollups.
- Vintage curves: loans grouped by origination cohort and tracked over their first 12 months.

**Exploratory analysis** in a Python notebook, with database credentials kept in a gitignored `.env` file.

## 5. Metric definitions

Full definitions are in `docs/metrics_definitions.md`. The three that matter most:

- **DPD** is the payment day minus the due day for each instalment. A positive value means late.
- **PAR30/60/90** is the share of loans that were ever 30, 60 or 90+ days late. It counts loans, not balances.
- **Vintage curve** is the cumulative share of loans in a cohort that have been 30+ days late by each month since origination. Each cohort has a fixed set of loans, so the curve can only rise.

## 6. Findings

### 6.1 Portfolio overview

![Overview page](images/page1_overview.png)

- Only 8.07% of applicants defaulted (24,825 of 307,511). At that imbalance, accuracy is a useless model metric, so the scorecard will be judged on KS, Gini and PSI.
- About 92% of instalments were paid on time or early. Late instalments are concentrated in the 1-30 day bucket, and the 31-60, 61-90 and 90+ buckets together hold well under 1% of instalments.
- PAR falls from 2.32% at 30+ days to 0.83% at 90+. Of loans that were ever 60+ days late, about 81% were also ever 90+ days late (0.83% of 1.02%). Once a loan is two months behind, it rarely recovers.

### 6.2 Vintage analysis

![Vintage page](images/page2_vintage.png)

- Delinquency accumulates with loan age in every cohort.
- At 12 months, cumulative 30+ day delinquency is 0.67% for the cohort originated one year before the reference date (Y-1), rising to 1.22% (Y-2), 1.81% (Y-3), 2.56% (Y-4) and 5.45% (Y-5). It then falls to 4.14% (Y-6), 3.84% (Y-7) and 3.02% (Y-8).
- The data cannot separate two explanations: weaker underwriting in older cohorts, or a different mix of loan products. Dates are relative, so I can't tie cohorts to calendar events.

### 6.3 Borrower risk profile

![Borrower page](images/page3_borrowers.png)

- **Education:** default falls as education rises: 10.93% (lower secondary), 8.94% (secondary), 8.48% (incomplete higher), 5.36% (higher education), 1.83% (academic degree).
- **Family status:** civil marriage (9.94%) and single (9.81%) sit above married (7.56%) and widow (5.82%).
- **Income type:** working applicants default at 9.59%, commercial associates at 7.48% and state servants at 5.75%. Segments under 100 applicants are excluded, because a few applicants produce extreme rates.
- **Income distribution:** median income is 147,150, with a long right tail. Three applicants report income above 10 million, which I treat as data artifacts. I cap income at the 99th percentile for clustering and leave it unchanged for scorecard binning, where it falls into the top bin.

## 7. Limitations

- **Consumer credit, not MSME.** Small-business borrowers behave differently, so treat the patterns as illustrative of the method.
- **Relative dates.** Offsets from a reference point replace calendar dates, so "vintage" means years before application, not calendar years.
- **PAR is an estimate.** There is no outstanding-balance field, so PAR here means "ever late", counted by loan, not a point-in-time share of balances.
- **Mixed units.** The dashboard counts applicants (default rate), loans (PAR) and instalments (DPD distribution). Each visual is labelled with its unit.
- **Small segments** are excluded from the segment charts.

## 8. What a lender would do with this

- **Escalate at 60 days.** With 81% of 60+ day loans later reaching 90+, collection effort at 60 days targets loans unlikely to cure on their own.
- **Watch 12-month delinquency by cohort.** The vintage curve gives an early read on whether a new cohort tracks above or below older ones.
- **Treat education and family status as screening signals** and confirm them in the scorecard before using them in any decision.

## 9. Next steps

- Risk watchlist page: loans currently 61-90 or 90+ days late, filterable by borrower.
- Borrower segmentation (RFM and k-means).
- Data quality checks, tested against injected errors.
- Scorecard prototype: WoE binning, logistic regression versus gradient boosting, KS/Gini/PSI.
- Data dictionary, SQL snippet library and sample weekly and monthly lender reports.

## Appendix: repository layout

```
msme-portfolio-analytics/
├── sql/            staging views, metrics layer, type-repair script
├── notebooks/      01_eda
├── dashboards/     Power BI file and screenshots
├── docs/           metrics_definitions.md, this report
└── data/           gitignored; raw CSVs stay local
```

To reproduce: load the six CSVs into PostgreSQL, run `sql/00_fix_data_types.sql`, then the staging and metrics scripts in order, then refresh the Power BI file.
