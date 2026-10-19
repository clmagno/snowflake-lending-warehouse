-- =============================================================================
-- 02_raw_layer.sql
-- File format, internal stage and RAW tables. Run as LOADER.
-- =============================================================================
USE ROLE LOADER;
USE WAREHOUSE LOADING_WH;
USE SCHEMA LENDING.RAW;

CREATE FILE FORMAT IF NOT EXISTS CSV_WITH_HEADER
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL', 'None')
  EMPTY_FIELD_AS_NULL = TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE;

-- Internal stage; files arrive via PUT from loader/load_to_snowflake.py.
-- In production this would be an external stage on S3 with a storage integration.
CREATE STAGE IF NOT EXISTS LENDING_LANDING
  FILE_FORMAT = CSV_WITH_HEADER
  COMMENT = 'Daily extracts from the core lending system';

-- RAW tables keep source columns as delivered plus load metadata.
-- Every table records which file each row came from and when it landed,
-- so any number in a mart can be traced back to a source file.

CREATE TABLE IF NOT EXISTS BORROWERS (
  BORROWER_ID      VARCHAR,
  FIRST_NAME       VARCHAR,
  LAST_NAME        VARCHAR,
  EMAIL            VARCHAR,
  DATE_OF_BIRTH    DATE,
  REGION           VARCHAR,
  EMPLOYMENT_TYPE  VARCHAR,
  ANNUAL_INCOME    NUMBER(12,2),
  CREDIT_SCORE     NUMBER(4,0),
  CREATED_AT       TIMESTAMP_NTZ,
  _SOURCE_FILE     VARCHAR,
  _LOADED_AT       TIMESTAMP_LTZ
);

CREATE TABLE IF NOT EXISTS LOANS (
  LOAN_ID              VARCHAR,
  BORROWER_ID          VARCHAR,
  PRODUCT_CODE         VARCHAR,
  PRINCIPAL_AMOUNT     NUMBER(14,2),
  ANNUAL_INTEREST_RATE NUMBER(6,4),
  TERM_MONTHS          NUMBER(4,0),
  ORIGINATION_DATE     DATE,
  ORIGINATION_CHANNEL  VARCHAR,
  _SOURCE_FILE         VARCHAR,
  _LOADED_AT           TIMESTAMP_LTZ
);

CREATE TABLE IF NOT EXISTS PAYMENTS (
  PAYMENT_ID           VARCHAR,
  LOAN_ID              VARCHAR,
  PAYMENT_DATE         DATE,
  AMOUNT               NUMBER(14,2),
  PAYMENT_METHOD       VARCHAR,
  SOURCE_EXTRACTED_AT  TIMESTAMP_NTZ,
  _SOURCE_FILE         VARCHAR,
  _LOADED_AT           TIMESTAMP_LTZ
)
COMMENT = 'Append-only. The source can re-send a payment, and staging de-duplicates on PAYMENT_ID.';
