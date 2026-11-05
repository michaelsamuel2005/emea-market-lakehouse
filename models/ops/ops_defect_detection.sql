-- How well the silver checks catch the problems planted in the synthetic raw files.
-- The generator logs every defect it injects (seeds/answer_key/answer_key_defects.csv); this model
-- scores the pipeline against that log: for each defect type, how many were injected, how many
-- were quarantined or repaired, and the detection rate. Honest numbers belong in the README.

with injected as (

    select
        market_id,
        dataset,
        row_key,
        defect_type
    from {{ ref('answer_key_defects') }}
    where dataset = 'deals'

),

deals as (

    select
        market_id,
        deal_ref,
        quarantine_reason,
        rent_suppressed_reason,
        submarket_derived_from_building
    from {{ ref('int_deals') }}

),

scored as (

    select
        i.defect_type,
        i.market_id,
        i.row_key,
        -- a duplicate pair shares the original's reference: the copy is the row that must be caught
        max(case when d.quarantine_reason is not null then 1 else 0 end) as was_quarantined,
        max(case when d.submarket_derived_from_building or d.rent_suppressed_reason is not null then 1 else 0 end) as was_repaired
    from injected as i
    left join deals as d
        on i.market_id = d.market_id
        and i.row_key = d.deal_ref
    group by i.defect_type, i.market_id, i.row_key

)

select
    defect_type,
    case
        when defect_type in ('exact_duplicate', 'near_duplicate') then 'quarantine as duplicate_submission'
        when defect_type = 'future_date' then 'quarantine as deal_dated_after_submission'
        when defect_type = 'wrong_rent_unit' then 'keep the deal, suppress the rent (rent_out_of_range)'
        when defect_type = 'wrong_area_unit' then 'quarantine as area_out_of_range or area_exceeds_building'
        when defect_type = 'missing_submarket' then 'repair from the building register'
        when defect_type = 'confidential_rent' then 'allowed: rent left null'
    end as expected_handling,
    count(*) as injected_rows,
    sum(was_quarantined) as quarantined_rows,
    sum(was_repaired) as repaired_rows,
    case
        when defect_type in ('missing_submarket', 'wrong_rent_unit') then round(100.0 * sum(was_repaired) / count(*), 1)
        when defect_type = 'confidential_rent' then round(100.0 * (count(*) - sum(was_quarantined)) / count(*), 1)
        else round(100.0 * sum(was_quarantined) / count(*), 1)
    end as handled_correctly_pct
from scored
group by defect_type
