-- Paris (PAR): deals in the shared staging layout.
-- All market-specific parsing is driven by vars.markets.PAR in dbt_project.yml.
{{ stage_deals('PAR') }}
