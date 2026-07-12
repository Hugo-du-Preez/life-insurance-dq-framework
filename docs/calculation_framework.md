# Calculation Framework

Every management metric is defined once, here, and implemented as a SQL view in
`sql/03_calculation_framework.sql`. Power BI and Excel read these views rather
than re-deriving the logic, so finance, actuarial and IT all report off the same
definition.

> Change control: any change to a formula below must be made in this document
> **and** the corresponding view in the same commit, with a reviewer sign-off.

---

### Annualised Premium Income (API): `dw.vw_api`
**Definition:** Total in-force premium expressed on an annual basis.
**Formula:** `Σ (payment_frequency = 'Annual' ? monthly_premium : monthly_premium × 12)`
**Scope:** In-Force policies with a positive premium only.
**Why it matters:** Headline measure of the book's recurring revenue.

### Loss Ratio: `dw.vw_loss_ratio`
**Definition:** Approved claims incurred as a percentage of earned premium.
**Formula:** `100 × (Σ approved claim_amount) / (Σ paid premium amount)`, per product.
**Business rule:** Only claims with `decision = 'Approved'` are incurred; only
premium transactions with `status = 'Paid'` are earned.
**Why it matters:** Core profitability KPI; a ratio > 100% means claims exceed premium.

### Lapse Rate: `dw.vw_lapse_rate`
**Definition:** Share of policies that have lapsed.
**Formula:** `100 × (policies where status = 'Lapsed') / (total policies)`, per product.
**Why it matters:** Leading indicator of retention and future premium erosion.

### Persistency Rate: `dw.vw_persistency`
**Definition:** Share of a start-year cohort still In-Force.
**Formula:** `100 × (In-Force policies) / (policies written)`, grouped by `YEAR(start_date)`.
**Why it matters:** Standard industry retention measure by cohort.

### Claims Summary: `dw.vw_claims_summary`
**Definition:** Claim count, average and total settlement by type and decision.
**Formula:** `COUNT(*)`, `AVG(claim_amount)`, `SUM(claim_amount)` grouped by `claim_type, decision`.
**Why it matters:** Drives claims frequency and severity analysis.

### Executive Summary: `dw.vw_exec_summary`
Single-row KPI header for the dashboard: in-force policy count, total exposure
(Σ sum assured), annual premium income, overall lapse rate, overall loss ratio.

---

## Assumptions and limitations
- Earned premium is approximated by paid premium transactions. There is no
  unearned-premium reserve modelling, which is out of scope for an operational
  reporting layer.
- The data is synthetic, so the figures show how the framework works, not a real book.
- All amounts are in ZAR.
