-- Reported take-up versus the area of the deals the market logged, per submarket and quarter.
-- The deal log should explain the headline: a gap beyond vars.take_up_reconciliation_tolerance_pct
-- means deals are missing from the log, deals were held back by a silver check, or the headline
-- was not built from the log. Warning level. quarantined_deals_m2 shows how much of a gap the
-- silver checks explain (duplicates excluded, because they were never real take-up).

with quarantined as (

    select
        market_id,
        submarket_id,
        quarter_id,
        sum(area_m2) as quarantined_deals_m2,
        count(*) as quarantined_deal_count
    from {{ ref('int_deals') }}
    where quarantine_reason is not null
        and quarantine_reason <> 'duplicate_submission'
        and submarket_id is not null
    group by market_id, submarket_id, quarter_id

)

select
    f.market_id,
    f.submarket_id,
    f.quarter_id,
    f.period_end_date,
    f.take_up_m2 as reported_take_up_m2,
    f.deals_area_m2 as logged_deals_m2,
    f.deal_count,
    coalesce(q.quarantined_deals_m2, 0) as quarantined_deals_m2,
    coalesce(q.quarantined_deal_count, 0) as quarantined_deal_count,
    ({{ safe_divide('f.deals_area_m2', 'f.take_up_m2') }} - 1) * 100 as gap_pct,
    ({{ safe_divide('f.deals_area_m2 + coalesce(q.quarantined_deals_m2, 0)', 'f.take_up_m2') }} - 1) * 100 as gap_including_quarantined_pct,
    -- no reported take-up but deals logged (or nothing at all) cannot be reconciled: flag it
    coalesce(
        abs({{ safe_divide('f.deals_area_m2', 'f.take_up_m2') }} - 1) * 100 > {{ var('take_up_reconciliation_tolerance_pct') }},
        true
    ) as is_outside_tolerance
from {{ ref('fct_market_quarter') }} as f
left join quarantined as q
    on f.market_id = q.market_id
    and f.submarket_id = q.submarket_id
    and f.quarter_id = q.quarter_id
