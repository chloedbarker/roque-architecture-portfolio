-- Auto Athenium | Pre-implementation checks from dq_rules.txt
-- Run one statement at a time. See the document for interpretation.
-- Start with A (observed dates), F/G (audit match coverage), and H (employee IDs).
-- Confirm schedule, audit-cycle mapping and ID definitions with the owners.

-- Check A: Run Schedule (Rules 6 and 9)
SELECT
    CAST(process_date AS DATE) AS process_date,
    DAY_OF_WEEK(CAST(process_date AS DATE)) AS day_of_week,
    COUNT(*) AS row_count
FROM uw_analytics.new_business_randomization_hist
WHERE CAST(process_date AS DATE) >= CURRENT_DATE - INTERVAL '30' DAY
GROUP BY CAST(process_date AS DATE), DAY_OF_WEEK(CAST(process_date AS DATE))
ORDER BY process_date DESC;

-- Check B: Date Range of Each Table (Rules 1, 2, 3 and 5)
SELECT 'audit_mart_hist' AS table_name,
       CAST(MIN(process_date) AS VARCHAR) AS first_date,
       CAST(MAX(process_date) AS VARCHAR) AS last_date
FROM uw_analytics.new_business_audit_mart_hist
UNION ALL
SELECT 'audit_hist',
       CAST(MIN(process_date) AS VARCHAR),
       CAST(MAX(process_date) AS VARCHAR)
FROM uw_analytics.new_business_audit_hist
UNION ALL
SELECT 'randomization_hist',
       CAST(MIN(process_date) AS VARCHAR),
       CAST(MAX(process_date) AS VARCHAR)
FROM uw_analytics.new_business_randomization_hist;

-- Check C: Missing Transaction Numbers by Source (Rule 2)
SELECT
    data_source,
    COUNT(DISTINCT policynumber) AS policies,
    COUNT(DISTINCT CASE WHEN transaction_number IS NULL THEN policynumber END) AS policies_missing_txn_number
FROM uw_analytics.new_business_randomization_hist
GROUP BY data_source
ORDER BY policies_missing_txn_number DESC;

-- Check D: Product Scope (Rules 1-6)
SELECT
    product,
    COUNT(DISTINCT policynumber) AS policies
FROM uw_analytics.new_business_randomization_hist
GROUP BY product
ORDER BY policies DESC;

-- Check E: Selection Indicator Values (Rules 3, 4 and 5)
SELECT
    select_indicator,
    COUNT(*) AS row_count
FROM uw_analytics.new_business_audit_hist
GROUP BY select_indicator
ORDER BY row_count DESC;

-- Check F: Which Policy Number Field Matches (Rule 10)
WITH selected AS (
    SELECT DISTINCT TRIM(CAST(policynumber AS VARCHAR)) AS policy_number
    FROM uw_analytics.new_business_randomization_hist
    WHERE CAST(process_date AS DATE)
          BETWEEN CURRENT_DATE - INTERVAL '60' DAY
              AND CURRENT_DATE - INTERVAL '30' DAY
      AND NULLIF(TRIM(CAST(policynumber AS VARCHAR)), '') IS NOT NULL
),
audit_policy_number AS (
    SELECT DISTINCT TRIM(CAST(policy_number AS VARCHAR)) AS policy_number
    FROM insurance_master.policy_audit_transactions_master
),
audit_policy_number_full AS (
    SELECT DISTINCT TRIM(CAST(policy_number_full AS VARCHAR)) AS policy_number
    FROM insurance_master.policy_audit_transactions_master
)
SELECT
    (SELECT COUNT(*) FROM selected) AS selected_policies,
    (SELECT COUNT(*)
       FROM selected s
       INNER JOIN audit_policy_number a ON s.policy_number = a.policy_number) AS matched_on_policy_number,
    (SELECT COUNT(*)
       FROM selected s
       INNER JOIN audit_policy_number_full a ON s.policy_number = a.policy_number) AS matched_on_policy_number_full;

