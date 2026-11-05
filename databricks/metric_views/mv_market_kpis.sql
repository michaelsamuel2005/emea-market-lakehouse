-- Unity Catalog metric view: the market KPIs defined once, on the central platform.
-- Run in the Databricks SQL editor after `dbt build --target databricks`.
-- Query it with MEASURE(): see the example at the bottom. YAML version 1.1 (used here for synonyms, display
-- names and formats) needs compute on Databricks Runtime 17.3 or above.
-- Ratios are built from sums (sum of vacant over sum of stock), so they are right at any grouping; NULLIF
-- returns null instead of failing when a grouping has no stock. Stock is a quarter-end snapshot: group by a
-- quarter (or filter to one) rather than adding stock across quarters.

create or replace view workspace.gold.mv_market_kpis
with metrics
language yaml
as $$
version: 1.1
comment: "EMEA office market KPIs by market, submarket and quarter. Definitions match gold.dim_metric_definition."
source: workspace.gold.fct_market_quarter

joins:
  - name: market
    source: workspace.gold.dim_market
    'on': source.market_id = market.market_id
  - name: submarket
    source: workspace.gold.dim_submarket
    'on': source.submarket_key = submarket.submarket_key
  - name: quarter
    source: workspace.gold.dim_quarter
    'on': source.quarter_id = quarter.quarter_id

fields:
  - name: market_name
    expr: market.market_name
    comment: "Market (city)"
    synonyms: ['city', 'market']
  - name: country_name
    expr: market.country_name
  - name: region
    expr: market.region
  - name: submarket_name
    expr: submarket.submarket_name
    comment: "Submarket within the market"
    synonyms: ['district', 'area']
  - name: quarter_id
    expr: source.quarter_id
    comment: "Quarter id, e.g. 2026Q3"
  - name: quarter_label
    expr: quarter.quarter_label
    comment: "Quarter, e.g. Q3 2026"
    synonyms: ['period', 'quarter']
  - name: quarter_end_date
    expr: source.period_end_date
  - name: year_number
    expr: quarter.year_number
    synonyms: ['year']

measures:
  - name: stock_m2
    expr: SUM(source.stock_m2)
    comment: "Total office stock, square metres"
    display_name: "Office stock (sq m)"
    synonyms: ['stock', 'floorspace', 'inventory']
  - name: vacant_m2
    expr: SUM(source.vacant_m2)
    comment: "Vacant space, square metres"
    display_name: "Vacant space (sq m)"
  - name: vacancy_rate
    expr: SUM(source.vacant_m2) / NULLIF(SUM(source.stock_m2), 0)
    comment: "Stock-weighted vacancy rate: vacant space divided by stock (0.10 = 10%)"
    display_name: "Vacancy rate"
    synonyms: ['vacancy', 'availability rate']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
  - name: take_up_m2
    expr: SUM(source.take_up_m2)
    comment: "Floorspace let in the quarter, square metres"
    display_name: "Take-up (sq m)"
    synonyms: ['leasing volume', 'absorption', 'letting activity']
  - name: occupied_m2
    expr: SUM(source.occupied_m2)
    comment: "Occupied space (stock minus vacant) at the quarter end; the change between quarters is net absorption (gold.mart_market_kpis.net_absorption_m2)"
    display_name: "Occupied space (sq m)"
    synonyms: ['occupied space', 'let space']
  - name: prime_rent_eur_m2_yr
    expr: MAX(source.prime_rent_eur_m2_yr)
    comment: "Prime rent in EUR per square metre per year (the best submarket in the grouping)"
    display_name: "Prime rent (EUR/sq m/year)"
    synonyms: ['headline rent', 'top rent', 'rent']
    format:
      type: currency
      currency_code: EUR
      decimal_places:
        type: exact
        places: 0
  - name: prime_yield
    expr: MIN(source.prime_yield)
    comment: "Prime yield as a fraction (0.04 = 4%); the keenest submarket in the grouping"
    display_name: "Prime yield"
    synonyms: ['yield', 'cap rate', 'capitalisation rate']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2
  - name: under_construction_m2
    expr: SUM(source.under_construction_m2)
    comment: "Space under construction at the quarter end, square metres"
    display_name: "Under construction (sq m)"
    synonyms: ['pipeline', 'development pipeline']
  - name: deal_count
    expr: SUM(source.deal_count)
    comment: "Leasing deals logged that passed every data quality check"
    display_name: "Deals"
    synonyms: ['transactions', 'lettings', 'number of deals']
  - name: register_vacancy_rate
    expr: SUM(source.register_available_m2) / NULLIF(SUM(source.register_tracked_area_m2), 0)
    comment: "Bottom-up vacancy from the tracked building register, for reconciliation"
    display_name: "Register vacancy rate"
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
$$;

-- Example: market-level KPIs for the latest quarter
-- select market_name, quarter_label,
--        measure(vacancy_rate) as vacancy_rate, measure(take_up_m2) as take_up_m2,
--        measure(prime_rent_eur_m2_yr) as prime_rent, measure(prime_yield) as prime_yield, measure(deal_count) as deals
-- from workspace.gold.mv_market_kpis
-- where quarter_id = '2026Q3'
-- group by market_name, quarter_label
-- order by market_name;
