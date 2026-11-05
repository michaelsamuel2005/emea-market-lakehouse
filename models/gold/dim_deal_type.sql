-- Shared deal-type codes, with every local label that maps to each one (for reference and for Genie).

with labels as (

    select
        deal_type_code,
        count(*) as local_label_count
    from {{ ref('ref_deal_type_mapping') }}
    group by deal_type_code

)

select
    d.deal_type_code,
    d.deal_type_name,
    coalesce(l.local_label_count, 0) as local_label_count
from {{ ref('ref_deal_types') }} as d
left join labels as l
    on d.deal_type_code = l.deal_type_code
