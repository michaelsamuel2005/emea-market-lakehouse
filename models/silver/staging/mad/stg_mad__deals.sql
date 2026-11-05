-- Madrid (MAD): deals in the shared staging layout.
-- All market-specific parsing is driven by vars.markets.MAD in dbt_project.yml.
{{ stage_deals('MAD') }}
