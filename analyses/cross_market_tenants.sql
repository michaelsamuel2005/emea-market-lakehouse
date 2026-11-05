-- Occupiers active in more than one market, with their deals by market.
select
    t.tenant_name,
    t.sector_name,
    t.markets_active,
    d.market_id,
    count(*) as deals,
    round(sum(d.area_m2)) as area_m2
from {{ ref('dim_tenant') }} as t
inner join {{ ref('fct_leasing_deal') }} as d
    on t.tenant_key = d.tenant_key
where t.markets_active > 1
group by t.tenant_name, t.sector_name, t.markets_active, d.market_id
order by t.markets_active desc, t.tenant_name asc, d.market_id asc
