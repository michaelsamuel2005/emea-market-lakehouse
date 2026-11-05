-- Warsaw (WAW): deals in the shared staging layout.
-- All market-specific parsing is driven by vars.markets.WAW in dbt_project.yml.
{{ stage_deals('WAW') }}
