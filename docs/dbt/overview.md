{% docs __overview__ %}

# EMEA Office Market Lakehouse

Five office markets' quarterly research submissions, onboarded in their own templates, standardised
once in silver, and served as a star schema and a shared KPI layer in gold. Synthetic data. The same
project builds on DuckDB, Databricks and Snowflake.

Start with the lineage graph (bottom right): bronze seeds on the left, `stg_<market>__<dataset>`
views, the `int_` tables where markets are unioned and checked, then `dim_`, `fct_` and `mart_`.

- Definitions of every KPI: `dim_metric_definition`. Every gold column is described.
- Buildings as they were on a given date: `dim_building_history` (type 2).
- What was held back and why: `ops_dq_quarantine_summary`.
- Whether the markets' headlines agree with their own detail: `ops_dq_reconciliation_vacancy`, `ops_dq_reconciliation_take_up`.
- How well the checks catch planted defects: `ops_defect_detection`.

The repository README has the results and where the project has run; `databricks/` and `snowflake/` have the runbooks.

{% enddocs %}
