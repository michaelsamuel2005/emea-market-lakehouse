-- One row per onboarded market, with the conventions it reports in. The conventions are kept so a
-- reader of the gold layer can see where a number came from, but every measure in the facts is
-- already converted: areas in m2, rents in EUR per m2 per year, yields as fractions.

select
    market_id,
    market_name,
    country_code,
    country_name,
    region,
    currency_code as reporting_currency,
    area_unit as reporting_area_unit,
    rent_unit as reporting_rent_unit,
    timezone
from {{ ref('ref_markets') }}
