-- Snowflake semantic view: the market KPIs defined once, over the gold star schema.
-- The Snowflake counterpart of databricks/metric_views/mv_market_kpis.sql. Run it in a Snowsight worksheet
-- (role TRANSFORMER) after `dbt build --target snowflake`. Cortex Analyst and Snowflake Intelligence read
-- the synonyms and comments to answer questions in English.
--
-- Ratios are defined from sums (sum of vacant over sum of stock), never as an average of rates, so the
-- vacancy rate is right at any grouping: by market, by submarket, or across all markets. Stock is a
-- quarter-end snapshot: group by a quarter (or filter to one) rather than adding stock across quarters.

create or replace semantic view emea_market_lakehouse.gold.sv_market_kpis

    tables (
        markets as emea_market_lakehouse.gold.dim_market
            primary key (market_id)
            with synonyms ('cities', 'office markets')
            comment = 'The onboarded office markets, one row each',
        submarkets as emea_market_lakehouse.gold.dim_submarket
            primary key (submarket_key)
            with synonyms ('districts')
            comment = 'Submarkets within each market',
        quarters as emea_market_lakehouse.gold.dim_quarter
            primary key (quarter_id)
            comment = 'Calendar quarters',
        market_quarter as emea_market_lakehouse.gold.fct_market_quarter
            primary key (market_quarter_key)
            comment = 'One row per market, submarket and quarter: the market''s reported figures and the bottom-up checks'
    )

    relationships (
        market_quarter_to_market as market_quarter (market_id) references markets,
        market_quarter_to_submarket as market_quarter (submarket_key) references submarkets,
        market_quarter_to_quarter as market_quarter (quarter_id) references quarters
    )

    -- Dimension names differ from the column names they read (market reads market_name), as in Snowflake's
    -- own examples, so an expression never has to guess whether a name means the column or the dimension.
    dimensions (
        markets.market as markets.market_name
            with synonyms ('city', 'market name')
            comment = 'Market (city), e.g. London',
        markets.country as markets.country_name
            comment = 'Country of the market',
        submarkets.submarket as submarkets.submarket_name
            with synonyms ('district', 'area')
            comment = 'Submarket within the market, e.g. West End',
        quarters.quarter as quarters.quarter_id
            comment = 'Quarter id, e.g. 2026Q3',
        quarters.quarter_name as quarters.quarter_label
            with synonyms ('period')
            comment = 'Quarter, e.g. Q3 2026',
        quarters.quarter_end as quarters.quarter_end_date
            comment = 'Last day of the quarter',
        quarters.calendar_year as quarters.year_number
            with synonyms ('year')
            comment = 'Calendar year'
    )

    metrics (
        market_quarter.total_stock_m2 as sum(market_quarter.stock_m2)
            with synonyms ('stock', 'office stock', 'floorspace', 'inventory')
            comment = 'Total office stock at the quarter end, square metres',
        market_quarter.total_vacant_m2 as sum(market_quarter.vacant_m2)
            with synonyms ('vacant space', 'vacancy area')
            comment = 'Vacant space at the quarter end, square metres',
        market_quarter.stock_weighted_vacancy_rate as sum(market_quarter.vacant_m2) / nullif(sum(market_quarter.stock_m2), 0)
            with synonyms ('vacancy rate', 'vacancy', 'availability rate')
            comment = 'Vacant space divided by stock, as a fraction (0.10 = 10%); weighted by stock, never an average of rates',
        market_quarter.total_take_up_m2 as sum(market_quarter.take_up_m2)
            with synonyms ('take-up', 'take up', 'leasing volume', 'letting activity')
            comment = 'Floorspace let in the period, square metres',
        market_quarter.top_prime_rent_eur_m2_yr as max(market_quarter.prime_rent_eur_m2_yr)
            with synonyms ('prime rent', 'headline rent', 'top rent')
            comment = 'Prime rent in EUR per square metre per year; the highest submarket in the grouping',
        market_quarter.keenest_prime_yield as min(market_quarter.prime_yield)
            with synonyms ('prime yield', 'yield', 'cap rate')
            comment = 'Prime yield as a fraction (0.04 = 4%); the lowest submarket in the grouping',
        market_quarter.total_under_construction_m2 as sum(market_quarter.under_construction_m2)
            with synonyms ('pipeline', 'development pipeline', 'under construction')
            comment = 'Space under construction at the quarter end, square metres',
        market_quarter.total_deals as sum(market_quarter.deal_count)
            with synonyms ('deals', 'number of deals', 'transactions', 'lettings')
            comment = 'Leasing deals that passed every data quality check',
        market_quarter.register_vacancy_rate_weighted as sum(market_quarter.register_available_m2) / nullif(sum(market_quarter.register_tracked_area_m2), 0)
            with synonyms ('register vacancy', 'bottom-up vacancy')
            comment = 'Vacancy computed from the tracked building register, for reconciliation with the reported rate'
    )

    comment = 'EMEA office market KPIs by market, submarket and quarter. Synthetic data. Definitions match gold.dim_metric_definition.';

-- Market KPIs for the latest quarter:
-- select *
-- from semantic_view(
--     emea_market_lakehouse.gold.sv_market_kpis
--     dimensions markets.market, quarters.quarter
--     metrics market_quarter.stock_weighted_vacancy_rate, market_quarter.total_take_up_m2,
--             market_quarter.top_prime_rent_eur_m2_yr, market_quarter.keenest_prime_yield, market_quarter.total_deals
--     where quarters.quarter = '2026Q3'
-- )
-- order by market;
