-- Vacancy rate by market and quarter, with the register's bottom-up rate alongside for reconciliation.
select
    k.market_id,
    k.quarter_id,
    round(k.vacancy_rate * 100, 1) as vacancy_rate_pct,
    round(k.register_vacancy_rate * 100, 1) as register_vacancy_rate_pct,
    round(k.vacancy_rate_change_qoq * 100, 2) as change_qoq_pp,
    round(k.net_absorption_m2) as net_absorption_m2
from {{ ref('mart_market_kpis') }} as k
order by k.market_id, k.quarter_id
