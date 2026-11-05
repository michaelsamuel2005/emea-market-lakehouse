-- Building dimension with history (slowly changing dimension, type 2). Grain: one row per building
-- and version. fct_leasing_deal carries building_version_key, so a deal is reported against the
-- building as it was on the deal date (its grade before or after a refurbishment); dim_building
-- holds only the current version, for questions about the building stock today.
-- A version applies to dates d with valid_from <= d < valid_to.

select
    v.building_version_key,
    v.building_key,
    v.market_id,
    v.building_id_local,
    v.version_number,
    v.valid_from,
    v.valid_to,
    v.is_current,
    v.building_name,
    {{ surrogate_key(['v.market_id', 'v.submarket_id']) }} as submarket_key,
    v.submarket_id,
    v.grade_code,
    g.grade_name,
    v.grade_local,
    v.total_area_m2,
    v.year_built,
    v.year_refurbished,
    v.last_updated
from {{ ref('int_building_versions') }} as v
left join {{ ref('ref_grades') }} as g
    on v.grade_code = g.grade_code
