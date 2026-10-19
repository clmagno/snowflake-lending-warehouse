{#
  Vintage analysis: for each origination quarter, the share of loans that
  have ever been 90+ days past due by each month on book. Comparing curves
  shows whether newer cohorts are performing better or worse than older ones.
#}

with snapshot as (
    select
        origination_quarter,
        product_family,
        months_on_book,
        loan_id,
        ever_90_plus_dpd
    from {{ ref('fct_loan_monthly_snapshot') }}
)

select
    origination_quarter,
    product_family,
    months_on_book,
    count(*)                                                     as loans_observed,
    sum(case when ever_90_plus_dpd then 1 else 0 end)            as loans_ever_90_plus,
    cast(sum(case when ever_90_plus_dpd then 1 else 0 end) as double)
        / nullif(count(*), 0)                                    as cumulative_90_plus_rate
from snapshot
group by 1, 2, 3
