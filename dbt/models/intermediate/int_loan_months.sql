{#
  One row per loan per calendar month, from the origination month to the
  reporting cut-off (var as_of_date). Rows continue past maturity so that a
  final repayment made after the maturity month, or arrears still owed on a
  matured loan, are captured; such loans show as CLOSED once fully repaid.
#}
with loans as (
    select * from {{ ref('stg_lending__loans') }}
),

months as (
    {{ month_spine('2015-01-01', var('as_of_date')) }}
)

select
    loans.loan_id,
    months.month_start                                                        as snapshot_month,
    cast({{ dbt.last_day('months.month_start', 'month') }} as date)           as month_end,
    {{ dbt.datediff('loans.origination_month', 'months.month_start', 'month') }} as months_on_book
from loans
inner join months
    on months.month_start >= loans.origination_month
