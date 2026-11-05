-- Local labels the reference mappings do not know. Each row is a mapping to add in seeds/reference
-- (or a typo for the market to fix). tests/assert_no_unmapped_codes.sql fails the build if any
-- non-blank label is unmapped, because an unmapped code means rows silently fall out of gold.

with deal_types as (

    select
        market_id,
        'deal_type' as code_type,
        deal_type_local as local_label,
        count(*) as row_count
    from {{ ref('int_deals') }}
    where deal_type_code is null and deal_type_local is not null and trim(deal_type_local) <> ''
    group by market_id, deal_type_local

),

sectors as (

    select
        market_id,
        'sector' as code_type,
        sector_local as local_label,
        count(*) as row_count
    from {{ ref('int_deals') }}
    where sector_code is null and sector_local is not null and trim(sector_local) <> ''
    group by market_id, sector_local

),

grades as (

    select
        market_id,
        'grade' as code_type,
        grade_local as local_label,
        count(*) as row_count
    from {{ ref('int_buildings') }}
    where grade_code is null and grade_local is not null
    group by market_id, grade_local

),

submarkets as (

    select
        market_id,
        'submarket' as code_type,
        submarket_local_name as local_label,
        count(*) as row_count
    from {{ ref('int_market_stats') }}
    where submarket_id is null and submarket_local_name is not null
    group by market_id, submarket_local_name

)

select * from deal_types
union all
select * from sectors
union all
select * from grades
union all
select * from submarkets
