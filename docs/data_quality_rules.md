# Data Quality Rules Catalogue

Ten validation rules, each mapped to a DAMA data-quality dimension and a
severity. Implemented in `sql/02_data_quality_checks.sql`, which logs every
result to `dq.results` and prints the scorecard.

Severity model: **Critical** failures block a data release, **High** must be
fixed within the reporting cycle, and **Medium** is logged and monitored.

| Rule | Dimension | Severity | Table | What it checks |
|---|---|---|---|---|
| DQ01 | Completeness | High | policies | `sum_assured` is populated |
| DQ02 | Completeness | Medium | customers | `gender` is populated |
| DQ03 | Validity | Critical | policies | `monthly_premium` > 0 |
| DQ04 | Validity | High | policies | `start_date` is not in the future |
| DQ05 | Validity | High | customers | Age is between 18 and 90 |
| DQ06 | Uniqueness | Critical | policies | `policy_id` is unique |
| DQ07 | Consistency | Critical | policies | Every policy's `customer_id` exists (referential integrity) |
| DQ08 | Consistency | Medium | customers | `province` is one of the 9 valid SA provinces |
| DQ09 | Accuracy | Critical | claims | `claim_amount` ≤ `sum_assured` |
| DQ10 | Accuracy | Medium | premiums | Paid premium equals the policy's `monthly_premium` |

## Scorecard output
Each run rebuilds the scorecard from scratch. The script truncates `dq.results`
first, so running it more than once never double-counts. For each rule it records
`records_checked`, `records_failed`, `pass_rate_pct`, a PASS/FAIL result and a
`checked_at` timestamp. If you wanted to track pass rates over time, you could
copy each run into a dated history table before the truncate.

The accuracy rules (DQ09, DQ10) look up the parent policy with `OUTER APPLY ... TOP 1`
instead of a plain join. This matters because the data contains a duplicate
`policy_id` on purpose (DQ06); a plain join would match it twice and overstate
the failure counts.

## How to extend
1. Add the rule definition as a row in the table above.
2. Add one `INSERT INTO dq.results …` block in `02_data_quality_checks.sql`.
3. Commit both together.
