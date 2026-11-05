-- The shared KPI definitions as a table, so a dashboard, a Genie space or a reviewer can read what
-- each gold column means and how it is computed. The same rows are the data contract in docs/.

select
    metric_name,
    gold_column,
    definition,
    unit,
    formula,
    grain,
    owner
from {{ ref('ref_metric_definitions') }}
