with source as (
    select * from {{ source('raw', 'loans') }}
),

latest as (
    select *
    from source
    qualify row_number() over (partition by loan_id order by _loaded_at desc) = 1
),

typed as (
    select
        loan_id,
        borrower_id,
        upper(product_code)                              as product_code,
        cast(principal_amount as decimal(14, 2))         as principal_amount,
        cast(annual_interest_rate as decimal(6, 4))      as annual_interest_rate,
        cast(annual_interest_rate as double) / 12        as monthly_rate,
        term_months,
        origination_date,
        upper(origination_channel)                       as origination_channel,
        _loaded_at
    from latest
)

select
    loan_id,
    borrower_id,
    product_code,
    case
        when product_code like 'HOME_LOAN%' then 'HOME_LOAN'
        when product_code = 'PERSONAL_LOAN' then 'PERSONAL_LOAN'
        when product_code = 'CAR_LOAN' then 'CAR_LOAN'
        else 'OTHER'
    end                                                  as product_family,
    product_code = 'HOME_LOAN_FIXED'                     as is_fixed_rate,
    principal_amount,
    annual_interest_rate,
    monthly_rate,
    term_months,
    -- standard amortising instalment: P * r / (1 - (1 + r)^-n)
    cast(round(
        principal_amount * monthly_rate / (1 - power(1 + monthly_rate, -term_months)),
        2
    ) as decimal(14, 2))                                 as monthly_installment,
    origination_date,
    cast(date_trunc('month', origination_date) as date)  as origination_month,
    cast(date_trunc('quarter', origination_date) as date) as origination_quarter,
    cast({{ dbt.dateadd('month', 'term_months', 'origination_date') }} as date) as maturity_date,
    origination_channel,
    _loaded_at
from typed
