# Contributing

The project follows the team standards in `docs/naming_standards.md`, and every change goes
through a pull request with the checklist in `.github/PULL_REQUEST_TEMPLATE.md`.

## Set up

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
dbt build
```

## Before you open a pull request

```bash
python generator/generate.py --check      # raw files unchanged (or regenerated deliberately)
python scripts/scaffold_market.py         # generated YAML current
dbt build                                 # everything passes, unit tests included; note any new warning in the PR
sqlfluff lint models tests analyses
pytest tests_py                           # includes: every gold column is documented
```

CI also builds the change on Spark and on the Snowflake emulator and compares the tables with DuckDB's
(`scripts/engines/README.md`). A new SQL function that only one engine has belongs in
`macros/cross_db.sql`, with a `default__` and a `snowflake__` version, never in a model.

## Where things go

- A new market: `docs/onboarding_a_market.md`.
- A new check on deals: `models/silver/intermediate/int_deals.sql` (add a reason to the `case`, to the
  accepted values in `_intermediate.yml`, a row to the `deal_checks_...` unit test in
  `models/silver/_unit_tests.yml`, and to `ops_defect_detection` if the generator plants it).
- A new KPI: `models/gold/mart_market_kpis.sql`, its description in `models/gold/_gold.yml`, a row in
  `seeds/reference/ref_metric_definitions.csv`, a measure in `databricks/metric_views/mv_market_kpis.sql`
  and a metric in `snowflake/semantic_views/sv_market_kpis.sql`, a unit test if it has a formula, and the
  data contract.
- A new gold column: a description in `models/gold/_gold.yml` (reuse a `doc()` block from
  `docs/dbt/columns.md` if the column appears elsewhere); the docs-coverage test fails without one.
- A new reference mapping: the seed, never a model.

## Review

Reviewers run the build and read the four ops tables (`ops_dq_unmapped_codes`,
`ops_dq_quarantine_summary`, the two reconciliations) before approving. "It compiles" is not a review.
