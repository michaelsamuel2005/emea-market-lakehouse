{# Column descriptions used in more than one gold model. Each is written once here and referenced from
   models/gold/_gold.yml with doc('...'), so the same column means the same thing in every table, in
   the dbt docs site, and in the warehouse comments that persist_docs writes for Genie and Cortex Analyst. #}

{% docs col_market_id %}
Market code: LON (London), PAR (Paris), AMS (Amsterdam), FRA (Frankfurt), WAW (Warsaw). Joins to dim_market.
{% enddocs %}

{% docs col_market_name %}
Market name, e.g. London.
{% enddocs %}

{% docs col_submarket_id %}
Shared submarket code, unique within a market (e.g. CITY in London, QCA in Paris).
{% enddocs %}

{% docs col_submarket_key %}
Surrogate key of market_id and submarket_id. Joins to dim_submarket.
{% enddocs %}

{% docs col_quarter_id %}
Quarter as yyyyQn, e.g. 2026Q3. Joins to dim_quarter.
{% enddocs %}

{% docs col_period_end_date %}
Last day of the quarter: 31 March, 30 June, 30 September or 31 December.
{% enddocs %}

{% docs col_building_key %}
Surrogate key of market_id and the market's own building id. The same for every version of a building. Joins to dim_building.
{% enddocs %}

{% docs col_building_version_key %}
Surrogate key of one version of a building (market, local building id, version number). Joins to dim_building_history.
{% enddocs %}

{% docs col_building_id_local %}
The market's own building id, e.g. LON-B0001.
{% enddocs %}

{% docs col_building_name %}
Building name as the market's register gives it.
{% enddocs %}

{% docs col_grade_code %}
Building grade on the shared scale: A, B or C. Null where the market left the grade blank.
{% enddocs %}

{% docs col_grade_name %}
Display name of grade_code, e.g. Grade A.
{% enddocs %}

{% docs col_grade_local %}
Grade as the market wrote it, e.g. Klasse A (Frankfurt) or Prime (Paris), before mapping to grade_code.
{% enddocs %}

{% docs col_total_area_m2 %}
Lettable area of the building in square metres (London's sq ft converted with 10.7639 sq ft per m2).
{% enddocs %}

{% docs col_year_built %}
Year the building was completed, as reported.
{% enddocs %}

{% docs col_year_refurbished %}
Year of the last major refurbishment, as reported; null if never refurbished.
{% enddocs %}

{% docs col_last_updated %}
Date the market last updated the building's register entry. A later row for the same building starts a new version.
{% enddocs %}

{% docs col_tenant_key %}
Surrogate key of the normalised tenant name (lower case, trimmed, trailing "ltd" removed). Joins to dim_tenant.
{% enddocs %}

{% docs col_sector_code %}
Occupier sector on the shared code list (e.g. FIN, TMT). Joins to dim_sector.
{% enddocs %}

{% docs col_sector_name %}
Display name of sector_code.
{% enddocs %}

{% docs col_deal_type_code %}
Deal type on the shared code list: NEW (new lease), REN (renewal), EXP (expansion), SUB (sublease), PRE (pre-let). Joins to dim_deal_type.
{% enddocs %}

{% docs col_stock_m2 %}
Total office stock at the quarter end, in square metres, as reported by the market (converted from sq ft for London).
{% enddocs %}

{% docs col_vacant_m2 %}
Vacant space at the quarter end, in square metres. Frankfurt reports a rate instead, so its vacant_m2 is stock_m2 x the reported rate.
{% enddocs %}

{% docs col_vacancy_rate %}
vacant_m2 / stock_m2, as a fraction (0.10 = 10%). At market level it is weighted by stock (sum of vacant over sum of stock), never an average of submarket rates.
{% enddocs %}

{% docs col_occupied_m2 %}
stock_m2 - vacant_m2: space let or in use at the quarter end, square metres.
{% enddocs %}

{% docs col_take_up_m2 %}
Floorspace let during the quarter, in square metres, as reported by the market.
{% enddocs %}

{% docs col_prime_rent_eur_m2_yr %}
Prime (top achievable) rent in EUR per square metre per year, converted once in silver from the market's own currency and basis with that quarter's FX rate. At market level, the highest submarket.
{% enddocs %}

{% docs col_prime_yield %}
Prime yield as a fraction (0.04 = 4%). At market level, the lowest (keenest) submarket.
{% enddocs %}

{% docs col_completions_m2 %}
New office space completed during the quarter, square metres.
{% enddocs %}

{% docs col_under_construction_m2 %}
Office space under construction at the quarter end, square metres.
{% enddocs %}

{% docs col_register_vacancy_rate %}
Bottom-up vacancy from the tracked building register: register_available_m2 / register_tracked_area_m2. Reconciled against the reported vacancy_rate in ops_dq_reconciliation_vacancy.
{% enddocs %}

{% docs col_deal_count %}
Number of leasing deals that passed every silver check.
{% enddocs %}

{% docs col_deals_area_m2 %}
Total area of those deals, square metres.
{% enddocs %}

{% docs col_avg_deal_size_m2 %}
deals_area_m2 / deal_count, square metres; null when there were no deals.
{% enddocs %}

{% docs col_largest_deal_m2 %}
Area of the largest single deal, square metres.
{% enddocs %}

{% docs col_market_kpi_key %}
Surrogate key of market_id and quarter_id.
{% enddocs %}

{% docs col_submitted_at %}
When the market's portal received the submission the row came from.
{% enddocs %}
