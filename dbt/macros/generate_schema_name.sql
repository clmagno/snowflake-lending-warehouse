{#
  Use the custom schema name as-is (STAGING, MARTS) instead of dbt's default
  "<target_schema>_<custom_schema>", so every environment gets the same layout.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema | trim }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
