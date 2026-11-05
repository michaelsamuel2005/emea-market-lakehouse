# Onboarding a market

The playbook for bringing a market's datasets onto the platform. Madrid's files are in
`exercise/madrid/` so you can do it end to end; the steps are the same for a real market.

## 0. Understand the source (talk to the market first)

Before any code, fill in this table with the local stakeholder. Every answer becomes configuration.

| Question | Madrid's answer |
| --- | --- |
| What files arrive, how often, from whom? | Four CSVs each quarter from the Madrid research team |
| Area unit? | m² |
| Rent convention and currency? | EUR per m² per **month** |
| How is the quarter written? | `3T 2026` |
| Number format? | `2 400 000` thousands separated by spaces, `34,74` decimal comma (the `fr` format here) |
| Date format in the deal log? | `30/09/2026` |
| Is vacancy an area or a rate? | an area (`Disponibilidad_m2`) |
| How are yields written? | in percent, `4,9 %` (`rate_format: percent`; Warsaw's `0.0625` would be `fraction`) |
| What are the submarkets, and what are they called locally? | CBD (Castellana), Centro Secundario, Periferia, Satélite |
| What grade scale? Deal types? Sector labels? | `A+`, `A`, `B`, `C`; Spanish deal-type and sector labels |
| What does the market consider a duplicate, and how are resubmissions handled? | Same deal reference; a later submission replaces an earlier one |

## 1. Land the raw files (bronze)

Copy the four files to `seeds/bronze/` with the standard names `<market>_<dataset>.csv`:

```bash
cp exercise/madrid/raw/mad_*.csv seeds/bronze/
```

Bronze keeps columns as strings, so no file is edited. (On Databricks the same files go into the
`landing` Volume and the notebook in `databricks/notebooks/` lands them.)

## 2. Describe the market in configuration

Add a `MAD:` block at the end of `vars.markets` in `dbt_project.yml`, copying the shape of `FRA` (also a
monthly-rent, decimal-comma market) and changing the conventions and column names to Madrid's
(`head -1 seeds/bronze/mad_*.csv` shows the headers):

```yaml
    MAD:
      market_name: Madrid
      currency: EUR
      area_unit: m2
      rent_unit: per_m2_month
      number_format: fr           # 2 400 000 and 34,74
      period_format: es           # "3T 2026"
      date_format: dmy_slash      # 30/09/2026
      vacancy_reported_as: area
      rate_format: percent        # "4,9 %"
      market_stats:
        source: mad_market_stats
        columns: {period: Trimestre, submarket: Submercado, stock: Stock_m2, vacant: Disponibilidad_m2,
                  take_up: Contratacion_m2, prime_rent: Renta_prime_EUR_m2_mes, prime_yield: Rentabilidad_prime,
                  completions: Entregas_m2, under_construction: En_construccion_m2, submitted_at: Fecha_envio}
      deals:
        source: mad_deals
        columns: {deal_ref: Referencia, deal_date: Fecha, building: Edificio, address: Direccion, submarket: Submercado,
                  tenant: Inquilino, sector: Sector, area: Superficie_m2, rent: Renta_EUR_m2_mes, term_years: Plazo_anos,
                  deal_type: Tipo_operacion, submitted_at: Fecha_envio}
      buildings:
        source: mad_buildings
        columns: {building_id: Id_edificio, name: Nombre, address: Direccion, postcode: CP, submarket: Submercado,
                  grade: Categoria, area: SBA_m2, year_built: Ano_construccion, year_refurbished: Ano_reforma,
                  last_updated: Actualizado}
      availability:
        source: mad_availability
        columns: {period: Trimestre, building_id: Id_edificio, available: Disponible_m2, sublease: Subarriendo_m2,
                  submitted_at: Fecha_envio}
```

Every convention is a named option the macros already understand; a typo fails the build with
"Unknown number_format" (or period, date, rate format) rather than parsing the market wrongly. If the
market's quarter label or date format is genuinely new, add a pattern to `period_year` /
`period_quarter` / `parse_date` in `macros/parse.sql` (one line each), a row to the format table in
this document, and a case to the unit tests in `models/silver/_unit_tests.yml`.

## 3. Add the reference rows

Append Madrid's rows to the reference seeds. The rows are prepared in `exercise/madrid/reference/`:

```bash
for f in ref_markets ref_submarkets ref_grade_mapping ref_deal_type_mapping ref_sector_mapping; do
  tail -n +2 exercise/madrid/reference/${f}_rows.csv >> seeds/reference/${f}.csv
done
```

For a real market you write these rows yourself from step 0. Every local label the market uses must
be mapped; the build fails on an unmapped one and `ops.ops_dq_unmapped_codes` lists it.

Madrid's files also contain planted defects, logged by the generator. To score the silver checks on
them as well (step 5), add Madrid's rows to the answer key the pipeline reads:

```bash
grep '^MAD,' generator/answer_key/defects.csv >> seeds/answer_key/answer_key_defects.csv
```

(`python generator/generate.py --check` knows Madrid is onboarded once its block is in `dbt_project.yml`,
and then expects these files to contain Madrid's rows.)

## 4. Scaffold the models

```bash
python scripts/scaffold_market.py MAD
```

creates `models/silver/staging/mad/stg_mad__*.sql` (four one-line macro calls) and regenerates
`models/bronze/sources.yml` and `seeds/bronze/_bronze_seeds.yml`. Then add the four Madrid models to
`models/silver/staging/_staging.yml`, each after its Warsaw equivalent with the same column alias
(`columns: *market_stats_columns`, `*deals_columns`, `*buildings_columns`, `*availability_columns`),
and change the `distinct_count_equals` expectation on `int_market_stats` (in
`models/silver/intermediate/_intermediate.yml`) from 5 to 6.

The four `int_<dataset>_unioned` views pick the new market up automatically
(`macros/union_markets.sql` loops over `vars.markets`), and everything downstream reads them, so no
intermediate or gold model changes. The unit tests mock the unioned views, so they do not change either.

## 5. Build and read the results

```bash
dbt build
python scripts/fact_sheet.py
pytest tests_py -q                    # follows the markets in dbt_project.yml, Madrid included
python generator/generate.py --check  # the committed files are still the generator's output
```

`dbt build` should end with two warnings, as before; the take-up reconciliation now lists 16
submarket-quarters (two of them Madrid's) instead of 14.

Then read, in this order:

1. `ops.ops_dq_unmapped_codes`: must be empty. If not, step 3 is incomplete.
2. `ops.ops_dq_quarantine_summary` for MAD: what was held back and why. A high `duplicate_submission`
   rate is normal for a first load; `unknown_building` means the deal log and the register use
   different building names.
3. `ops.ops_dq_reconciliation_vacancy` and `_take_up` for MAD: do the market's headline figures agree
   with its own detail? Gaps are questions for the market, not for the code.
4. `gold.mart_market_kpis` for MAD: do the numbers look like Madrid? In 2026Q3 the vacancy rate is
   about 10% and the prime rent about 490 EUR per m² per year (about 41 a month, Madrid's own
   convention, annualised). A prime rent in the thousands means the rent unit in step 2 is wrong.
5. `ops.ops_defect_detection`: with Madrid's answer-key rows added, the detection rates still hold
   (every check at 100% except areas in the wrong unit), which shows the checks work on a market they
   were not written for.

## 6. Document and review

- Add Madrid to the markets table in `README.md` and the row count to the results.
- Open a pull request with the PR template; the checklist is the review. A second person runs
  `dbt build` and reads the four ops tables above before approving.
- If the Databricks workspace is live, `dbt build --target databricks`, then add Madrid to the
  metric view filters if any were hard-coded (none are by default).

## What usually goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| `quarter_id` null in staging | Period label format not in `period_year` | Add the regex pattern |
| Every rent 12× too high or low | Wrong `rent_unit` | Check the market's convention |
| Every yield 100× too small, or yields above 100% | Wrong `rate_format` | `percent` for "4,9 %" or "4.9", `fraction` for "0.049" |
| `Unknown number_format` (or period, date, rate) at compile time | A typo in the market's block | Use one of the options listed in the LON block's comments |
| `unmapped_deal_type` / `unmapped_sector` in quarantine | Labels missing from the mapping seeds | Add rows (mapping is case-insensitive) |
| `unknown_building` for most deals | Deal log names differ from the register | Agree one building id with the market |
| Vacancy reconciliation always off by a constant | The market reports availability (incl. under offer) not vacancy | Note it in the market's block and in the contract |
