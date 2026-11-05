"""Summarise the last dbt run from target/run_results.json: slowest nodes, failures and warnings.

    python scripts/monitor.py              # after any dbt command
    python scripts/monitor.py --top 15

The same information is stored in ops.dbt_run_results by the on-run-end hook for trend analysis;
this script is the quick look at a single run, and works without a database connection.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--top", type=int, default=10, help="how many of the slowest nodes to list")
    ap.add_argument("--path", default=str(ROOT / "target" / "run_results.json"))
    args = ap.parse_args()
    data = json.loads(Path(args.path).read_text(encoding="utf-8"))
    results = data["results"]
    total = sum(r["execution_time"] for r in results)
    by_status: dict[str, int] = {}
    for r in results:
        by_status[r["status"]] = by_status.get(r["status"], 0) + 1
    print(f"dbt {data['metadata']['dbt_version']} | {data['args'].get('which', '?')} | {len(results)} nodes | "
          f"{total:.1f}s of node time | elapsed {data['elapsed_time']:.1f}s")
    print("statuses:", ", ".join(f"{k}={v}" for k, v in sorted(by_status.items())))
    problems = [r for r in results if r["status"] not in ("success", "pass")]
    if problems:
        print("\nnot green:")
        for r in problems:
            print(f"  {r['status']:<6} {r['unique_id']}  {(r.get('message') or '')[:100]}")
    print(f"\nslowest {args.top}:")
    for r in sorted(results, key=lambda x: -x["execution_time"])[: args.top]:
        rows = (r.get("adapter_response") or {}).get("rows_affected")
        print(f"  {r['execution_time']:7.2f}s  {r['unique_id']:<70} rows={rows if rows is not None else '-'}")


if __name__ == "__main__":
    main()
