-- =============================================================================
-- 04_governance.sql
-- Dynamic data masking for borrower PII. Run as TRANSFORMER.
--
-- The policies are created once here. dbt attaches them to the mart columns
-- after every build (see the apply_pii_masking macro), because rebuilding a
-- table drops the policies attached to its columns.
-- =============================================================================
USE ROLE TRANSFORMER;
USE SCHEMA LENDING.GOVERNANCE;

-- Full value for PII_READER and TRANSFORMER; everyone else sees a mask.
CREATE MASKING POLICY IF NOT EXISTS PII_STRING_MASK AS (val STRING) RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('PII_READER') OR IS_ROLE_IN_SESSION('TRANSFORMER') THEN val
    ELSE '***MASKED***'
  END;

-- Emails keep the domain so analysts can still group by it.
CREATE MASKING POLICY IF NOT EXISTS PII_EMAIL_MASK AS (val STRING) RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('PII_READER') OR IS_ROLE_IN_SESSION('TRANSFORMER') THEN val
    ELSE '***@' || SPLIT_PART(val, '@', 2)
  END;

-- Dates of birth collapse to the year.
CREATE MASKING POLICY IF NOT EXISTS PII_DATE_MASK AS (val DATE) RETURNS DATE ->
  CASE
    WHEN IS_ROLE_IN_SESSION('PII_READER') OR IS_ROLE_IN_SESSION('TRANSFORMER') THEN val
    ELSE DATE_FROM_PARTS(YEAR(val), 1, 1)
  END;

-- Check what an analyst sees:
-- USE ROLE ANALYST;
-- SELECT BORROWER_ID, FULL_NAME, EMAIL, DATE_OF_BIRTH FROM LENDING.MARTS.DIM_BORROWER LIMIT 5;
