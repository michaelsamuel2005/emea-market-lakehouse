"""Print the project's headline numbers from the built DuckDB database, so the README and a CV quote
figures that come from the pipeline rather than from memory.

    dbt build && python scripts/fact_sheet.py
"""

from __future__ import annotations

import json
import os
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
DB = Path(os.environ.get("DUCKDB_PATH", ROOT / "target" / "emea_market_lakehouse.duckdb"))


def main():
    con = duckdb.connect(str(DB), read_only=True)
    q = lambda sql: con.execute(sql).fetchall()  # noqa: E731
    facts = {}
    facts["markets"] = q("select count(*) from gold.dim_market")[0][0]
    facts["submarkets"] = q("select count(*) from gold.dim_submarket")[0][0]
    facts["quarters"] = q("select count(distinct quarter_id) from gold.fct_market_quarter")[0][0]
    facts["first_quarter"], facts["last_quarter"] = q("select min(quarter_id), max(quarter_id) from gold.fct_market_quarter")[0]
    facts["bronze_rows"] = sum(
        con.execute(f'select count(*) from bronze."{t}"').fetchone()[0]
        for (t,) in q("select table_name from information_schema.tables where table_schema = 'bronze' order by 1")
    )
    facts["deals_submitted"] = q("select count(*) from silver.int_deals")[0][0]
    facts["deals_in_gold"] = q("select count(*) from gold.fct_leasing_deal")[0][0]
    facts["deals_quarantined"] = q("select count(*) from silver.int_deals where quarantine_reason is not null")[0][0]
    facts["deals_rent_suppressed"] = q("select count(*) from silver.int_deals where rent_suppressed_reason is not null")[0][0]
    facts["deals_submarket_repaired"] = q("select count(*) from silver.int_deals where submarket_derived_from_building")[0][0]
    facts["buildings"] = q("select count(*) from gold.dim_building")[0][0]
    facts["building_versions"] = q("select count(*) from gold.dim_building_history")[0][0]
    facts["deals_on_an_earlier_building_version"], facts["deals_whose_building_grade_changed_since"] = q("""
        select count(*), count(case when h.grade_code <> b.grade_code then 1 end)
        from gold.fct_leasing_deal f
        join gold.dim_building_history h on h.building_version_key = f.building_version_key
        join gold.dim_building b on b.building_key = f.building_key
        where not h.is_current
    """)[0]
    facts["tenants"] = q("select count(*) from gold.dim_tenant")[0][0]
    facts["tenants_in_several_markets"] = q("select count(*) from gold.dim_tenant where markets_active > 1")[0][0]
    facts["availability_rows"] = q("select count(*) from gold.fct_building_availability")[0][0]
    facts["kpis_defined"] = q("select count(*) from gold.dim_metric_definition")[0][0]
    facts["detection"] = {r[0]: r[1] for r in q("select defect_type, handled_correctly_pct from ops.ops_defect_detection order by 1")}
    facts["false_positives"] = q("""
        select count(*) from silver.int_deals d
        left join answer_key.answer_key_defects k on k.market_id = d.market_id and k.dataset = 'deals' and k.row_key = d.deal_ref
        where d.quarantine_reason is not null and k.row_key is null
    """)[0][0]
    facts["vacancy_reconciliation"] = {
        "mean_abs_gap_pp": round(q("select avg(abs(gap_pp)) from ops.ops_dq_reconciliation_vacancy")[0][0], 2),
        "outside_tolerance": q("select count(*) from ops.ops_dq_reconciliation_vacancy where is_outside_tolerance")[0][0],
        "rows": q("select count(*) from ops.ops_dq_reconciliation_vacancy")[0][0],
    }
    facts["take_up_reconciliation"] = {
        "outside_tolerance": q("select count(*) from ops.ops_dq_reconciliation_take_up where is_outside_tolerance")[0][0],
        "rows": q("select count(*) from ops.ops_dq_reconciliation_take_up")[0][0],
    }
    facts["latest_kpis"] = [
        {"market": r[0], "vacancy_rate_pct": round(r[1] * 100, 1), "take_up_m2": round(r[2]), "prime_rent_eur_m2_yr": round(r[3]),
         "prime_yield_pct": round(r[4] * 100, 2), "deals": r[5]}
        for r in q("""select m.market_name, k.vacancy_rate, k.take_up_m2, k.prime_rent_eur_m2_yr, k.prime_yield, k.deal_count
                      from gold.mart_market_kpis k join gold.dim_market m using (market_id)
                      where k.quarter_id = (select max(quarter_id) from gold.mart_market_kpis) order by 1""")
    ]
    manifest = ROOT / "target" / "manifest.json"
    if manifest.exists():  # test counts as dbt sees them, from the last dbt command
        nodes = json.loads(manifest.read_text(encoding="utf-8"))
        by_type: dict[str, int] = {}
        for node in nodes["nodes"].values():
            if node["resource_type"] == "test":
                kind = node["test_metadata"]["name"] if node.get("test_metadata") else "singular"
                by_type[kind] = by_type.get(kind, 0) + 1
        facts["data_tests"] = {"total": sum(by_type.values()), **dict(sorted(by_type.items(), key=lambda kv: -kv[1]))}
        facts["unit_tests"] = len(nodes.get("unit_tests", {}))
    print(json.dumps(facts, indent=2, default=str))


if __name__ == "__main__":
    main()
