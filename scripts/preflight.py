"""Check the environment for a target before running a runbook, then run `dbt debug` against it.

    python scripts/preflight.py databricks      # or: databricks_token, snowflake, snowflake_password, duckdb
    python scripts/preflight.py snowflake --no-connect   # check the variables and files only

It checks the Python version, that the adapter for the target is installed, that every environment
variable the target needs is set and looks right (host without https://, HTTP path of the right shape,
account identifier of the form ORGNAME-ACCOUNTNAME, private key file present and in PEM form), and then
runs `dbt debug`. Nothing secret is printed: values are shown masked.
"""

from __future__ import annotations

import argparse
import importlib
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

TARGETS = {
    "duckdb": {"adapter": "dbt.adapters.duckdb", "package": "dbt-duckdb", "vars": []},
    "databricks": {
        "adapter": "dbt.adapters.databricks", "package": "dbt-databricks (requirements-databricks.txt)",
        "vars": ["DATABRICKS_HOST", "DATABRICKS_HTTP_PATH"],
    },
    "databricks_token": {
        "adapter": "dbt.adapters.databricks", "package": "dbt-databricks (requirements-databricks.txt)",
        "vars": ["DATABRICKS_HOST", "DATABRICKS_HTTP_PATH", "DATABRICKS_TOKEN"],
    },
    "snowflake": {
        "adapter": "dbt.adapters.snowflake", "package": "dbt-snowflake (requirements-snowflake.txt)",
        "vars": ["SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER", "SNOWFLAKE_PRIVATE_KEY_PATH"],
    },
    "snowflake_password": {
        "adapter": "dbt.adapters.snowflake", "package": "dbt-snowflake (requirements-snowflake.txt)",
        "vars": ["SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER", "SNOWFLAKE_PASSWORD"],
    },
}

SECRET = ("TOKEN", "PASSWORD", "PASSPHRASE")


def mask(name: str, value: str) -> str:
    if any(s in name for s in SECRET):
        return f"{'*' * 8} ({len(value)} characters)"
    return value


def check_value(name: str, value: str) -> str | None:
    """Return a problem description, or None when the value looks right."""
    if name == "DATABRICKS_HOST":
        if value.startswith("http"):
            return "remove the https:// prefix; dbt wants only the host name"
        if "/" in value or not re.match(r"^[A-Za-z0-9.-]+$", value):
            return "should be a host name only, e.g. dbc-a1b2c3d4-e5f6.cloud.databricks.com"
    if name == "DATABRICKS_HTTP_PATH" and not value.startswith("/sql/1.0/warehouses/"):
        return "should start with /sql/1.0/warehouses/ (SQL Warehouses > your warehouse > Connection details)"
    if name == "DATABRICKS_TOKEN" and not value.startswith("dapi"):
        return "Databricks personal access tokens start with dapi; check you copied the whole token"
    if name == "SNOWFLAKE_ACCOUNT":
        if "." in value or value.lower().startswith("http"):
            return "use the account identifier ORGNAME-ACCOUNTNAME, not the URL (Snowsight: account menu > View account details)"
        if "-" not in value:
            return "expected the form ORGNAME-ACCOUNTNAME (with a hyphen)"
    if name == "SNOWFLAKE_USER" and "@" in value:
        return "this should be the login name (run `select current_user();` in Snowsight), not an email address"
    if name == "SNOWFLAKE_PRIVATE_KEY_PATH":
        path = Path(os.path.expanduser(value))
        if not path.is_file():
            return f"no file at {path}"
        head = path.read_bytes()[:40]
        if b"PRIVATE KEY-----" not in head:
            return "the file does not start with a PEM header (-----BEGIN ENCRYPTED PRIVATE KEY-----); is this rsa_key.p8?"
        if b"ENCRYPTED" in head and not os.environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE"):
            return "the key is encrypted but SNOWFLAKE_PRIVATE_KEY_PASSPHRASE is not set"
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("target", choices=sorted(TARGETS))
    ap.add_argument("--no-connect", action="store_true", help="check variables and files only; do not run dbt debug")
    args = ap.parse_args()
    spec = TARGETS[args.target]
    problems = 0

    def report(ok: bool, text: str):
        nonlocal problems
        problems += 0 if ok else 1
        print(("  ok   " if ok else "  FAIL ") + text)

    print(f"preflight for target '{args.target}' in {ROOT}")
    report(sys.version_info >= (3, 11), f"Python {sys.version.split()[0]} (3.11 or later needed)")
    report((ROOT / "dbt_project.yml").is_file() and (ROOT / "profiles.yml").is_file(), "dbt_project.yml and profiles.yml found")

    try:
        importlib.import_module(spec["adapter"])
        report(True, f"adapter installed: {spec['package']}")
    except ImportError:
        report(False, f"adapter not installed: pip install -r requirements.txt and {spec['package']}")

    for name in spec["vars"]:
        value = os.environ.get(name, "")
        if not value:
            report(False, f"{name} is not set (see .env.example; `source .env` after filling it in)")
            continue
        problem = check_value(name, value)
        report(problem is None, f"{name} = {mask(name, value)}" + (f": {problem}" if problem else ""))

    if args.target.startswith("snowflake"):
        for name in ("SNOWFLAKE_ROLE", "SNOWFLAKE_WAREHOUSE", "SNOWFLAKE_DATABASE", "SNOWFLAKE_SCHEMA"):
            print(f"  info {name} = {os.environ.get(name) or '(default from profiles.yml)'}")
    if args.target.startswith("databricks"):
        for name in ("DATABRICKS_CATALOG", "DATABRICKS_SCHEMA"):
            print(f"  info {name} = {os.environ.get(name) or '(default from profiles.yml)'}")

    if problems:
        print(f"\n{problems} problem(s) above; fix them before running dbt.")
        return 1
    if args.no_connect:
        print("\nvariables and files look right (connection not tested).")
        return 0

    print(f"\nrunning: dbt debug --target {args.target}")
    from dbt.cli.main import dbtRunner

    os.chdir(ROOT)
    result = dbtRunner().invoke(["debug", "--target", args.target])
    if result.success:
        print("\nconnection works. Next: dbt build --target " + args.target)
        return 0
    print("\ndbt debug failed: read the message above, then the Troubleshooting table in the runbook.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
