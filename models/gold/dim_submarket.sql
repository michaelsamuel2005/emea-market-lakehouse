-- One row per submarket, with its shared name and the local name the market reports under.

select
    {{ surrogate_key(['s.market_id', 's.submarket_id']) }} as submarket_key,
    s.market_id,
    m.market_name,
    s.submarket_id,
    s.submarket_name,
    s.local_name as submarket_local_name
from {{ ref('ref_submarkets') }} as s
inner join {{ ref('dim_market') }} as m
    on s.market_id = m.market_id
