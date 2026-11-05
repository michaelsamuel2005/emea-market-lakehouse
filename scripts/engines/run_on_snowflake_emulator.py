"""Run dbt with the real dbt-snowflake adapter, its SQL executed by fakesnow (a local Snowflake emulator).

    python scripts/engines/run_on_snowflake_emulator.py build --target snowflake_emulator --exclude "test_type:unit"

A test harness for CI. dbt-snowflake generates exactly the SQL it would send to Snowflake (uppercase
identifiers, transient tables, the snowflake__ versions of the macros in macros/cross_db.sql); fakesnow
parses that SQL as Snowflake SQL and runs it on DuckDB. It catches dialect mistakes (a function Snowflake
does not have, HAVING without GROUP BY) without a Snowflake account. It is an emulator, not Snowflake:
snowflake/RUNBOOK.md runs the project on a real account. Two things the emulator cannot do are left out:
table and column comments (persist_docs is off for this target in dbt_project.yml) and unit tests, which
dbt-snowflake runs through temporary tables (exclude them; they run on DuckDB and Spark).

Needs: pip install dbt-snowflake==1.12.5 "snowflake-connector-python==4.8.1" fakesnow==0.12.1
The emulated database is written to target/snowflake_emulator/.
"""

import sys
from pathlib import Path

import fakesnow

DB_PATH = Path("target/snowflake_emulator")
DB_PATH.mkdir(parents=True, exist_ok=True)

with fakesnow.patch(db_path=str(DB_PATH)):
    from dbt.cli.main import dbtRunner

    result = dbtRunner().invoke(sys.argv[1:])

sys.exit(0 if result.success else 1)
