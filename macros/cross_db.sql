{#- ------------------------------------------------------------------------------------------
    The few places where DuckDB, Databricks (Spark SQL) and Snowflake disagree, in one file.

    Every model is written in SQL the three engines share. Where they spell a function differently
    or behave differently on bad input, the difference is handled here, through adapter.dispatch,
    so no model contains an engine check. dbt looks for <adapter>__<macro> first (snowflake__,
    databricks__, spark__, duckdb__) and falls back to default__.
   ------------------------------------------------------------------------------------------ -#}

{#- The text captured by one group of a regular expression, or null when the pattern does not match.
    DuckDB and Spark call it regexp_extract and return '' when nothing matches; Snowflake calls it
    regexp_substr (with the 'e' parameter to return a group) and returns null. nullif makes the
    three agree. Patterns must avoid backslashes: the engines escape them differently in literals. -#}
{% macro regex_group(expr, pattern, group=1) -%}
    {{ return(adapter.dispatch('regex_group', 'emea_market_lakehouse')(expr, pattern, group)) }}
{%- endmacro %}

{% macro default__regex_group(expr, pattern, group) -%}
    nullif(regexp_extract({{ expr }}, '{{ pattern }}', {{ group }}), '')
{%- endmacro %}

{% macro snowflake__regex_group(expr, pattern, group) -%}
    regexp_substr({{ expr }}, '{{ pattern }}', 1, 1, 'e', {{ group }})
{%- endmacro %}

{#- A date from year, month and day (integers or digit strings), or null if a part is missing or
    the parts are not a real date (31 June). make_date and date_from_parts are spelt differently
    and raise an error on an impossible date under ANSI mode (Databricks); try_cast of an ISO
    string returns null on all three engines. -#}
{% macro date_from_parts(year_expr, month_expr, day_expr) -%}
    case
        when {{ year_expr }} is null or {{ month_expr }} is null or {{ day_expr }} is null then null
        else try_cast(concat(
            lpad(cast({{ year_expr }} as {{ dbt.type_string() }}), 4, '0'), '-',
            lpad(cast({{ month_expr }} as {{ dbt.type_string() }}), 2, '0'), '-',
            lpad(cast({{ day_expr }} as {{ dbt.type_string() }}), 2, '0')
        ) as date)
    end
{%- endmacro %}

{#- Division that returns null instead of failing when the denominator is zero. Databricks runs
    in ANSI mode, where x / 0 raises an error; DuckDB and Snowflake would return null or infinity.
    Dividing by nullif(d, 0) gives null on every engine. -#}
{% macro safe_divide(numerator, denominator) -%}
    ({{ numerator }}) / nullif({{ denominator }}, 0)
{%- endmacro %}

{#- Numbers as text for sentences. Casting a double to text gives '10.0' on DuckDB and Spark but
    '10' on Snowflake; a fixed-scale decimal prints the same on all three. -#}
{% macro format_decimal(expr, places) -%}
    cast(cast(round({{ expr }}, {{ places }}) as decimal(18, {{ places }})) as {{ dbt.type_string() }})
{%- endmacro %}

{% macro format_integer(expr) -%}
    cast(cast(round({{ expr }}) as bigint) as {{ dbt.type_string() }})
{%- endmacro %}
