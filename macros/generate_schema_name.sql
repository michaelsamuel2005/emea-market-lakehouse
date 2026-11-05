{#- A custom schema name is used as-is (bronze, silver, gold, ops, reference) instead of dbt's default
    "<target schema>_<custom>" so the medallion layers read the same on DuckDB and on Databricks. -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
