-- Every distinct payment in RAW must reach fct_payments exactly once, for the
-- same total amount. Returns rows (= fails) when counts or totals differ.
with source_totals as (
    select count(*) as payment_count, sum(amount) as total_amount
    from (
        select payment_id, max(amount) as amount
        from {{ source('raw', 'payments') }}
        group by payment_id
    ) as distinct_payments
),

mart_totals as (
    select count(*) as payment_count, sum(amount) as total_amount
    from {{ ref('fct_payments') }}
)

select
    source_totals.payment_count as source_count,
    mart_totals.payment_count   as mart_count,
    source_totals.total_amount  as source_amount,
    mart_totals.total_amount    as mart_amount
from source_totals
cross join mart_totals
where source_totals.payment_count != mart_totals.payment_count
   or abs(source_totals.total_amount - mart_totals.total_amount) > 0.01
