"""Check that another engine built exactly the same tables as DuckDB.

    python scripts/engines/compare_with_duckdb.py spark                # after run_on_spark.py build
    python scripts/engines/compare_with_duckdb.py snowflake_emulator   # after run_on_snowflake_emulator.py build

Compares every silver, gold and ops table row for row with the DuckDB build in target/ (run `dbt build`
first). Doubles are compared to six decimal places, because engines add up floating-point numbers in a
different order. Surrogate-key columns (*_key) are left out: they are md5 hashes of text, and engines
print timestamps as text differently (Snowflake adds milliseconds), so the hashes differ while the rows
they identify are the same. Exits 1 if any table differs.
"""

import math
import sys
from decimal import Decimal
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[2]
DUCKDB_PATH = ROOT / "target" / "emea_market_lakehouse.duckdb"
SKIP = {"dbt_run_results", "ops_run_history", "ops_runtime_alerts"}   # run history differs by design
TEST_TABLE_PREFIXES = ("assert_", "not_null_", "unique_", "accepted_values_", "relationships_",
                       "expect_between_", "is_positive_", "distinct_count_")


def normalise(value):
    if isinstance(value, (float, Decimal)):
        value = float(value)
        return "nan" if math.isnan(value) else round(value, 6)
    if hasattr(value, "isoformat"):
        return value.isoformat()[:19].replace("T", " ")
    return value


def rows_of(fetch):
    return sorted((tuple(normalise(v) for v in row) for row in fetch), key=repr)


def main(engine: str) -> int:
    duck = duckdb.connect(str(DUCKDB_PATH), read_only=True)
    tables = [(s, t) for s, t in duck.execute("""
        select table_schema, table_name from information_schema.tables
        where table_schema in ('silver', 'gold', 'ops') order by 1, 2""").fetchall()
        if t not in SKIP and not t.startswith(TEST_TABLE_PREFIXES)]

    if engine == "spark":
        from pyspark.sql import SparkSession

        spark = (SparkSession.builder.master("local[2]").enableHiveSupport()
                 .config("spark.ui.enabled", "false").getOrCreate())
        spark.sparkContext.setLogLevel("ERROR")

        def other(schema, table, columns):
            return spark.sql(f"select {', '.join('`' + c + '`' for c in columns)} from {schema}.{table}").collect()
    elif engine == "snowflake_emulator":
        emulated = duckdb.connect(str(ROOT / "target" / "snowflake_emulator" / "EMEA_MARKET_LAKEHOUSE.db"), read_only=True)

        def other(schema, table, columns):
            cols = ", ".join('"' + c.upper() + '"' for c in columns)
            return emulated.execute(f"select {cols} from EMEA_MARKET_LAKEHOUSE.{schema.upper()}.{table.upper()}").fetchall()
    else:
        sys.exit("engine must be spark or snowflake_emulator")

    differing = 0
    for schema, table in tables:
        columns = [c for (c,) in duck.execute(
            "select column_name from information_schema.columns where table_schema = ? and table_name = ? "
            "order by ordinal_position", [schema, table]).fetchall() if not c.endswith("_key")]
        expected = rows_of(duck.execute(f"select {', '.join(chr(34) + c + chr(34) for c in columns)} from {schema}.{table}").fetchall())
        actual = rows_of(other(schema, table, columns))
        if expected == actual:
            print(f"same   {schema}.{table} ({len(expected)} rows)")
            continue
        differing += 1
        print(f"DIFF   {schema}.{table}: duckdb {len(expected)} rows, {engine} {len(actual)} rows")
        for i, column in enumerate(columns):
            if sorted(map(repr, (r[i] for r in expected))) != sorted(map(repr, (r[i] for r in actual))):
                print(f"         column {column} differs")
    print(f"{len(tables) - differing} of {len(tables)} tables identical to the DuckDB build")
    return 1 if differing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else ""))
