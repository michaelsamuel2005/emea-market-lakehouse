{{ config(liquid_clustered_by=['market_id', 'deal_date']) }}

-- Transaction fact. Grain: one row per leasing deal that passed every silver check.
-- Liquid-clustered by market and deal date on Databricks (DuckDB and Snowflake ignore the config).
-- Rents are in EUR per m2 per year for every market; the local figure is kept for traceability.
-- Two building keys: building_key to dim_building (the building today) and building_version_key to
-- dim_building_history (the building on the deal date, e.g. its grade before a refurbishment).

select
    d.deal_key,
    d.market_id,
    {{ surrogate_key(['d.market_id', 'd.submarket_id']) }} as submarket_key,
    d.submarket_id,
    d.building_key,
    bv.building_version_key,
    d.tenant_key,
    dt.date_key as deal_date_key,
    d.deal_date,
    d.quarter_id,
    d.deal_type_code,
    d.sector_code,
    d.deal_ref,
    d.area_m2,
    d.rent_eur_m2_yr,
    d.area_m2 * d.rent_eur_m2_yr as annual_rent_eur,
    d.rent_local_as_reported as rent_local,
    d.rent_currency as rent_local_currency,
    d.rent_unit as rent_local_unit,
    d.rent_to_prime_ratio,
    d.rent_suppressed_reason,
    d.lease_term_years,
    d.submarket_derived_from_building,
    d.submitted_at
from {{ ref('int_deals_clean') }} as d
left join {{ ref('dim_date') }} as dt
    on d.deal_date = dt.date_day
left join {{ ref('dim_building_history') }} as bv
    on d.building_key = bv.building_key
    and d.deal_date >= bv.valid_from
    and d.deal_date < bv.valid_to
