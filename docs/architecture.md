# Architecture

## Layers

| Layer | dbt schema | Materialisation | Rule |
| --- | --- | --- | --- |
| Bronze | `bronze` | seed (or Delta table via `COPY INTO`) | Rows exactly as the market sent them. Every column is a string. Never edited. |
| Silver, staging | `silver` | view | One model per market and dataset. Parse the market's formats, convert units, rename to the shared layout. No joins, no business rules. |
| Silver, intermediate | `silver` | view / table | `int_<dataset>_unioned` views stack the markets; the `int_` tables map local codes to shared ones, convert rents to EUR per m² per year with the quarter's FX rate, keep the latest submission, version the building register, and hold back rows that fail a check. Business logic lives here, once. |
| Gold | `gold` | table | Star schema (with a type 2 building history) and the KPI mart. Only clean rows. Every column documented, which a test enforces, and written to the warehouse as comments. |
| Ops | `ops` | table / view | What was held back and why, reconciliations, unmapped codes, run history and alerts, detection score. |
| Reference | `reference` | seed | Markets, submarkets, FX, code mappings, KPI definitions. Changed through pull requests. |

The layer is the dbt schema, so the same names appear in DuckDB (`silver.int_deals`), Databricks
(`workspace.silver.int_deals`) and Snowflake (`EMEA_MARKET_LAKEHOUSE.SILVER.INT_DEALS`).
`macros/generate_schema_name.sql` makes dbt use the custom schema name as given.

## Why staging is a macro call

Twenty staging models that each parse a slightly different file is the classic place for logic to
drift: one market's model handles a decimal comma, another forgets. Here the parsing lives in four
macros (`macros/stage_*.sql`) that read the market's conventions from `vars.markets.<ID>` in
`dbt_project.yml`. A staging model is:

```sql
{{ stage_market_stats('PAR') }}
```

so a reviewer checks the configuration block, not twenty files, and a fix to the quarter parser
reaches every market. The compiled SQL is still plain SQL (`dbt compile`, then `target/compiled/`).

## Portability: one project, three engines

The same files build on DuckDB, Databricks and Snowflake. Models use SQL the three share (`try_cast` on
strings, `replace`, `lpad`, `md5`, `concat_ws`, window functions); the few things they spell or behave
differently live in `macros/cross_db.sql`, dispatched by adapter so no model contains an engine check:
`regex_group` (`regexp_extract` on DuckDB and Databricks, `regexp_substr(..., 'e', n)` on Snowflake,
null when nothing matches on all three), `date_from_parts` (no `make_date`, and null rather than an error
for an impossible date), `safe_divide` (Databricks runs in ANSI mode, where dividing by zero is an error),
and `format_decimal` / `format_integer` (numbers print the same way in text). Regular expressions avoid
backslashes, which the engines escape differently. `dbt.type_string()` and `dbt.dateadd()` are dbt's own
cross-database macros. No dbt packages are needed, so there is no `dbt deps` step.

CI checks the two warehouses' dialects without an account (`scripts/engines/`): it builds the project on
Apache Spark 4 with ANSI mode on and with the real dbt-snowflake adapter on a Snowflake emulator, and
compares every table with the DuckDB build. Unity Catalog, metric views, Snowflake roles and semantic
views are exercised by the runbooks in `databricks/` and `snowflake/`.

## Flow of one London deal

1. **Bronze** `lon_deals`: `Deal_Ref=LON-20263-00017, Deal_Date=14/08/2026, Area_sq_ft="24,757", Rent_GBP_psf_pa=131.20, Deal_Type="New Lease "`.
2. **Staging** `stg_lon__deals`: `deal_date=2026-08-14`, `area_m2=2300.0`, `rent_local=131.20`, `rent_currency=GBP`, `rent_unit=per_sqft_year`, `deal_type_local="New Lease"`.
3. **Intermediate** `int_deals`: building matched to the register (`building_key`, submarket WEND); `deal_type_code=NEW`; `sector_code=FIN`; FX 2026Q3 GBP = 0.853 per EUR, so `rent_eur_m2_yr = 131.20 × 10.764 / 0.853 = 1,656`; `rent_to_prime_ratio = 0.88`; `duplicate_rank = 1`; `quarantine_reason = null`.
4. **Gold** `fct_leasing_deal`: the row with surrogate keys to `dim_submarket`, `dim_building`, `dim_tenant`, `dim_date`; `annual_rent_eur = 2300 × 1656`.
5. **KPI mart** `mart_market_kpis` 2026Q3 London: this deal is one of 115, 2,300 m² of the 249,111 m² of reported take-up.

## Checks, in the order they run

0. Unit tests (`models/*/_unit_tests.yml`): fixed input rows and the exact output each rule must give.
   They cover the parsing of each market's formats, the quarantine and repair rules, the stock-weighted
   vacancy rate, rolling and year-on-year KPIs, and the building history, and run before the model
   they test.
1. Schema tests on staging (not null, accepted values, plausible yields).
2. Silver checks in `int_deals` (a row gets the first reason that applies): duplicate submission,
   missing or post-submission date, missing or impossible area, unknown building, area exceeding the
   building, missing submarket, unmapped deal type or sector, missing FX rate. A rent far outside the
   submarket's prime rent does not reject the row: the rent is suppressed and the deal kept.
3. Tests on intermediate and gold: keys unique, relationships hold, ranges plausible, every submarket
   reports every quarter, the KPI mart adds up to the fact, FX covers every market-quarter, no
   unmapped codes, quarantine rate under the threshold.
4. Reconciliations as warnings: reported vacancy against the register (2 pp), take-up against the
   deal log (10%).
5. The on-run-end hook records the run; `ops_runtime_alerts` compares it with history.

## Performance monitoring

`macros/store_run_results.sql` runs after every dbt command and inserts one row per node into
`ops.dbt_run_results` (status, execution time, rows affected, failures, message). `ops_run_history`
exposes it and `ops_runtime_alerts` flags any node whose latest run failed or took more than twice
its average over at least three earlier runs. `scripts/monitor.py` prints the same for a single run
from `target/run_results.json`, without a database connection, which is what CI shows.

## What is deliberately not here

- No incremental models: the data is small and a full rebuild is seconds on DuckDB and minutes on
  serverless Databricks. The seeds-as-bronze design would be replaced by `COPY INTO` or Auto Loader
  from a Volume before incremental processing is worth adding.
- No dbt snapshot for the building history. A snapshot records what the table looked like each time
  dbt ran, so its history would start the day the project was deployed. The markets already date their
  register rows (`last_updated`), so `int_building_versions` builds the type 2 history from the
  submissions themselves, and a rebuild from scratch gives the same history. A source without its own
  dates (one that only ever shows the current state) is where `dbt snapshot` would be the right tool.
- No dbt packages: `dbt_utils` would replace `union_markets` and `surrogate_key`, at the cost of a
  network dependency in CI and in the Free Edition workspace.
