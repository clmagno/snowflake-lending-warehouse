select
    loan_id,
    payment_month,
    sum(amount)        as amount_paid,
    count(*)           as payment_count,
    max(payment_date)  as last_payment_date
from {{ ref('stg_lending__payments') }}
group by 1, 2
