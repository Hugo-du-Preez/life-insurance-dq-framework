-- Creates the database and generates the synthetic data in T-SQL.
-- Some data-quality problems are added on purpose so script 02 has things to catch.
-- SQL Server 2022 / Azure SQL. Run this, then 02, then 03.

IF DB_ID('LifeInsuranceDQ') IS NULL CREATE DATABASE LifeInsuranceDQ;
GO
USE LifeInsuranceDQ;
GO
IF SCHEMA_ID('dw') IS NULL EXEC('CREATE SCHEMA dw');
IF SCHEMA_ID('dq') IS NULL EXEC('CREATE SCHEMA dq');
GO

-- No constraints on these tables, otherwise the bad rows below wouldn't load.
DROP TABLE IF EXISTS dw.premiums;
DROP TABLE IF EXISTS dw.claims;
DROP TABLE IF EXISTS dw.policies;
DROP TABLE IF EXISTS dw.customers;

CREATE TABLE dw.customers (
    customer_id   VARCHAR(10),
    date_of_birth DATE,
    gender        VARCHAR(10),
    smoker_status VARCHAR(20),
    province      VARCHAR(50)
);
CREATE TABLE dw.policies (
    policy_id         VARCHAR(10),
    customer_id       VARCHAR(10),
    product           VARCHAR(30),
    channel           VARCHAR(30),
    status            VARCHAR(20),
    start_date        DATE,
    sum_assured       DECIMAL(14,2),
    monthly_premium   DECIMAL(14,2),
    payment_frequency VARCHAR(10)
);
CREATE TABLE dw.premiums (
    payment_id   VARCHAR(12),
    policy_id    VARCHAR(10),
    payment_date DATE,
    amount       DECIMAL(14,2),
    status       VARCHAR(10)
);
CREATE TABLE dw.claims (
    claim_id     VARCHAR(12),
    policy_id    VARCHAR(10),
    claim_date   DATE,
    claim_type   VARCHAR(30),
    claim_amount DECIMAL(14,2),
    decision     VARCHAR(15)
);

DROP TABLE IF EXISTS dq.results;
CREATE TABLE dq.results (
    run_id          INT,
    rule_id         VARCHAR(20),
    rule_name       VARCHAR(200),
    dimension       VARCHAR(50),
    severity        VARCHAR(20),
    table_name      VARCHAR(50),
    records_checked BIGINT,
    records_failed  BIGINT,
    checked_at      DATETIME2 DEFAULT SYSUTCDATETIME()
);
GO

-- 4,000 customers. ABS(CHECKSUM(NEWID())) gives a random int per row.
INSERT dw.customers (customer_id, date_of_birth, gender, smoker_status, province)
SELECT
    'C' + RIGHT('00000' + CAST(g.value AS VARCHAR(5)), 5),
    DATEADD(DAY, -(ABS(CHECKSUM(NEWID())) % 365),
        DATEADD(YEAR, -(18 + ABS(CHECKSUM(NEWID())) % 58), '2026-07-01')),
    CASE WHEN ABS(CHECKSUM(NEWID())) % 2 = 0 THEN 'M' ELSE 'F' END,
    CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 75 THEN 'Non-Smoker' ELSE 'Smoker' END,
    CASE ABS(CHECKSUM(NEWID())) % 9
        WHEN 0 THEN 'Gauteng'      WHEN 1 THEN 'Western Cape' WHEN 2 THEN 'KwaZulu-Natal'
        WHEN 3 THEN 'Eastern Cape' WHEN 4 THEN 'Free State'   WHEN 5 THEN 'Limpopo'
        WHEN 6 THEN 'Mpumalanga'   WHEN 7 THEN 'North West'   ELSE 'Northern Cape' END
FROM GENERATE_SERIES(1, 4000) AS g;

-- 5,000 policies. Premium is roughly 0.05%-0.15% of the sum assured per month.
INSERT dw.policies (policy_id, customer_id, product, channel, status,
                    start_date, sum_assured, monthly_premium, payment_frequency)
SELECT
    'P' + RIGHT('000000' + CAST(g.value AS VARCHAR(6)), 6),
    'C' + RIGHT('00000' + CAST(1 + ABS(CHECKSUM(NEWID())) % 4000 AS VARCHAR(5)), 5),
    CASE ABS(CHECKSUM(NEWID())) % 5
        WHEN 0 THEN 'Life Cover'    WHEN 1 THEN 'Funeral Cover' WHEN 2 THEN 'Disability Cover'
        WHEN 3 THEN 'Critical Illness' ELSE 'Credit Life' END,
    CASE ABS(CHECKSUM(NEWID())) % 5
        WHEN 0 THEN 'Broker' WHEN 1 THEN 'Direct' WHEN 2 THEN 'Bancassurance'
        WHEN 3 THEN 'Tied Agent' ELSE 'Online' END,
    CASE WHEN r.p < 70 THEN 'In-Force' WHEN r.p < 88 THEN 'Lapsed'
         WHEN r.p < 95 THEN 'Cancelled' ELSE 'Claimed' END,
    DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 3805, '2016-01-01'),
    sa.sum_assured,
    CAST(sa.sum_assured * (5 + ABS(CHECKSUM(NEWID())) % 11) / 10000.0 AS DECIMAL(14,2)),
    CASE WHEN ABS(CHECKSUM(NEWID())) % 4 = 0 THEN 'Annual' ELSE 'Monthly' END
