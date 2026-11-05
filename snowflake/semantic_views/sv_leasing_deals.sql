-- Snowflake semantic view over the leasing deals, with the dimensions joined.
-- The Snowflake counterpart of databricks/metric_views/mv_leasing_deals.sql. Deals join the building history
-- on building_version_key, so building_grade_at_deal is the grade the building had when the lease was signed.

create or replace semantic view emea_market_lakehouse.gold.sv_leasing_deals

    tables (
        deals as emea_market_lakehouse.gold.fct_leasing_deal
            primary key (deal_key)
            with synonyms ('leases', 'lettings', 'transactions')
            comment = 'Leasing deals that passed every data quality check; rents in EUR per square metre per year',
        markets as emea_market_lakehouse.gold.dim_market
            primary key (market_id),
        submarkets as emea_market_lakehouse.gold.dim_submarket
            primary key (submarket_key),
        tenants as emea_market_lakehouse.gold.dim_tenant
            primary key (tenant_key)
            with synonyms ('occupiers', 'lessees'),
        building_versions as emea_market_lakehouse.gold.dim_building_history
            primary key (building_version_key)
            comment = 'Each building as it was over a period (grade before and after a refurbishment)',
        deal_types as emea_market_lakehouse.gold.dim_deal_type
            primary key (deal_type_code),
        sectors as emea_market_lakehouse.gold.dim_sector
            primary key (sector_code)
    )

    relationships (
        deal_to_market as deals (market_id) references markets,
        deal_to_submarket as deals (submarket_key) references submarkets,
        deal_to_tenant as deals (tenant_key) references tenants,
        deal_to_building_version as deals (building_version_key) references building_versions,
        deal_to_deal_type as deals (deal_type_code) references deal_types,
        deal_to_sector as deals (sector_code) references sectors
    )

    dimensions (
        markets.market as markets.market_name
            with synonyms ('city', 'market name'),
        submarkets.submarket as submarkets.submarket_name
            with synonyms ('district'),
        deals.deal_quarter as deals.quarter_id
            comment = 'Quarter of the deal date, e.g. 2026Q3',
        deals.signed_date as deals.deal_date
            with synonyms ('deal date', 'date')
            comment = 'Date the lease was signed',
        deals.signed_year as year(deals.deal_date)
            with synonyms ('year'),
        tenants.tenant as tenants.tenant_name
            with synonyms ('occupier', 'company', 'lessee'),
        sectors.sector as sectors.sector_name
            with synonyms ('industry', 'occupier sector'),
        deal_types.deal_type as deal_types.deal_type_name
            comment = 'New lease, Renewal, Expansion, Sublease or Pre-let',
        building_versions.building as building_versions.building_name,
        building_versions.building_grade_at_deal as building_versions.grade_code
            with synonyms ('grade', 'building grade', 'quality')
            comment = 'A, B or C: the grade the building had on the deal date'
    )

    metrics (
        deals.deal_count as count(deals.deal_key)
            with synonyms ('number of deals', 'transactions', 'lettings'),
        deals.total_area_let_m2 as sum(deals.area_m2)
            with synonyms ('take-up', 'space let', 'volume')
            comment = 'Floorspace let, square metres',
        deals.average_deal_size_m2 as avg(deals.area_m2)
            comment = 'Average deal size, square metres',
        deals.largest_deal_m2 as max(deals.area_m2)
            comment = 'Largest single deal, square metres',
        deals.achieved_rent_eur_m2_yr as sum(deals.annual_rent_eur) / nullif(sum(case when deals.rent_eur_m2_yr is not null then deals.area_m2 end), 0)
            with synonyms ('average rent', 'rent achieved')
            comment = 'Area-weighted average rent of deals with a disclosed rent, EUR per square metre per year',
        deals.average_lease_term_years as avg(deals.lease_term_years)
            with synonyms ('lease length', 'term')
    )

    comment = 'Leasing deals across the EMEA office markets. Synthetic data.';

-- The ten most active tenants since 2025:
-- select *
-- from semantic_view(
--     emea_market_lakehouse.gold.sv_leasing_deals
--     dimensions tenants.tenant
--     metrics deals.deal_count, deals.total_area_let_m2
--     where deals.signed_year >= 2025
-- )
-- order by total_area_let_m2 desc
-- limit 10;
