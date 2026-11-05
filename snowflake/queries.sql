-- The dashboard tile queries for Snowflake: the same SQL as databricks/dashboard/tiles.sql, reading
-- EMEA_MARKET_LAKEHOUSE instead of the Databricks catalog. Run each in a Snowsight worksheet and use Chart,
-- or add them to a Snowsight dashboard. Every query reads gold or ops tables, so the numbers match the tests.

-- Tile 1: KPI table, latest quarter
select
    m.market_name,
    round(k.vacancy_rate * 100, 1) as vacancy_rate_pct,
    round(k.vacancy_rate_change_qoq * 100, 2) as vacancy_change_pp,
    round(k.take_up_m2) as take_up_m2,
    round(k.prime_rent_eur_m2_yr) as prime_rent_eur_m2_yr,
    round(k.prime_rent_growth_yoy * 100, 1) as prime_rent_growth_yoy_pct,
    round(k.prime_yield * 100, 2) as prime_yield_pct,
    k.deal_count
from emea_market_lakehouse.gold.mart_market_kpis as k
inner join emea_market_lakehouse.gold.dim_market as m on k.market_id = m.market_id
where k.quarter_id = (select max(quarter_id) from emea_market_lakehouse.gold.mart_market_kpis)
order by m.market_name;

-- Tile 2: prime rent by market over time (line chart: x = period_end_date, y = prime_rent, colour = market)
select m.market_name, k.period_end_date, round(k.prime_rent_eur_m2_yr) as prime_rent_eur_m2_yr
from emea_market_lakehouse.gold.mart_market_kpis as k
inner join emea_market_lakehouse.gold.dim_market as m on k.market_id = m.market_id
order by k.period_end_date, m.market_name;

-- Tile 3: take-up by quarter and market (stacked bar)
select m.market_name, k.quarter_id, round(k.take_up_m2) as take_up_m2
from emea_market_lakehouse.gold.mart_market_kpis as k
inner join emea_market_lakehouse.gold.dim_market as m on k.market_id = m.market_id
order by k.quarter_id, m.market_name;

-- Tile 4: vacancy rate trend (line)
select m.market_name, k.period_end_date, round(k.vacancy_rate * 100, 1) as vacancy_rate_pct
from emea_market_lakehouse.gold.mart_market_kpis as k
inner join emea_market_lakehouse.gold.dim_market as m on k.market_id = m.market_id
order by k.period_end_date, m.market_name;

-- Tile 5: reported vs register vacancy (scatter, one point per submarket-quarter; outliers are the reconciliation cases)
select market_id, submarket_id, quarter_id,
       round(reported_vacancy_rate * 100, 1) as reported_pct,
       round(register_vacancy_rate * 100, 1) as register_pct,
       is_outside_tolerance
from emea_market_lakehouse.ops.ops_dq_reconciliation_vacancy;

-- Tile 6: data quality, latest build (table)
select market_id, quarantine_reason, row_count, market_quarantine_rate_pct
from emea_market_lakehouse.ops.ops_dq_quarantine_summary
order by market_id, row_count desc;

-- Tile 7: top tenants by space taken (bar)
select tenant_name, sector_name, markets_active, deal_count
from emea_market_lakehouse.gold.dim_tenant
order by deal_count desc
limit 15;

-- Tile 8: last run health (table)
select node_name, resource_type, status, round(execution_time_seconds, 2) as seconds
from emea_market_lakehouse.ops.ops_run_history
where invocation_id = (select invocation_id from emea_market_lakehouse.ops.ops_run_history order by run_started_at desc limit 1)
order by execution_time_seconds desc
limit 20;
