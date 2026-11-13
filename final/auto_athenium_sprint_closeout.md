# Auto Athenium data quality | Sprint closeout

November 13, 2026 · Chloe Barker

The [rule document](dq_rules.txt) contains the eight current checks, three proposed additions and questions for review. The [rule SQL](auto_athenium_rules.sql) and [Athena validation queries](dq_rule_validation.sql) follow the same numbering. Live Athena results are pending.

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

| Rule | Business reason | Evidence to collect |
|---|---|---|
| **9. Selection data freshness** | A missing load could delay new audit work while Rule 6 still evaluates an older date. | Use Check A and the run log to confirm the expected days, deadline and treatment of valid empty runs. The draft alerts if the newest date is missing or more than one calendar day old. |
| **10. Selected policy reaches audit tracking** | A selected policy can fail to reach the audit team's work list after passing upstream reconciliation. | Use Checks F and G to compare policy fields and match coverage by age. Verify known selections in the expected cycle or work item. Confirm the audit scope and handoff deadline before implementing the provisional 30–60 day check. The draft reports missing policy-number matches across the audit master. |
| **11. Reviewer is not the policy's agent** | A populated and consistently assigned reviewer can still be reviewing their own work. | Use Check H to profile both IDs. Confirm they identify employees in the same system, who the agent field represents, and whether the business prohibits self-review. |

## Questions on the current checks

- Should Rules 1, 2, 3 and 5 use a common completed date or another agreed scope? A retained historical exception can keep an all-history check failing.
- Which sources require transaction numbers for Rule 2? Check C measures policies with NULL transaction numbers by source. Confirm the count before reporting it.
- Does Collibra count the returned rows for Rules 7 and 8? Use Check J to compare the full exception counts against the 100-row display cap.
- Should Rule 8 group by employee ID within each cycle and assignment date, with agent name for display? Name variants can split a single employee's assignments.

## Additional ideas for later review

- **Source match-key completeness.** Extend Check C to profile the other required key fields. Consider a separate rule if missing fields explain reconciliation failures and the source owner confirms they are mandatory.
- **Conflicting final selection decisions.** Check for both true and false on the same transaction within one run once the run and final decision can be identified. Valid revisions may explain some candidates.
