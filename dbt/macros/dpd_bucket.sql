{#
  Days-past-due bucket from the number of instalments in arrears at month end.
  One missed instalment = 1-30 days, two = 31-60, three = 61-90, four or more = 90+.
#}
{% macro dpd_bucket(installments_in_arrears) %}
    case
        when {{ installments_in_arrears }} = 0 then 'CURRENT'
        when {{ installments_in_arrears }} = 1 then '1-30'
        when {{ installments_in_arrears }} = 2 then '31-60'
        when {{ installments_in_arrears }} = 3 then '61-90'
        else '90+'
    end
{% endmacro %}
