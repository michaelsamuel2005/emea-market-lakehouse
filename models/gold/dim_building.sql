-- One row per building across every market: the current version of each building's register entry.

select
    b.building_key,
    b.market_id,
    b.building_id_local,
    b.building_name,
    b.building_address,
    b.postcode,
    {{ surrogate_key(['b.market_id', 'b.submarket_id']) }} as submarket_key,
    b.submarket_id,
    b.grade_code,
    g.grade_name,
    b.grade_local,
    b.total_area_m2,
    b.year_built,
    b.year_refurbished,
    coalesce(b.year_refurbished, b.year_built) as effective_year,
    b.last_updated
from {{ ref('int_buildings') }} as b
left join {{ ref('ref_grades') }} as g
    on b.grade_code = g.grade_code
