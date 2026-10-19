{#
  One row per month start between two dates (inclusive), named month_start.
  Implemented per adapter: Snowflake uses GENERATOR, DuckDB uses RANGE.
#}
{% macro month_spine(start_date, end_date) -%}
    {{ return(adapter.dispatch('month_spine', 'lending_warehouse')(start_date, end_date)) }}
{%- endmacro %}

{% macro snowflake__month_spine(start_date, end_date) %}
    select month_start
    from (
        select dateadd(
                   month,
                   row_number() over (order by seq4()) - 1,
                   date_trunc('month', to_date('{{ start_date }}'))
               ) as month_start
        from table(generator(rowcount => 600))
    )
    where month_start <= to_date('{{ end_date }}')
{% endmacro %}

{% macro default__month_spine(start_date, end_date) %}
    select cast(range as date) as month_start
    from range(
        date_trunc('month', date '{{ start_date }}'),
        date '{{ end_date }}' + interval 1 day,
        interval 1 month
    )
{% endmacro %}
