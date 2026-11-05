-- Prime rent league table for the latest quarter: every market in one unit, with the market's own figure beside it.
select
    m.market_name,
    f.submarket_id,
    f.quarter_id,
    round(f.prime_rent_eur_m2_yr) as prime_rent_eur_m2_yr,
    f.prime_rent_local,
    f.prime_rent_local_currency,
    f.prime_rent_local_unit,
    round(f.prime_yield * 100, 2) as prime_yield_pct
from {{ ref('fct_market_quarter') }} as f
inner join {{ ref('dim_market') }} as m
    on f.market_id = m.market_id
where f.quarter_id = (select max(x.quarter_id) from {{ ref('fct_market_quarter') }} as x)
order by prime_rent_eur_m2_yr desc
