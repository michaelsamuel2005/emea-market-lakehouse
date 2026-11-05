-- AI-ready view of the market KPIs. Grain: one row per market and quarter.
-- Same numbers as mart_market_kpis, shaped for retrieval and for language models: every column
-- name carries its unit, every row carries a plain-language summary sentence, and the names and
-- units match ref_metric_definitions, which doubles as the instructions for a Genie space.

with kpis as (

    select * from {{ ref('mart_market_kpis') }}

),

markets as (

    select * from {{ ref('dim_market') }}

),

quarters as (

    select * from {{ ref('dim_quarter') }}

)

select
    k.market_kpi_key,
    k.market_id,
    m.market_name,
    m.country_name,
    m.region,
    k.quarter_id,
    q.quarter_label,
    k.period_end_date,
    cast(round(k.stock_m2) as bigint) as office_stock_sqm,
    cast(round(k.vacant_m2) as bigint) as vacant_space_sqm,
    round(k.vacancy_rate * 100, 1) as vacancy_rate_pct,
    cast(round(k.take_up_m2) as bigint) as take_up_quarter_sqm,
    cast(round(k.take_up_rolling_4q_m2) as bigint) as take_up_rolling_12m_sqm,
    cast(round(k.net_absorption_m2) as bigint) as net_absorption_sqm,
    cast(round(k.prime_rent_eur_m2_yr) as bigint) as prime_rent_eur_per_sqm_per_year,
    round(k.prime_rent_growth_yoy * 100, 1) as prime_rent_growth_yoy_pct,
    round(k.prime_yield * 100, 2) as prime_yield_pct,
    cast(round(k.under_construction_m2) as bigint) as under_construction_sqm,
    cast(k.deal_count as bigint) as leasing_deals_count,
    cast(round(k.avg_deal_size_m2) as bigint) as average_deal_size_sqm,
    -- Built with || rather than concat(): || returns null when any piece is null on all three engines
    -- (DuckDB's concat skips nulls), so each optional figure falls back to a phrase via coalesce.
    -- format_decimal / format_integer print numbers the same way on DuckDB, Databricks and Snowflake.
    m.market_name || ' office market, ' || q.quarter_label || ': '
    || coalesce('vacancy rate ' || {{ format_decimal('k.vacancy_rate * 100', 1) }} || '%', 'vacancy rate not reported')
    || coalesce(', take-up ' || {{ format_integer('k.take_up_m2') }} || ' sq m in the quarter', ', take-up not reported')
    || coalesce(', prime rent EUR ' || {{ format_integer('k.prime_rent_eur_m2_yr') }} || ' per sq m per year', ', prime rent not reported')
    || coalesce(' (' || {{ format_decimal('k.prime_rent_growth_yoy * 100', 1) }} || '% year on year)', '')
    || coalesce(', prime yield ' || {{ format_decimal('k.prime_yield * 100', 2) }} || '%', ', prime yield not reported')
    || ', ' || coalesce({{ format_integer('k.deal_count') }}, '0') || ' leasing deals logged.' as summary_text
from kpis as k
inner join markets as m
    on k.market_id = m.market_id
inner join quarters as q
    on k.quarter_id = q.quarter_id
