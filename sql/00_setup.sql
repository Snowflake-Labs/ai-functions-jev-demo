-- 00_setup.sql
-- Returns Decision Desk | Not Every Return Needs a Bigger Model
-- Creates a demo database, schema, CSV format, stage, and three input tables.
-- Run section A first. PAUSE to upload the CSVs, then run sections B and C.
-- No AI inference in this file. Loading/querying still uses warehouse resources.
-- SQL has not been executed or compile-validated in Snowflake.
--
-- Before you run:
--   Select an authorized role and an existing warehouse in your worksheet.
--   Use a new, dedicated demo database. Change the database/schema names in
--   ALL THREE SQL files if these names are already used for something else.
--   The scripts do not change account-wide settings or grant privileges.
--   CSV names and column order follow data/README.md; check your actual files.
--
-- Optional: set your existing role and warehouse explicitly.
-- USE ROLE YOUR_DEMO_ROLE;
-- USE WAREHOUSE YOUR_WAREHOUSE;

-- ============================================================================
-- A. Create the demo objects
-- ============================================================================
CREATE DATABASE IF NOT EXISTS RETURNS_DECISION_DEMO;
CREATE SCHEMA IF NOT EXISTS RETURNS_DECISION_DEMO.DEMO;

USE DATABASE RETURNS_DECISION_DEMO;
USE SCHEMA DEMO;

SELECT CURRENT_ROLE() AS active_role,
       CURRENT_WAREHOUSE() AS active_warehouse,
       CURRENT_DATABASE() AS active_database,
       CURRENT_SCHEMA() AS active_schema;

-- A one-line header followed by standard UTF-8 CSV rows.
-- Quoted commas, quotes, and multiline transcripts are supported.
-- Loading is POSITIONAL: the CSV column order must match each table below.
-- Empty fields become SQL NULL; no rows are silently skipped on load errors.
CREATE FILE FORMAT IF NOT EXISTS RETURNS_CSV_FORMAT
    TYPE = CSV
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    MULTI_LINE = TRUE
    ESCAPE_UNENCLOSED_FIELD = NONE
    EMPTY_FIELD_AS_NULL = TRUE
    NULL_IF = ('')
    DATE_FORMAT = 'YYYY-MM-DD'
    ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
    ENCODING = 'UTF8';

CREATE STAGE IF NOT EXISTS RETURNS_CSV_STAGE
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    FILE_FORMAT = (FORMAT_NAME = 'RETURNS_CSV_FORMAT');

-- Required by 01_decision_and_triage.sql.
CREATE TABLE IF NOT EXISTS RETURNS_TICKETS (
    TICKET_ID VARCHAR,
    ORDER_ID VARCHAR,
    REQUEST_DATE DATE,
    CHANNEL VARCHAR,
    TICKET_TEXT VARCHAR
);

-- ============================================================================
-- PAUSE: Download data/*.csv from the repository and upload them to the stage
-- ============================================================================
-- Download the actual CSV file:
--   data/returns_tickets.csv
--
-- In Snowsight:
--   Ingestion > Add Data > Load files into a Stage.
--   Select the CSV and this destination:
--     RETURNS_DECISION_DEMO.DEMO.RETURNS_CSV_STAGE
--   Leave the optional stage path EMPTY so the CSV land at the stage root.
--   Upload, then continue below.
--
-- Alternative: run this PUT in a supported client such as Snowflake CLI or
-- SnowSQL, NOT in a Snowsight worksheet. Replace the local absolute path.
-- AUTO_COMPRESS = FALSE preserves the .csv filename used by COPY INTO.
--
-- PUT 'file:///absolute/path/to/returns-decision-desk/data/*.csv'
--     @RETURNS_DECISION_DEMO.DEMO.RETURNS_CSV_STAGE
--     AUTO_COMPRESS = FALSE
--     OVERWRITE = FALSE;
--
-- References:
-- https://docs.snowflake.com/en/user-guide/data-load-local-file-system-stage-ui
-- https://docs.snowflake.com/en/sql-reference/sql/put

-- ============================================================================
-- B. Load the staged CSV into their tables
-- ============================================================================
-- Continue only after the files are uploaded.
-- File names are case-sensitive and must match these FILES clauses.
-- COPY uses file-load history. Do not add FORCE = TRUE for a routine rerun.
-- IF NOT EXISTS above preserves existing tables and does not fix their schema.

LIST @RETURNS_CSV_STAGE;

COPY INTO RETURNS_TICKETS
FROM @RETURNS_CSV_STAGE
FILES = ('returns_tickets.csv')
FILE_FORMAT = (FORMAT_NAME = 'RETURNS_CSV_FORMAT')
ON_ERROR = 'ABORT_STATEMENT';

-- ============================================================================
-- C. Inspect the loaded data
-- ============================================================================
SELECT 'RETURNS_TICKETS' AS table_name, COUNT(*) AS loaded_rows
FROM RETURNS_TICKETS;

SELECT COUNT(*) AS loaded_requests,
       COALESCE(COUNT_IF(NULLIF(TRIM(ticket_text), '') IS NULL), 0) AS missing_text
FROM RETURNS_TICKETS;

-- Expected: no rows. Resolve duplicate or missing ticket IDs before continuing.
SELECT ticket_id, COUNT(*) AS occurrences
FROM RETURNS_TICKETS
GROUP BY ticket_id
HAVING COUNT(*) > 1 OR NULLIF(TRIM(ticket_id), '') IS NULL;

SELECT ticket_id, order_id, request_date, channel,
       LEFT(ticket_text, 240) AS message_excerpt
FROM RETURNS_TICKETS
ORDER BY ticket_id
LIMIT 5;

-- Next: sql/01_decision_and_triage.sql.
