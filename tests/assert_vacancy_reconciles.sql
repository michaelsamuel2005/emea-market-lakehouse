{{ config(severity='warn') }}

-- Reported vacancy should agree with the building register within the tolerance.
-- A warning, not a failure: a gap is a question for the market (see ops.ops_dq_reconciliation_vacancy).

select
    market_id,
    submarket_id,
    quarter_id,
    round(gap_pp, 2) as gap_pp
from {{ ref('ops_dq_reconciliation_vacancy') }}
where is_outside_tolerance
