-- Auto Athenium | Pre-implementation checks from dq_rules.txt
-- Run one statement at a time. See the document for interpretation.
-- Checks A-E and I-L support Rules 1-11. Checks F, G and H support ideas for later review.
-- Confirm load frequency, transaction keys and product scope with the owners.

-- Check A: Observed Selection Dates (Rules 6 and 11)
SELECT
    process_date,
    DAY_OF_WEEK(process_date) AS weekday_number,
    COUNT(*) AS selection_rows
FROM uw_analytics.new_business_randomization_hist
WHERE process_date IS NOT NULL
GROUP BY process_date
ORDER BY process_date DESC
LIMIT 30;

-- Check B: Date Range of Each Table (Rules 1, 2, 3, 5 and 11)
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

-- Check C: Missing Transaction Numbers by Source (Rules 2 and 10)
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

-- Check E: Selection Indicator Values (Rules 3, 4, 5 and 9)
SELECT
    select_indicator,
    COUNT(*) AS row_count
FROM uw_analytics.new_business_audit_hist
GROUP BY select_indicator
ORDER BY row_count DESC;

-- Check F: Which Policy Number Field Matches (Later Idea: Audit Tracking)
WITH latest_run AS (
    SELECT MAX(process_date) AS current_process_date
    FROM uw_analytics.new_business_randomization_hist
),
selected AS (
    SELECT DISTINCT TRIM(CAST(r.policynumber AS VARCHAR)) AS policy_number
    FROM uw_analytics.new_business_randomization_hist r
    CROSS JOIN latest_run d
    WHERE r.process_date = d.current_process_date
      AND NULLIF(TRIM(CAST(r.policynumber AS VARCHAR)), '') IS NOT NULL
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
    d.current_process_date AS evaluated_process_date,
    (SELECT COUNT(*) FROM selected) AS selected_policies,
    (SELECT COUNT(*)
       FROM selected s
       INNER JOIN audit_policy_number a ON s.policy_number = a.policy_number) AS matched_on_policy_number,
    (SELECT COUNT(*)
       FROM selected s
       INNER JOIN audit_policy_number_full a ON s.policy_number = a.policy_number) AS matched_on_policy_number_full
FROM latest_run d;

-- Check G: Audit Tracking Match Coverage by Selection Date (Later Idea: Audit Tracking)
WITH observed_dates AS (
    SELECT DISTINCT process_date
    FROM uw_analytics.new_business_randomization_hist
    WHERE process_date IS NOT NULL
    ORDER BY process_date DESC
    LIMIT 30
),
selected AS (
    SELECT DISTINCT
        r.process_date,
        TRIM(CAST(r.policynumber AS VARCHAR)) AS policy_number
    FROM uw_analytics.new_business_randomization_hist r
    INNER JOIN observed_dates d ON r.process_date = d.process_date
    WHERE NULLIF(TRIM(CAST(r.policynumber AS VARCHAR)), '') IS NOT NULL
),
audit_keys AS (
    SELECT DISTINCT TRIM(CAST(policy_number AS VARCHAR)) AS policy_number
    FROM insurance_master.policy_audit_transactions_master
)
SELECT
    s.process_date,
    COUNT(*) AS selected_policies,
    COUNT(a.policy_number) AS found_in_audit,
    ROUND(100.0 * COUNT(a.policy_number) / COUNT(*), 1) AS pct_found
FROM selected s
LEFT JOIN audit_keys a ON s.policy_number = a.policy_number
GROUP BY s.process_date
ORDER BY s.process_date DESC;

-- Check H: Agent and Reviewer ID Formats (Later Idea: Self-Review)
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

-- Check I: Which Schema Holds the Production Tables (Rules 7 and 8)
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

-- Check K: Days Between Runs (Rules 6 and 11)
WITH run_dates AS (
    SELECT DISTINCT process_date
    FROM uw_analytics.new_business_randomization_hist
    WHERE process_date IS NOT NULL
)
SELECT
    process_date,
    DAY_OF_WEEK(process_date) AS weekday_number,
    DATE_DIFF('day', LAG(process_date) OVER (ORDER BY process_date), process_date) AS days_since_prior_run
FROM run_dates
ORDER BY process_date DESC
LIMIT 60;

-- Check L: Records Evaluated by Rules 7 and 8
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
)
SELECT
    a.region_long_name,
    COUNT(*) AS audit_records,
    COUNT(a.reviewer_1_employee_id) AS records_with_reviewer_id,
    COUNT(a.agent_employee_id) AS records_with_agent_id,
    COUNT(a.reviewer_1_start_date) AS records_with_start_date
FROM insurance_master.policy_audit_transactions_master a
CROSS JOIN latest_auto_month c
WHERE a.region_long_name = CONCAT('Auto ', c.cycle_month)
GROUP BY a.region_long_name;
