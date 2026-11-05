{#- Generic tests used throughout the project. Written in portable SQL; no package needed. -#}

{#- Every non-null value of the column lies within [min_value, max_value]. -#}
{% test expect_between(model, column_name, min_value, max_value, row_condition=none) %}
select {{ column_name }} as failing_value
from {{ model }}
where {{ column_name }} is not null
  and ({{ column_name }} < {{ min_value }} or {{ column_name }} > {{ max_value }})
  {%- if row_condition %}
  and ({{ row_condition }})
  {%- endif %}
{% endtest %}

{#- Every non-null value of the column is greater than zero. -#}
{% test is_positive(model, column_name) %}
select {{ column_name }} as failing_value
from {{ model }}
where {{ column_name }} is not null
  and {{ column_name }} <= 0
{% endtest %}

{#- The combination of columns is unique (a composite primary key). -#}
{% test unique_combination(model, combination_of_columns) %}
select
    {{ combination_of_columns | join(', ') }},
    count(*) as duplicate_rows
from {{ model }}
group by {{ combination_of_columns | join(', ') }}
having count(*) > 1
{% endtest %}

{#- The column's distinct count equals an expected number (e.g. five markets). A subquery rather than
    HAVING without GROUP BY, which Snowflake does not accept. -#}
{% test distinct_count_equals(model, column_name, expected) %}
select actual_distinct
from (
    select count(distinct {{ column_name }}) as actual_distinct
    from {{ model }}
) as counted
where actual_distinct <> {{ expected }}
{% endtest %}
