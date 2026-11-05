{#- ------------------------------------------------------------------------------------------
    union_markets(dataset): "select * from stg_lon__<dataset> union all select * from stg_par__<dataset> ..."
    for every market configured in vars.markets. Used by the four int_<dataset>_unioned views. Because
    every staging model produces the same columns in the same order, a market is onboarded into the
    unions by being added to the vars block and getting its four staging models. Nothing in
    silver.int_* (and no unit test) needs editing.
   ------------------------------------------------------------------------------------------ -#}
{% macro union_markets(dataset) -%}
{%- for market_id in var('markets') %}
select * from {{ ref('stg_' ~ market_id | lower ~ '__' ~ dataset) }}
{%- if not loop.last %}
union all
{%- endif %}
{%- endfor %}
{%- endmacro %}
