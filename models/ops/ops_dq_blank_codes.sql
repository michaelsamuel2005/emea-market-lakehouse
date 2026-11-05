-- Rows a market sent with a blank code: not an error the pipeline can fix, but a figure to report
-- back to the market each quarter (for example buildings without a grade).

select
    market_id,
    'buildings' as dataset,
    'grade' as code_type,
    count(*) as blank_rows
from {{ ref('int_buildings') }}
where grade_local is null
group by market_id

union all

select
    market_id,
    'deals' as dataset,
    'rent' as code_type,
    count(*) as blank_rows
from {{ ref('int_deals') }}
where rent_local_as_reported is null and quarantine_reason is null
group by market_id
