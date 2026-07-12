-- The reporting metrics, each as a view. Power BI reads these so the numbers match the SQL.
-- The definitions are written up in docs/calculation_framework.md.

USE LifeInsuranceDQ;
GO

-- Annualised premium income by product and channel (in-force policies only)
CREATE OR ALTER VIEW dw.vw_api AS
SELECT
    product,
    channel,
    COUNT(*)                                          AS policy_count,
    SUM(CASE WHEN payment_frequency = 'Annual'
             THEN monthly_premium ELSE monthly_premium * 12 END) AS annualised_premium_income
FROM dw.policies
WHERE status = 'In-Force' AND monthly_premium > 0
GROUP BY product, channel;
GO

-- Loss ratio = approved claims / earned premium, per product.
-- Only approved claims count, and only paid premiums count as earned.
CREATE OR ALTER VIEW dw.vw_loss_ratio AS
WITH earned AS (
    SELECT p.product, SUM(pr.amount) AS earned_premium
    FROM dw.premiums pr
    JOIN dw.policies p ON p.policy_id = pr.policy_id
    WHERE pr.status = 'Paid'
    GROUP BY p.product
),
incurred AS (
    SELECT p.product, SUM(cl.claim_amount) AS claims_paid
    FROM dw.claims cl
    JOIN dw.policies p ON p.policy_id = cl.policy_id
    WHERE cl.decision = 'Approved'
    GROUP BY p.product
)
SELECT
    e.product,
    e.earned_premium,
    ISNULL(i.claims_paid, 0)                                        AS claims_paid,
    CAST(100.0 * ISNULL(i.claims_paid,0) / NULLIF(e.earned_premium,0) AS DECIMAL(6,2)) AS loss_ratio_pct
FROM earned e
LEFT JOIN incurred i ON i.product = e.product;
GO

-- Lapse rate = lapsed policies / total policies, per product
CREATE OR ALTER VIEW dw.vw_lapse_rate AS
SELECT
    product,
    COUNT(*)                                                   AS total_policies,
    SUM(CASE WHEN status = 'Lapsed' THEN 1 ELSE 0 END)         AS lapsed_policies,
    CAST(100.0 * SUM(CASE WHEN status = 'Lapsed' THEN 1 ELSE 0 END)
         / NULLIF(COUNT(*),0) AS DECIMAL(5,2))                 AS lapse_rate_pct
FROM dw.policies
GROUP BY product;
GO

-- Persistency = share of a start-year that is still in force
CREATE OR ALTER VIEW dw.vw_persistency AS
SELECT
    YEAR(start_date)                                          AS cohort_year,
    COUNT(*)                                                  AS policies_written,
    SUM(CASE WHEN status = 'In-Force' THEN 1 ELSE 0 END)      AS still_in_force,
    CAST(100.0 * SUM(CASE WHEN status = 'In-Force' THEN 1 ELSE 0 END)
         / NULLIF(COUNT(*),0) AS DECIMAL(5,2))                AS persistency_pct
FROM dw.policies
WHERE start_date IS NOT NULL
GROUP BY YEAR(start_date);
GO

-- Claims count and average/total settlement by type and decision
CREATE OR ALTER VIEW dw.vw_claims_summary AS
SELECT
    claim_type,
    decision,
    COUNT(*)                    AS claim_count,
    AVG(claim_amount)           AS avg_claim_amount,
    SUM(claim_amount)           AS total_claim_amount
FROM dw.claims
GROUP BY claim_type, decision;
GO

-- One-row summary for the KPI cards on the dashboard
CREATE OR ALTER VIEW dw.vw_exec_summary AS
SELECT
    (SELECT COUNT(*) FROM dw.policies WHERE status = 'In-Force')                      AS inforce_policies,
    (SELECT SUM(sum_assured) FROM dw.policies WHERE status = 'In-Force')              AS total_exposure,
    (SELECT SUM(CASE WHEN payment_frequency='Annual' THEN monthly_premium
                     ELSE monthly_premium*12 END)
       FROM dw.policies WHERE status='In-Force' AND monthly_premium>0)               AS annual_premium_income,
    (SELECT CAST(100.0*SUM(CASE WHEN status='Lapsed' THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,2))
       FROM dw.policies)                                                             AS overall_lapse_rate_pct,
    (SELECT CAST(100.0*
             (SELECT SUM(claim_amount) FROM dw.claims WHERE decision='Approved') /
             NULLIF((SELECT SUM(amount) FROM dw.premiums WHERE status='Paid'),0) AS DECIMAL(6,2)))
                                                                                     AS overall_loss_ratio_pct;
GO

PRINT 'Views created (dw.vw_*).';
