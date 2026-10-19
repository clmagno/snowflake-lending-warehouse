{{
    config(
        post_hook="{{ apply_pii_masking({
            'first_name': 'pii_string_mask',
            'last_name': 'pii_string_mask',
            'full_name': 'pii_string_mask',
            'email': 'pii_email_mask',
            'date_of_birth': 'pii_date_mask'
        }) }}"
    )
}}

{# PII columns are masked in Snowflake for every role except PII_READER and TRANSFORMER. #}

with borrowers as (
    select * from {{ ref('stg_lending__borrowers') }}
),

loan_counts as (
    select
        borrower_id,
        count(*)                as total_loans,
        sum(principal_amount)   as total_principal_borrowed,
        min(origination_date)   as first_loan_date
    from {{ ref('stg_lending__loans') }}
    group by 1
)

select
    borrowers.borrower_id,
    borrowers.first_name,
    borrowers.last_name,
    borrowers.full_name,
    borrowers.email,
    borrowers.date_of_birth,
    borrowers.region_code,
    borrowers.employment_type,
    borrowers.annual_income,
    case
        when borrowers.annual_income < 60000 then 'UNDER_60K'
        when borrowers.annual_income < 100000 then '60K_100K'
        when borrowers.annual_income < 150000 then '100K_150K'
        else '150K_PLUS'
    end                                                 as income_band,
    borrowers.credit_score,
    borrowers.credit_band,
    borrowers.customer_since,
    coalesce(loan_counts.total_loans, 0)                as total_loans,
    coalesce(loan_counts.total_principal_borrowed, 0)   as total_principal_borrowed,
    loan_counts.first_loan_date
from borrowers
left join loan_counts
    on borrowers.borrower_id = loan_counts.borrower_id
