-- The KPI mart must add up to the fact it is built from: total take-up and stock per market and
-- quarter in mart_market_kpis equal the sums over fct_market_quarter. Guards against a join
-- in the mart duplicating or dropping submarkets.

with fact as (

    select
        market_id,
        quarter_id,
        sum(take_up_m2) as take_up_m2,
        sum(stock_m2) as stock_m2
    from {{ ref('fct_market_quarter') }}
    group by market_id, quarter_id

)

select
    k.market_id,
    k.quarter_id,
    k.take_up_m2 as kpi_take_up,
    f.take_up_m2 as fact_take_up,
    k.stock_m2 as kpi_stock,
    f.stock_m2 as fact_stock
from {{ ref('mart_market_kpis') }} as k
full outer join fact as f
    on k.market_id = f.market_id
    and k.quarter_id = f.quarter_id
where abs(coalesce(k.take_up_m2, 0) - coalesce(f.take_up_m2, 0)) > 0.5
    or abs(coalesce(k.stock_m2, 0) - coalesce(f.stock_m2, 0)) > 0.5
