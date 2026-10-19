{{
    config(
        materialized='table',
        cluster_by=['snapshot_month']
    )
}}

{#
  Month-end position of every loan: what was due, what was paid, arrears,
  days-past-due bucket and an estimated balance. This is the table credit
  risk reporting is built on.

  Simplifications (documented in the README):
  * instalment k falls due k months after origination;
  * arrears = scheduled repayments to date - cumulative repayments, floored at 0;
  * the balance follows the amortisation schedule, adjusted for arrears and
    prepayments; interest on arrears is ignored.
#}

with loan_months as (
    select * from {{ ref('int_loan_months') }}
),

loans as (
    select * from {{ ref('stg_lending__loans') }}
),

payments as (
    select * from {{ ref('int_payments_by_loan_month') }}
),

joined as (
    select
        loan_months.loan_id,
        loan_months.snapshot_month,
        loan_months.month_end,
        loan_months.months_on_book,
        loans.borrower_id,
        loans.product_code,
        loans.product_family,
        loans.origination_quarter,
        loans.principal_amount,
        loans.monthly_rate,
        loans.monthly_installment,
        loans.term_months,
        coalesce(payments.amount_paid, 0)    as amount_paid_in_month,
        coalesce(payments.payment_count, 0)  as payments_in_month
    from loan_months
    inner join loans
        on loan_months.loan_id = loans.loan_id
    left join payments
        on loan_months.loan_id = payments.loan_id
       and loan_months.snapshot_month = payments.payment_month
),

cumulative as (
    select
        *,
        least(months_on_book, term_months) as installments_due,
        sum(amount_paid_in_month) over (
            partition by loan_id
            order by snapshot_month
            rows between unbounded preceding and current row
        ) as cumulative_paid
    from joined
),

positions as (
    select
        *,
        installments_due * monthly_installment as expected_paid_to_date,
        greatest(installments_due * monthly_installment - cumulative_paid, 0) as arrears_amount,
        greatest(cumulative_paid - installments_due * monthly_installment, 0) as prepaid_amount,
        -- scheduled balance after k instalments: P(1+r)^k - I((1+r)^k - 1)/r
        greatest(
            principal_amount * power(1 + monthly_rate, installments_due)
              - monthly_installment * (power(1 + monthly_rate, installments_due) - 1) / monthly_rate,
            0
        ) as scheduled_balance
    from cumulative
),

classified as (
    select
        *,
        case
            when arrears_amount < 1 then 0  -- ignore cent-level rounding
            else cast(ceil(arrears_amount / monthly_installment) as integer)
        end as installments_in_arrears
    from positions
),

final as (
    select
        *,
        greatest(scheduled_balance + arrears_amount - prepaid_amount, 0) as estimated_balance
    from classified
)

select
    loan_id || '|' || cast(snapshot_month as varchar)          as loan_month_key,
    loan_id,
    snapshot_month,
    month_end,
    borrower_id,
    product_code,
    product_family,
    origination_quarter,
    months_on_book,
    installments_due,
    cast(monthly_installment as decimal(14, 2))                 as monthly_installment,
    cast(amount_paid_in_month as decimal(14, 2))                as amount_paid_in_month,
    payments_in_month,
    cast(cumulative_paid as decimal(16, 2))                     as cumulative_paid,
    cast(expected_paid_to_date as decimal(16, 2))               as expected_paid_to_date,
    cast(arrears_amount as decimal(16, 2))                      as arrears_amount,
    cast(prepaid_amount as decimal(16, 2))                      as prepaid_amount,
    installments_in_arrears,
    installments_in_arrears * 30                                as days_past_due_estimate,
    {{ dpd_bucket('installments_in_arrears') }}                 as dpd_bucket,
    installments_in_arrears >= 2                                as is_30_plus_dpd,
    installments_in_arrears >= 4                                as is_90_plus_dpd,
    max(case when installments_in_arrears >= 4 then 1 else 0 end) over (
        partition by loan_id
        order by snapshot_month
        rows between unbounded preceding and current row
    ) = 1                                                       as ever_90_plus_dpd,
    cast(estimated_balance as decimal(16, 2))                   as estimated_balance,
    case
        when estimated_balance < 1 and arrears_amount < 1 then 'CLOSED'
        when installments_in_arrears >= 4 then 'DEFAULT'
        when installments_in_arrears >= 1 then 'ARREARS'
        else 'PERFORMING'
    end                                                         as account_status
from final
