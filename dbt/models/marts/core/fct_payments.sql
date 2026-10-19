{{
    config(
        materialized='incremental',
        unique_key='payment_id',
        incremental_strategy=('merge' if target.type == 'snowflake' else 'delete+insert'),
        on_schema_change='append_new_columns'
    )
}}

{#
  One row per repayment. Incremental: each run only processes payments that
  landed in RAW since the last run, and merges on payment_id so a payment
  re-sent by the source updates the existing row instead of duplicating it.
#}

with payments as (
    select * from {{ ref('stg_lending__payments') }}
    {% if is_incremental() %}
    where _loaded_at > (select coalesce(max(_loaded_at), cast('1900-01-01' as timestamp)) from {{ this }})
    {% endif %}
),

loans as (
    select loan_id, borrower_id, product_code, product_family, origination_date, monthly_installment
    from {{ ref('stg_lending__loans') }}
)

select
    payments.payment_id,
    payments.loan_id,
    loans.borrower_id,
    loans.product_code,
    loans.product_family,
    payments.payment_date,
    payments.payment_month,
    payments.amount,
    payments.payment_method,
    payments.amount > loans.monthly_installment * 1.05      as is_overpayment,
    {{ dbt.datediff('loans.origination_date', 'payments.payment_date', 'day') }} as days_since_origination,
    payments.source_extracted_at,
    payments._loaded_at
from payments
inner join loans
    on payments.loan_id = loans.loan_id
