# Checking the project on Spark and Snowflake without a workspace

The project is written once and built on three engines. DuckDB is where it is developed and tested. A
Databricks workspace and a Snowflake account are where it is meant to run, but CI cannot keep either open
for free, so CI checks the two dialects with stand-ins on every push:

| Script | What runs the SQL | What it proves | What it cannot prove |
| --- | --- | --- | --- |
| `run_on_spark.py` | Apache Spark 4.0 inside the Python process (dbt-spark, `session` method), ANSI mode on | Every model, seed and test runs in the Spark SQL dialect, under the same strict ANSI rules as a Databricks SQL warehouse (division by zero, bad casts and overflows raise errors) | Unity Catalog, Delta tables, liquid clustering, metric views, Genie: see `databricks/RUNBOOK.md` |
| `run_on_snowflake_emulator.py` | fakesnow, an open-source Snowflake emulator on DuckDB, driven by the real dbt-snowflake adapter | dbt-snowflake generates its real SQL (upper-case identifiers, transient tables, the `snowflake__` macros) and that SQL parses and runs as Snowflake SQL | Warehouses, roles, key-pair sign-in, column comments, semantic views: see `snowflake/RUNBOOK.md` |
| `dbt compile --no-populate-cache` with the `databricks_token` and `snowflake_password` targets | nothing: the real dbt-databricks and dbt-snowflake adapters render every model offline, with placeholder credentials | Every model, test and macro compiles for both adapters (their own `databricks__` / `snowflake__` macros, configs such as `liquid_clustered_by`) | That the SQL runs: the two rows above do that |
| `compare_with_duckdb.py` | reads both results | Every silver, gold and ops table is row-for-row identical to the DuckDB build (doubles to six decimals; surrogate keys left out, see the script) | |

```bash
pip install -r requirements.txt -r requirements-engines.txt     # Spark also needs Java 17 or later
dbt build                                                        # the DuckDB build the others are compared with
python scripts/engines/run_on_spark.py build --target spark
python scripts/engines/compare_with_duckdb.py spark
python scripts/engines/run_on_snowflake_emulator.py build --target snowflake_emulator --exclude "test_type:unit"
python scripts/engines/compare_with_duckdb.py snowflake_emulator
```

The Spark build takes about three minutes (Spark starts once per statement batch); the emulator about one.

## Why the runners patch dbt

Both are test harnesses, so they are allowed to bend the tools to make the check stricter, and each says so
in its docstring:

- dbt-spark's session mode switches ANSI mode off to stay compatible with Spark 3. A Databricks SQL
  warehouse runs with it on, which is stricter, so `run_on_spark.py` switches it back on.
- dbt-spark's session mode writes seed values into SQL without escaping quotes ("avenue d'Italie" breaks it)
  and writes a missing value as the text 'None'. The runner escapes values and writes NULL, which is what
  the Databricks adapter does.
- fakesnow cannot store table and column comments, so `dbt_project.yml` skips `persist_docs` for the
  `snowflake_emulator` target only; every real target writes them.
- fakesnow cannot create the temporary tables dbt-snowflake uses to run unit tests, so the emulator build
  excludes them (`--exclude "test_type:unit"`); the unit tests run on DuckDB and on Spark.

## Dialect differences handled

Found while porting the project to Spark and Snowflake, from the engines' SQL references; the checks above
confirm each fix, and the last one was found by the table comparison itself.

- `HAVING` without `GROUP BY` in the `distinct_count_equals` test: DuckDB and Spark accept it, but
  Snowflake's reference only describes `HAVING` after `GROUP BY`, so it is now a subquery every engine accepts.
- `regexp_extract` and `make_date` do not exist on Snowflake. Both now go through `macros/cross_db.sql`
  (`regex_group` dispatches to `regexp_substr(..., 'e', group)`; dates are built with `try_cast`, which
  also returns null for an impossible date such as 31 February instead of failing under ANSI mode).
- `regexp_extract` returns `''` on DuckDB and Spark when nothing matches, while Snowflake returns null;
  `regex_group` makes all three return null.
- Division by zero raises an error under ANSI mode: every division goes through `safe_divide`.
- `concat` skips nulls on DuckDB but returns null on Spark and Snowflake, and a double prints as `10.0` on
  DuckDB and Spark but `10` on Snowflake: the AI summary sentence uses `||` with `coalesce` and fixed-scale
  decimals, so it reads the same on every engine.
- Found by the comparison: a count summed on DuckDB is a 128-bit integer and came back from the emulator
  as a double, so the summary sentence said "107.0 leasing deals". Counts are now cast to `bigint`.
