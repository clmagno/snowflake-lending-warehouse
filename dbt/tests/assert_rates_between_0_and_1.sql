select *
from {{ ref('mart_portfolio_monthly') }}
where pct_loans_30_plus_dpd not between 0 and 1
   or pct_loans_90_plus_dpd not between 0 and 1
   or pct_balance_30_plus_dpd not between 0 and 1
