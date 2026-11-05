-- Quarter dimension for the periodic snapshot facts: one row per quarter, with the previous
-- quarter's id so measures can compute quarter-on-quarter change without date arithmetic.

with quarters as (

    select distinct
        quarter_id,
        year_number,
        quarter_number,
        quarter_end_date
    from {{ ref('dim_date') }}

)

select
    quarter_id,
    year_number,
    quarter_number,
    quarter_end_date,
    concat('Q', cast(quarter_number as {{ dbt.type_string() }}), ' ', cast(year_number as {{ dbt.type_string() }})) as quarter_label,
    lag(quarter_id) over (order by quarter_end_date) as previous_quarter_id,
    lag(quarter_id, 4) over (order by quarter_end_date) as same_quarter_previous_year_id
from quarters
