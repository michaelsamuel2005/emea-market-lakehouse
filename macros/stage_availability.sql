{#- ------------------------------------------------------------------------------------------
    stage_availability(market_id): one market's quarterly building availability snapshot ->
    the shared staging layout (areas in m2, standard quarter id).
   ------------------------------------------------------------------------------------------ -#}
{% macro stage_availability(market_id) -%}
{%- set m = var('markets')[market_id] -%}
{%- set ds = m['availability'] -%}
{%- set c = ds['columns'] -%}
{%- set nf = m['number_format'] -%}

{#- The bronze table is loaded as a dbt seed in this project, so declare the dependency: `dbt build` then
    loads the seed before building this view. The source() below still gives freshness and lineage. -#}
-- depends_on: {{ ref(ds['source']) }}
with source as (

    select * from {{ source('bronze', ds['source']) }}

),

parsed as (

    select
        '{{ market_id }}' as market_id,
        trim({{ c['building_id'] }}) as building_id_local,
        trim({{ c['period'] }}) as period_label,
        {{ period_year(c['period'], m['period_format']) }} as period_year,
        {{ period_quarter(c['period'], m['period_format']) }} as period_quarter,
        {{ to_m2(parse_number(c['available'], nf), m['area_unit']) }} as available_m2,
        {{ to_m2(parse_number(c['sublease'], nf), m['area_unit']) }} as sublease_m2,
        {{ parse_timestamp(c['submitted_at']) }} as submitted_at,
        '{{ ds['source'] }}' as source_table
    from source

)

select
    market_id,
    building_id_local,
    period_label,
    {{ quarter_id('period_year', 'period_quarter') }} as quarter_id,
    {{ quarter_end_date('period_year', 'period_quarter') }} as period_end_date,
    available_m2,
    sublease_m2,
    submitted_at,
    source_table
from parsed
{%- endmacro %}
