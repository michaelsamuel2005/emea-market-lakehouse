{{ config(materialized='table') }}

-- Every market's quarterly building availability in one table, joined to the conformed building
-- register for the submarket. Grain: one row per building and quarter (latest submission wins).

with unioned as (

    select * from {{ ref('int_availability_unioned') }}

),

ranked as (

    select
        *,
        row_number() over (
            partition by market_id, building_id_local, quarter_id
            order by submitted_at desc
        ) as submission_rank
    from unioned

),

buildings as (

    select * from {{ ref('int_buildings') }}

)

select
    {{ surrogate_key(['r.market_id', 'r.building_id_local', 'r.quarter_id']) }} as building_quarter_key,
    b.building_key,
    r.market_id,
    r.building_id_local,
    b.submarket_id,
    r.quarter_id,
    r.period_end_date,
    r.available_m2,
    r.sublease_m2,
    b.total_area_m2,
    {{ safe_divide('r.available_m2', 'b.total_area_m2') }} as availability_rate,
    r.submitted_at,
    r.source_table
from ranked as r
left join buildings as b
    on r.market_id = b.market_id
    and r.building_id_local = b.building_id_local
where r.submission_rank = 1
