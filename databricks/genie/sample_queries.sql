-- Example SQL for the Genie space (Configure > Instructions > Example SQL queries). Each one is a
-- question a research analyst or market lead would ask, answered the way the definitions require.

-- Q: What was the vacancy rate in each market in the latest quarter?
select market_name, quarter_label, measure(vacancy_rate) as vacancy_rate
from workspace.gold.mv_market_kpis
where quarter_id = (select max(quarter_id) from workspace.gold.fct_market_quarter)
group by market_name, quarter_label
order by vacancy_rate desc;

-- Q: How has prime rent in Paris changed over the last two years?
select quarter_id, prime_rent_eur_m2_yr, round(prime_rent_growth_yoy * 100, 1) as growth_yoy_pct
from workspace.gold.mart_market_kpis
where market_id = 'PAR' and quarter_id >= '2024Q3'
order by quarter_id;

-- Q: Which submarket has the highest prime rent in London?
select submarket_name, measure(prime_rent_eur_m2_yr) as prime_rent_eur_m2_yr
from workspace.gold.mv_market_kpis
where market_name = 'London' and quarter_id = '2026Q3'
group by submarket_name
order by prime_rent_eur_m2_yr desc
limit 1;

-- Q: Total take-up by market in 2026 so far
select market_name, measure(take_up_m2) as take_up_m2
from workspace.gold.mv_market_kpis
where year_number = 2026
group by market_name
order by take_up_m2 desc;

-- Q: Which tenants have taken space in more than one market?
select tenant_name, markets_active, deal_count
from workspace.gold.dim_tenant
where markets_active > 1
order by markets_active desc, deal_count desc;

-- Q: Largest leasing deals in Frankfurt since 2025
select deal_date, tenant_name, submarket_name, measure(total_area_m2) as area_m2, deal_type_name
from workspace.gold.mv_leasing_deals
where market_name = 'Frankfurt' and deal_year >= 2025
group by deal_date, tenant_name, submarket_name, deal_type_name
order by area_m2 desc
limit 10;

-- Q: Which sectors drive take-up in Warsaw?
select sector_name, measure(deal_count) as deals, measure(total_area_m2) as area_m2
from workspace.gold.mv_leasing_deals
where market_name = 'Warsaw'
group by sector_name
order by area_m2 desc;

-- Q: Summarise the Amsterdam market in Q3 2026
select summary_text
from workspace.gold.mart_ai_market_facts
where market_name = 'Amsterdam' and quarter_id = '2026Q3';
