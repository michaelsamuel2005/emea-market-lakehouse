-- Every local label a market uses must be in the reference mappings; otherwise rows fall out of
-- gold silently. Fails the build. Fix: add the mapping row in seeds/reference, or correct the market.

select *
from {{ ref('ops_dq_unmapped_codes') }}
