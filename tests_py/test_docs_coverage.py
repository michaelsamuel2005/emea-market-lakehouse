"""Every gold column is documented. Gold is the contract with BI and Genie, and persist_docs writes these
descriptions into the warehouse, so an undocumented column is a gap in the contract. Reads the DuckDB build
and target/manifest.json (both written by `dbt build`)."""

import json
import os
from pathlib import Path

import duckdb
import pytest

ROOT = Path(__file__).resolve().parent.parent
DB = Path(os.environ.get("DUCKDB_PATH", ROOT / "target" / "emea_market_lakehouse.duckdb"))
MANIFEST = ROOT / "target" / "manifest.json"


@pytest.fixture(scope="module")
def built():
    if not DB.exists() or not MANIFEST.exists():
        pytest.skip("run `dbt build` first")
    con = duckdb.connect(str(DB), read_only=True)
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    return con, manifest


def test_every_gold_model_and_column_is_documented(built):
    con, manifest = built
    models = {n["name"]: n for n in manifest["nodes"].values() if n["resource_type"] == "model" and n["schema"] == "gold"}
    missing = []
    for table, column in con.execute(
        "select table_name, column_name from information_schema.columns where table_schema = 'gold' order by 1, 2"
    ).fetchall():
        node = models.get(table)
        if node is None or not node["description"].strip():
            missing.append(f"{table} (model)")
            continue
        described = {name.lower(): col.get("description", "").strip() for name, col in node["columns"].items()}
        if not described.get(column.lower()):
            missing.append(f"{table}.{column}")
    assert not missing, "undocumented in models/gold/_gold.yml: " + ", ".join(sorted(set(missing)))
