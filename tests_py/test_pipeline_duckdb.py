"""End-to-end checks against the DuckDB build: numbers the README quotes, and invariants dbt tests
cannot express easily. Run `dbt build` first (CI does), or set DUCKDB_PATH to a built database."""

import os
from pathlib import Path

import duckdb
import pytest
import yaml

ROOT = Path(__file__).resolve().parent.parent
DB = Path(os.environ.get("DUCKDB_PATH", ROOT / "target" / "emea_market_lakehouse.duckdb"))
CONFIG = yaml.safe_load((ROOT / "dbt_project.yml").read_text(encoding="utf-8"))["vars"]["markets"]
ASSUMPTIONS = yaml.safe_load((ROOT / "generator" / "assumptions.yaml").read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def con():
    if not DB.exists():
        pytest.skip(f"{DB} not found: run `dbt build` first")
    return duckdb.connect(str(DB), read_only=True)


def one(con, sql):
    return con.execute(sql).fetchone()


def test_every_configured_market_and_fifteen_quarters(con):
    markets, quarters = one(con, "select count(distinct market_id), count(distinct quarter_id) from gold.fct_market_quarter")
    assert markets == len(CONFIG) and quarters == 15


def test_prime_rents_are_in_a_shared_unit(con):
    """After conversion every market's prime rent sits in the same plausible EUR per m2 per year range."""
    lo, hi = one(con, "select min(prime_rent_eur_m2_yr), max(prime_rent_eur_m2_yr) from gold.fct_market_quarter")
    assert 100 < lo < hi < 3000, "a monthly rent left unannualised would be below 100; the same range as the dbt test"


def test_london_rent_conversion_uses_sqft_and_gbp(con):
    """A London prime rent of X GBP per sq ft per year must equal X * 10.7639 / (GBP per EUR) in EUR per m2 per year."""
    local, eur, fx = one(con, """
        select f.prime_rent_local, f.prime_rent_eur_m2_yr, x.units_per_eur
        from gold.fct_market_quarter f
        join reference.ref_fx_rates x on x.quarter_id = f.quarter_id and x.currency_code = 'GBP'
        where f.market_id = 'LON' and f.submarket_id = 'WEND' and f.quarter_id = '2026Q3'
    """)
    assert abs(eur - local * 10.763910416709722 / fx) < 0.01


def test_frankfurt_monthly_rent_is_annualised(con):
    local, eur = one(con, """
        select prime_rent_local, prime_rent_eur_m2_yr from gold.fct_market_quarter
        where market_id = 'FRA' and submarket_id = 'BANK' and quarter_id = '2026Q3'
    """)
    assert abs(eur - local * 12) < 0.01


def test_frankfurt_vacancy_rate_became_an_area(con):
    rate, stock, vacant = one(con, """
        select vacancy_rate, stock_m2, vacant_m2 from gold.fct_market_quarter
        where market_id = 'FRA' and submarket_id = 'ESCH' and quarter_id = '2026Q3'
    """)
    assert abs(vacant - stock * rate) < 1


def test_resubmitted_quarters_keep_the_latest_submission(con):
    (count,) = one(con, "select count(*) from silver.int_market_stats where submission_count > 1")
    assert count == 4, "two resubmissions each in London and Paris"
    (dupes,) = one(con, """
        select count(*) from (
            select market_id, submarket_id, quarter_id from silver.int_market_stats group by 1, 2, 3 having count(*) > 1
        )
    """)
    assert dupes == 0


def test_no_false_positives_in_quarantine(con):
    """Every quarantined deal row corresponds to a planted defect: the checks never hold back a genuine deal."""
    (false_positives,) = one(con, """
        select count(*)
        from silver.int_deals d
        left join answer_key.answer_key_defects k
            on k.market_id = d.market_id and k.dataset = 'deals' and k.row_key = d.deal_ref
        where d.quarantine_reason is not null and k.row_key is null
    """)
    assert false_positives == 0


def test_detection_rates(con):
    rates = dict(con.execute("select defect_type, handled_correctly_pct from ops.ops_defect_detection").fetchall())
    for defect in ("exact_duplicate", "near_duplicate", "future_date", "wrong_rent_unit", "missing_submarket", "confidential_rent"):
        assert rates[defect] == 100.0, (defect, rates[defect])
    assert 30 <= rates["wrong_area_unit"] <= 60, "the documented gap: small areas typed in the wrong unit still look plausible"


def test_planted_vacancy_mismatch_is_the_only_reconciliation_breach(con):
    breaches = con.execute("select market_id, submarket_id, quarter_id from ops.ops_dq_reconciliation_vacancy where is_outside_tolerance").fetchall()
    assert breaches == [("WAW", "CBD", "2024Q1")]


def test_kpi_mart_adds_up_to_the_fact(con):
    (gaps,) = one(con, """
        select count(*) from gold.mart_market_kpis k
        join (select market_id, quarter_id, sum(take_up_m2) t from gold.fct_market_quarter group by 1, 2) f
            on f.market_id = k.market_id and f.quarter_id = k.quarter_id
        where abs(k.take_up_m2 - f.t) > 0.5
    """)
    assert gaps == 0


def test_ai_summary_mentions_every_number_it_should(con):
    (text,) = one(con, "select summary_text from gold.mart_ai_market_facts where market_id = 'LON' and quarter_id = '2026Q3'")
    for phrase in ("London office market, Q3 2026", "vacancy rate", "take-up", "prime rent EUR", "prime yield", "leasing deals logged"):
        assert phrase in text


def test_run_results_were_recorded(con):
    (runs,) = one(con, "select count(distinct invocation_id) from ops.ops_run_history")
    assert runs >= 1


def test_refurbished_buildings_keep_their_history(con):
    """Six buildings per market were sent twice after a refurbishment: each has two versions, only the latest current."""
    versions, buildings, current = one(con, """
        select count(*), count(distinct building_key), sum(case when is_current then 1 else 0 end)
        from gold.dim_building_history
    """)
    resubmitted = ASSUMPTIONS["defects"]["buildings"]["refurbished_resubmissions"] * len(CONFIG)
    assert versions - buildings == resubmitted and current == buildings


def test_deals_are_reported_against_the_grade_at_the_deal_date(con):
    """Every deal finds exactly one building version; deals signed before a refurbishment keep the old grade."""
    (unmatched,) = one(con, "select count(*) from gold.fct_leasing_deal where building_version_key is null")
    assert unmatched == 0
    (regraded,) = one(con, """
        select count(*)
        from gold.fct_leasing_deal f
        join gold.dim_building_history h on h.building_version_key = f.building_version_key
        join gold.dim_building b on b.building_key = f.building_key
        where h.grade_code <> b.grade_code
    """)
    assert regraded > 0, "some deals were signed while the building still had its pre-refurbishment grade"
