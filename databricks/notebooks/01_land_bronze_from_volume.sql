-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Land the market files into bronze from a Volume
-- MAGIC
-- MAGIC Production-style alternative to `dbt seed`: the market files are dropped in a Unity Catalog Volume
-- MAGIC and `COPY INTO` lands them as Delta tables, every column a string, with the source file name and
-- MAGIC the load time recorded. `COPY INTO` is idempotent: rerunning it loads only new files.
-- MAGIC
-- MAGIC Before running: **Catalog** > `workspace` > `bronze` > **Create** > **Volume** named `landing`,
-- MAGIC then upload the CSVs from `seeds/bronze/` into it (drag and drop in the Catalog UI).
-- MAGIC The table names match the dbt sources, so the rest of the project is unchanged.

-- COMMAND ----------

create schema if not exists workspace.bronze;
create volume if not exists workspace.bronze.landing;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC One block per market and dataset. `inferSchema` is left off so every column lands as a string,
-- MAGIC exactly as sent; parsing happens in silver. `mergeSchema` lets a market add a column later
-- MAGIC without the load failing.

-- COMMAND ----------

create table if not exists workspace.bronze.lon_market_stats;
copy into workspace.bronze.lon_market_stats
from (select *, _metadata.file_name as _source_file, current_timestamp() as _loaded_at
      from '/Volumes/workspace/bronze/landing/')
fileformat = csv
pattern = 'lon_market_stats.csv'
format_options ('header' = 'true', 'mergeSchema' = 'true')
copy_options ('mergeSchema' = 'true');

-- COMMAND ----------

create table if not exists workspace.bronze.lon_deals;
copy into workspace.bronze.lon_deals
from (select *, _metadata.file_name as _source_file, current_timestamp() as _loaded_at
      from '/Volumes/workspace/bronze/landing/')
fileformat = csv
pattern = 'lon_deals.csv'
format_options ('header' = 'true', 'mergeSchema' = 'true')
copy_options ('mergeSchema' = 'true');

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Repeat the block for `lon_buildings`, `lon_availability` and the other four markets (twenty tables in
-- MAGIC all), or generate the statements:
-- MAGIC
-- MAGIC ```python
-- MAGIC markets = ["lon", "par", "ams", "fra", "waw"]
-- MAGIC datasets = ["market_stats", "deals", "buildings", "availability"]
-- MAGIC for m in markets:
-- MAGIC     for d in datasets:
-- MAGIC         t = f"{m}_{d}"
-- MAGIC         spark.sql(f"create table if not exists workspace.bronze.{t}")
-- MAGIC         spark.sql(f"""
-- MAGIC           copy into workspace.bronze.{t}
-- MAGIC           from (select *, _metadata.file_name as _source_file, current_timestamp() as _loaded_at
-- MAGIC                 from '/Volumes/workspace/bronze/landing/')
-- MAGIC           fileformat = csv
-- MAGIC           pattern = '{t}.csv'
-- MAGIC           format_options ('header' = 'true', 'mergeSchema' = 'true')
-- MAGIC           copy_options ('mergeSchema' = 'true')
-- MAGIC         """)
-- MAGIC ```

-- COMMAND ----------

select 'lon_market_stats' as table_name, count(*) as rows, max(_loaded_at) as loaded_at from workspace.bronze.lon_market_stats
union all
select 'lon_deals', count(*), max(_loaded_at) from workspace.bronze.lon_deals;
