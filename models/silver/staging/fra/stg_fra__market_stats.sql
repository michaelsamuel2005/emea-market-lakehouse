-- Frankfurt (FRA): market stats in the shared staging layout.
-- All market-specific parsing is driven by vars.markets.FRA in dbt_project.yml.
{{ stage_market_stats('FRA') }}
