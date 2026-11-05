{{ config(liquid_clustered_by=['market_id', 'quarter_id']) }}

-- Periodic snapshot fact. Grain: one row per market, submarket and quarter.
-- On Databricks the table is liquid-clustered by market and quarter (the two filters every query uses);
-- dbt-databricks runs OPTIMIZE after each build. DuckDB ignores the config.
-- The reported figures come from the market's quarterly submission (latest version); alongside
-- them sit the two bottom-up views the lakehouse can compute itself: the vacancy implied by the
-- building register and the take-up implied by the logged deals. The gaps between reported and
-- bottom-up figures are what ops.ops_dq_reconciliation_* report on.

with reported as (

    select * from {{ ref('int_market_stats') }}

),

register_space as (

    select
        market_id,
        submarket_id,
        quarter_id,
        sum(available_m2) as register_available_m2,
        sum(sublease_m2) as register_sublease_m2,
        count(*) as register_buildings_with_space
    from {{ ref('int_availability') }}
    group by market_id, submarket_id, quarter_id

),

register_stock as (

    -- the whole tracked register, including fully let buildings, is the denominator of the bottom-up vacancy rate
    select
        market_id,
        submarket_id,
        sum(total_area_m2) as register_tracked_area_m2,
        count(*) as register_buildings
    from {{ ref('int_buildings') }}
    group by market_id, submarket_id

),

register as (

    select
        sp.market_id,
        sp.submarket_id,
        sp.quarter_id,
        sp.register_available_m2,
        sp.register_sublease_m2,
        sp.register_buildings_with_space,
        st.register_tracked_area_m2,
        st.register_buildings
    from register_space as sp
    inner join register_stock as st
        on sp.market_id = st.market_id
        and sp.submarket_id = st.submarket_id

),

deals as (

    select
        market_id,
        submarket_id,
        quarter_id,
        count(*) as deal_count,
        sum(area_m2) as deals_area_m2,
        avg(area_m2) as avg_deal_size_m2,
        max(area_m2) as largest_deal_m2,
        sum(case when rent_eur_m2_yr is not null then area_m2 end) as deals_area_with_rent_m2,
        sum(rent_eur_m2_yr * area_m2) as rent_weighted_sum_eur
    from {{ ref('int_deals_clean') }}
    group by market_id, submarket_id, quarter_id

)

select
    r.market_quarter_key,
    {{ surrogate_key(['r.market_id', 'r.submarket_id']) }} as submarket_key,
    r.market_id,
    r.submarket_id,
    r.quarter_id,
    r.period_end_date,
    -- reported by the market
    r.stock_m2,
    r.vacant_m2,
    r.vacancy_rate,
    r.stock_m2 - r.vacant_m2 as occupied_m2,
    r.take_up_m2,
    r.prime_rent_eur_m2_yr,
    r.prime_rent_local,
    r.rent_currency as prime_rent_local_currency,
    r.rent_unit as prime_rent_local_unit,
    r.prime_yield,
    r.completions_m2,
    r.under_construction_m2,
    -- bottom-up from the building register (tracked buildings only)
    g.register_available_m2,
    g.register_sublease_m2,
    g.register_tracked_area_m2,
    g.register_buildings,
    g.register_buildings_with_space,
    {{ safe_divide('g.register_available_m2', 'g.register_tracked_area_m2') }} as register_vacancy_rate,
    -- bottom-up from the deal log
    coalesce(d.deal_count, 0) as deal_count,
    coalesce(d.deals_area_m2, 0) as deals_area_m2,
    d.avg_deal_size_m2,
    d.largest_deal_m2,
    {{ safe_divide('d.rent_weighted_sum_eur', 'd.deals_area_with_rent_m2') }} as achieved_rent_eur_m2_yr,
    -- provenance
    r.submitted_at as reported_submitted_at,
    r.submission_count
from reported as r
left join register as g
    on r.market_id = g.market_id
    and r.submarket_id = g.submarket_id
    and r.quarter_id = g.quarter_id
left join deals as d
    on r.market_id = d.market_id
    and r.submarket_id = d.submarket_id
    and r.quarter_id = d.quarter_id
