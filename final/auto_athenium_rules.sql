-- Auto Athenium data quality | Sprint closeout draft
-- Source: dq_rules.txt. Run one statement at a time in Athena.
-- Rules 1-8 are current. Rules 9-11 are proposed.
-- Rule 9 uses a provisional 1-calendar-day allowance.
-- Rule 10 is an exploratory policy-number match across the audit master.
-- Confirm the audit cycle/work-item key and deadline before monitoring.
-- Rule 11 assumes both fields identify people in the same employee ID system.

-- Rule 1: Policy Number Completeness
SELECT DISTINCT
    process_date,
    data_source,
    product,
    transaction_number,
    transaction_term_effective_date,
    transaction_timestamp,
    employeeid
FROM uw_analytics.new_business_randomization_hist
WHERE policynumber IS NULL
   OR TRIM(CAST(policynumber AS VARCHAR)) = ''
ORDER BY process_date DESC, data_source, product;

-- Rule 2: Selected Policy Exists in Source Mart
WITH randomized AS (
    SELECT DISTINCT
        process_date,
        data_source,
        product,
        CAST(policynumber AS VARCHAR) AS policy_number,
        CAST(transaction_number AS VARCHAR) AS transaction_number,
        CAST(transaction_term_effective_date AS DATE) AS term_effective_date,
        CAST(transaction_timestamp AS TIMESTAMP) AS transaction_timestamp
    FROM uw_analytics.new_business_randomization_hist
)
SELECT r.*
FROM randomized r
WHERE NOT EXISTS (
    SELECT 1
    FROM uw_analytics.new_business_audit_mart_hist m
    WHERE m.data_source = r.data_source
      AND m.product = r.product
      AND CAST(m.policynumber AS VARCHAR) = r.policy_number
      AND CAST(m.transaction_number AS VARCHAR) = r.transaction_number
      AND CAST(m.transaction_term_effective_date AS DATE) = r.term_effective_date
      AND CAST(m.transaction_timestamp AS TIMESTAMP) = r.transaction_timestamp
)
ORDER BY r.process_date DESC, r.data_source, r.product, r.policy_number;

-- Rule 3: Selection Reconciliation
WITH selected AS (
    SELECT DISTINCT
        process_date,
        data_source,
        product,
        CAST(policy_number AS VARCHAR) AS policy_number,
        CAST(term_effective_date AS DATE) AS term_effective_date,
        CAST(transaction_timestamp AS TIMESTAMP) AS transaction_timestamp
    FROM uw_analytics.new_business_audit_hist
    WHERE select_indicator = 'true'
),
randomized AS (
    SELECT DISTINCT
        process_date,
        data_source,
        product,
        CAST(policynumber AS VARCHAR) AS policy_number,
        CAST(transaction_term_effective_date AS DATE) AS term_effective_date,
        CAST(transaction_timestamp AS TIMESTAMP) AS transaction_timestamp
    FROM uw_analytics.new_business_randomization_hist
)
SELECT
    COALESCE(s.process_date, r.process_date) AS process_date,
    COALESCE(s.data_source, r.data_source) AS data_source,
    COALESCE(s.product, r.product) AS product,
    COALESCE(s.policy_number, r.policy_number) AS policy_number,
    COALESCE(s.term_effective_date, r.term_effective_date) AS term_effective_date,
    COALESCE(s.transaction_timestamp, r.transaction_timestamp) AS transaction_timestamp,
    CASE
        WHEN s.policy_number IS NULL THEN 'RANDOMIZATION_WITHOUT_TRUE_SELECTION'
        WHEN r.policy_number IS NULL THEN 'TRUE_SELECTION_MISSING_FROM_RANDOMIZATION'
    END AS dq_issue
FROM selected s
FULL OUTER JOIN randomized r
    ON s.process_date = r.process_date
   AND s.data_source = r.data_source
   AND s.product = r.product
   AND s.policy_number = r.policy_number
   AND s.term_effective_date = r.term_effective_date
   AND s.transaction_timestamp = r.transaction_timestamp
WHERE s.policy_number IS NULL
   OR r.policy_number IS NULL
ORDER BY process_date DESC, dq_issue, data_source, product, policy_number;