FROM GENERATE_SERIES(1, 5000) AS g
CROSS APPLY (VALUES (ABS(CHECKSUM(NEWID())) % 100)) AS r(p)
CROSS APPLY (VALUES (CAST(20000 + ABS(CHECKSUM(NEWID())) % 1980000 AS DECIMAL(14,2)))) AS sa(sum_assured);

-- 12-48 monthly payments per policy (skip cancelled ones). About 8% come back as missed.
-- The count is keyed on policy_id, not NEWID(), so a re-run generates the same number of rows.
INSERT dw.premiums (payment_id, policy_id, payment_date, amount, status)
SELECT
    'PAY' + RIGHT('0000000' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS VARCHAR(7)), 7),
    p.policy_id,
    DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 912, '2024-01-01'),
    CASE WHEN rnd.r < 8 THEN 0 ELSE p.monthly_premium END,
    CASE WHEN rnd.r < 8 THEN 'Missed' ELSE 'Paid' END
FROM dw.policies p
CROSS APPLY GENERATE_SERIES(1, 12 + ABS(CHECKSUM(p.policy_id)) % 37) AS n
CROSS APPLY (VALUES (ABS(CHECKSUM(NEWID())) % 100)) AS rnd(r)
WHERE p.status <> 'Cancelled';

-- One claim per claimed policy, sized at 20-60% of the cover.
INSERT dw.claims (claim_id, policy_id, claim_date, claim_type, claim_amount, decision)
SELECT
    'CLM' + RIGHT('000000' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS VARCHAR(6)), 6),
    p.policy_id,
    DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 912, '2024-01-01'),
    CASE ABS(CHECKSUM(NEWID())) % 4
        WHEN 0 THEN 'Death' WHEN 1 THEN 'Disability'
        WHEN 2 THEN 'Critical Illness' ELSE 'Retrenchment' END,
    CAST(p.sum_assured * (20 + ABS(CHECKSUM(NEWID())) % 41) / 100.0 AS DECIMAL(14,2)),
    CASE WHEN ABS(CHECKSUM(NEWID())) % 100 < 75 THEN 'Approved'
         WHEN ABS(CHECKSUM(NEWID())) % 100 < 90 THEN 'Repudiated' ELSE 'Pending' END
FROM dw.policies p
WHERE p.status = 'Claimed';
GO

-- Now break some rows on purpose. Each one maps to a check in script 02.
UPDATE TOP (15) dw.policies SET sum_assured = NULL;                               -- DQ01 missing sum assured
UPDATE TOP (20) dw.customers SET gender = NULL;                                   -- DQ02 missing gender
UPDATE TOP (18) dw.policies SET monthly_premium = -ABS(monthly_premium)
    WHERE status = 'Cancelled';                                                  -- DQ03 negative premium (cancelled, so no premium rows are hit)
UPDATE TOP (10) dw.policies SET start_date = '2027-03-01';                        -- DQ04 future start date
UPDATE TOP (15) dw.customers SET date_of_birth = '2030-01-01';                    -- DQ05 impossible age
INSERT dw.policies SELECT TOP (1) * FROM dw.policies ORDER BY policy_id;          -- DQ06 duplicate policy_id
INSERT dw.policies (policy_id, customer_id, product, channel, status, start_date,
                    sum_assured, monthly_premium, payment_frequency)             -- DQ07 policies with a customer that doesn't exist
SELECT 'P9' + RIGHT('00000' + CAST(g.value AS VARCHAR(5)), 5),
       'C99999', 'Life Cover', 'Broker', 'In-Force', '2023-06-01',
       500000, 350.00, 'Monthly'
FROM GENERATE_SERIES(1, 12) AS g;
UPDATE TOP (18) dw.customers                                                     -- DQ08 province not on the valid list
SET province = CASE ABS(CHECKSUM(NEWID())) % 4
                   WHEN 0 THEN 'Unknown' WHEN 1 THEN 'XX'
                   WHEN 2 THEN 'Gautng'  ELSE 'Cape Town' END;
UPDATE TOP (8) dw.claims SET claim_amount = claim_amount * 3;                     -- DQ09 claim bigger than the cover
UPDATE TOP (30) dw.premiums SET amount = amount + 250 WHERE status = 'Paid';      -- DQ10 paid amount doesn't match the premium
GO

-- row counts
SELECT 'customers' AS table_name, COUNT(*) AS rows FROM dw.customers
UNION ALL SELECT 'policies', COUNT(*) FROM dw.policies
UNION ALL SELECT 'premiums', COUNT(*) FROM dw.premiums
UNION ALL SELECT 'claims',   COUNT(*) FROM dw.claims;
PRINT 'Data generated. Now run 02_data_quality_checks.sql';
