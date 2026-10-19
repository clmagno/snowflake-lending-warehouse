with loans as (
    select * from {{ ref('stg_lending__loans') }}
),

latest_position as (
    select *
    from {{ ref('fct_loan_monthly_snapshot') }}
    qualify row_number() over (partition by loan_id order by snapshot_month desc) = 1
)

select
    loans.loan_id,
    loans.borrower_id,
    loans.product_code,
    loans.product_family,
    loans.is_fixed_rate,
    loans.principal_amount,
    loans.annual_interest_rate,
    loans.term_months,
    loans.monthly_installment,
    loans.origination_date,
    loans.origination_month,
    loans.origination_quarter,
    loans.maturity_date,
    loans.origination_channel,
    latest_position.snapshot_month          as latest_snapshot_month,
    latest_position.account_status          as current_status,
    latest_position.dpd_bucket              as current_dpd_bucket,
    latest_position.arrears_amount          as current_arrears_amount,
    latest_position.estimated_balance       as current_estimated_balance,
    latest_position.ever_90_plus_dpd
from loans
left join latest_position
    on loans.loan_id = latest_position.loan_id
