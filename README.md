# Not Every Return Needs a Bigger Model

## Build a Returns Decision Desk with Snowflake AI Functions

A frustrated customer may need a straightforward exchange. A polite customer
contacting support for the third time may need a closer look.

This SQL tutorial uses `snowflake-decision` to assess returns conversations,
turn the answers into a readable triage table, and send only selected requests
to a general-purpose LLM for an internal review note.

```text
CSV files -> stage -> input tables
                          |
                    RETURNS_TICKETS
                          |
                  snowflake-decision
                          |
                 RETURNS_DEMO_TRIAGE
                  /        |        \
     STANDARD_QUEUE   DEEPER_REVIEW   CHECK_INPUT_OR_ERROR
                           |
                    Optional LLM pass
                           |
                 Issue | Evidence | Next check
```

## Repository structure

```text
returns-decision-desk/
|-- README.md
|-- .gitignore
|-- data/
|   |-- README.md
|   |-- returns_tickets.csv       # Add the existing CSV
`-- sql/
    |-- 00_setup.sql
    |-- 01_decision_and_triage.sql
    `-- 02_llm_review.sql         # Optional
```

| File | What it does | What to inspect |
|---|---|---|
| [00_setup.sql](sql/00_setup.sql) | Creates the database, schema, stage, CSV format, and three input tables; loads the staged files. | Load results, row counts, missing text, and sample messages. |
| [01_decision_and_triage.sql](sql/01_decision_and_triage.sql) | Samples up to 100 readable tickets, runs the decision model, flattens the answers, and applies routing rules. | Raw JSON, `RETURNS_DEMO_TRIAGE`, and route counts. |
| [02_llm_review.sql](sql/02_llm_review.sql) | Saves the `DEEPER_REVIEW` subset and generates a short internal note for each selected ticket. | `RETURNS_DEMO_REVIEWS` and missing-response counts. |

## Before you begin

Use a Snowflake account enabled for `snowflake-decision`, a role authorized to
run `AI_COMPLETE` and create the demo objects, and an existing warehouse.
Have your administrator confirm the current [model-access and cross-region
prerequisites][decision-docs]. The documentation labels the model private
preview as of October 9, 2026. These scripts do not change account-wide settings
or grant privileges.

Check [current AI Functions pricing][cost-docs] before running `02`.
The optional pass defaults to `claude-sonnet-5-5`; select a supported model
available in your account by editing `review_model` in `02`.

Use a dedicated demo database. The default is `RETURNS_DECISION_DEMO.DEMO`.
Change the names in all three scripts to use another database/schema. Select
an authorized role and a warehouse in each worksheet.

## 00. Set up and load the CSV

Open [00_setup.sql](sql/00_setup.sql) in a Snowsight SQL worksheet and run
**section A only**. It creates the database, schema, format, stage, and tables.

At the **PAUSE** comment, download the actual CSV files from the repository's
`data/` folder. In Snowsight, choose **Ingestion > Add Data > Load files into a
Stage**. Upload all three files to
`RETURNS_DECISION_DEMO.DEMO.RETURNS_CSV_STAGE`, leaving the optional path empty.
See [staging files in Snowsight][stage-docs].

A commented `PUT` alternative is included for supported clients. `PUT` cannot
run from a Snowsight worksheet. The example disables automatic compression so
its staged filenames match the `.csv` names in the load statements.
See the [PUT reference][put-docs].

Continue with **sections B and C**. `LIST` shows the staged files; the three
`COPY INTO` statements load them into their corresponding tables. Review each
load result, compare row counts with the CSVs, and inspect sample messages.
Resolve any duplicate or missing ticket IDs before continuing.

The format handles quoted commas and multiline text. Loading is **positional**:
CSV columns must match the order in the table definitions. Check the
[data contract](data/README.md) rather than assuming headers are mapped by name.
See [CSV format options][format-docs] and [COPY INTO][copy-docs].

## 01. Make the decisions and inspect the triage table

Run [01_decision_and_triage.sql](sql/01_decision_and_triage.sql) section by
section. It starts with the first 100 non-empty requests ordered by ticket ID.
Missing transcripts are counted separately, not treated as routine requests.

One `AI_COMPLETE` call per sampled row asks three independent questions:

