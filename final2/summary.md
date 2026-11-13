# Auto Athenium data quality | Sprint closeout

November 13, 2026 · Chloe Barker

The [rule document](dq_rules.txt) contains the eight current checks, three proposed additions and questions for review. The [rule SQL](auto_athenium_rules.sql) and [Athena validation queries](dq_rule_validation.sql) follow the same numbering. The results below come from the Athena check outputs shared on November 12, 2026.

## Current rules

| Rule | What it checks |
|---|---|
| 1. Policy number completeness | Final selections have a populated policy number. |
| 2. Source match | Final selections match the source mart on all six key fields. |
| 3. Selection reconciliation | True decisions and final selections agree in both directions for the same date. |
| 4. Repeat processing | Transactions processed on the latest date did not already receive a decision on an earlier date. |
| 5. Agent identifier completeness | Completed true/false decisions carry the agent identifier. |
| 6. Volume anomaly | Selected transaction volume by state is within the range derived from prior dates on the same weekday. |
| 7. Reviewer completeness | Audit records in the latest monthly Auto cycle have a primary reviewer employee ID. |
| 8. Reviewer assignment consistency | Within the latest monthly Auto cycle, each agent and assignment date group has one primary reviewer. |

## Proposed additions

| Rule | Business reason | Evidence |
|---|---|---|
| **9. Selection indicator validity** | Rules 3–5 filter on `'true'` and `'false'`, so any other value is excluded from all three without notice. | Check E returned only `'true'` and `'false'`. The rule is expected to pass today. |
| **10. Selection key completeness** | A missing match field appears as a reconciliation failure in Rules 2–4 without showing the cause. | Check C found `transaction_number` missing for every PSTAR and HUON policy. It is excluded until the owners confirm which sources require it. |
| **11. Selection data freshness** | Rules 4 and 6 evaluate the latest available date, so a stopped load re-evaluates old data and passes. | Check B shows the latest dates are January 26, 2026 and September 15, 2026. All three tables would currently fail. |

## Why these three checks were proposed

Each proposed rule protects an assumption that Rules 1–8 already make, so none depends on new business definitions or cross-system mappings. Rule 9 confirms the decision values that Rules 3–5 filter on. Rule 10 confirms the match fields that Rules 2–4 join on. Rule 11 confirms that the latest date evaluated by Rules 4 and 6 is current. Rule 11 uses a seven-day tolerance as a placeholder because Check A shows a run every five days since January 11, 2026. Confirm the run schedule with the data owner.

Earlier drafts of Rules 9–11 (expected selection date, audit tracking handoff and reviewer self-review) moved to ideas for later review. Each depended on an external schedule, a cross-schema match or an unconfirmed employee ID mapping.

## Prioritized questions for Rules 1–8

1. **Rules 1–6 — Are the pipeline tables still being loaded?** Randomization history and the source mart end on January 26, 2026. Audit history ends on September 15, 2026. Until this is confirmed, Rules 1, 2 and 6 evaluate January data, and Rule 3 reports every later true selection as missing from randomization history.
2. **Rule 6 — Does the same-weekday baseline still fit the run schedule?** Runs were daily through January 8, 2026 and every five days from January 11, with larger volumes per run. The same weekday now recurs only every 35 days, and the baseline includes single-day runs from the earlier schedule.
3. **Rules 2–4 — Which fields identify a transaction?** Rule 2 matches on six fields, including `transaction_number`. Rules 3 and 4 use five fields without it. Every PSTAR and HUON policy has at least one selection with no transaction number, so those selections cannot pass Rule 2. Agree on one key per source and apply it consistently.
4. **Rules 1, 2, 3 and 5 — Which window should monitoring use?** These rules scan full history. With a zero threshold, one historical exception fails every future run.
5. **Rules 1–6 — Are all product codes Auto?** Check D shows fourteen codes, such as ATX, AMO and OHA, which appear to be state-level Auto codes. If the owner confirms this, no product filter is needed.
6. **Rules 3–5 — Is a 54% selection rate expected?** Check E shows 89,280 of 165,212 decision rows are true. These counts are rows, not distinct transactions.
7. **Rule 6 — How should a thin baseline be reported?** The rule returns PASS with fewer than ten comparable dates. A separate `INSUFFICIENT_HISTORY` status would show that the evaluation was skipped.
8. **Rules 7 and 8 — Which schema and cycle were evaluated?** Check J returned zero exceptions. Record the schema, Auto cycle and number of records evaluated (Check L) before calling the checks clean. Check I pointed to `insurance_master_prod`, but the rules query `insurance_master`. Use an uncapped count if Collibra counts returned rows.
9. **Rule 8 — Should the agent name affect grouping?** A name variation can split one agent into two groups and hide a reviewer conflict. Records without an agent ID or reviewer start date are also excluded.
10. **Rule 4 — Can a transaction re-enter selection after a false decision?** Both true and false decisions currently count as processed.

