-- One row per occupier across every market. Tenant names are matched on a normalised form (case,
-- whitespace and a trailing "Ltd" ignored) so the same occupier taking space in London and Paris
-- is one tenant. The sector is the one most often reported for that tenant.

with deals as (

    select
        tenant_key,
        tenant_name_norm,
        tenant_name_raw,
        sector_code,
        market_id,
        deal_date
    from {{ ref('int_deals_clean') }}

),

sector_votes as (

    select
        tenant_key,
        sector_code,
        count(*) as deals_in_sector,
        row_number() over (partition by tenant_key order by count(*) desc, sector_code) as sector_rank
    from deals
    group by tenant_key, sector_code

),

names as (

    select
        tenant_key,
        tenant_name_raw,
        row_number() over (partition by tenant_key order by count(*) desc, tenant_name_raw) as name_rank
    from deals
    group by tenant_key, tenant_name_raw

),

summary as (

    select
        tenant_key,
        min(tenant_name_norm) as tenant_name_norm,
        count(*) as deal_count,
        count(distinct market_id) as markets_active,
        min(deal_date) as first_deal_date,
        max(deal_date) as latest_deal_date
    from deals
    group by tenant_key

)

select
    s.tenant_key,
    n.tenant_name_raw as tenant_name,
    s.tenant_name_norm,
    v.sector_code,
    sec.sector_name,
    s.deal_count,
    s.markets_active,
    s.first_deal_date,
    s.latest_deal_date
from summary as s
inner join names as n
    on s.tenant_key = n.tenant_key and n.name_rank = 1
left join sector_votes as v
    on s.tenant_key = v.tenant_key and v.sector_rank = 1
left join {{ ref('ref_sectors') }} as sec
    on v.sector_code = sec.sector_code
