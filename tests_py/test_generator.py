"""Checks on the synthetic raw files: the generator is reproducible, the files follow each market's
conventions, and the answer key describes what is actually in them."""

import csv
import hashlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parent.parent
BRONZE = ROOT / "seeds" / "bronze"
# The markets configured in dbt_project.yml: the five core markets, plus Madrid once it is onboarded.
CONFIG = yaml.safe_load((ROOT / "dbt_project.yml").read_text(encoding="utf-8"))["vars"]["markets"]
MARKETS = [m.lower() for m in CONFIG]


def rows(path: Path) -> list[dict]:
    with path.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def test_generator_is_reproducible():
    """Regenerating into a temp folder gives byte-identical files (the committed data is the generator's output)."""
    result = subprocess.run([sys.executable, str(ROOT / "generator" / "generate.py"), "--check"], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.parametrize("market", MARKETS)
def test_every_dataset_exists_with_rows(market):
    for ds in ("market_stats", "deals", "buildings", "availability"):
        data = rows(BRONZE / f"{market}_{ds}.csv")
        assert len(data) > 10, f"{market}_{ds} is empty"


def test_period_labels_follow_each_markets_convention():
    patterns = {
        "lon": (r"^Q[1-4] \d{4}$", "Period"),
        "par": (r"^T[1-4] \d{4}$", "Trimestre"),
        "ams": (r"^\d{4}-Q[1-4]$", "Quarter"),
        "fra": (r"^[1-4]\. Quartal \d{4}$", "Quartal"),
        "waw": (r"^\d{4}Q[1-4]$", "period"),
    }
    for market, (pattern, column) in patterns.items():
        for r in rows(BRONZE / f"{market}_market_stats.csv"):
            assert re.match(pattern, r[column]), f"{market}: {r[column]!r}"


def test_number_formats_follow_each_markets_convention():
    """London uses thousands commas, Paris spaces and decimal commas, Frankfurt points and decimal commas."""
    lon = rows(BRONZE / "lon_market_stats.csv")[0]
    assert re.match(r"^\d{1,3}(,\d{3})+$", lon["Total_Stock_sq_ft"])
    assert re.match(r"^\d+\.\d{2}$", lon["Prime_Rent_GBP_psf_pa"])
    par = rows(BRONZE / "par_market_stats.csv")[0]
    assert " " in par["Parc_total_m2"] and "," in par["Loyer_prime_EUR_m2_an"]
    assert par["Taux_prime"].endswith(" %")
    fra = rows(BRONZE / "fra_market_stats.csv")[0]
    assert "." in fra["Flaechenbestand_m2"] and "," in fra["Spitzenmiete_EUR_m2_monat"]
    waw = rows(BRONZE / "waw_market_stats.csv")[0]
    assert float(waw["prime_yield"]) < 1, "Warsaw reports yields as decimal fractions"


def test_frankfurt_reports_a_vacancy_rate_not_an_area():
    for r in rows(BRONZE / "fra_market_stats.csv"):
        value = float(r["Leerstandsquote_prozent"].replace(".", "").replace(",", "."))
        assert 0 < value < 40


def test_warsaw_logs_some_deals_in_pln():
    currencies = {r["rent_currency"] for r in rows(BRONZE / "waw_deals.csv")}
    assert currencies == {"EUR", "PLN"}


def test_answer_key_rows_exist_in_the_raw_files():
    """Every deal defect in the answer key refers to a deal reference that is in that market's file."""
    refs = {}
    for market in MARKETS:
        ref_col = CONFIG[market.upper()]["deals"]["columns"]["deal_ref"]
        refs[market.upper()] = {r[ref_col] for r in rows(BRONZE / f"{market}_deals.csv")}
    missing = []
    for d in rows(ROOT / "seeds" / "answer_key" / "answer_key_defects.csv"):
        if d["dataset"] == "deals" and d["row_key"] not in refs[d["market_id"]]:
            missing.append(d)
    assert not missing, missing[:5]


def test_exact_duplicates_are_really_duplicated():
    """Each exact_duplicate entry's reference appears at least twice in the raw deals file."""
    lon = rows(BRONZE / "lon_deals.csv")
    counts = {}
    for r in lon:
        counts[r["Deal_Ref"]] = counts.get(r["Deal_Ref"], 0) + 1
    for d in rows(ROOT / "seeds" / "answer_key" / "answer_key_defects.csv"):
        if d["market_id"] == "LON" and d["defect_type"] == "exact_duplicate":
            assert counts[d["row_key"]] >= 2, d


def test_building_names_are_unique_within_a_market():
    """The deal log is matched to the register by building name, so names must not collide."""
    for market in MARKETS:
        columns = CONFIG[market.upper()]["buildings"]["columns"]
        data = rows(BRONZE / f"{market}_buildings.csv")
        by_name = {}
        for r in data:
            by_name.setdefault(r[columns["name"]], set()).add(r[columns["building_id"]])
        collisions = {k: v for k, v in by_name.items() if len(v) > 1}
        assert not collisions, f"{market}: {collisions}"


def test_reference_seeds_cover_every_market():
    markets = {r["market_id"] for r in rows(ROOT / "seeds" / "reference" / "ref_markets.csv")}
    assert markets == {m.upper() for m in MARKETS}
    for name in ("ref_submarkets", "ref_grade_mapping", "ref_deal_type_mapping", "ref_sector_mapping"):
        covered = {r["market_id"] for r in rows(ROOT / "seeds" / "reference" / f"{name}.csv")}
        assert covered == markets, name
