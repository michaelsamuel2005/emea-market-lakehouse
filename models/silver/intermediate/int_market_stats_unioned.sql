{{ config(materialized='view') }}

-- Every configured market's quarterly market submissions, stacked: one row per staging row, nothing changed.
-- The union is its own model so the rules that read it can be unit-tested with one input, however many
-- markets are configured: onboarding a market adds it here (union_markets loops over vars.markets) and
-- no test has to change.

{{ union_markets('market_stats') }}
