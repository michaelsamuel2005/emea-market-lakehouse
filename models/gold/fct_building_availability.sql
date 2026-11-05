{{ config(liquid_clustered_by=['market_id', 'quarter_id']) }}

-- Periodic snapshot fact. Grain: one row per tracked building and quarter with space available.
-- Liquid-clustered by market and quarter on Databricks (DuckDB ignores the config).

select
    a.building_quarter_key,
    a.building_key,
    a.market_id,
    {{ surrogate_key(['a.market_id', 'a.submarket_id']) }} as submarket_key,
    a.submarket_id,
    a.quarter_id,
    a.period_end_date,
    a.available_m2,
    a.sublease_m2,
    a.available_m2 - a.sublease_m2 as direct_available_m2,
    a.total_area_m2 as building_area_m2,
    a.availability_rate
from {{ ref('int_availability') }} as a
