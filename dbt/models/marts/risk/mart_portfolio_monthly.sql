{#
  Portfolio health by month and product family: the numbers a credit risk
  committee pack opens with. Closed loans are excluded from the active book.
#}

with snapshot as (
    select * from {{ ref('fct_loan_monthly_snapshot') }}
    where account_status != 'CLOSED'
)

select
    snapshot_month,
    product_family,
    count(*)                                                        as active_loans,
    sum(estimated_balance)                                          as total_balance,
    sum(arrears_amount)                                             as total_arrears,
    sum(case when is_30_plus_dpd then 1 else 0 end)                 as loans_30_plus_dpd,
    sum(case when is_90_plus_dpd then 1 else 0 end)                 as loans_90_plus_dpd,
    cast(sum(case when is_30_plus_dpd then 1 else 0 end) as double)
        / nullif(count(*), 0)                                       as pct_loans_30_plus_dpd,
    cast(sum(case when is_90_plus_dpd then 1 else 0 end) as double)
        / nullif(count(*), 0)                                       as pct_loans_90_plus_dpd,
    cast(sum(case when is_30_plus_dpd then estimated_balance else 0 end) as double)
        / nullif(sum(estimated_balance), 0)                         as pct_balance_30_plus_dpd,
    sum(amount_paid_in_month)                                       as collections_in_month
from snapshot
group by 1, 2
