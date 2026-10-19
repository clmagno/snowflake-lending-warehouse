-- =============================================================================
-- 03_copy_into.sql
-- Load staged files into RAW. Safe to re-run: Snowflake keeps 64 days of load
-- metadata per table and skips files it has already loaded, so a re-run only
-- picks up new files. The loader script runs these same statements.
-- =============================================================================
USE ROLE LOADER;
USE WAREHOUSE LOADING_WH;
USE SCHEMA LENDING.RAW;

ALTER SESSION SET QUERY_TAG = 'lending:load';

COPY INTO BORROWERS
FROM (
  SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
         METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @LENDING_LANDING/borrowers/
)
FILE_FORMAT = (FORMAT_NAME = CSV_WITH_HEADER)
ON_ERROR = ABORT_STATEMENT;

COPY INTO LOANS
FROM (
  SELECT $1, $2, $3, $4, $5, $6, $7, $8,
         METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @LENDING_LANDING/loans/
)
FILE_FORMAT = (FORMAT_NAME = CSV_WITH_HEADER)
ON_ERROR = ABORT_STATEMENT;

-- Payments arrive as one file per month. A bad row is logged and skipped
-- rather than failing the whole month; review with the VALIDATE query below.
COPY INTO PAYMENTS
FROM (
  SELECT $1, $2, $3, $4, $5, $6,
         METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @LENDING_LANDING/payments/
)
FILE_FORMAT = (FORMAT_NAME = CSV_WITH_HEADER)
PATTERN = '.*payments_[0-9]{4}_[0-9]{2}[.]csv([.]gz)?'
ON_ERROR = CONTINUE;

-- Rows rejected by the last COPY INTO PAYMENTS, if any:
-- SELECT * FROM TABLE(VALIDATE(PAYMENTS, JOB_ID => '_last'));

-- Load history for the last day:
-- SELECT FILE_NAME, ROW_COUNT, ROW_PARSED, ERROR_COUNT, STATUS, LAST_LOAD_TIME
-- FROM INFORMATION_SCHEMA.LOAD_HISTORY
-- WHERE SCHEMA_NAME = 'RAW' AND LAST_LOAD_TIME > DATEADD(day, -1, CURRENT_TIMESTAMP())
-- ORDER BY LAST_LOAD_TIME DESC;
