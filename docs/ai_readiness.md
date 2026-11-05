# AI-ready foundations

What "preparing clean, well-structured datasets for AI and agentic applications" means in this
project, concretely, and why each choice helps a language model or an agent use the data correctly.

## 1. One meaning per column, and the unit in the name

An agent that sees `prime_rent_eur_m2_yr` does not have to guess the unit; one that sees `rent` does.
Gold columns carry their unit (`_m2`, `_eur_m2_yr`, `_rate`), and `mart_ai_market_facts` goes further
with spelled-out suffixes (`vacancy_rate_pct`, `prime_rent_eur_per_sqm_per_year`) and rounded values,
because models read column names as text.

## 2. Definitions as data

`gold.dim_metric_definition` holds every KPI's definition, unit, formula and grain. The Genie
instructions (`databricks/genie/instructions.md`) are written from it, so the model aggregates the
right way: sum take-up, never average prime rents, treat yields as fractions. When a definition
changes, the table, the instructions and the metric view change in the same pull request.

## 3. A semantic layer the platform understands

The Unity Catalog metric views (`databricks/metric_views/`) declare measures with `comment`,
`display_name`, `format` and `synonyms`; the Snowflake semantic views (`snowflake/semantic_views/`) do
the same for Cortex Analyst, with the relationships between the fact and its dimensions declared. A
question about "headline rent" or "lettings" resolves to the declared measure rather than to an
improvised `AVG(rent)`, and ratios are defined from sums, so "vacancy rate by country" is stock-weighted
however the question groups it. Dimensions are joined inside the view, so an agent never has to work out
the star schema's keys.

## 4. Pre-written natural language

`mart_ai_market_facts.summary_text` is one sentence per market-quarter with every headline number
and its unit. It is a retrieval unit: a RAG application can index these rows and answer "how is the
Paris market doing" from text that the pipeline wrote and tested, rather than from a table the model
has to interpret.

## 5. Only checked data, with provenance

Gold holds rows that passed every check; the held-back rows and reasons are in ops, not mixed in.
Provenance columns (`source_table`, `reported_submitted_at`, `submission_count`,
`submarket_derived_from_building`, `rent_suppressed_reason`) let an agent qualify an answer
("this rent was withheld by the market") instead of inventing one.

## 6. Guard rails in the instructions

The Genie instructions say what the data is (synthetic, five markets, 2023Q1 to 2026Q3), which table
answers which question, the definitions, and what to decline. `databricks/genie/sample_questions.md`
is a benchmark set: the questions a research analyst asks, with what a correct answer uses.

## 7. Descriptions where the agent reads them

Every gold column is described once in `models/gold/_gold.yml` (a pytest fails if one is missing), and
`persist_docs` writes the descriptions to Unity Catalog and Snowflake as table and column comments, which
is where Genie, Catalog Explorer and Cortex Analyst read them.

## What would come next

- A vector index over `summary_text` (Databricks Vector Search; Free Edition allows one endpoint).
- Row-level security on `dim_market` for market-restricted users, so an agent inherits the viewer's permissions.
