-- What silver held back from gold, by market and reason, with the share of each market's rows.
-- A market whose quarantine rate exceeds vars.quarantine_rate_threshold_pct fails the build
-- (tests/assert_quarantine_rate_below_threshold.sql).

with deals as (

    select
        market_id,
        quarantine_reason,
        count(*) as row_count
    from {{ ref('int_deals') }}
    group by market_id, quarantine_reason

),

totals as (

    select
        market_id,
        sum(row_count) as submitted_rows,
        sum(case when quarantine_reason is not null then row_count else 0 end) as quarantined_rows
    from deals
    group by market_id

)

select
    d.market_id,
    'deals' as dataset,
    d.quarantine_reason,
    d.row_count,
    t.submitted_rows,
    t.quarantined_rows,
    round(100.0 * t.quarantined_rows / t.submitted_rows, 2) as market_quarantine_rate_pct,
    round(100.0 * d.row_count / t.submitted_rows, 2) as reason_rate_pct
from deals as d
inner join totals as t
    on d.market_id = t.market_id
where d.quarantine_reason is not null