-- Rule 4: Previously Processed Policy Re-entered Selection
WITH latest_run AS (
    SELECT MAX(process_date) AS current_process_date
    FROM uw_analytics.new_business_audit_hist
),
current_run AS (
    SELECT DISTINCT
        h.process_date,
        h.data_source,
        h.product,
        CAST(h.policy_number AS VARCHAR) AS policy_number,
        CAST(h.term_effective_date AS DATE) AS term_effective_date,
        CAST(h.transaction_timestamp AS TIMESTAMP) AS transaction_timestamp,
        h.transaction_user,
        h.select_indicator
    FROM uw_analytics.new_business_audit_hist h
    CROSS JOIN latest_run r
    WHERE h.process_date = r.current_process_date
      AND h.select_indicator IN ('true', 'false')
),
prior_history AS (
    SELECT DISTINCT
        h.data_source,
        h.product,
        CAST(h.policy_number AS VARCHAR) AS policy_number,
        CAST(h.term_effective_date AS DATE) AS term_effective_date,
        CAST(h.transaction_timestamp AS TIMESTAMP) AS transaction_timestamp
    FROM uw_analytics.new_business_audit_hist h
    CROSS JOIN latest_run r
    WHERE h.process_date < r.current_process_date
      AND h.select_indicator IN ('true', 'false')
)
SELECT c.*
FROM current_run c
INNER JOIN prior_history p
    ON c.data_source = p.data_source
   AND c.product = p.product
   AND c.policy_number = p.policy_number
   AND c.term_effective_date = p.term_effective_date
   AND c.transaction_timestamp = p.transaction_timestamp
ORDER BY c.data_source, c.product, c.policy_number;

-- Rule 5: Agent Identifier Completeness
SELECT DISTINCT
    process_date,
    data_source,
    product,
    policy_number,
    term_effective_date,
    transaction_timestamp,
    select_indicator
FROM uw_analytics.new_business_audit_hist
WHERE select_indicator IN ('true', 'false')
  AND (
        transaction_user IS NULL
        OR TRIM(CAST(transaction_user AS VARCHAR)) = ''
      )
ORDER BY process_date DESC, data_source, product, policy_number;

-- Rule 6: Selected Policy Volume Anomaly by State
WITH current_run AS (
    SELECT MAX(process_date) AS current_process_date
    FROM uw_analytics.new_business_randomization_hist
),
policy_transactions AS (
    SELECT DISTINCT
        process_date,
        state,
        data_source,
        product,
        CAST(policynumber AS VARCHAR) AS policy_number,
        CAST(transaction_number AS VARCHAR) AS transaction_number,
        CAST(transaction_term_effective_date AS DATE) AS term_effective_date,
        CAST(transaction_timestamp AS TIMESTAMP) AS transaction_timestamp
    FROM uw_analytics.new_business_randomization_hist
    WHERE state IS NOT NULL
      AND TRIM(state) <> ''
),
daily_counts AS (
    SELECT
        process_date,
        state,
        COUNT(*) AS selected_policy_count
    FROM policy_transactions
    GROUP BY process_date, state
),
same_weekday_dates AS (
    SELECT process_date
    FROM (
        SELECT
            d.process_date,
            ROW_NUMBER() OVER (ORDER BY d.process_date DESC) AS rn
        FROM (
            SELECT DISTINCT process_date
            FROM daily_counts
        ) d
        CROSS JOIN current_run c
        WHERE d.process_date < c.current_process_date
          AND DAY_OF_WEEK(d.process_date) = DAY_OF_WEEK(c.current_process_date)
    ) x
    WHERE rn <= 10
),
relevant_states AS (
    SELECT DISTINCT d.state
    FROM daily_counts d
    CROSS JOIN current_run c
    WHERE d.process_date = c.current_process_date
    UNION
    SELECT DISTINCT d.state
    FROM daily_counts d
    INNER JOIN same_weekday_dates b
        ON d.process_date = b.process_date
),
history_grid AS (
    SELECT
        b.process_date,
        s.state,
        COALESCE(d.selected_policy_count, 0) AS selected_policy_count
    FROM same_weekday_dates b
    CROSS JOIN relevant_states s
    LEFT JOIN daily_counts d
        ON d.process_date = b.process_date
       AND d.state = s.state
),
baseline AS (
    SELECT
        state,
        COUNT(*) AS baseline_days,
        AVG(CAST(selected_policy_count AS DOUBLE)) AS avg_selected_count,
        STDDEV_SAMP(CAST(selected_policy_count AS DOUBLE)) AS std_selected_count
    FROM history_grid
    GROUP BY state
),
current_counts AS (
    SELECT
        s.state,
        COALESCE(d.selected_policy_count, 0) AS current_selected_count
    FROM relevant_states s
    CROSS JOIN current_run c
    LEFT JOIN daily_counts d
        ON d.process_date = c.current_process_date
       AND d.state = s.state
)
SELECT
    c.current_process_date AS process_date,
    cc.state,
    cc.current_selected_count,
    COALESCE(b.baseline_days, 0) AS baseline_days,
    ROUND(b.avg_selected_count, 2) AS avg_selected_count,
    ROUND(b.std_selected_count, 2) AS std_selected_count,
    ROUND(
        GREATEST(0, b.avg_selected_count - (3 * b.std_selected_count)),
        2
    ) AS lower_threshold,
    ROUND(
        b.avg_selected_count + (3 * b.std_selected_count),
        2
    ) AS upper_threshold,
    CASE
        WHEN COALESCE(b.baseline_days, 0) < 10
             OR b.std_selected_count IS NULL
            THEN 'PASS'
        WHEN cc.current_selected_count
             < GREATEST(0, b.avg_selected_count - (3 * b.std_selected_count))
          OR cc.current_selected_count
             > b.avg_selected_count + (3 * b.std_selected_count)
            THEN 'ALERT'
        ELSE 'PASS'
    END AS dq_status
