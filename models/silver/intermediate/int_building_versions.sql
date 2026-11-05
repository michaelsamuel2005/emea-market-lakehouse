{{ config(materialized='table') }}

-- Every version of every building the markets have sent, with the dates each version was true.
-- Grain: one row per building and version. A market sends a building again when something about it
-- changes (a refurbishment moves it from grade B to A); both rows are kept here, so a deal signed
-- before the refurbishment can be reported against the grade the building had at the time.
--
-- Effective dating (slowly changing dimension, type 2):
--   * a version is valid from its register date (last_updated) until the next version's date
--   * the first version is valid from 1900-01-01: the register is a snapshot of buildings that already
--     exist, so its first row describes the building as it was before any change the market reported
--   * the current version is valid to 9999-12-31 and has is_current = true
-- valid_to is exclusive: a version applies to dates d with valid_from <= d < valid_to.
-- int_buildings keeps the current version of each building; dim_building_history exposes all of them.

with unioned as (

    select * from {{ ref('int_buildings_unioned') }}

),

versioned as (

    select
        *,
        row_number() over (
            partition by market_id, building_id_local
            order by last_updated asc, year_refurbished asc nulls first
        ) as version_number,
        row_number() over (
            partition by market_id, building_id_local
            order by last_updated desc, year_refurbished desc nulls last
        ) as version_rank,
        count(*) over (partition by market_id, building_id_local) as version_count,
        lead(last_updated) over (
            partition by market_id, building_id_local
            order by last_updated asc, year_refurbished asc nulls first
        ) as next_version_from
    from unioned

),

submarkets as (

    select * from {{ ref('ref_submarkets') }}

),

grades as (

    select * from {{ ref('ref_grade_mapping') }}

)

select
    {{ surrogate_key(['v.market_id', 'v.building_id_local', 'v.version_number']) }} as building_version_key,
    {{ surrogate_key(['v.market_id', 'v.building_id_local']) }} as building_key,
    v.market_id,
    v.building_id_local,
    v.version_number,
    v.version_rank,
    v.version_count,
    case when v.version_number = 1 then cast('1900-01-01' as date) else v.last_updated end as valid_from,
    coalesce(v.next_version_from, cast('9999-12-31' as date)) as valid_to,
    v.version_rank = 1 as is_current,
    v.building_name,
    v.building_address,
    v.postcode,
    s.submarket_id,
    v.submarket_local_name,
    g.grade_code,
    v.grade_local,
    v.total_area_m2,
    v.year_built,
    v.year_refurbished,
    v.last_updated,
    v.source_table
from versioned as v
left join submarkets as s
    on v.market_id = s.market_id
    and {{ normalise_text('v.submarket_local_name') }} = {{ normalise_text('s.local_name') }}
left join grades as g
    on v.market_id = g.market_id
    and {{ normalise_text('v.grade_local') }} = {{ normalise_text('g.local_grade') }}
