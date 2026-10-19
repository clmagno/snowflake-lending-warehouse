-- Collections in the monthly snapshot must equal the payments fact for every
-- month up to the reporting cut-off (no payment dropped or double counted).
with snapshot as (
    select snapshot_month, sum(amount_paid_in_month) as collected
    from {{ ref('fct_loan_monthly_snapshot') }}
    group by 1
),

payments as (
    select payment_month, sum(amount) as collected
    from {{ ref('fct_payments') }}
    group by 1
)

select
    payments.payment_month,
    payments.collected  as payments_total,
    snapshot.collected  as snapshot_total
from payments
left join snapshot
    on payments.payment_month = snapshot.snapshot_month
where abs(payments.collected - coalesce(snapshot.collected, 0)) > 0.01
