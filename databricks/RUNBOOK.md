# Running the lakehouse on Databricks (Free Edition)

The dbt project that builds on DuckDB builds on Databricks unchanged: the medallion layers become Unity
Catalog schemas (`workspace.bronze`, `workspace.silver`, `workspace.gold`, `workspace.ops`,
`workspace.reference`, `workspace.answer_key`) and every model is a Delta table or view. The first run
takes about an hour, most of it in the workspace UI.

**Run status.** The SQL is checked on every push: CI builds the whole project on Apache Spark 4 with ANSI
mode on, the dialect a Databricks SQL warehouse speaks, and compares every table with the DuckDB build
(`scripts/engines/`). Unity Catalog, Delta, liquid clustering, metric views, Genie and the dashboard only
exist in a workspace, so they are tested by following this runbook. Record each run (date, result, anything
you had to change) in the run status table in the README.

Databricks Free Edition gives one serverless SQL warehouse (2X-Small), serverless notebooks, Unity Catalog
and Jobs (at most five concurrent tasks); it has no custom compute and a fair-use quota. This project is
small: 14,762 bronze rows.

## 1. Connect

1. Sign in to the workspace. The address bar shows the host, e.g. `dbc-a1b2c3d4-e5f6.cloud.databricks.com`.
2. **SQL Warehouses** in the sidebar > open the warehouse (Free Edition has one; start it) >
   **Connection details** > copy the **HTTP path** (`/sql/1.0/warehouses/...`).
