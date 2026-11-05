-- A market whose quarantined deals exceed the threshold has a submission problem that needs a
-- conversation, not a silent drop. Fails the build.

select distinct
    market_id,
    market_quarantine_rate_pct
from {{ ref('ops_dq_quarantine_summary') }}
where market_quarantine_rate_pct > {{ var('quarantine_rate_threshold_pct') }}
