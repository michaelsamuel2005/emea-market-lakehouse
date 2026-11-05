# Extension: bring in real data

The core project is synthetic so that every defect is known and every check can be scored. These two
extensions add real open data without changing the model. Do them in the Databricks workspace or
locally; both are documented as the steps a market onboarding would follow.

## A. Real FX rates (ECB euro reference rates) — 30 minutes

`seeds/reference/ref_fx_rates.csv` holds synthetic quarterly rates. The European Central Bank
publishes daily euro reference rates for GBP, PLN and others as a CSV (`eurofxref-hist.csv`, one row
per day, one column per currency, values are units of currency per euro, which is exactly this
project's convention).

1. Download the historical CSV from the ECB's euro foreign exchange reference rates page
   (data.ecb.europa.eu / the "eurofxref-hist" file). Check the licence note on the page.
2. Reduce it to quarter-end rates (the last available day of each quarter from 2023Q1 to 2026Q3)
   for `GBP` and `PLN`, add `EUR = 1.0`, and write `quarter_id, currency_code, units_per_eur, rate_date`.
   A few lines of pandas or DuckDB:
   ```sql
   select strftime(Date, '%Y') || 'Q' || cast(quarter(Date) as varchar) as quarter_id, 'GBP' as currency_code, GBP as units_per_eur, Date as rate_date
   from read_csv_auto('eurofxref-hist.csv') qualify row_number() over (partition by quarter_id order by Date desc) = 1
   ```
3. Replace `ref_fx_rates.csv`, run `dbt build`. Prime rents and deal rents in EUR move slightly; the
   tests still pass because the ranges are wide. Note in `CHANGELOG.md` that rents are now at ECB rates.

What it demonstrates: a reference dataset onboarded from an external source with a stated
convention, and the pipeline's sensitivity to it (compare `mart_market_kpis.prime_rent_eur_m2_yr`
before and after).

## B. A real building stock source (VOA non-domestic rating list, England and Wales) — half a day

The Valuation Office Agency publishes the full non-domestic rating list as open data: every
commercial property in England and Wales with its address, description (offices among them),
floor area where held, and rateable value. It is a real "market-specific dataset" with its own
layout, which makes it a good onboarding exercise for the building register.

1. Download the current compiled list entries from the VOA open data page (a large text file; check
   the published data specification for the field layout, which uses `*` as the delimiter).
2. Filter to London offices (description codes for offices, billing authority codes for the London
   boroughs) in DuckDB or a Databricks notebook; keep address, postcode, floor area and rateable value.
3. Treat it as a new bronze source `lon_voa_buildings`: add a `voa` block to the London configuration
   with its column names, a staging model, and map postcodes to the London submarkets through a
   small `ref_postcode_submarket` seed you write for the central London postcode districts.
4. Extend `int_buildings` to prefer the register row and fall back to the VOA row for buildings the
   market did not send, with `source_table` showing which.

What it demonstrates: real-world messiness (delimiters, missing floor areas, descriptions as free
text) handled with the same pattern as the synthetic markets, and a documented decision about which
source wins when two describe the same building.

## Rules for both

- Keep the raw download out of the repository if it is large; commit the reduced file and the script
  that produced it, with the source URL and the download date in its header.
- Respect the source's licence note in `README.md`.
- Add a row to `CHANGELOG.md` and update the data contract if a definition changes.