## Athena results to date

| Check | Observed result | Interpretation |
|---|---|---|
| A. Selection dates | January 26, 2026 is the latest date shown, with 47,139 selection detail rows. The sample includes weekend dates and gaps. | Runs were daily through January 8, 2026 and every five days from January 11. This sets the minimum Rule 11 tolerance and affects the Rule 6 baseline. |
| B. Date coverage | Audit history spans March 15, 2024 to September 15, 2026. Randomization history spans June 25, 2024 to January 26, 2026. Source mart history spans July 9, 2024 to January 26, 2026. | All three tables are behind the current date. For Rule 3, compare a date both feeds were expected to cover. |
| C. NULL transaction numbers | PSTAR has 8,841 of 8,841 policies with at least one NULL transaction number, HUON has 4,596 of 4,596, and GW has 0 of 63,490. | Rule 2 cannot match a row with a NULL transaction number. Rule 10 excludes this field until the owners confirm which sources supply it. |
| D. Product scope | Fourteen product codes, led by ATX (27,995 policies) and AMO (18,396). | The codes appear to be state-level Auto codes. Confirm with the data owner. |
| E. Selection indicators | 89,280 rows show `true` and 75,932 show `false`. | Supports the values used in Rules 3–5 and the allowed values in Rule 9. |
| F and G. Audit handoff | The comparison could not run across the two tables in the current Athena setup. | Supports the audit tracking idea for later review. |
| H and I. Reviewer IDs and schema | Both employee ID columns are `integer`. `agent_user_id` and `reviewer_1_username` hold the employee ID with or without an E prefix. Check I pointed to `insurance_master_prod`. | Integer IDs cannot be blank, so Rule 7's NULL check is sufficient. Both IDs appear to use the same employee numbering. Confirm which schema the monitoring job should use. |
| J. Uncapped reviewer checks | Zero exceptions reported for Rules 7 and 8. | Record the queried schema, Auto cycle, and eligible row or group count to establish the scope of these results. |

## Checks to run next

- **Rules 9, 10 and 11.** Run each once. Rule 9 should return zero rows based on Check E, and Rule 11 should return all three tables based on Check B. Rule 10 has not been run.
- **Check K. Days between runs.** Confirms when the schedule changed and sets the Rule 11 tolerance.
- **Check L. Records evaluated by Rules 7 and 8.** Confirms that the zero results in Check J came from a populated cycle. Run it against the schema Collibra will use.

## Additional ideas for later review

- **Expected selection date presence.** Superseded by Rule 11. Revisit if a run-control table becomes available.
- **Selected policy reaches audit tracking.** Depends on cross-schema access, an agreed policy key and a mapping from selection date to audit cycle.
- **Reviewer is not the policy's agent.** Check H suggests both IDs use the same employee numbering. Confirm that self-review is prohibited and that an agent can be assigned as a reviewer.
- **Reviewer assignment field completeness.** Agent ID and reviewer start date for the latest Auto cycle, since Rule 8 excludes records missing either field.
- **Audit date order.** Reviewer finalization date should not precede reviewer start date.
- **Conflicting decisions and duplicate transactions within a run.** Require an agreed run identifier and transaction key.
