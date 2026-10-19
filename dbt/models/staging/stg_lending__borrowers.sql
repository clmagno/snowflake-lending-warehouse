with source as (
    select * from {{ source('raw', 'borrowers') }}
),

latest as (
    -- keep the most recent version of each borrower if a record is re-delivered
    select *
    from source
    qualify row_number() over (partition by borrower_id order by _loaded_at desc) = 1
)

select
    borrower_id,
    first_name,
    last_name,
    first_name || ' ' || last_name                 as full_name,
    lower(trim(email))                             as email,
    date_of_birth,
    upper(region)                                  as region_code,
    upper(employment_type)                         as employment_type,
    cast(annual_income as decimal(12, 2))          as annual_income,
    credit_score,
    case
        when credit_score >= 800 then 'EXCELLENT'
        when credit_score >= 700 then 'GOOD'
        when credit_score >= 600 then 'FAIR'
        else 'POOR'
    end                                            as credit_band,
    cast(created_at as timestamp)                  as customer_since,
    _loaded_at
from latest
