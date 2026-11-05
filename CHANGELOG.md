# Changelog

## 1.1.0 — 2026-11

- **Three engines from one codebase.** The engine differences are in `macros/cross_db.sql` (a
  regular-expression group, building a date, safe division, numbers as text), dispatched by adapter. New
  `snowflake` target (key-pair authentication) with `snowflake/RUNBOOK.md`, `setup.sql` (warehouse, role,
  database, credit quota), two semantic views and dashboard queries.
- **CI checks both warehouse dialects without an account**: the project builds on Apache Spark 4 with ANSI
  mode on and through the real dbt-snowflake adapter on the fakesnow emulator, every table is compared with
  the DuckDB build, and both real adapters compile the project offline (`scripts/engines/`).
- **Unit tests**: eight dbt unit tests for the market formats, the quarantine and repair rules, the
  stock-weighted vacancy rate, rolling and year-on-year KPIs, and the building history.
- **Building history (type 2)**: `int_building_versions` and `dim_building_history` keep every version of a
  building with `valid_from` / `valid_to`; `fct_leasing_deal.building_version_key` points at the version on
  the deal date. New singular test: the versions tile time.
- **Every gold column documented**, with shared descriptions in `docs/dbt/columns.md`, enforced by
  `tests_py/test_docs_coverage.py`; `persist_docs` scoped to gold.
- Yields and rates are parsed by an explicit `rate_format` per market (percent or fraction) instead of a
  "greater than 1 means percent" rule. Dates accept one-digit days and months.
- The market unions are their own views (`int_<dataset>_unioned`), so the rules can be unit-tested
  without listing every market, and onboarding a market changes no test.
- The generator and the Python tests follow the markets configured in `dbt_project.yml`, so the Madrid
  exercise passes CI once onboarded; the playbook was corrected against a full run of the exercise.
- **Power BI guide** (`powerbi/`): the report a BI developer would build on the gold layer, connected to the
  Databricks SQL warehouse: model, relationships, 19 DAX measures (ratios from sums, growth read from the
  KPI mart, a fact-versus-mart check measure), a market overview page and a leasing deals page.
- Fixes: the metric view measure `net_absorption_m2` was occupied space and is now `occupied_m2`; metric
  and semantic view ratios divide by `NULLIF(..., 0)`; the AI summary sentence reads the same on every
  engine; counts are `bigint`; corrected counts in the Databricks runbook; README states where the
  project has and has not run.

Data contract version: 1 (additive changes only: `dim_building_history`, `fct_leasing_deal.building_version_key`).

## 1.0.0 — 2026-11

First release.

- Five markets (London, Paris, Amsterdam, Frankfurt, Warsaw), four datasets each, 2023Q1 to 2026Q3, synthetic.
- Medallion layers in dbt with DuckDB and Databricks targets; configuration-driven staging; silver checks with quarantine and repair.
- Gold star schema (9 dimensions, 3 facts), KPI mart with 15 defined KPIs, AI-ready summary table.
- 317 data tests, two reconciliations, defect detection scored against the generator's answer key.
- Run-results audit table and runtime alerts; CI with generate --check, build, freshness, lint, pytest, docs.
- Databricks layer: runbook, two metric views, dashboard tiles, Genie instructions and benchmark questions, Volume landing notebook.
- Madrid onboarding exercise.
- Liquid clustering on the facts, maintenance SQL, performance notes, request-to-model examples, token-based Databricks target.
