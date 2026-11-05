# Gold data contract

What a consumer (a BI developer, a dashboard, the Genie space, an AI application) can rely on.
Changes to this contract are versioned in `CHANGELOG.md` and announced in the pull request.

## Guarantees

1. **Units.** Every area is square metres. Every rent is EUR per square metre per year. Every rate,
   ratio and yield is a fraction (0.04 = 4%) unless the column is suffixed `_pct`. Money is EUR.
   The market's original figure is kept in a `_local` column with its currency and basis alongside.
2. **Grain.** `fct_market_quarter`: one row per market, submarket and quarter, and every submarket
   has a row for every quarter between the market's first and last submission. `fct_leasing_deal`:
   one row per deal; a deal submitted twice appears once. `fct_building_availability`: one row per
   tracked building and quarter with space available. `mart_market_kpis`: one row per market and quarter.
   `dim_building_history`: one row per building version; the versions of a building tile time with no
   gap or overlap (tested), so every deal date falls in exactly one.
3. **Keys.** Every `_key` column is unique in its dimension and every fact key resolves to a dimension
   row (tested on every build). Surrogate keys are deterministic (md5 of the natural key), so they are
   stable across rebuilds. They are hashes of text, so a key that includes a timestamp differs between
   engines (Snowflake prints milliseconds); compare engines on natural keys.
4. **Latest wins, history kept where it matters.** When a market resubmits a quarter, the latest
   submission is the one in gold and `submission_count` shows it happened. When it resubmits a building,
   `dim_building` holds the latest version and `dim_building_history` every version with its dates;
   `fct_leasing_deal.building_version_key` points at the version in force on the deal date.
5. **Only checked rows.** A deal reaches gold only if it passed every silver check. Held-back rows and
   the reason are in `ops.ops_dq_quarantine_summary`; a suppressed rent is null in gold with the reason
   in `rent_suppressed_reason`.
6. **Definitions are written down.** `gold.dim_metric_definition` (from `seeds/reference/ref_metric_definitions.csv`)
   defines every KPI column in `mart_market_kpis`: name, definition, unit, formula, grain, owner. A dashboard
   that shows "vacancy rate" shows `vacancy_rate` from the mart, not a recomputation.
7. **Freshness.** Bronze sources carry the market's submission timestamp; `dbt source freshness` warns
   after 120 days without a submission.
8. **Documented in the warehouse.** Every gold table and column has a description in
   `models/gold/_gold.yml` (a test fails the build otherwise), written to Databricks and Snowflake as
   table and column comments. The same numbers come out of DuckDB, Databricks and Snowflake.

## KPI definitions

| KPI | Column | Unit | Definition |
| --- | --- | --- | --- |
| Office stock | `stock_m2` | m² | Total office floorspace as reported, converted to m² |
| Vacant space | `vacant_m2` | m² | Space available to let at quarter end; stock × rate where a market reports a rate |
| Vacancy rate | `vacancy_rate` | fraction | vacant / stock; stock-weighted across submarkets |
| Take-up | `take_up_m2` | m² | Floorspace let in the quarter, summed across submarkets |
| Take-up YTD | `take_up_ytd_m2` | m² | Sum from the first quarter of the calendar year |
| Take-up rolling 12 months | `take_up_rolling_4q_m2` | m² | Sum of this and the three previous quarters; null until four exist |
| Net absorption | `net_absorption_m2` | m² | Change in occupied space (stock − vacant) since the previous quarter |
| Prime rent | `prime_rent_eur_m2_yr` | EUR/m²/yr | Converted once with the quarter's FX rate; market level is the highest submarket |
| Prime rent growth YoY | `prime_rent_growth_yoy` | fraction | Against the same quarter a year earlier |
| Prime yield | `prime_yield` | fraction | Market level is the lowest submarket |
| Under construction | `under_construction_m2` | m² | At quarter end |
| Development pipeline rate | `development_pipeline_rate` | fraction | under construction / stock |
| Register vacancy rate | `register_vacancy_rate` | fraction | Bottom-up from the tracked building register |
| Deal count | `deal_count` | count | Deals that passed every check |
| Average deal size | `avg_deal_size_m2` | m² | deals area / deal count |
| Deal log coverage | `deal_log_coverage_of_take_up` | ratio | deals area / reported take-up |

## Known limitations consumers should know

- Prime rent and yield are "best submarket" figures at market level by definition, not averages.
- Rents are available on about 97% of deals; the rest were withheld by the market or suppressed as implausible.
- The building register is a tracked sample (30 buildings per submarket), so `register_vacancy_rate`
  is a reconciliation signal, not a second vacancy measure.
- FX rates are quarterly, one rate per quarter and currency.

## Breaking vs non-breaking

Adding a column, a market, a quarter or a KPI is non-breaking. Renaming or removing a column,
changing a unit, or changing a KPI definition is breaking: it bumps the major version in
`CHANGELOG.md`, and the Databricks metric views and Snowflake semantic views are updated in the same
pull request.
