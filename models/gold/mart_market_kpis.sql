{{ config(liquid_clustered_by=['market_id']) }}

-- The shared KPI definitions, computed once. Grain: one row per market and quarter.
-- Every BI product, metric view and Genie answer reads these numbers rather than recomputing them,
-- so "vacancy rate" means the same thing in every market and every report.
-- Definitions are listed in seeds/reference/ref_metric_definitions.csv and docs/data_contract.md.

with by_submarket as (

    select * from {{ ref('fct_market_quarter') }}

),

by_market as (

    select
        market_id,
        quarter_id,
        period_end_date,
        sum(stock_m2) as stock_m2,
        sum(vacant_m2) as vacant_m2,
        sum(take_up_m2) as take_up_m2,
        sum(completions_m2) as completions_m2,
        sum(under_construction_m2) as under_construction_m2,
        max(prime_rent_eur_m2_yr) as prime_rent_eur_m2_yr,          -- the market's prime rent is its best submarket
        min(prime_yield) as prime_yield,                            -- and its prime yield the keenest
        sum(register_available_m2) as register_available_m2,
        sum(register_tracked_area_m2) as register_tracked_area_m2,
        cast(sum(deal_count) as bigint) as deal_count,             -- bigint on every engine (DuckDB would return int128)
        sum(deals_area_m2) as deals_area_m2,
        max(largest_deal_m2) as largest_deal_m2
    from by_submarket
    group by market_id, quarter_id, period_end_date

),

windowed as (

    select
        *,
        stock_m2 - vacant_m2 as occupied_m2,
        lag(stock_m2 - vacant_m2) over (partition by market_id order by period_end_date) as previous_occupied_m2,
        lag(prime_rent_eur_m2_yr) over (partition by market_id order by period_end_date) as previous_prime_rent_eur_m2_yr,
        lag(prime_rent_eur_m2_yr, 4) over (partition by market_id order by period_end_date) as prime_rent_eur_m2_yr_year_ago,
        lag({{ safe_divide('vacant_m2', 'stock_m2') }}) over (partition by market_id order by period_end_date) as previous_vacancy_rate,
        sum(take_up_m2) over (
            partition by market_id, year(period_end_date) order by period_end_date
            rows between unbounded preceding and current row
        ) as take_up_ytd_m2,
        sum(take_up_m2) over (
            partition by market_id order by period_end_date
            rows between 3 preceding and current row
        ) as take_up_rolling_4q_m2,
        count(*) over (
            partition by market_id order by period_end_date
            rows between 3 preceding and current row
        ) as quarters_in_rolling_window
    from by_market

)

select
    {{ surrogate_key(['market_id', 'quarter_id']) }} as market_kpi_key,
    market_id,
    quarter_id,
    period_end_date,
    stock_m2,
    vacant_m2,
    occupied_m2,
    {{ safe_divide('vacant_m2', 'stock_m2') }} as vacancy_rate,
    {{ safe_divide('vacant_m2', 'stock_m2') }} - previous_vacancy_rate as vacancy_rate_change_qoq,
    take_up_m2,
    take_up_ytd_m2,
    case when quarters_in_rolling_window = 4 then take_up_rolling_4q_m2 end as take_up_rolling_4q_m2,
    occupied_m2 - previous_occupied_m2 as net_absorption_m2,
    prime_rent_eur_m2_yr,
    {{ safe_divide('prime_rent_eur_m2_yr', 'previous_prime_rent_eur_m2_yr') }} - 1 as prime_rent_growth_qoq,
    {{ safe_divide('prime_rent_eur_m2_yr', 'prime_rent_eur_m2_yr_year_ago') }} - 1 as prime_rent_growth_yoy,
    prime_yield,
    completions_m2,
    under_construction_m2,
    {{ safe_divide('under_construction_m2', 'stock_m2') }} as development_pipeline_rate,
    {{ safe_divide('register_available_m2', 'register_tracked_area_m2') }} as register_vacancy_rate,
    deal_count,
    deals_area_m2,
    {{ safe_divide('deals_area_m2', 'deal_count') }} as avg_deal_size_m2,
    largest_deal_m2,
    {{ safe_divide('deals_area_m2', 'take_up_m2') }} as deal_log_coverage_of_take_up
from windowed
