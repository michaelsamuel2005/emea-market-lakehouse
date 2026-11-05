{{ config(materialized='table') }}

-- Every market's building register in one conformed table.
-- Grain: one row per building (market_id + local building id): the current version, i.e. the latest
-- row the market sent (for example after a refurbishment changed its grade). Every version, with the
-- dates it was valid, is in int_building_versions; the union, the submarket mapping and the grade
-- mapping are done there once. A grade the mapping does not know is kept as null and surfaced by
-- ops.ops_dq_unmapped_codes.

select
    building_key,
    market_id,
    building_id_local,
    building_name,
    building_address,
    postcode,
    submarket_id,
    submarket_local_name,
    grade_code,
    grade_local,
    total_area_m2,
    year_built,
    year_refurbished,
    last_updated,
    version_rank,
    version_count,
    source_table
from {{ ref('int_building_versions') }}
where is_current
