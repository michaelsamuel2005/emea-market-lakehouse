{#- ------------------------------------------------------------------------------------------
    stage_market_stats(market_id)

    Turns one market's quarterly submission (its own column names, units, number and period
    formats) into the shared staging layout. The market's conventions come from
    vars.markets.<market_id> in dbt_project.yml, so a staging model is one line:

        {{ stage_market_stats('PAR') }}

    Output grain: one row per submission row (resubmissions are still present; silver.int_market_stats
    keeps the latest per market, submarket and quarter).
   ------------------------------------------------------------------------------------------ -#}
{% macro stage_market_stats(market_id) -%}
{%- set m = var('markets')[market_id] -%}
{%- set ds = m['market_stats'] -%}
{%- set c = ds['columns'] -%}
{%- set nf = m['number_format'] -%}
{%- set rf = m['rate_format'] -%}

{#- The bronze table is loaded as a dbt seed in this project, so declare the dependency: `dbt build` then
    loads the seed before building this view. The source() below still gives freshness and lineage. -#}
-- depends_on: {{ ref(ds['source']) }}
with source as (

    select * from {{ source('bronze', ds['source']) }}

),

parsed as (

    select
        '{{ market_id }}' as market_id,
        trim({{ c['submarket'] }}) as submarket_local_name,
        trim({{ c['period'] }}) as period_label,
        {{ period_year(c['period'], m['period_format']) }} as period_year,
        {{ period_quarter(c['period'], m['period_format']) }} as period_quarter,
        {{ to_m2(parse_number(c['stock'], nf), m['area_unit']) }} as stock_m2,
        {%- if m.get('vacancy_reported_as', 'area') == 'rate' %}
        cast(null as double) as vacant_m2_reported,
        {{ parse_rate(c['vacant'], nf, rf) }} as vacancy_rate_reported,
        {%- else %}
        {{ to_m2(parse_number(c['vacant'], nf), m['area_unit']) }} as vacant_m2_reported,
        cast(null as double) as vacancy_rate_reported,
        {%- endif %}
        {{ to_m2(parse_number(c['take_up'], nf), m['area_unit']) }} as take_up_m2,
        {{ parse_number(c['prime_rent'], nf) }} as prime_rent_local,
        '{{ m['currency'] }}' as rent_currency,
        '{{ m['rent_unit'] }}' as rent_unit,
        {{ parse_rate(c['prime_yield'], nf, rf) }} as prime_yield,
        {{ to_m2(parse_number(c['completions'], nf), m['area_unit']) }} as completions_m2,
        {{ to_m2(parse_number(c['under_construction'], nf), m['area_unit']) }} as under_construction_m2,
        {{ parse_timestamp(c['submitted_at']) }} as submitted_at,
        '{{ ds['source'] }}' as source_table
    from source

)

select
    market_id,
    submarket_local_name,
    period_label,
    period_year,
    period_quarter,
    {{ quarter_id('period_year', 'period_quarter') }} as quarter_id,
    {{ quarter_end_date('period_year', 'period_quarter') }} as period_end_date,
    stock_m2,
    coalesce(vacant_m2_reported, stock_m2 * vacancy_rate_reported) as vacant_m2,
    take_up_m2,
    prime_rent_local,
    rent_currency,
    rent_unit,
    prime_yield,
    completions_m2,
    under_construction_m2,
    submitted_at,
    source_table
from parsed
{%- endmacro %}
