-- Each building's versions must tile time exactly: the first starts at 1900-01-01, each one ends where
-- the next begins, the last ends at 9999-12-31, and exactly one is current. A gap would leave a deal with
-- no building version; an overlap would give it two.

with ordered as (

    select
        building_key,
        version_number,
        valid_from,
        valid_to,
        is_current,
        lead(valid_from) over (partition by building_key order by version_number) as next_valid_from,
        count(*) over (partition by building_key) as versions,
        sum(case when is_current then 1 else 0 end) over (partition by building_key) as current_versions
    from {{ ref('int_building_versions') }}

)

select
    building_key,
    version_number,
    valid_from,
    valid_to,
    next_valid_from
from ordered
where valid_from >= valid_to
    or (version_number = 1 and valid_from <> cast('1900-01-01' as date))
    or (next_valid_from is not null and valid_to <> next_valid_from)
    or (next_valid_from is null and valid_to <> cast('9999-12-31' as date))
    or current_versions <> 1
    or (is_current and version_number <> versions)
