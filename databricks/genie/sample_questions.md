# Questions to try in the Genie space

Use these to check the space answers with the right definitions, and as benchmark questions.

| Question | What a correct answer uses |
| --- | --- |
| What is the vacancy rate in London right now? | `mv_market_kpis`, latest quarter (2026Q3), stock-weighted ratio, shown as a percentage |
| Which market has the highest prime rent? | MAX of prime rent per market, EUR per sq m per year, latest quarter |
| How much space was let in Paris in 2026? | SUM of take-up over 2026Q1-Q3 |
| Compare prime yields across the five markets | MIN of prime yield per market, latest quarter, as percentages |
| Has Warsaw's vacancy gone up or down this year? | `mart_market_kpis.vacancy_rate` for 2025Q4 vs 2026Q3 |
| Who are the biggest occupiers in Amsterdam? | `mv_leasing_deals` grouped by tenant, ordered by area |
| Which sector leases the most space in Frankfurt? | grouped by sector_name |
| What does net absorption mean? | `dim_metric_definition` |
| Show me the biggest deal of 2026 | `fct_leasing_deal` ordered by area_m2, with tenant and building |
| Summarise the London market last quarter | `mart_ai_market_facts.summary_text` |

Questions the space should decline or qualify: "Is this real data?" (no: synthetic, illustrative);
"What is the rent in GBP per sq ft?" (the gold layer holds EUR per sq m; the local figure is in
`rent_local` on deals and `prime_rent_local` on the fact).
