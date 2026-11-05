# Generator

`generate.py` writes every raw file from `assumptions.yaml` and a fixed seed, so the data is
reproducible and every planted defect is logged.

- `assumptions.yaml`: the markets, their conventions, submarkets with illustrative 2026 levels and
  trends, FX drift, shared taxonomies, and the defect rates.
- `answer_key/defects.csv`: every injected defect with the row it affects. `seeds/answer_key/` holds
  the same rows as a seed so `ops.ops_defect_detection` can score the pipeline.
- `answer_key/truth_*.csv`: the clean numbers behind each market's files.
- `answer_key/fact_sheet.json`: the headline numbers from the last `scripts/fact_sheet.py` run.

`python generator/generate.py --check` regenerates into a temporary folder and fails if any committed
file differs; CI runs it on every push. The generator reads `vars.markets` in `dbt_project.yml`: once the
Madrid exercise is onboarded, Madrid counts as a modelled market, so its raw files in `seeds/bronze`, its
reference rows and its answer-key rows are expected too (with the same random draws, so nothing else
changes). Change `assumptions.yaml`, run the generator, run `dbt build`,
and update the README results with `scripts/fact_sheet.py`.

The levels are illustrative, not market data: prime rents, yields, stock and take-up are plausible for
2026 but chosen to exercise unit and currency conversion, resubmissions, duplicates, reconciliation and
code mapping, not to describe any market.
