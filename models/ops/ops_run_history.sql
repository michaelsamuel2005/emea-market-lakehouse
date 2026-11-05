{{ config(
    materialized='view',
    pre_hook="{{ ensure_run_results_table() }}"
) }}

-- Every dbt run's timings, from the audit table the on-run-end hook appends to.
-- The pre-hook creates the table on a brand-new database so this view can always be built.

select
    invocation_id,
    run_started_at,
    node_id,
    resource_type,
    node_name,
    schema_name,
    status,
    execution_time_seconds,
    rows_affected,
    failures,
    message,
    recorded_at
from {{ run_results_relation() }}
