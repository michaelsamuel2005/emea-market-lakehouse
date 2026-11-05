-- London (LON): availability in the shared staging layout.
-- All market-specific parsing is driven by vars.markets.LON in dbt_project.yml.
{{ stage_availability('LON') }}
