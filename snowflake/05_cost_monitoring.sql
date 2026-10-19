-- =============================================================================
-- 05_cost_monitoring.sql
-- Queries for watching credit spend and slow queries. Run as ACCOUNTADMIN
-- (ACCOUNT_USAGE views can lag by up to ~3 hours).
-- =============================================================================
USE ROLE ACCOUNTADMIN;

-- Credits per warehouse per day, last 30 days
SELECT
  DATE_TRUNC('day', START_TIME) AS usage_day,
  WAREHOUSE_NAME,
  ROUND(SUM(CREDITS_USED), 3)   AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME >= DATEADD(day, -30, CURRENT_DATE())
  AND WAREHOUSE_NAME IN ('LOADING_WH', 'TRANSFORM_WH', 'REPORTING_WH')
GROUP BY 1, 2
ORDER BY 1 DESC, 3 DESC;

-- Time spent per workload, using the query tags set by the loader and dbt
SELECT
  QUERY_TAG,
  COUNT(*)                                    AS queries,
  ROUND(SUM(TOTAL_ELAPSED_TIME) / 1000, 1)    AS total_seconds,
  ROUND(SUM(BYTES_SCANNED) / POWER(1024, 3), 2) AS gb_scanned
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD(day, -7, CURRENT_DATE())
  AND QUERY_TAG LIKE 'lending:%'
GROUP BY 1
ORDER BY total_seconds DESC;

-- Slowest dbt models in the last 7 days, and how well they pruned partitions
SELECT
  QUERY_TAG,
  LEFT(QUERY_TEXT, 120)                        AS query_start,
  ROUND(TOTAL_ELAPSED_TIME / 1000, 1)          AS seconds,
  PARTITIONS_SCANNED,
  PARTITIONS_TOTAL,
  ROUND(PARTITIONS_SCANNED / NULLIF(PARTITIONS_TOTAL, 0) * 100, 1) AS pct_partitions_scanned
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD(day, -7, CURRENT_DATE())
  AND QUERY_TAG = 'lending:dbt'
ORDER BY TOTAL_ELAPSED_TIME DESC
LIMIT 20;

-- Clustering health of the monthly snapshot (clustered on SNAPSHOT_MONTH)
SELECT SYSTEM$CLUSTERING_INFORMATION('LENDING.MARTS.FCT_LOAN_MONTHLY_SNAPSHOT');
