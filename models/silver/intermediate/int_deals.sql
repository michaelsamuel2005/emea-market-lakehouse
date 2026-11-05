{{ config(materialized='table') }}

-- Every market's leasing deals in one conformed table, with the checks a deal must pass before it
-- reaches gold. Grain: one row per submitted deal row. Nothing is deleted here: duplicates and
-- rows that fail a check carry a quarantine_reason, int_deals_clean keeps the rest, and
-- ops.ops_dq_quarantine_summary reports what was held back and why.
--
-- Standardisation done once, here, for every market:
--   * local deal-type and sector labels -> shared codes (ref_deal_type_mapping, ref_sector_mapping)
--   * a blank submarket is derived from the building register
--   * rent in the market's own currency and basis -> EUR per m2 per year, with the quarter's FX rate
--   * the deal's rent is compared with its submarket's prime rent for that quarter, which catches
--     monthly figures typed into an annual file (12x) and the reverse: the deal is kept, its rent is suppressed

with unioned as (

    select * from {{ ref('int_deals_unioned') }}

),

prepared as (

    select
        *,
        {{ quarter_id('year(deal_date)', 'quarter(deal_date)') }} as quarter_id,
        regexp_replace({{ normalise_text('tenant_name_raw') }}, ' ltd$', '') as tenant_name_norm
    from unioned

),

buildings as (

    select * from {{ ref('int_buildings') }}

),

submarkets as (

    select * from {{ ref('ref_submarkets') }}

),

deal_types as (

    select * from {{ ref('ref_deal_type_mapping') }}

),

sectors as (

    select * from {{ ref('ref_sector_mapping') }}

),

fx as (

    select * from {{ ref('ref_fx_rates') }}

),

market_stats as (

    select
        market_id,
        submarket_id,
        quarter_id,
        prime_rent_eur_m2_yr
    from {{ ref('int_market_stats') }}

),

joined as (

    select
        p.market_id,
        p.deal_ref,
        p.deal_date,
        p.deal_date_raw,
        p.quarter_id,
        p.building_name,
        p.building_address,
        b.building_key,
        b.building_id_local,
        b.total_area_m2 as building_area_m2,
        coalesce(s.submarket_id, b.submarket_id) as submarket_id,
        p.submarket_local_name,
        (s.submarket_id is null and b.submarket_id is not null) as submarket_derived_from_building,
        p.tenant_name_raw,
        p.tenant_name_norm,
        p.sector_local,
        sec.sector_code,
        p.deal_type_local,
        dt.deal_type_code,
        p.area_m2,
        p.rent_local,
        p.rent_currency,
        p.rent_unit,
        fx.units_per_eur,
        {{ rent_to_eur_m2_year_by_column('p.rent_local', 'p.rent_unit', 'fx.units_per_eur') }} as rent_eur_m2_yr,
        ms.prime_rent_eur_m2_yr as submarket_prime_rent_eur_m2_yr,
        p.lease_term_years,
        p.submitted_at,
        p.source_table
    from prepared as p
    left join buildings as b
        on p.market_id = b.market_id
        and {{ normalise_text('p.building_name') }} = {{ normalise_text('b.building_name') }}
    left join submarkets as s
        on p.market_id = s.market_id
        and {{ normalise_text('p.submarket_local_name') }} = {{ normalise_text('s.local_name') }}
    left join deal_types as dt
        on p.market_id = dt.market_id
        and {{ normalise_text('p.deal_type_local') }} = {{ normalise_text('dt.local_deal_type') }}
    left join sectors as sec
        on p.market_id = sec.market_id
        and {{ normalise_text('p.sector_local') }} = {{ normalise_text('sec.local_sector') }}
    left join fx
        on p.quarter_id = fx.quarter_id
        and p.rent_currency = fx.currency_code
    left join market_stats as ms
        on p.market_id = ms.market_id
        and coalesce(s.submarket_id, b.submarket_id) = ms.submarket_id
        and p.quarter_id = ms.quarter_id

),

deduplicated as (

    -- The same deal sent twice (identical, or with the tenant spelt differently) shares the market,
    -- date, building, size and normalised tenant. The first submission is kept.
    select
        *,
        row_number() over (
            partition by market_id, deal_date, building_name, round(area_m2, 0), tenant_name_norm
            order by submitted_at, deal_ref
        ) as duplicate_rank,
        first_value(deal_ref) over (
            partition by market_id, deal_date, building_name, round(area_m2, 0), tenant_name_norm
            order by submitted_at, deal_ref
        ) as first_submission_deal_ref
    from joined

),

checked as (

    select
        *,
        {{ safe_divide('rent_eur_m2_yr', 'submarket_prime_rent_eur_m2_yr') }} as rent_to_prime_ratio,
        case
            when duplicate_rank > 1 then 'duplicate_submission'
            when deal_date is null then 'missing_deal_date'
            when deal_date > cast(submitted_at as date) then 'deal_dated_after_submission'
            when area_m2 is null then 'missing_area'
            when area_m2 < 100 or area_m2 > 60000 then 'area_out_of_range'
            when building_key is null then 'unknown_building'
            when building_area_m2 is not null and area_m2 > building_area_m2 * 1.05 then 'area_exceeds_building'
            when submarket_id is null then 'missing_submarket'
            when deal_type_code is null then 'unmapped_deal_type'
            when sector_code is null then 'unmapped_sector'
            when rent_local is not null and units_per_eur is null then 'missing_fx_rate'
        end as quarantine_reason,
        -- a rent far outside its submarket's prime rent is almost always a unit mix-up (monthly in an
        -- annual file, or the reverse): the deal is real, so the row is kept and only the rent is suppressed
        case
            when {{ safe_divide('rent_eur_m2_yr', 'submarket_prime_rent_eur_m2_yr') }} > 1.6
                or {{ safe_divide('rent_eur_m2_yr', 'submarket_prime_rent_eur_m2_yr') }} < 0.15
                then 'rent_out_of_range'
        end as rent_suppressed_reason
    from deduplicated

)

select
    {{ surrogate_key(['market_id', 'deal_ref', 'submitted_at']) }} as deal_row_key,
    {{ surrogate_key(['market_id', 'deal_ref']) }} as deal_key,
    market_id,
    deal_ref,
    deal_date,
    deal_date_raw,
    quarter_id,
    building_key,
    building_id_local,
    building_name,
    building_address,
    building_area_m2,
    submarket_id,
    submarket_local_name,
    submarket_derived_from_building,
    {{ surrogate_key(['tenant_name_norm']) }} as tenant_key,
    tenant_name_raw,
    tenant_name_norm,
    sector_code,
    sector_local,
    deal_type_code,
    deal_type_local,
    area_m2,
    rent_local as rent_local_as_reported,
    rent_currency,
    rent_unit,
    units_per_eur,
    case when rent_suppressed_reason is null then rent_eur_m2_yr end as rent_eur_m2_yr,
    rent_eur_m2_yr as rent_eur_m2_yr_as_reported,
    submarket_prime_rent_eur_m2_yr,
    rent_to_prime_ratio,
    rent_suppressed_reason,
    lease_term_years,
    duplicate_rank,
    case when duplicate_rank > 1 then first_submission_deal_ref end as duplicate_of_deal_ref,
    quarantine_reason,
    submitted_at,
    source_table
from checked
