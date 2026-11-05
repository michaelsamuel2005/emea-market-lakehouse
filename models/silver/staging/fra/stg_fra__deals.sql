-- Frankfurt (FRA): deals in the shared staging layout.
-- All market-specific parsing is driven by vars.markets.FRA in dbt_project.yml.
{{ stage_deals('FRA') }}
