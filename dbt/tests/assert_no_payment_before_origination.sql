{{ config(severity='warn') }}
-- A repayment dated before its loan was originated points to a source data issue.
select payment_id, loan_id, days_since_origination
from {{ ref('fct_payments') }}
where days_since_origination < 0
