# Running the lakehouse on Snowflake (trial account)

The same dbt project builds on Snowflake with the `snowflake` target: the medallion layers become schemas in
one database (`EMEA_MARKET_LAKEHOUSE.BRONZE`, `.SILVER`, `.GOLD`, `.OPS`, `.REFERENCE`, `.ANSWER_KEY`), every
model is a table or view, and two semantic views define the shared KPIs for Cortex Analyst. The first run
takes about an hour.

**Run status.** CI compiles the project with the real dbt-snowflake adapter on every push and runs the
SQL it generates on fakesnow, an open-source Snowflake emulator, then compares every table with the DuckDB
build (`scripts/engines/`). That catches Snowflake dialect mistakes; it is not Snowflake. Warehouses, roles,
key-pair sign-in, column comments and the semantic views are tested by following this runbook. Record each
run (date, result, anything you had to change) in the run status table in the README.

## 1. A trial account

Sign up at [signup.snowflake.com](https://signup.snowflake.com/). The trial runs for 30 days or until its
free credits are used, whichever comes first, and needs no payment details. Choose the **Enterprise**
edition, so nothing below is missing, and a European region on AWS (for example Europe (London)). AI
features such as Cortex Analyst stay disabled on a trial until a credit card is added; every step except the
optional step 8 works without one.

The trial is also where Snowflake's free **Hands-On Essentials** badges are done (Badge 1 is the Data
Warehousing Workshop), so it is worth doing both within the same 30 days.

## 2. Warehouse, role and database

In Snowsight, open a new SQL worksheet and run `snowflake/setup.sql` (as ACCOUNTADMIN, the trial's first
role). It creates an extra-small warehouse that suspends after 60 seconds idle, a resource monitor with a
20-credit monthly quota so a forgotten warehouse cannot use up the trial, the `TRANSFORMER` role that dbt
builds with, the `EMEA_MARKET_LAKEHOUSE` database, and gives your user the role.

## 3. Key-pair sign-in for dbt

Snowflake is retiring single-factor password sign-in for people, and a pipeline should not use a password
anyway. Generate a key pair on your computer (macOS, Linux, or Git Bash on Windows):

```bash
mkdir -p ~/.snowflake && cd ~/.snowflake
openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 aes-256-cbc -inform PEM -out rsa_key.p8   # asks for a passphrase
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
openssl rsa -pubin -in rsa_key.pub -outform DER | openssl dgst -sha256 -binary | openssl enc -base64   # fingerprint
```

Register the public key on your user in Snowsight (`select current_user();` shows the name; paste the
contents of `rsa_key.pub` without the `BEGIN` and `END` lines):

```sql
alter user <your user name> set rsa_public_key = 'MIIBIjANBgkqh...';
desc user <your user name>;   -- RSA_PUBLIC_KEY_FP should be SHA256: followed by the fingerprint above
```

The private key never leaves your computer and never goes in the repository (`*.p8` is gitignored).

## 4. Connect

The account identifier is in Snowsight: account menu (bottom left) > your account > **View account details**
> **Account identifier**, in the form `ORGNAME-ACCOUNTNAME`.

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt -r requirements-snowflake.txt
export SNOWFLAKE_ACCOUNT=ORGNAME-ACCOUNTNAME
export SNOWFLAKE_USER=<your user name>
export SNOWFLAKE_PRIVATE_KEY_PATH="$HOME/.snowflake/rsa_key.p8"
export SNOWFLAKE_PRIVATE_KEY_PASSPHRASE='the passphrase you chose'
python scripts/preflight.py snowflake         # checks the variables and the key file, then runs dbt debug
```

`ROLE`, `WAREHOUSE`, `DATABASE` and `SCHEMA` default to what `setup.sql` created (`profiles.yml`). If you
would rather use your trial password for a first look, set `SNOWFLAKE_PASSWORD` and use
`--target snowflake_password` instead; trial accounts are exempt from Snowflake's MFA requirement.

## 5. Build

```bash
dbt build --target snowflake
```

31 seeds load (inserted in batches, a minute or two on an extra-small warehouse), then 23 views and 26
tables are built, 340 data tests and 8 unit tests run, and the run's timings go to `OPS.DBT_RUN_RESULTS`.
dbt-snowflake creates tables as transient (no Fail-safe storage), which suits rebuildable models. The
result should match DuckDB: everything passes, with the same two warnings (`assert_vacancy_reconciles`,
1 row; `assert_take_up_reconciles`, 14 rows), which are the planted reconciliation cases.

A full build uses well under one credit. Then look at it: **Data** > **Databases** >
`EMEA_MARKET_LAKEHOUSE` > `GOLD`. Table and column comments come from `models/gold/_gold.yml`.

## 6. The semantic layer: semantic views

In a worksheet (role `TRANSFORMER`), run `snowflake/semantic_views/sv_market_kpis.sql` and then
`snowflake/semantic_views/sv_leasing_deals.sql`. They define the same measures as the Databricks metric
views, over the same gold star schema: relationships between the fact and its dimensions, dimensions with
synonyms, and metrics built from sums (vacancy rate is sum of vacant over sum of stock). Query one:

```sql
select *
from semantic_view(
    emea_market_lakehouse.gold.sv_market_kpis
    dimensions markets.market, quarters.quarter
    metrics market_quarter.stock_weighted_vacancy_rate, market_quarter.total_take_up_m2,
            market_quarter.top_prime_rent_eur_m2_yr, market_quarter.keenest_prime_yield
    where quarters.quarter = '2026Q3'
)
order by market;
```

Semantic views are the newest part of this project. If Snowflake rejects a clause, the error names it; fix
it against the [CREATE SEMANTIC VIEW](https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view)
reference and record the change.

## 7. Queries for a dashboard

`snowflake/queries.sql` has the same tiles as the Databricks dashboard (latest-quarter KPIs, prime rent
over time, take-up by quarter, reported against register vacancy, quarantine summary). Run them in a
worksheet and use **Chart** on each result, or add them to a Snowsight dashboard.

## 8. Optional: questions in English (needs a card on the trial)

With AI features enabled, Cortex Analyst answers questions over `SV_MARKET_KPIS` and `SV_LEASING_DEALS`
using their synonyms and comments; the sample questions in `databricks/genie/sample_questions.md` work as
the benchmark here too.

## 9. Costs and clean-up

The warehouse suspends itself after 60 seconds and the resource monitor suspends it at 20 credits a month.
When you are done, the last lines of `setup.sql` drop everything it created.

## Troubleshooting

| What you see | What to do |
| --- | --- |
| `JWT token is invalid` | The public key on the user does not match the private key: compare `RSA_PUBLIC_KEY_FP` with the openssl fingerprint, and check the account identifier is `ORGNAME-ACCOUNTNAME`. |
| `Incorrect username or password was specified` with the key | `SNOWFLAKE_USER` is the login name (`select current_user();`), not your email address. |
| `Object does not exist or not authorized` | The role or warehouse is missing: rerun `setup.sql`, or check `SNOWFLAKE_ROLE` and `SNOWFLAKE_WAREHOUSE`. |
| `invalid identifier` on a seed column | Seed columns are created unquoted (`+quote_columns: false` in `dbt_project.yml`) so Snowflake stores them in upper case and the models' lower-case names match. Keep that setting. |
| The warehouse is suspended mid-build | The resource monitor reached its quota. Raise `credit_quota` in `setup.sql` if that was intended. |
