-- Calendar dimension, one row per day from 2023-01-01 to 2027-12-31, generated in portable SQL
-- (a digits cross join rather than an engine-specific generate_series). Facts join on date_key
-- (yyyymmdd) for deal dates and on quarter_id for quarterly snapshots.

with digits as (

    select 0 as d
    union all
    select 1
    union all
    select 2
    union all
    select 3
    union all
    select 4
    union all
    select 5
    union all
    select 6
    union all
    select 7
    union all
    select 8
    union all
    select 9

),

numbers as (

    select d1.d + 10 * d2.d + 100 * d3.d + 1000 * d4.d as n
    from digits as d1
    cross join digits as d2
    cross join digits as d3
    cross join digits as d4

),

days as (

    select cast({{ dbt.dateadd('day', 'n', "cast('2023-01-01' as date)") }} as date) as date_day
    from numbers
    where n < 1826

)

select
    cast(year(date_day) * 10000 + month(date_day) * 100 + day(date_day) as integer) as date_key,
    date_day,
    year(date_day) as year_number,
    quarter(date_day) as quarter_number,
    {{ quarter_id('year(date_day)', 'quarter(date_day)') }} as quarter_id,
    {{ quarter_end_date('year(date_day)', 'quarter(date_day)') }} as quarter_end_date,
    month(date_day) as month_number,
    cast(year(date_day) * 100 + month(date_day) as integer) as year_month,
    date_day = last_day(date_day) as is_month_end,
    date_day = {{ quarter_end_date('year(date_day)', 'quarter(date_day)') }} as is_quarter_end
from days
