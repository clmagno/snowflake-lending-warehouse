{#
  Attach the masking policies from snowflake/04_governance.sql to PII columns.
  Called as a post-hook, because rebuilding a table drops its column policies.
  Does nothing outside Snowflake.

  columns: mapping of column name -> policy name in LENDING.GOVERNANCE
#}
{% macro apply_pii_masking(columns) %}
    {% if target.type == 'snowflake' %}
        {% for column, policy in columns.items() %}
            alter table {{ this }} modify column {{ column }}
                set masking policy {{ target.database }}.governance.{{ policy }} force;
        {% endfor %}
    {% else %}
        select 1 /* masking policies are Snowflake-only */
    {% endif %}
{% endmacro %}
