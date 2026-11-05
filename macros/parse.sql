{#- ------------------------------------------------------------------------------------------
    Parsing and conversion helpers shared by every market's staging model.

    Each macro returns a SQL expression that runs unchanged on DuckDB, Databricks and Snowflake.
    The few functions the engines spell differently (a regular-expression group, building a date)
    go through macros/cross_db.sql; everything else uses functions all three share (try_cast on
    strings, replace, trim, lpad, concat, md5, concat_ws). No regular expression contains a
    backslash, because the engines treat backslashes in string literals differently.
   ------------------------------------------------------------------------------------------ -#}

{#- A raw string in the market's number convention -> double. Blanks become null. -#}
{% macro parse_number(expr, number_format) -%}
    {%- set cleaned = "nullif(trim(" ~ expr ~ "), '')" -%}
    {%- if number_format == 'point' -%}
        try_cast(replace({{ cleaned }}, ',', '') as double)
    {%- elif number_format == 'plain' -%}
        try_cast({{ cleaned }} as double)
    {%- elif number_format in ('fr', 'de') -%}
        try_cast(replace(replace(replace({{ cleaned }}, ' ', ''), '.', ''), ',', '.') as double)
    {%- else -%}
        {{ exceptions.raise_compiler_error("Unknown number_format: " ~ number_format) }}
    {%- endif -%}
{%- endmacro %}

{#- A yield or rate -> a fraction (0.0375). How the market writes it is configuration, not a guess:
    rate_format "percent" for "3.75%", "3,75 %" or "3.75"; "fraction" for "0.0375". -#}
{% macro parse_rate(expr, number_format, rate_format) -%}
    {%- set stripped = "replace(replace(" ~ expr ~ ", '%', ''), ' ', '')" -%}
    {%- if rate_format == 'percent' -%}
        {{ parse_number(stripped, number_format) }} / 100.0
    {%- elif rate_format == 'fraction' -%}
        {{ parse_number(stripped, number_format) }}
    {%- else -%}
        {{ exceptions.raise_compiler_error("Unknown rate_format: " ~ rate_format ~ " (expected percent or fraction)") }}
    {%- endif -%}
{%- endmacro %}

{#- Quarter labels. Each market writes the quarter differently; these extract the year and quarter number. -#}
{% macro period_year(expr, period_format) -%}
    {%- set patterns = {
        'uk':      'Q[1-4][ ]*([0-9]{4})',
        'fr':      'T[1-4][ ]*([0-9]{4})',
        'iso_q':   '([0-9]{4})-Q[1-4]',
        'de':      'Quartal[ ]*([0-9]{4})',
        'compact': '([0-9]{4})Q[1-4]',
        'es':      '[1-4]T[ ]*([0-9]{4})'
    } -%}
    {%- if period_format not in patterns -%}
        {{ exceptions.raise_compiler_error("Unknown period_format: " ~ period_format) }}
    {%- endif -%}
    try_cast({{ regex_group('trim(' ~ expr ~ ')', patterns[period_format]) }} as integer)
{%- endmacro %}

{% macro period_quarter(expr, period_format) -%}
    {%- set patterns = {
        'uk':      'Q([1-4])',
        'fr':      'T([1-4])',
        'iso_q':   '[0-9]{4}-Q([1-4])',
        'de':      '([1-4])[.][ ]*Quartal',
        'compact': '[0-9]{4}Q([1-4])',
        'es':      '([1-4])T'
    } -%}
    {%- if period_format not in patterns -%}
        {{ exceptions.raise_compiler_error("Unknown period_format: " ~ period_format) }}
    {%- endif -%}
    try_cast({{ regex_group('trim(' ~ expr ~ ')', patterns[period_format]) }} as integer)
{%- endmacro %}

{#- From a year and quarter number already parsed: the standard quarter id "2026Q3" and the quarter's last day. -#}
{% macro quarter_id(year_expr, quarter_expr) -%}
    {#- null-safe: DuckDB's concat skips nulls, Databricks' and Snowflake's return null; a failed parse must be null on all -#}
    case
        when {{ year_expr }} is null or {{ quarter_expr }} is null then null
        else concat(cast({{ year_expr }} as {{ dbt.type_string() }}), 'Q', cast({{ quarter_expr }} as {{ dbt.type_string() }}))
    end
{%- endmacro %}

{#- A quarter ends on 31 March, 30 June, 30 September or 31 December. -#}
{% macro quarter_end_date(year_expr, quarter_expr) -%}
    {{ date_from_parts(year_expr, '(' ~ quarter_expr ~ ') * 3', 'case when (' ~ quarter_expr ~ ') in (1, 4) then 31 else 30 end') }}
{%- endmacro %}

{#- Dates in the market's convention -> date. Day and month may have one or two digits (1/9/2026). -#}
{% macro parse_date(expr, date_format) -%}
    {%- set x = "trim(" ~ expr ~ ")" -%}
    {%- if date_format == 'iso' -%}
        try_cast(nullif({{ x }}, '') as date)
    {%- elif date_format in ('dmy_slash', 'dmy_dot') -%}
        {%- set sep = '/' if date_format == 'dmy_slash' else '[.]' -%}
        {%- set pattern = '^([0-9]{1,2})' ~ sep ~ '([0-9]{1,2})' ~ sep ~ '([0-9]{4})$' -%}
        {{ date_from_parts(regex_group(x, pattern, 3), regex_group(x, pattern, 2), regex_group(x, pattern, 1)) }}
    {%- else -%}
        {{ exceptions.raise_compiler_error("Unknown date_format: " ~ date_format) }}
    {%- endif -%}
{%- endmacro %}

{#- Submission timestamps are written by the portal in one format for every market. -#}
{% macro parse_timestamp(expr) -%}
    try_cast(nullif(trim({{ expr }}), '') as timestamp)
{%- endmacro %}

{#- Areas: everything downstream is in square metres. -#}
{% macro to_m2(expr, area_unit) -%}
    {%- if area_unit == 'sqft' -%}
        ({{ expr }}) / {{ var('sqft_per_m2') }}
    {%- elif area_unit == 'm2' -%}
        ({{ expr }})
    {%- else -%}
        {{ exceptions.raise_compiler_error("Unknown area_unit: " ~ area_unit) }}
    {%- endif -%}
{%- endmacro %}

{#- Rents: everything downstream is EUR per square metre per year.
    fx_expr is units of the rent's currency per one euro (GBP ~0.86, PLN ~4.3, EUR 1). -#}
{% macro rent_to_eur_m2_year(rent_expr, rent_unit, fx_expr) -%}
    {%- if rent_unit == 'per_sqft_year' -%}
        ({{ rent_expr }}) * {{ var('sqft_per_m2') }} / ({{ fx_expr }})
    {%- elif rent_unit == 'per_m2_year' -%}
        ({{ rent_expr }}) / ({{ fx_expr }})
    {%- elif rent_unit == 'per_m2_month' -%}
        ({{ rent_expr }}) * 12 / ({{ fx_expr }})
    {%- else -%}
        {{ exceptions.raise_compiler_error("Unknown rent_unit: " ~ rent_unit) }}
    {%- endif -%}
{%- endmacro %}

{#- The same conversion when the rent unit is a column rather than a compile-time constant
    (the conformed silver tables hold several markets, each with its own basis). -#}
{% macro rent_to_eur_m2_year_by_column(rent_expr, unit_expr, fx_expr) -%}
    case {{ unit_expr }}
        when 'per_sqft_year' then ({{ rent_expr }}) * {{ var('sqft_per_m2') }} / ({{ fx_expr }})
        when 'per_m2_year' then ({{ rent_expr }}) / ({{ fx_expr }})
        when 'per_m2_month' then ({{ rent_expr }}) * 12 / ({{ fx_expr }})
    end
{%- endmacro %}

{#- Deterministic surrogate key from one or more columns. -#}
{% macro surrogate_key(columns) -%}
    md5(concat_ws('|'
    {%- for c in columns -%}
        , coalesce(cast({{ c }} as {{ dbt.type_string() }}), '')
    {%- endfor -%}
    ))
{%- endmacro %}

{#- Lower-case, trimmed text for matching local codes and names regardless of casing or stray spaces. -#}
{% macro normalise_text(expr) -%}
    lower(trim({{ expr }}))
{%- endmacro %}
