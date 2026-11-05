-- Each submarket should report every quarter between the market's first and last submission.
-- A gap means a missing submission (fails the build so it is chased, not averaged over).

with span as (

    select
        market_id,
        min(period_end_date) as first_period,
        max(period_end_date) as last_period
    from {{ ref('fct_market_quarter') }}
    group by market_id

),

expected as (

    select
        s.market_id,
        sm.submarket_id,
        q.quarter_id
    from span as s
    inner join {{ ref('dim_submarket') }} as sm
        on s.market_id = sm.market_id
    inner join {{ ref('dim_quarter') }} as q
        on q.quarter_end_date between s.first_period and s.last_period

)

select
    e.market_id,
    e.submarket_id,
    e.quarter_id
from expected as e
left join {{ ref('fct_market_quarter') }} as f
    on e.market_id = f.market_id
    and e.submarket_id = f.submarket_id
    and e.quarter_id = f.quarter_id
where f.market_quarter_key is null
