{{ config(severity='warn') }}

-- The deal log should explain reported take-up within the tolerance.
-- A warning, not a failure (see ops.ops_dq_reconciliation_take_up for the explained part).

select
    market_id,
    submarket_id,
    quarter_id,
    round(gap_pct, 1) as gap_pct,
    round(gap_including_quarantined_pct, 1) as gap_including_quarantined_pct
from {{ ref('ops_dq_reconciliation_take_up') }}
where is_outside_tolerance
