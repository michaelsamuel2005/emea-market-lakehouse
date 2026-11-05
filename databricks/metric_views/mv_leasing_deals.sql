-- Unity Catalog metric view over the leasing deals, with the dimensions joined for Genie and dashboards.
-- Deals join the building history on building_version_key, so building_grade_at_deal is the grade the
-- building had when the lease was signed; building_grade is its grade today.

create or replace view workspace.gold.mv_leasing_deals
with metrics
language yaml
as $$
version: 1.1
comment: "Leasing deals across the EMEA office markets that passed every data quality check. Rents in EUR per sq m per year."
source: workspace.gold.fct_leasing_deal

joins:
  - name: market
    source: workspace.gold.dim_market
    'on': source.market_id = market.market_id
  - name: submarket
    source: workspace.gold.dim_submarket
    'on': source.submarket_key = submarket.submarket_key
  - name: tenant
    source: workspace.gold.dim_tenant
    'on': source.tenant_key = tenant.tenant_key
  - name: building
    source: workspace.gold.dim_building
    'on': source.building_key = building.building_key
  - name: building_version
    source: workspace.gold.dim_building_history
    'on': source.building_version_key = building_version.building_version_key
  - name: deal_type
    source: workspace.gold.dim_deal_type
    'on': source.deal_type_code = deal_type.deal_type_code
  - name: sector
    source: workspace.gold.dim_sector
    'on': source.sector_code = sector.sector_code

fields:
  - name: market_name
    expr: market.market_name
    synonyms: ['city', 'market']
  - name: submarket_name
    expr: submarket.submarket_name
    synonyms: ['district']
  - name: quarter_id
    expr: source.quarter_id
    comment: "Quarter of the deal date, e.g. 2026Q3"
  - name: deal_date
    expr: source.deal_date
  - name: deal_year
    expr: YEAR(source.deal_date)
    synonyms: ['year']
  - name: tenant_name
    expr: tenant.tenant_name
    synonyms: ['occupier', 'company', 'lessee']
  - name: sector_name
    expr: sector.sector_name
    synonyms: ['industry', 'occupier sector']
  - name: deal_type_name
    expr: deal_type.deal_type_name
    comment: "New lease, Renewal, Expansion, Sublease or Pre-let"
  - name: building_name
    expr: building.building_name
  - name: building_grade
    expr: building.grade_code
    comment: "A, B or C: the building's grade today"
    synonyms: ['current grade']
  - name: building_grade_at_deal
    expr: building_version.grade_code
    comment: "A, B or C: the grade the building had on the deal date (before or after a refurbishment)"
    synonyms: ['grade', 'quality', 'building grade']

measures:
  - name: deal_count
    expr: COUNT(1)
    display_name: "Deals"
    synonyms: ['number of deals', 'transactions', 'lettings']
  - name: total_area_m2
    expr: SUM(source.area_m2)
    comment: "Floorspace let, square metres"
    display_name: "Area let (sq m)"
    synonyms: ['take-up', 'space let', 'volume']
  - name: average_deal_size_m2
    expr: AVG(source.area_m2)
    display_name: "Average deal size (sq m)"
  - name: largest_deal_m2
    expr: MAX(source.area_m2)
    display_name: "Largest deal (sq m)"
  - name: achieved_rent_eur_m2_yr
    expr: SUM(source.annual_rent_eur) / NULLIF(SUM(CASE WHEN source.rent_eur_m2_yr IS NOT NULL THEN source.area_m2 END), 0)
    comment: "Area-weighted average rent of deals with a disclosed rent, EUR per sq m per year"
    display_name: "Achieved rent (EUR/sq m/year)"
    synonyms: ['average rent', 'rent achieved']
    format:
      type: currency
      currency_code: EUR
      decimal_places:
        type: exact
        places: 0
  - name: average_lease_term_years
    expr: AVG(source.lease_term_years)
    display_name: "Average lease term (years)"
    synonyms: ['term', 'lease length']
$$;

-- Example: the ten most active tenants across all markets since 2025
-- select tenant_name, measure(deal_count) as deals, measure(total_area_m2) as area_m2
-- from workspace.gold.mv_leasing_deals
-- where deal_year >= 2025
-- group by tenant_name
-- order by area_m2 desc
-- limit 10;
