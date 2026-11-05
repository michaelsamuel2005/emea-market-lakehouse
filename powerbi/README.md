# Power BI on the gold layer

A Power BI report over the gold star schema, read straight from the Databricks SQL warehouse. It is the
handover point the lakehouse exists for: the Analytics Engineering side builds the data assets, the BI
Development side builds reports on them, and the two must agree on every number. Building the report
yourself is the quickest way to find out whether the gold layer is actually easy to report on.

**Build status:** not yet built. When it is, record the date here, add the screenshots to `docs/img/`,
and commit the report file (see step 7).

Time: about four hours the first time. Needs: Windows (Power BI Desktop runs only on Windows), the
project built on Databricks (`databricks/RUNBOOK.md`, steps 1 and 2), and a personal access token.

## 1. Connect

1. Install **Power BI Desktop** (free, Microsoft Store or the Power BI download page) on the Windows
   machine.
2. In the Databricks workspace, create a personal access token if you do not have one: your username >
   **Settings** > **Developer** > **Access tokens** > **Manage** > **Generate new token**. Set a
   lifetime (30 days is enough) and copy it once; it is shown only once.
3. In Power BI Desktop: **Home** > **Get data** > **More...** > search for `Databricks`. Two connectors
   appear. Use **Azure Databricks**: Microsoft's documentation says its personal-access-token sign-in
   works for AWS, Azure or GCP workspaces and to use it for all Databricks SQL warehouse data unless told
   otherwise. (The connector called just **Databricks** is for OAuth sign-in on AWS; it also works if you
   would rather sign in through the browser.)
4. **Server hostname**: the workspace host without `https://`, the same value as `DATABRICKS_HOST`
   (e.g. `dbc-a1b2c3d4-e5f6.cloud.databricks.com`). **HTTP path**: the warehouse's HTTP path, the same
   value as `DATABRICKS_HTTP_PATH` (`/sql/1.0/warehouses/...`). Leave the catalog and database blank.
5. **Data connectivity mode: Import.** The whole gold layer is under 20,000 rows, Import makes the
   report work (and refresh instantly) whether or not the Free Edition warehouse is running, and it
   lets you use every DAX function. DirectQuery is the choice when the data is too big to import or
   must be live to the second; neither applies here. Be ready to say this in an interview.
6. Sign in with **Personal Access Token**, paste the token, connect.

## 2. Choose the tables

In the Navigator, expand `workspace` > `gold` and tick:

| Table | Role in the model | Rows |
| --- | --- | --- |
| `fct_market_quarter` | the snapshot fact: one row per market, submarket and quarter | 360 |
| `fct_leasing_deal` | the transaction fact: one row per deal that passed every check | 5,608 |
| `mart_market_kpis` | the KPI mart: the shared definitions at market × quarter grain | 75 |
| `dim_market`, `dim_submarket`, `dim_quarter`, `dim_date` | dimensions shared by both facts | 5, 24, 20, 1,826 |
| `dim_tenant`, `dim_deal_type`, `dim_sector` | deal dimensions | 299, 5, 10 |
| `dim_building_history` | the building as it was on the deal date (type 2) | 750 |
| `dim_metric_definition` | the KPI definitions, shown on the report as a reference table | 15 |

Leave out `dim_building` (the deals page uses the history version), `fct_building_availability` and
the `silver`, `ops` and `bronze` schemas: a report reads gold only. The table and column descriptions
you see in the Navigator come from `models/gold/_gold.yml` through `persist_docs`.

Click **Load** (no transformation needed; that is the point of a gold layer).

## 3. Relationships (Model view)

Power BI will guess some relationships from column names. Check them against this list and delete any
others. Every relationship is **many-to-one, single direction**, from the fact to the dimension:

| From (many) | To (one) |
| --- | --- |
| `fct_market_quarter[submarket_key]` | `dim_submarket[submarket_key]` |
| `fct_market_quarter[quarter_id]` | `dim_quarter[quarter_id]` |
| `fct_market_quarter[market_id]` | `dim_market[market_id]` |
| `fct_leasing_deal[market_id]` | `dim_market[market_id]` |
| `fct_leasing_deal[submarket_key]` | `dim_submarket[submarket_key]` |
| `fct_leasing_deal[quarter_id]` | `dim_quarter[quarter_id]` |
| `fct_leasing_deal[deal_date_key]` | `dim_date[date_key]` |
| `fct_leasing_deal[tenant_key]` | `dim_tenant[tenant_key]` |
| `fct_leasing_deal[deal_type_code]` | `dim_deal_type[deal_type_code]` |
| `fct_leasing_deal[sector_code]` | `dim_sector[sector_code]` |
| `fct_leasing_deal[building_version_key]` | `dim_building_history[building_version_key]` |
| `mart_market_kpis[market_id]` | `dim_market[market_id]` |
| `mart_market_kpis[quarter_id]` | `dim_quarter[quarter_id]` |

Two things not to do: do not relate `dim_submarket` to `dim_market` (both facts already carry
`market_id`, and a second path between them would make the model ambiguous), and do not relate
`dim_date` to `dim_quarter` for the same reason. If Power BI created either, delete it.

