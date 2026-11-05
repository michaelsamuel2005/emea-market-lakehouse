# Performance: monitoring and optimising the models

What "basic performance monitoring" and "optimising data models" mean in this project, and the
evidence each claim rests on.

## Monitoring

1. **Every run is recorded.** `macros/store_run_results.sql` runs after every dbt command and appends
   one row per node to `ops.dbt_run_results`: status, execution time, rows affected, failures.
2. **Trends and alerts.** `ops.ops_run_history` is the table; `ops.ops_runtime_alerts` lists nodes whose
   latest run failed or took more than twice their average over at least three earlier runs.
3. **Single-run view.** `python scripts/monitor.py` prints the slowest nodes and anything not green from
   `target/run_results.json`, which CI shows on every push.
4. **On Databricks**, the warehouse's **Query History** shows each dbt statement's duration and the
   query profile (scan size, pruning, shuffle); `describe history <table>` shows the OPTIMIZE operations.

## Optimising the models

| Decision | Why |
| --- | --- |
| Staging as views, intermediate and gold as tables | Staging is cheap and must reflect bronze exactly; everything downstream is read many times, so it is materialised once per build. |
| Liquid clustering on the facts (`liquid_clustered_by` on `fct_market_quarter`, `fct_leasing_deal`, `fct_building_availability`, `mart_market_kpis`) | Every dashboard, Genie and reconciliation query filters by market and quarter (or deal date). Clustering by those keys lets Delta skip files instead of scanning the table. dbt-databricks runs OPTIMIZE after building each of these tables. DuckDB and Snowflake ignore the setting; at this size Snowflake's automatic micro-partitioning needs no clustering key. |
| Surrogate keys as md5 strings, natural keys kept beside them | Joins on one column; the natural keys stay for filtering and for people. |
| Deduplication and checks in one intermediate table (`int_deals`) rather than in every consumer | The expensive window functions run once; gold and ops read the result. |
| Reference lookups as small seeds joined in silver | The mappings are a few hundred rows; joining them once at the intermediate layer is cheaper than mapping in each market's staging view. |
| No incremental models yet | The data is small (14,762 bronze rows); a full rebuild takes about 20 seconds on DuckDB, about three minutes on a local Spark session, and should take a few minutes on a serverless warehouse. Incremental processing would be the right change once bronze arrives daily rather than quarterly; `int_deals` keyed on `deal_row_key` is ready for it. |

`databricks/maintenance.sql` holds the weekly housekeeping (OPTIMIZE, ANALYZE TABLE statistics, VACUUM).

## How to check a change made things faster

1. `dbt build --target databricks` before and after; compare the node's `execution_time_seconds` in `ops.ops_run_history`.
2. In the SQL editor, run the dashboard tile query and open the **Query profile**: files pruned, bytes read.
3. For a model change, `dbt build --select <model>+ ` and read `ops_runtime_alerts`: nothing should appear.
