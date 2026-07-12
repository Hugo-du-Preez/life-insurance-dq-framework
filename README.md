# Life Insurance Data Quality & Reporting Framework

A SQL Server project for a life-insurance book. It generates a synthetic
policy / premium / claims dataset, runs a set of data-quality checks against it,
defines the management metrics as SQL views, and reports on those views in
Power BI.

I built it to practise the parts of a data analyst role that show up in
insurance work: keeping data clean, writing checks that catch bad records, and
turning the results into a dashboard that a manager can read.

## Dashboard
[![Life insurance data-quality dashboard](https://res.cloudinary.com/dxrak5fdv/image/upload/v1783362890/Screenshot_2026-07-06_203415_rburjm.png)](https://app.powerbi.com/view?r=eyJrIjoiYjQ1Y2Y4NjYtMDkzYy00YWMyLWEwNWMtNWE4MmMyZGIzZWQ0IiwidCI6ImVhMWE5MDliLTY2MDAtNGEyNS04MmE1LTBjNmVkN2QwNTEzYiIsImMiOjl9)

**Links:** [Live Power BI report](https://app.powerbi.com/view?r=eyJrIjoiYjQ1Y2Y4NjYtMDkzYy00YWMyLWEwNWMtNWE4MmMyZGIzZWQ0IiwidCI6ImVhMWE5MDliLTY2MDAtNGEyNS04MmE1LTBjNmVkN2QwNTEzYiIsImMiOjl9) · [GitHub repository](https://github.com/Hugo-du-Preez/life-insurance-dq-framework)

## How it fits together
```
 01_setup_and_generate     ->  dw.customers / dw.policies / dw.premiums / dw.claims
                                (synthetic data, with some defects added on purpose)
 02_data_quality_checks     ->  dq.results   (10 checks, written to a scorecard table)
 03_calculation_framework   ->  dw.vw_*       (metric views used by Power BI)
```

- **Data quality checks** – 10 rules across Completeness, Validity, Uniqueness,
  Consistency and Accuracy, each with a severity and a pass rate.
- **Calculation views** – Loss Ratio, Lapse Rate, Persistency, Annualised Premium
  Income, and a claims summary, each defined once as a SQL view.
- **Docs** – a data dictionary, the rules catalogue, and the metric definitions
  are in `docs/`.
- **Power BI** – the dashboard reads the views directly, so the numbers match the SQL.
- **Process analysis** – an As-Is/To-Be map of the claims process that shows where the
  data-quality failures originate and redesigns the process to catch them at capture.
  See `docs/process_analysis.md`.

## Running it (SQL Server 2022 / Azure SQL)
Open the three scripts in SQL Server Management Studio and run them in order:

| Step | Script | What it does |
|---|---|---|
| 1 | `sql/01_setup_and_generate.sql` | Creates the database and generates the data in T-SQL |
| 2 | `sql/02_data_quality_checks.sql` | Runs the 10 checks and prints the scorecard |
| 3 | `sql/03_calculation_framework.sql` | Builds the `dw.vw_*` metric views |

Everything is generated inside SQL Server. There are no CSV files or Python to set up.

The Power BI report is in `Life_Insurance_Portfolio.pbix`. Open it in Power BI
Desktop and point it at your `LifeInsuranceDQ` database (Transform data > Data
source settings), then refresh.

## Example scorecard
The data is generated with a fixed number of defects added on purpose, so the
checks have something real to find. A typical run flags around 145 bad records
across ~5,000 policies and ~139,000 premium transactions:

| Rule | Dimension | Severity | Failed |
|---|---|---|---|
| DQ01 | Completeness | High | 16 |
| DQ02 | Completeness | Medium | 20 |
| DQ03 | Validity | Critical | 18 |
| DQ04 | Validity | High | 11 |
| DQ05 | Validity | High | 15 |
| DQ06 | Uniqueness | Critical | 1 |
| DQ07 | Consistency | Critical | 12 |
| DQ08 | Consistency | Medium | 18 |
| DQ09 | Accuracy | Critical | 4 |
| DQ10 | Accuracy | Medium | 30 |

The exact counts move a little each run because the data is random.

## Repository layout
```
sql/                          01 generate data · 02 quality checks · 03 metric views (T-SQL)
docs/                         data dictionary · rules catalogue · metric definitions · process analysis
docs/process/                 As-Is / To-Be BPMN diagrams (draw.io source + PNG)
Life_Insurance_Portfolio.pbix the Power BI report
```

## Docs
- [Data Dictionary](docs/data_dictionary.md)
- [Data Quality Rules](docs/data_quality_rules.md)
- [Calculation Framework](docs/calculation_framework.md)
- [Process Analysis (As-Is / To-Be)](docs/process_analysis.md)

## Tech
Microsoft SQL Server 2022 / Azure SQL (T-SQL), Power BI.

> The data is synthetic and generated locally. It does not represent any real policyholders.