FROM current_counts cc
CROSS JOIN current_run c
LEFT JOIN baseline b
    ON cc.state = b.state
ORDER BY dq_status DESC, cc.state;

-- Rule 7: Reviewer Assignment Completeness
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
LIMIT 100;

-- Rule 8: Agent-to-Reviewer Assignment Consistency
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
ORDER BY reviewer_count DESC, policy_count DESC
LIMIT 100;

-- Rule 9: Selection Data Freshness (Proposed)
WITH latest_selection AS (
    SELECT MAX(CAST(process_date AS DATE)) AS latest_process_date
    FROM uw_analytics.new_business_randomization_hist
)
SELECT
    latest_process_date,
    DATE_DIFF('day', latest_process_date, CURRENT_DATE) AS days_since_latest_selection,
    CASE
        WHEN latest_process_date IS NULL THEN 'NO_SELECTION_DATE'
        ELSE 'STALE_SELECTION_DATA'
    END AS dq_issue
FROM latest_selection
WHERE latest_process_date IS NULL
   OR DATE_DIFF('day', latest_process_date, CURRENT_DATE) > 1;

-- Rule 10: Selected Policy Reaches Audit Tracking (Proposed)
WITH selected AS (
    SELECT DISTINCT
        CAST(process_date AS DATE) AS process_date,
        data_source,
        product,
        TRIM(CAST(policynumber AS VARCHAR)) AS policy_number
    FROM uw_analytics.new_business_randomization_hist
    WHERE CAST(process_date AS DATE)
          BETWEEN CURRENT_DATE - INTERVAL '60' DAY
              AND CURRENT_DATE - INTERVAL '30' DAY
      AND NULLIF(TRIM(CAST(policynumber AS VARCHAR)), '') IS NOT NULL
)
SELECT s.*
FROM selected s
WHERE NOT EXISTS (
    SELECT 1
    FROM insurance_master.policy_audit_transactions_master a
    WHERE TRIM(CAST(a.policy_number AS VARCHAR)) = s.policy_number
)
ORDER BY s.process_date DESC, s.data_source, s.product, s.policy_number;

-- Rule 11: Reviewer Is Not the Policy's Agent (Proposed)
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
    a.policy_number_full,
    a.agent_employee_id,
    a.agent_name,
    a.reviewer_1_employee_id,
    a.reviewer_1_first_name,
    a.reviewer_1_last_name
FROM insurance_master.policy_audit_transactions_master a
CROSS JOIN latest_auto_month c
WHERE a.region_long_name = CONCAT('Auto ', c.cycle_month)
  AND NULLIF(TRIM(CAST(a.agent_employee_id AS VARCHAR)), '')
      = NULLIF(TRIM(CAST(a.reviewer_1_employee_id AS VARCHAR)), '')
ORDER BY a.agent_employee_id, a.policy_number_full;
