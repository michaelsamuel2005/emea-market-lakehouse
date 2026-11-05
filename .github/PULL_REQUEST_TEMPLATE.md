## What changes

<!-- One or two sentences. Link the issue if there is one. -->

## Checklist (team standards: docs/naming_standards.md)

- [ ] `dbt build` passes locally with no new warnings (paste the `Done.` line)
- [ ] Every new model and column has a description in its `_*.yml`
- [ ] New columns follow the naming standard (unit suffixes: `_m2`, `_eur_m2_yr`, `_pct` / fractions named `_rate`)
- [ ] Any business logic change is made in ONE place (silver for conversions and mappings, `mart_market_kpis` for KPI definitions) and `ref_metric_definitions.csv` is updated if a definition changed
- [ ] New market: block in `dbt_project.yml`, seeds, mapping rows, `scripts/scaffold_market.py <ID>` run, `docs/onboarding_a_market.md` followed
- [ ] A rule or formula that changed has a unit test (`models/*/_unit_tests.yml`), and it fails without the change
- [ ] `sqlfluff lint models tests analyses` is clean
- [ ] `pytest tests_py` passes
- [ ] CI's `engines` job is green (the change builds on Spark and the Snowflake emulator with the same results)

## How I checked it

<!-- Row counts, a reconciliation query, a before/after of a KPI, screenshots of a Databricks or Snowflake run... -->
