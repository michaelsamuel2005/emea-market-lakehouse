-- London (LON): buildings in the shared staging layout.
-- All market-specific parsing is driven by vars.markets.LON in dbt_project.yml.
{{ stage_buildings('LON') }}
