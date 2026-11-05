# From a request to a data structure: design scenarios

How the model answers the kind of request a Research or BI team sends. The data is synthetic, so these
are not stories from a real team: each is a request the design was built to handle, the questions it
raises, and where in the model the answer lives. The same reasoning applies to new requests.

## 1. "We need one vacancy chart across all markets"

Questions to ask first: is vacancy an area or a rate in each market? (Frankfurt reports a rate.) What is
the denominator? (Stock, as reported, in m².) Is it weighted when aggregated? (Yes, by stock.)

In the model: `vacant_m2` is derived as stock × rate where a market reports a rate (`stage_market_stats`),
`vacancy_rate` is computed once in `int_market_stats`, and the market-level figure in `mart_market_kpis`
is `sum(vacant) / sum(stock)`, never an average of rates. The definition is a row in
`ref_metric_definitions`, and a unit test (`market_vacancy_is_stock_weighted_not_an_average_of_rates`)
fails if the formula changes.

## 2. "The prime rent for La Défense looks wrong"

Questions: which quarter, and which submission? A market can send a quarter twice, with the second
copy correcting the first.

In the model: `int_market_stats` keeps the latest submission per market, submarket and quarter
(`submission_rank = 1`) and carries `submission_count` into `fct_market_quarter`, so a dashboard shows
the corrected figure and a reviewer can see a correction happened. The generator plants two resubmitted
quarters each in London and Paris, and a test checks that the later one wins.

## 3. "Can we compare prime rents? London is per sq ft, Frankfurt is per month"

Questions: what is the common unit? (EUR per m² per year.) Which FX rate? (The quarter-end rate from
one reference table, not whatever each market used.)

In the model: `rent_to_eur_m2_year_by_column` converts once in silver using the market's `rent_unit`
and `ref_fx_rates`; the local figure stays beside it (`prime_rent_local`, `prime_rent_local_currency`,
`prime_rent_local_unit`) so the market can recognise its own number.

## 4. "Why is take-up in Warsaw higher than the deals we logged?"

Questions: is the deal log complete? Are some deals being held back by a check? Are the headline
figures built from the log at all?

In the model: `ops_dq_reconciliation_take_up` compares reported take-up with the logged deals per
submarket and quarter, with `quarantined_deals_m2` showing how much of the gap the checks explain, and
flags gaps over 10% as a warning for the market to answer. The same reconciliation exposes the
wrong-unit areas the row-level checks miss (README, "the 41%").

## 5. "The BI team wants a tenant filter that works across markets"

Questions: do markets spell tenants the same way? (No: "Helix Technologies", "HELIX TECHNOLOGIES",
"Helix Technologies Ltd".) Which sector does a tenant belong to when markets code it differently?

In the model: `dim_tenant` keys tenants on a normalised name (case, spaces and a trailing "Ltd"
ignored), takes the most common spelling as the display name and the most common sector as the
sector, and reports `markets_active`. The raw name stays on `int_deals.tenant_name_raw`.

## 6. "How much Grade A space was let last year?"

Questions: the grade when the lease was signed, or the grade today? A building refurbished in
September 2026 is Grade A now but was Grade B for every deal signed before then.

In the model: buildings are a type 2 slowly changing dimension. `int_building_versions` keeps every
version a market sent, with `valid_from` and `valid_to`; `fct_leasing_deal.building_version_key`
points at the version in force on the deal date; `dim_building_history` exposes the grade at that time
and `dim_building` the grade today. In this data 207 deals were signed in buildings the market later
re-sent after a refurbishment; 128 of them were in Grade B or C buildings at the time, and would be
counted as Grade A deals without the history.

## 7. "Can the AI assistant answer 'how is the Paris market doing'?"

Questions: what does "doing" mean (which KPIs)? Which units should the answer quote? What must it decline?

In the model: `mart_ai_market_facts` writes one sentence per market-quarter from the KPI mart with
units in the text; the Databricks metric views and the Snowflake semantic views declare synonyms
("headline rent", "lettings"); `databricks/genie/instructions.md` gives the definitions and what to
decline (the data is synthetic; GBP per sq ft is not in gold).

## The pattern

1. Ask what the number means to the person asking, in their words, before touching a model.
2. Find the one place the logic should live (silver for conversions and mappings, the KPI mart for definitions).
3. Keep the original value beside the standardised one, so the market recognises its data.
4. Write the definition down (`ref_metric_definitions`, the data contract) and test the invariant.
