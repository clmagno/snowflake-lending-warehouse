with source as (
    select * from {{ source('raw', 'payments') }}
),

deduplicated as (
    -- The source re-sends some payments in later extracts. Keep one row per
    -- payment_id: the most recent extract wins.
    select *
    from source
    qualify row_number() over (
        partition by payment_id
        order by source_extracted_at desc, _loaded_at desc
    ) = 1
)

select
    payment_id,
    loan_id,
    payment_date,
    cast(date_trunc('month', payment_date) as date) as payment_month,
    cast(amount as decimal(14, 2))                  as amount,
    upper(payment_method)                           as payment_method,
    cast(source_extracted_at as timestamp)          as source_extracted_at,
    _loaded_at
from deduplicated
