{{ config(materialized='view') }}

-- The deals that passed every check in int_deals: one row per real deal, mapped and converted.
-- This is what gold.fct_leasing_deal is built from.

select *
from {{ ref('int_deals') }}
where quarantine_reason is null
