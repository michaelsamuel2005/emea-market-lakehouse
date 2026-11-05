"""Run dbt against Apache Spark inside this Python process, as strictly as a Databricks SQL warehouse would.

    python scripts/engines/run_on_spark.py build --target spark

This is a test harness for CI, not a way to run the project in production. It uses dbt-spark's `session`
connection method (Spark runs in-process; needs Java 17+ and `pip install pyspark`) with two changes:

  * session mode switches ANSI mode off; Databricks SQL warehouses run with it on (division by zero, an
    impossible cast or an overflow raises an error instead of returning null), so it is switched back on;
  * session mode writes seed values into SQL without escaping quotes and writes a missing value as the
    string 'None'; values are escaped and missing ones become NULL, as the Databricks adapter loads them.

Tables go to ./spark-warehouse and the metastore to ./metastore_db (both gitignored). It is not Databricks:
there is no Unity Catalog, Delta, liquid clustering or metric view here, only the Spark SQL dialect.
"""

import datetime as dt
import sys

import dbt.adapters.spark.session as spark_session

_execute = spark_session.Cursor.execute


def _execute_with_ansi(self, sql, *parameters):
    self.server_side_parameters["spark.sql.ansi.enabled"] = "true"
    return _execute(self, sql, *parameters)


def _escaped_binding(cls, value):
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, spark_session.NUMBERS):
        return repr(float(value))
    if isinstance(value, dt.datetime):
        return f"'{value.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]}'"
    text = str(value).replace("\\", "\\\\").replace("'", "\\'")
    return f"'{text}'"


spark_session.Cursor.execute = _execute_with_ansi
spark_session.SessionConnectionWrapper._fix_binding = classmethod(_escaped_binding)

from dbt.cli.main import dbtRunner  # noqa: E402  (after the patches)

result = dbtRunner().invoke(sys.argv[1:])
sys.exit(0 if result.success else 1)