3. In the project folder, on macOS or Linux:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt -r requirements-databricks.txt
export DATABRICKS_HOST=dbc-a1b2c3d4-e5f6.cloud.databricks.com      # no https://
export DATABRICKS_HTTP_PATH=/sql/1.0/warehouses/xxxxxxxxxxxxxxxx
python scripts/preflight.py databricks        # checks the variables, then runs dbt debug
```

On Windows (PowerShell): `py -m venv .venv`, `.venv\Scripts\Activate.ps1`, and
`$env:DATABRICKS_HOST = "dbc-..."` / `$env:DATABRICKS_HTTP_PATH = "/sql/1.0/warehouses/..."`.

`dbt debug` opens a browser window for an OAuth sign-in the first time (`auth_type: oauth` in
`profiles.yml`; nothing is stored in the repository). "All checks passed!" means the connection works.
If the browser does not open, copy the URL dbt prints into it.

**No browser available** (a remote shell, a CI runner)? Use a personal access token: in the workspace,
your username > **Settings** > **Developer** > **Access tokens** > **Manage** > **Generate new token**
(name it, set a lifetime), copy it, then

```bash
export DATABRICKS_TOKEN=dapi...          # keep it out of the repository; .env is gitignored
python scripts/preflight.py databricks_token
```

and use `--target databricks_token` in the commands below. Databricks recommends OAuth where a browser
exists; a token expires on the lifetime you set and can be revoked on the same page.

## 2. Build

```bash
dbt build --target databricks
```

In order: 31 seeds load into `workspace.bronze`, `workspace.reference` and `workspace.answer_key` (a few
minutes: seeds are inserted in batches); 23 views and 26 tables are created (staging views, five silver
tables, fifteen gold tables, the ops models); 340 data tests and 8 unit tests run; the on-run-end hook
writes the run's timings to `workspace.ops.dbt_run_results`. dbt-databricks runs `OPTIMIZE` after each
liquid-clustered table.

The result should match DuckDB: everything passes, with two warnings (`assert_vacancy_reconciles`,
1 row; `assert_take_up_reconciles`, 14 rows). Those are the planted reconciliation cases described in the
README, not problems with the build. Anything else is a difference between Spark and Databricks that CI
cannot see: note the error, fix it in `macros/cross_db.sql` if it is a dialect difference, and record it.

Then look at it: **Catalog** > `workspace` > `gold` > `mart_market_kpis` > **Sample data**. The table and
column comments come from `models/gold/_gold.yml` (`persist_docs`), and the **Lineage** tab of any gold
table shows the silver and bronze tables it came from.

```bash
dbt docs generate --target databricks && dbt docs serve     # the documentation site, with the lineage graph
python scripts/monitor.py                                   # slowest nodes and any failures from this run
```

## 3. The semantic layer: Unity Catalog metric views

Open the SQL editor, choose the warehouse, and run `databricks/metric_views/mv_market_kpis.sql`, then
`databricks/metric_views/mv_leasing_deals.sql`. Each creates a metric view in `workspace.gold` that
defines the shared measures once (vacancy rate as a stock-weighted ratio, take-up, prime rent, prime yield,
deal counts, achieved rent) with descriptions, formats and synonyms. Query one with:

```sql
select market_name, quarter_label, measure(vacancy_rate) as vacancy_rate, measure(take_up_m2) as take_up_m2
from workspace.gold.mv_market_kpis
group by market_name, quarter_label
order by market_name, quarter_label;
```

The views use YAML version 1.1 (synonyms, display names, formats), which needs compute on Databricks
Runtime 17.3 or above. If `WITH METRICS` is refused, the warehouse does not support it yet: the dashboard
and Genie steps below work from the gold tables directly.

## 4. An AI/BI dashboard

**Dashboards** > **Create dashboard** > **Data** tab > add `workspace.gold.mart_market_kpis`,
`workspace.gold.fct_leasing_deal` and the dimensions, or paste the tile queries from
`databricks/dashboard/tiles.sql` one at a time. A layout that works: a KPI row for the latest quarter
(vacancy rate, take-up, prime rent, prime yield per market), a line of prime rent by market over time, a
bar of take-up by quarter, a scatter of reported against register vacancy, and a table of the quarantine
summary. Name it "EMEA Office Markets".

## 5. A Genie space (questions in English)

**Genie** in the sidebar > **New** > choose `workspace.gold.mv_market_kpis` (or `mart_market_kpis`),
`mart_ai_market_facts`, `mv_leasing_deals` (or `fct_leasing_deal`), `dim_market`, `dim_submarket`,
`dim_tenant`, `dim_building_history` and `dim_metric_definition` > **Create**. Paste
`databricks/genie/instructions.md` into the space's instructions and add the example queries from
`databricks/genie/sample_queries.sql`. The questions in `databricks/genie/sample_questions.md` are the
benchmark: ask each one and compare Genie's answer with the expected one.

## 6. Alternative bronze landing: files in a Volume

Seeds are the simplest way to load bronze and are what CI uses. The production-style route is to drop
the market files in a Unity Catalog Volume and land them with `COPY INTO`, which is idempotent (a file
already loaded is skipped) and records the source file name:
`databricks/notebooks/01_land_bronze_from_volume.sql`. The dbt sources point at the same
`workspace.bronze` table names, so nothing downstream changes.

## 7. Keep it fast

The facts and the KPI mart are liquid-clustered by the columns every query filters on
(`liquid_clustered_by` in the model configs), and dbt-databricks optimizes them after each build.
`databricks/maintenance.sql` is the weekly housekeeping (OPTIMIZE, column statistics, VACUUM).
**Query History** on the warehouse shows every dbt statement's duration and query profile;
`ops.ops_run_history` keeps the per-model timings across runs and `ops.ops_runtime_alerts` flags slowdowns.

## 8. Schedule it

**Jobs & Pipelines** > **Create job**. If the workspace offers the **dbt** task type, point it at the
repository (a Git folder or a connected GitHub repository) with the command `dbt build --target databricks`.
Free Edition allows five concurrent tasks; daily is plenty, since the markets submit quarterly.

## 9. Power BI on top

With the gold layer built, [`../powerbi/README.md`](../powerbi/README.md) connects Power BI Desktop to the
same SQL warehouse (Server hostname and HTTP path as in step 1, a personal access token as in the
no-browser route) and builds the report a BI developer would build on it.

## Troubleshooting

| What you see | What to do |
| --- | --- |
| `dbt debug` cannot connect | Check the host has no `https://` and the HTTP path starts with `/sql/1.0/warehouses/`; start the warehouse first. |
| The OAuth window never appears | Copy the URL dbt prints into a browser, or use the `databricks_token` target. |
| Seeds are slow | Normal on serverless (batched inserts). Use the Volume route in step 6 for repeated loads. |
| `WITH METRICS` syntax error | Metric views are not available on that compute; skip to step 4 using the gold tables. |
| `[DIVIDE_BY_ZERO]` or `[CAST_INVALID_INPUT]` | ANSI mode caught an unguarded division or cast. Every division should go through `safe_divide` and every parse through `try_cast` (`macros/cross_db.sql`, `macros/parse.sql`). |
| Quota exhausted mid-run | Free Edition fair use. Wait for the reset, then `dbt retry --target databricks` reruns only what failed or was skipped. |
