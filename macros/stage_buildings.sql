{#- ------------------------------------------------------------------------------------------
    stage_buildings(market_id): one market's building register -> the shared staging layout.
    Grades stay local here and are mapped once in silver.int_buildings.
   ------------------------------------------------------------------------------------------ -#}
{% macro stage_buildings(market_id) -%}
{%- set m = var('markets')[market_id] -%}
{%- set ds = m['buildings'] -%}
{%- set c = ds['columns'] -%}
{%- set nf = m['number_format'] -%}

{#- The bronze table is loaded as a dbt seed in this project, so declare the dependency: `dbt build` then
    loads the seed before building this view. The source() below still gives freshness and lineage. -#}
-- depends_on: {{ ref(ds['source']) }}
with source as (

    select * from {{ source('bronze', ds['source']) }}

)

select
    '{{ market_id }}' as market_id,
    trim({{ c['building_id'] }}) as building_id_local,
    trim({{ c['name'] }}) as building_name,
    trim({{ c['address'] }}) as building_address,
    trim({{ c['postcode'] }}) as postcode,
    nullif(trim({{ c['submarket'] }}), '') as submarket_local_name,
    nullif(trim({{ c['grade'] }}), '') as grade_local,
    {{ to_m2(parse_number(c['area'], nf), m['area_unit']) }} as total_area_m2,
    try_cast(nullif(trim({{ c['year_built'] }}), '') as integer) as year_built,
    try_cast(nullif(trim({{ c['year_refurbished'] }}), '') as integer) as year_refurbished,
    {{ parse_date(c['last_updated'], m['date_format']) }} as last_updated,
    '{{ ds['source'] }}' as source_table
from source
{%- endmacro %}