| Question | Type | Meaning |
|---|---|---|
| `request_type` | `choice` | Refund, replacement, return status, or other/unclear. |
| `urgency` | `score` | Stated urgency on a three-level rubric, not anger or politeness. |
| `service_issue` | `noul` | Probability that the text describes an unresolved prior service failure. |

The raw output is saved in `RETURNS_DEMO_DECISIONS`. The next query extracts its
named JSON fields into `RETURNS_DEMO_TRIAGE`, retaining one row per ticket.
Read the [decision response documentation][decision-docs] for field semantics.

```sql
SELECT ticket_id, request_type, confidence, urgency,
       service_issue_probability, route
FROM RETURNS_DECISION_DEMO.DEMO.RETURNS_DEMO_TRIAGE
ORDER BY ticket_id;
```

The script also displays message excerpts and counts by route:

| Route | Meaning in this demo |
|---|---|
| `STANDARD_QUEUE` | A readable request with valid answers that meets none of the review rules. This is not return approval. |
| `DEEPER_REVIEW` | Unclear intent, confidence below `0.80`, urgency at least `1.50`, or service-issue probability at least `0.65`. |
| `CHECK_INPUT_OR_ERROR` | Missing or invalid decision output; investigate separately rather than treating it as routine. |

Thresholds are illustrative, not validated. Confidence is distinct from the
selected option's probability and is not measured accuracy. Scores can be
fractional. Use your own labeled workload to validate thresholds; see
[interpreting the answers][decision-docs].

You can stop here. No larger-model call is required to inspect the decisions.

## 02. Optionally take a closer look

Run [02_llm_review.sql](sql/02_llm_review.sql) after `01`. It materializes only
`DEEPER_REVIEW` rows in `RETURNS_DEMO_REVIEW_QUEUE`. Inspect that count before
continuing to the paid inference section. An empty queue means there are no
selected requests in this sample.

The larger model reads the original conversation, not the first model's
conclusions. It is asked for three short lines: **Issue, Evidence, Next check**.
Notes and their source text are saved in `RETURNS_DEMO_REVIEWS`. The final
queries display the results and count missing responses. No sample model
outputs or performance figures are invented in this repository.

These are internal notes for a person to review. Neither step approves a
refund, decides eligibility, sends a customer reply, or completes a case.

## Rerun only what you need

Results are stored in regular demo tables, not session-only temporary tables,
so `01` and `02` can run in separate worksheets. Each script sets its own
database/schema context; use the same authorized role and select a warehouse.

`00` preserves existing input tables. Its `COPY` statements use load history;
do not add `FORCE = TRUE` or rename/reload the same data to make a routine rerun
work. Load history is not permanent deduplication. Inspect row counts and IDs
after loading; see [COPY behavior][copy-docs].

`01` and `02` replace their derived tables. Rerunning an inference section
submits the rows again and can incur additional charges. Reading the stored
outputs does not call a model. To adjust thresholds, rerun only sections C and
D of `01`. To expand the sample, change `LIMIT 100` and rerun `01`. Refresh `02`
after changing triage; old review results are not updated automatically.

## Scope and data

Setup loads all three CSVs, but the core tutorial reads **only
`RETURNS_TICKETS`**. `RETURNS_ORDERS` is reserved for a business-context
extension; `RETURNS_LABELS` is reserved for later evaluation. Neither model
sees labels or label explanations.

This conversation-only demo does not implement the fuller returns policy used
to create `EXPECTED_ROUTE`. Do not compare those labels directly with the
simplified routes. Synthetic data and provisional labels do not establish
production accuracy, calibrated probabilities, or cost savings. Fewer calls
to the larger model are a workflow measurement, not a complete cost comparison.

## Clean up

Only after confirming the database contains no work you need to keep, remove
the demo database, including its stage and all input/output tables:

```sql
DROP DATABASE IF EXISTS RETURNS_DECISION_DEMO;
```

[decision-docs]: https://docs.snowflake.com/en/LIMITEDACCESS/snowflake-cortex/ai-complete-snowflake-decision
[cost-docs]: https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql-cost
[stage-docs]: https://docs.snowflake.com/en/user-guide/data-load-local-file-system-stage-ui
[put-docs]: https://docs.snowflake.com/en/sql-reference/sql/put
[format-docs]: https://docs.snowflake.com/en/sql-reference/sql/create-file-format
[copy-docs]: https://docs.snowflake.com/en/sql-reference/sql/copy-into-table
