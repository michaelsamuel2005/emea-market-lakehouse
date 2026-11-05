-- Table maintenance for the gold layer on Databricks. dbt-databricks already runs OPTIMIZE on the
-- liquid-clustered facts after each build; this script is the periodic housekeeping a job would run
-- weekly, and the statistics the query optimiser uses. Run in the SQL editor or as a job task.

-- Compact small files and cluster by the declared keys (no-op if already optimal)
optimize workspace.gold.fct_market_quarter;
optimize workspace.gold.fct_leasing_deal;
optimize workspace.gold.fct_building_availability;
optimize workspace.gold.mart_market_kpis;

-- Column statistics for the filters and joins the dashboards and Genie use most
analyze table workspace.gold.fct_market_quarter compute statistics for columns market_id, submarket_id, quarter_id;
analyze table workspace.gold.fct_leasing_deal compute statistics for columns market_id, submarket_key, quarter_id, deal_date, tenant_key;
analyze table workspace.gold.mart_market_kpis compute statistics for all columns;

-- Remove files no longer referenced by the current table version (keeps 7 days of history for time travel)
vacuum workspace.gold.fct_market_quarter retain 168 hours;
vacuum workspace.gold.fct_leasing_deal retain 168 hours;
vacuum workspace.silver.int_deals retain 168 hours;

-- What the tables look like after maintenance
describe detail workspace.gold.fct_leasing_deal;
describe history workspace.gold.fct_leasing_deal limit 5;
