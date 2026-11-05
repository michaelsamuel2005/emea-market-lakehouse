-- Every market-quarter in the submissions must have an FX rate for its reporting currency,
-- or the EUR conversion silently returns null.

select
    s.market_id,
    s.quarter_id,
    s.rent_currency
from {{ ref('int_market_stats') }} as s
left join {{ ref('ref_fx_rates') }} as fx
    on s.quarter_id = fx.quarter_id
    and s.rent_currency = fx.currency_code
where fx.units_per_eur is null
