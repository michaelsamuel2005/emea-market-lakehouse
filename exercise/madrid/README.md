# Exercise: onboard Madrid

A sixth market, generated with the same generator but not yet in the project. Its files are in `raw/`
(Spanish headers, `3T 2026` quarters, space-separated thousands and decimal commas, rents per month,
yields in percent) and the reference rows it needs are in `reference/`. Follow
[`docs/onboarding_a_market.md`](../../docs/onboarding_a_market.md): it uses Madrid as its worked
example.

Time: about an hour. Done means, on a branch, in one pull request:

- `dbt build` passes with the usual two warnings, and `ops.ops_dq_unmapped_codes` is empty;
- `gold.mart_market_kpis` shows Madrid in 2026Q3 at a vacancy rate of about 10% and a prime rent of
  about 490 EUR per m² per year;
- `pytest tests_py`, `python generator/generate.py --check` and `sqlfluff lint models tests analyses`
  pass, so CI is green;
- the pull request description says what was hard and what you would ask Madrid's research team.

Not written out for you in the playbook: the four entries in `models/silver/staging/_staging.yml` and
the change to the `distinct_count_equals` expectation (5 to 6) in
`models/silver/intermediate/_intermediate.yml`. Both are described there.
