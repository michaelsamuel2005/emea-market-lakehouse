-- One-off setup for running the lakehouse on Snowflake. Run it in a Snowsight SQL worksheet as ACCOUNTADMIN
-- (a new trial account's first user has that role). It creates:
--   * a credit quota, so a warehouse left running cannot use up the account's credits
--   * TRANSFORM_WH: an extra-small warehouse that suspends itself after 60 seconds idle
--   * TRANSFORMER: the role dbt builds with; it will own the BRONZE / SILVER / GOLD / OPS schemas dbt creates
--   * EMEA_MARKET_LAKEHOUSE: the database (dbt creates the schemas inside it)
-- and gives your own user the role. Safe to run twice.

use role accountadmin;

create resource monitor if not exists emea_lakehouse_monitor
    with credit_quota = 20
    frequency = monthly
    start_timestamp = immediately
    triggers on 75 percent do notify
             on 100 percent do suspend;

create warehouse if not exists transform_wh
    warehouse_size = xsmall
    auto_suspend = 60
    auto_resume = true
    initially_suspended = true
    comment = 'dbt builds and queries for the EMEA office market lakehouse';

alter warehouse transform_wh set resource_monitor = emea_lakehouse_monitor;

create role if not exists transformer
    comment = 'Builds and owns the EMEA market lakehouse schemas (dbt)';
grant role transformer to role sysadmin;    -- keep it under SYSADMIN in the role hierarchy

create database if not exists emea_market_lakehouse
    comment = 'EMEA office market lakehouse: medallion layers built by dbt (synthetic data)';

grant usage on warehouse transform_wh to role transformer;
grant usage, create schema on database emea_market_lakehouse to role transformer;

-- Your user: the role, and defaults so a new worksheet starts in the right place. (Built as text and run
-- with EXECUTE IMMEDIATE so the script works for whichever user you signed up as.)
set grant_role_sql = 'grant role transformer to user "' || current_user() || '"';
execute immediate $grant_role_sql;
set user_defaults_sql = 'alter user "' || current_user() || '" set default_role = transformer default_warehouse = transform_wh';
execute immediate $user_defaults_sql;

-- Key-pair authentication for dbt (snowflake/RUNBOOK.md, step 3). select current_user(); shows your user
-- name. Paste the contents of rsa_key.pub without the -----BEGIN PUBLIC KEY----- and -----END PUBLIC KEY-----
-- lines, then run:
--   alter user <your user name> set rsa_public_key = 'MIIBIjANBgkqh...';
--   desc user <your user name>;    -- RSA_PUBLIC_KEY_FP must match the fingerprint openssl printed

-- Clean-up when you are finished:
--   drop database emea_market_lakehouse; drop warehouse transform_wh; drop role transformer;
--   drop resource monitor emea_lakehouse_monitor;