-- Check G: Audit Tracking Match Coverage by Selection Age (Rule 10)
WITH selected AS (
    SELECT DISTINCT
        CAST(process_date AS DATE) AS process_date,
        TRIM(CAST(policynumber AS VARCHAR)) AS policy_number
    FROM uw_analytics.new_business_randomization_hist
    WHERE CAST(process_date AS DATE)
          BETWEEN CURRENT_DATE - INTERVAL '120' DAY AND CURRENT_DATE
      AND NULLIF(TRIM(CAST(policynumber AS VARCHAR)), '') IS NOT NULL
),
audit_keys AS (
    SELECT DISTINCT TRIM(CAST(policy_number AS VARCHAR)) AS policy_number
    FROM insurance_master.policy_audit_transactions_master
),
aged AS (
    SELECT
        DATE_DIFF('day', s.process_date, CURRENT_DATE) / 30 AS age_bucket_30_days,
        CASE WHEN a.policy_number IS NOT NULL THEN 1 ELSE 0 END AS found_in_audit
    FROM selected s
    LEFT JOIN audit_keys a
        ON s.policy_number = a.policy_number
)
SELECT
    age_bucket_30_days,
    COUNT(*) AS selected_policy_date_pairs,
    SUM(found_in_audit) AS found_in_audit,
    ROUND(100.0 * SUM(found_in_audit) / COUNT(*), 1) AS pct_found
FROM aged
GROUP BY age_bucket_30_days
ORDER BY age_bucket_30_days;

-- Check H: Agent and Reviewer ID Formats (Rule 11)
SELECT
    agent_employee_id,
    agent_user_id,
    reviewer_1_employee_id,
    reviewer_1_username,
    TYPEOF(agent_employee_id) AS agent_id_type,
    TYPEOF(reviewer_1_employee_id) AS reviewer_id_type
FROM insurance_master.policy_audit_transactions_master
WHERE REGEXP_LIKE(region_long_name, '^Auto [0-9]{4}-[0-9]{2}$')
LIMIT 20;

-- Check I: Which Schema Holds the Production Tables (Rules 7, 8, 10 and 11)
SHOW TABLES IN insurance_master;
SHOW TABLES IN insurance_master_prod;

-- Check J: True Failure Counts for Rules 7 and 8
-- Rule 7 uncapped count
WITH latest_auto_month AS (
    SELECT MAX(
        REGEXP_EXTRACT(
            region_long_name,
            '^Auto ([0-9]{4}-[0-9]{2})$',
            1
        )
    ) AS cycle_month
    FROM insurance_master.policy_audit_transactions_master
    WHERE REGEXP_LIKE(
        region_long_name,
        '^Auto [0-9]{4}-[0-9]{2}$'
    )
),
exceptions AS (
SELECT
    a.region_long_name,
    a.policy_number_full,
    a.agent_employee_id,
    a.agent_name,
    a.reviewer_1_username,
    a.reviewer_1_first_name,
    a.reviewer_1_last_name
FROM insurance_master.policy_audit_transactions_master a
CROSS JOIN latest_auto_month c
WHERE a.region_long_name = CONCAT('Auto ', c.cycle_month)
  AND a.reviewer_1_employee_id IS NULL
)
SELECT COUNT(*) AS failure_count FROM exceptions;

-- Rule 8 uncapped count
WITH latest_auto_month AS (
    SELECT MAX(
        REGEXP_EXTRACT(
            region_long_name,
            '^Auto ([0-9]{4}-[0-9]{2})$',
            1
        )
    ) AS cycle_month
    FROM insurance_master.policy_audit_transactions_master
    WHERE REGEXP_LIKE(
        region_long_name,
        '^Auto [0-9]{4}-[0-9]{2}$'
    )
),
exceptions AS (
SELECT
    a.region_long_name,
    a.agent_employee_id,
    a.agent_name,
    a.reviewer_1_start_date,
    COUNT(DISTINCT a.reviewer_1_employee_id) AS reviewer_count,
    ARRAY_AGG(DISTINCT a.reviewer_1_employee_id) AS reviewer_employee_ids,
    COUNT(DISTINCT a.policy_number_full) AS policy_count
FROM insurance_master.policy_audit_transactions_master a
CROSS JOIN latest_auto_month c
WHERE a.region_long_name = CONCAT('Auto ', c.cycle_month)
  AND a.agent_employee_id IS NOT NULL
  AND a.reviewer_1_employee_id IS NOT NULL
  AND a.reviewer_1_start_date IS NOT NULL
GROUP BY
    a.region_long_name,
    a.agent_employee_id,
    a.agent_name,
    a.reviewer_1_start_date
HAVING COUNT(DISTINCT a.reviewer_1_employee_id) > 1
)
SELECT COUNT(*) AS failure_count FROM exceptions;