Then: select `dim_date` > **Mark as date table** > `date_day`. Hide the key columns on the facts
(`*_key`, `market_id`, `quarter_id`) so report authors pick fields from the dimensions.

## 4. Measures

Paste the measures from [`measures.dax`](measures.dax), one at a time (**Home** > **New measure**), into
the table named in each comment. Two design rules carry over from the dbt project:

- **Ratios are built from sums**, never averaged: `Vacancy rate = DIVIDE(SUM(vacant), SUM(stock))`, so it
  is right for one submarket, one market or all five, whatever the slicers say. Prime rent is the
  highest submarket (MAX), prime yield the keenest (MIN), exactly as in `mart_market_kpis` and the metric
  view. `dim_metric_definition` is the written definition of each one.
- **The mart is the definition; the fact is the drill-down.** The year-on-year growth measure reads the
  mart's `prime_rent_growth_yoy` rather than recomputing it, and a check measure (`KPI check: vacancy`)
  shows the difference between the re-aggregated rate and the mart's rate: it must read 0.0 at market
  level, the same invariant as `tests/assert_market_kpis_match_fact.sql`.

Format percentages (`Vacancy rate`, `Prime yield`, growth) as percentage with 1 or 2 decimals, areas
as whole numbers with thousands separators, rents as whole numbers.

## 5. Page 1: Market overview

Slicers at the top: `dim_quarter[quarter_label]` (single select, default to Q3 2026) and
`dim_market[market_name]`.

| Visual | Fields |
| --- | --- |
| Card row (five cards) | `Vacancy rate`, `Take-up (sq m)`, `Prime rent (EUR/sq m/yr)`, `Prime yield`, `Deals` |
| Line chart: prime rent over time | x: `dim_quarter[quarter_end_date]`, y: `Prime rent (EUR/sq m/yr)`, legend: `dim_market[market_name]`. Drop the quarter slicer's filter on this visual (Format > Edit interactions) so it shows the full history |
| Clustered column chart: take-up by quarter | x: `dim_quarter[quarter_label]`, y: `Take-up (sq m)`, legend: market; same interaction edit |
| Table: markets this quarter | `dim_market[market_name]`, `Vacancy rate`, `Prime rent growth YoY`, `Prime yield`, `Take-up (sq m)`, `KPI check: vacancy` |
| Matrix: submarkets | rows `dim_submarket[submarket_name]`, values `Vacancy rate`, `Prime rent (EUR/sq m/yr)`, `Register vacancy rate` |

The `KPI check` column is deliberately on the page: a reviewer should see the fact and the mart agree.

## 6. Page 2: Leasing deals

Slicers: `dim_date[year_number]` (or a date range), `dim_market[market_name]`, `dim_sector[sector_name]`.

| Visual | Fields |
| --- | --- |
| Cards | `Deals (count)`, `Area let (sq m)`, `Achieved rent (EUR/sq m/yr)`, `Average deal size (sq m)` |
| Bar chart: top tenants | y: `dim_tenant[tenant_name]`, x: `Area let (sq m)`, top 10 filter |
| Column chart: deals by building grade at the deal date | x: `dim_building_history[grade_code]`, y: `Deals (count)` |
| Card | `Deals in re-graded buildings` (207 on the committed data: deals signed before a building the market later re-sent as Grade A was refurbished) |
| Table: deals | `fct_leasing_deal[deal_date]`, tenant, `dim_submarket[submarket_name]`, `fct_leasing_deal[area_m2]`, `fct_leasing_deal[rent_eur_m2_yr]`, `dim_deal_type[deal_type_name]`, `dim_building_history[grade_code]` |

Optional page 3, "Definitions": a table visual over `dim_metric_definition` (metric, definition, unit,
formula), so the report carries its own data contract.

## 7. Save, screenshot, commit

- Save as `powerbi/emea_office_markets.pbix`. If your Power BI Desktop offers **Power BI Project
  (.pbip)** as a save format (Options > Preview features), prefer it: the model and report are then
  text files that diff in git, and the folder it creates goes in `powerbi/` too.
- Screenshots of both pages to `docs/img/powerbi_market_overview.png` and
  `docs/img/powerbi_leasing_deals.png`, and of the Model view to `docs/img/powerbi_model.png`;
  reference them from the main README's Power BI section.
- The token stays in Power BI's credential store on your machine, never in the repository.
- Optional: **Publish** to My workspace in the Power BI service needs a work or school account (a
  university address works); it is not needed for the portfolio.

## What to be able to explain

- Why Import and not DirectQuery here, and when you would switch.
- Why the model is a star with single-direction relationships, and why `dim_submarket` is not related
  to `dim_market`.
- Why `Vacancy rate` is `DIVIDE(SUM, SUM)` and not `AVERAGE(vacancy_rate)`; what the check measure proves.
- Why deals use `dim_building_history` (grade on the deal date) and what `dim_building` would get wrong.
- Where a report author finds the definition of a measure (`dim_metric_definition`, the column
  comments, the dbt docs), and who owns a change to one (the KPI row in `ref_metric_definitions.csv`,
  changed in a pull request, with the metric view, semantic view and this report updated together).
