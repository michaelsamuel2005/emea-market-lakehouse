-- Amsterdam (AMS): market stats in the shared staging layout.
-- All market-specific parsing is driven by vars.markets.AMS in dbt_project.yml.
{{ stage_market_stats('AMS') }}
