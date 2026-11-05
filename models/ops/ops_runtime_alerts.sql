{{ config(materialized='view') }}

-- Basic performance monitoring: for each model, the latest run time against the average of its
-- earlier runs. A model that takes more than twice its usual time, or any node that failed or
-- errored in its latest run, is flagged. Reads the audit table through ops_run_history.

with history as (

    select
        node_id,
        node_name,
        resource_type,
        status,
        execution_time_seconds,
        run_started_at,
        row_number() over (partition by node_id order by run_started_at desc, recorded_at desc) as recency_rank
    from {{ ref('ops_run_history') }}
    where resource_type in ('model', 'seed', 'test')

),

latest as (

    select * from history where recency_rank = 1

),

baseline as (

    select
        node_id,
        avg(execution_time_seconds) as avg_previous_seconds,
        max(execution_time_seconds) as max_previous_seconds,
        count(*) as previous_runs
    from history
    where recency_rank > 1
    group by node_id

)

select
    l.node_name,
    l.resource_type,
    l.status as latest_status,
    l.run_started_at as latest_run_started_at,
    l.execution_time_seconds as latest_seconds,
    b.avg_previous_seconds,
    b.max_previous_seconds,
    b.previous_runs,
    {{ safe_divide('l.execution_time_seconds', 'b.avg_previous_seconds') }} as slowdown_ratio,
    case
        when l.status not in ('success', 'pass') then 'latest run did not succeed'
        when b.previous_runs >= 3 and l.execution_time_seconds > 2 * b.avg_previous_seconds
            and l.execution_time_seconds > 5 then 'more than twice the usual run time'
    end as alert
from latest as l
left join baseline as b
    on l.node_id = b.node_id
where l.status not in ('success', 'pass')
    or (b.previous_runs >= 3 and l.execution_time_seconds > 2 * b.avg_previous_seconds and l.execution_time_seconds > 5)
