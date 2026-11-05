-- Paris (PAR): market stats in the shared staging layout.
-- All market-specific parsing is driven by vars.markets.PAR in dbt_project.yml.
{{ stage_market_stats('PAR') }}
