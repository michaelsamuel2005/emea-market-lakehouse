-- Reported vacancy versus the vacancy implied by the building register, per submarket and quarter.
-- A gap beyond vars.vacancy_reconciliation_tolerance_pp is a question for the market, not a
-- build failure: tests/assert_vacancy_reconciles.sql warns, and the rows are listed here.

select
    market_id,
    submarket_id,
    quarter_id,
    period_end_date,
    vacancy_rate as reported_vacancy_rate,
    register_vacancy_rate,
    (register_vacancy_rate - vacancy_rate) * 100 as gap_pp,
    abs(register_vacancy_rate - vacancy_rate) * 100 > {{ var('vacancy_reconciliation_tolerance_pp') }} as is_outside_tolerance,
    register_buildings,
    register_buildings_with_space,
    register_tracked_area_m2,
    stock_m2 as reported_stock_m2
from {{ ref('fct_market_quarter') }}
where register_vacancy_rate is not null
