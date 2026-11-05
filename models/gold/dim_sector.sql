-- Shared occupier-sector codes.

select
    sector_code,
    sector_name
from {{ ref('ref_sectors') }}
