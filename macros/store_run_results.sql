{#- ------------------------------------------------------------------------------------------
    Basic performance monitoring. Runs as an on-run-end hook after every dbt command and appends
    one row per model, seed, snapshot or test to ops.dbt_run_results: status, execution time,
    rows affected and any failure count. ops.ops_run_history and ops.ops_runtime_alerts read it,
    so a model that suddenly takes much longer than usual, or a test that starts failing, shows up
    in the same place as the business data.
   ------------------------------------------------------------------------------------------ -#}
{% macro run_results_relation() -%}
    {{ return(api.Relation.create(database=target.database, schema='ops', identifier='dbt_run_results')) }}
{%- endmacro %}

{% macro ensure_run_results_table() -%}
    {%- if execute -%}
        {%- set rel = run_results_relation() -%}
        {%- do adapter.create_schema(rel) -%}
        {%- set ddl -%}
            create table if not exists {{ rel }} (
                invocation_id {{ dbt.type_string() }},
                run_started_at timestamp,
                node_id {{ dbt.type_string() }},
                resource_type {{ dbt.type_string() }},
                node_name {{ dbt.type_string() }},
                schema_name {{ dbt.type_string() }},
                status {{ dbt.type_string() }},
                execution_time_seconds double,
                rows_affected bigint,
                failures bigint,
                message {{ dbt.type_string() }},
                recorded_at timestamp
            )
        {%- endset -%}
        {%- do run_query(ddl) -%}
    {%- endif -%}
{%- endmacro %}

{% macro store_run_results(results) -%}
    {%- if execute and results | length > 0 -%}
        {%- do ensure_run_results_table() -%}
        {%- set rel = run_results_relation() -%}
        {%- set rows = [] -%}
        {%- set recorded_at = modules.datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S') -%}
        {%- for r in results -%}
            {%- set node = r.node -%}
            {%- set rows_affected = r.adapter_response.get('rows_affected') if r.adapter_response else none -%}
            {%- set msg = (r.message or '') | string | truncate(500, true, '') | replace("\\", "/") | replace("'", "''") | replace("\n", " ") -%}
            {%- do rows.append(
                "('" ~ invocation_id ~ "', cast('" ~ run_started_at.strftime('%Y-%m-%d %H:%M:%S') ~ "' as timestamp), '"
                ~ node.unique_id ~ "', '" ~ node.resource_type ~ "', '" ~ node.name ~ "', '" ~ (node.schema or '') ~ "', '"
                ~ r.status ~ "', " ~ (r.execution_time | round(3)) ~ ", "
                ~ (rows_affected if rows_affected is not none else 'null') ~ ", "
                ~ (r.failures if r.failures is not none else 'null') ~ ", '" ~ msg ~ "', cast('" ~ recorded_at ~ "' as timestamp))"
            ) -%}
        {%- endfor -%}
        {%- set insert_sql -%}
            insert into {{ rel }}
            (invocation_id, run_started_at, node_id, resource_type, node_name, schema_name, status,
             execution_time_seconds, rows_affected, failures, message, recorded_at)
            values {{ rows | join(',\n') }}
        {%- endset -%}
        {%- do run_query(insert_sql) -%}
        {%- do log("store_run_results: recorded " ~ rows | length ~ " results in " ~ rel, info=true) -%}
    {%- endif -%}
{%- endmacro %}
