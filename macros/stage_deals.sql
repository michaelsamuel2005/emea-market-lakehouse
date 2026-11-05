{#- ------------------------------------------------------------------------------------------
    stage_deals(market_id)

    One market's leasing deal log -> the shared staging layout. Rents stay in the market's own
    currency and basis here (rent_local / rent_currency / rent_unit); silver.int_deals converts
    them to EUR per m2 per year once, with the FX table. Codes (deal type, sector) stay local here
    and are mapped once in silver.int_deals too.
   ------------------------------------------------------------------------------------------ -#}
{% macro stage_deals(market_id) -%}
{%- set m = var('markets')[market_id] -%}
{%- set ds = m['deals'] -%}
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
    trim({{ c['deal_ref'] }}) as deal_ref,
    trim({{ c['deal_date'] }}) as deal_date_raw,
    {{ parse_date(c['deal_date'], m['date_format']) }} as deal_date,
    trim({{ c['building'] }}) as building_name,
    trim({{ c['address'] }}) as building_address,
    nullif(trim({{ c['submarket'] }}), '') as submarket_local_name,
    trim({{ c['tenant'] }}) as tenant_name_raw,
    trim({{ c['sector'] }}) as sector_local,
    {{ to_m2(parse_number(c['area'], nf), m['area_unit']) }} as area_m2,
    {{ parse_number(c['rent'], nf) }} as rent_local,
    {%- if ds.get('rent_currency_column') %}
    coalesce(nullif(trim({{ ds['rent_currency_column'] }}), ''), '{{ m['currency'] }}') as rent_currency,
    {%- else %}
    '{{ m['currency'] }}' as rent_currency,
    {%- endif %}
    '{{ m['rent_unit'] }}' as rent_unit,
    {{ parse_number(c['term_years'], 'plain') }} as lease_term_years,
    trim({{ c['deal_type'] }}) as deal_type_local,
    {{ parse_timestamp(c['submitted_at']) }} as submitted_at,
    '{{ ds['source'] }}' as source_table
from source
{%- endmacro %}
