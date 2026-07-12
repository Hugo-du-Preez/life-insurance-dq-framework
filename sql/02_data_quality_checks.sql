-- Runs 10 data-quality checks and writes the results to dq.results.
-- Each check counts how many rows it looked at and how many failed.
-- Run 01_setup_and_generate.sql first.

USE LifeInsuranceDQ;
GO

-- Clear the table first so running this more than once doesn't stack up old results.
TRUNCATE TABLE dq.results;
DECLARE @run_id INT = 1;

-- DQ01  sum assured should be filled in
INSERT INTO dq.results (run_id, rule_id, rule_name, dimension, severity, table_name, records_checked, records_failed)
SELECT @run_id, 'DQ01', 'Sum assured is populated', 'Completeness', 'High', 'dw.policies',
       COUNT(*), SUM(CASE WHEN sum_assured IS NULL THEN 1 ELSE 0 END)
FROM dw.policies;

-- DQ02  gender should be filled in
INSERT INTO dq.results (run_id, rule_id, rule_name, dimension, severity, table_name, records_checked, records_failed)
SELECT @run_id, 'DQ02', 'Customer gender is populated', 'Completeness', 'Medium', 'dw.customers',
       COUNT(*), SUM(CASE WHEN gender IS NULL THEN 1 ELSE 0 END)
FROM dw.customers;

-- DQ03  premium has to be greater than zero
INSERT INTO dq.results (run_id, rule_id, rule_name, dimension, severity, table_name, records_checked, records_failed)
SELECT @run_id, 'DQ03', 'Monthly premium is positive', 'Validity', 'Critical', 'dw.policies',
       COUNT(*), SUM(CASE WHEN monthly_premium IS NULL OR monthly_premium <= 0 THEN 1 ELSE 0 END)
FROM dw.policies;

-- DQ04  a policy can't start in the future
INSERT INTO dq.results (run_id, rule_id, rule_name, dimension, severity, table_name, records_checked, records_failed)
SELECT @run_id, 'DQ04', 'Policy start date is not in the future', 'Validity', 'High', 'dw.policies',
       COUNT(*), SUM(CASE WHEN start_date > CAST(SYSUTCDATETIME() AS DATE) THEN 1 ELSE 0 END)
FROM dw.policies;

-- DQ05  age should sit between 18 and 90
INSERT INTO dq.results (run_id, rule_id, rule_name, dimension, severity, table_name, records_checked, records_failed)
SELECT @run_id, 'DQ05', 'Customer age is within 18-90', 'Validity', 'High', 'dw.customers',
       COUNT(*),
       SUM(CASE WHEN date_of_birth IS NULL
                  OR DATEDIFF(YEAR, date_of_birth, CAST(SYSUTCDATETIME() AS DATE)) NOT BETWEEN 18 AND 90
                THEN 1 ELSE 0 END)
FROM dw.customers;

-- DQ06  policy_id should be unique (count the extra copies)
INSERT INTO dq.results (run_id, rule_id, rule_name, dimension, severity, table_name, records_checked, records_failed)
SELECT @run_id, 'DQ06', 'Policy ID is unique', 'Uniqueness', 'Critical', 'dw.policies',
       COUNT(*),
       (SELECT ISNULL(SUM(dup),0) FROM (SELECT COUNT(*) - 1 AS dup FROM dw.policies GROUP BY policy_id HAVING COUNT(*) > 1) d)
FROM dw.policies;

-- DQ07  every policy should point to a customer that exists
INSERT INTO dq.results (run_id, rule_id, rule_name, dimension, severity, table_name, records_checked, records_failed)
SELECT @run_id, 'DQ07', 'Policy customer exists (referential integrity)', 'Consistency', 'Critical', 'dw.policies',
       COUNT(*), SUM(CASE WHEN c.customer_id IS NULL THEN 1 ELSE 0 END)
FROM dw.policies p
LEFT JOIN dw.customers c ON c.customer_id = p.customer_id;

-- DQ08  province has to be one of the 9 real ones
INSERT INTO dq.results (run_id, rule_id, rule_name, dimension, severity, table_name, records_checked, records_failed)
SELECT @run_id, 'DQ08', 'Province is a valid SA province', 'Consistency', 'Medium', 'dw.customers',
       COUNT(*),
       SUM(CASE WHEN province NOT IN ('Gauteng','Western Cape','KwaZulu-Natal','Eastern Cape',
                                      'Free State','Limpopo','Mpumalanga','North West','Northern Cape')
                THEN 1 ELSE 0 END)
FROM dw.customers;

-- DQ09  a claim shouldn't be larger than the cover.
-- OUTER APPLY ... TOP 1 grabs one policy per claim, so the duplicate policy_id from DQ06 doesn't get counted twice.
INSERT INTO dq.results (run_id, rule_id, rule_name, dimension, severity, table_name, records_checked, records_failed)
SELECT @run_id, 'DQ09', 'Claim amount does not exceed sum assured', 'Accuracy', 'Critical', 'dw.claims',
       COUNT(*), SUM(CASE WHEN cl.claim_amount > p.sum_assured THEN 1 ELSE 0 END)
FROM dw.claims cl
OUTER APPLY (SELECT TOP 1 sum_assured FROM dw.policies p WHERE p.policy_id = cl.policy_id) p;

-- DQ10  a paid premium should match the policy's monthly premium (same TOP 1 trick as DQ09)
INSERT INTO dq.results (run_id, rule_id, rule_name, dimension, severity, table_name, records_checked, records_failed)
SELECT @run_id, 'DQ10', 'Paid premium matches policy premium', 'Accuracy', 'Medium', 'dw.premiums',
       COUNT(*),
       SUM(CASE WHEN pr.status = 'Paid' AND ABS(pr.amount - p.monthly_premium) > 0.01 THEN 1 ELSE 0 END)
FROM dw.premiums pr
OUTER APPLY (SELECT TOP 1 monthly_premium FROM dw.policies p WHERE p.policy_id = pr.policy_id) p;
GO

-- show the scorecard, worst severity first
;WITH latest AS (
    SELECT * FROM dq.results WHERE run_id = (SELECT MAX(run_id) FROM dq.results)
)
SELECT
    rule_id, rule_name, dimension, severity, records_checked, records_failed,
    CAST(100.0 * (records_checked - records_failed) / NULLIF(records_checked,0) AS DECIMAL(5,2)) AS pass_rate_pct,
    CASE WHEN records_failed = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM latest
ORDER BY CASE severity WHEN 'Critical' THEN 1 WHEN 'High' THEN 2 ELSE 3 END, records_failed DESC;
