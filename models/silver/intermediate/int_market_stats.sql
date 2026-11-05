{{ config(materialized='table') }}

-- Every market's quarterly submission in one conformed table.
-- Grain: one row per market, submarket and quarter, keeping only the LATEST submission when a
-- market-quarter was sent more than once (submission_rank = 1). Local submarket names are mapped
-- to the shared submarket ids, and the prime rent is converted once to EUR per m2 per year.

with unioned as (

    select * from {{ ref('int_market_stats_unioned') }}

),

ranked as (

    select
        *,
        row_number() over (
            partition by market_id, submarket_local_name, quarter_id
            order by submitted_at desc, period_label asc
        ) as submission_rank,
        count(*) over (partition by market_id, submarket_local_name, quarter_id) as submission_count
    from unioned

),

submarkets as (

    select * from {{ ref('ref_submarkets') }}

),

fx as (

    select * from {{ ref('ref_fx_rates') }}

)

select
    {{ surrogate_key(['r.market_id', 's.submarket_id', 'r.quarter_id']) }} as market_quarter_key,
    r.market_id,
    s.submarket_id,
    r.submarket_local_name,
    r.quarter_id,
    r.period_end_date,
    r.period_year,
    r.period_quarter,
    r.stock_m2,
    r.vacant_m2,
    {{ safe_divide('r.vacant_m2', 'r.stock_m2') }} as vacancy_rate,
    r.take_up_m2,
    r.prime_rent_local,
    r.rent_currency,
    r.rent_unit,
    {{ rent_to_eur_m2_year_by_column('r.prime_rent_local', 'r.rent_unit', 'fx.units_per_eur') }} as prime_rent_eur_m2_yr,
    r.prime_yield,
    r.completions_m2,
    r.under_construction_m2,
    r.submitted_at,
    r.submission_rank,
    r.submission_count,
    r.source_table
from ranked as r
left join submarkets as s
    on r.market_id = s.market_id
    and {{ normalise_text('r.submarket_local_name') }} = {{ normalise_text('s.local_name') }}
left join fx
    on r.quarter_id = fx.quarter_id
    and r.rent_currency = fx.currency_code
where r.submission_rank = 1
