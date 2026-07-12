# Data Dictionary

The tables below are the `dw.*` tables created by `sql/01_setup_and_generate.sql`.
The data is synthetic and generated in T-SQL.

## dw.customers: one row per insured life
| Column | Type | Description | Business rules |
|---|---|---|---|
| customer_id | VARCHAR | Unique customer key | Primary key |
| date_of_birth | DATE | Date of birth | Age must be 18–90 (DQ05) |
| gender | VARCHAR | M / F | Should be populated (DQ02) |
| smoker_status | VARCHAR | Smoker / Non-Smoker | Rating factor |
| province | VARCHAR | SA province of residence | Must be one of 9 valid provinces (DQ08) |

## dw.policies: one row per policy
| Column | Type | Description | Business rules |
|---|---|---|---|
| policy_id | VARCHAR | Unique policy key | Primary key, unique (DQ06) |
| customer_id | VARCHAR | FK to customers | Must exist (DQ07) |
| product | VARCHAR | Life / Funeral / Disability / Critical Illness / Credit Life | |
| channel | VARCHAR | Distribution channel | |
| status | VARCHAR | In-Force / Lapsed / Cancelled / Claimed | Drives lapse & persistency |
| start_date | DATE | Policy commencement | Not in the future (DQ04) |
| sum_assured | DECIMAL | Cover amount (ZAR) | Populated (DQ01); caps claims (DQ09) |
| monthly_premium | DECIMAL | Premium per month (ZAR) | Must be > 0 (DQ03) |
| payment_frequency | VARCHAR | Monthly / Annual | Drives API annualisation |

## dw.premiums: one row per premium transaction
| Column | Type | Description | Business rules |
|---|---|---|---|
| payment_id | VARCHAR | Unique payment key | Primary key |
| policy_id | VARCHAR | FK to policies | |
| payment_date | DATE | Date premium was due/paid | |
| amount | DECIMAL | Amount paid (ZAR) | If Paid, must match policy premium (DQ10) |
| status | VARCHAR | Paid / Missed | Missed = arrears indicator |

## dw.claims: one row per claim
| Column | Type | Description | Business rules |
|---|---|---|---|
| claim_id | VARCHAR | Unique claim key | Primary key |
| policy_id | VARCHAR | FK to policies | |
| claim_date | DATE | Date of claim | |
| claim_type | VARCHAR | Death / Disability / Critical Illness / Retrenchment | |
| claim_amount | DECIMAL | Settlement amount (ZAR) | Must not exceed sum assured (DQ09) |
| decision | VARCHAR | Approved / Repudiated / Pending | Only Approved counts toward loss ratio |
