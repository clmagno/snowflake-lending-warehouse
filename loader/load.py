"""Load the generated CSV extracts into the RAW layer.

Two targets:

* snowflake - PUT the files to the internal stage, then run the COPY INTO
              statements in snowflake/03_copy_into.sql. Re-running is safe:
              COPY skips files it has already loaded.
* duckdb    - load the same files into a local DuckDB file with the same
              RAW table layout, for development and CI without a Snowflake
              account.

Snowflake connection settings come from environment variables:

    SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER
    SNOWFLAKE_PASSWORD               or
    SNOWFLAKE_PRIVATE_KEY_PATH (+ optional SNOWFLAKE_PRIVATE_KEY_PASSPHRASE)
    SNOWFLAKE_ROLE (default LOADER), SNOWFLAKE_WAREHOUSE (default LOADING_WH)

Usage:
    python loader/load.py --target duckdb
    python loader/load.py --target snowflake
"""

from __future__ import annotations

import argparse
import logging
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data" / "raw"
COPY_SQL = ROOT / "snowflake" / "03_copy_into.sql"
DUCKDB_PATH = ROOT / "data" / "lending.duckdb"

log = logging.getLogger("loader")

# Same layout as snowflake/02_raw_layer.sql
RAW_TABLES = {
    "borrowers": {
        "files": ["borrowers.csv"],
        "columns": {
            "borrower_id": "VARCHAR",
            "first_name": "VARCHAR",
            "last_name": "VARCHAR",
            "email": "VARCHAR",
            "date_of_birth": "DATE",
            "region": "VARCHAR",
            "employment_type": "VARCHAR",
            "annual_income": "DECIMAL(12,2)",
            "credit_score": "INTEGER",
            "created_at": "TIMESTAMP",
        },
    },
    "loans": {
        "files": ["loans.csv"],
        "columns": {
            "loan_id": "VARCHAR",
            "borrower_id": "VARCHAR",
            "product_code": "VARCHAR",
            "principal_amount": "DECIMAL(14,2)",
            "annual_interest_rate": "DECIMAL(6,4)",
            "term_months": "INTEGER",
            "origination_date": "DATE",
            "origination_channel": "VARCHAR",
        },
    },
    "payments": {
        "files": ["payments/payments_*.csv"],
        "columns": {
            "payment_id": "VARCHAR",
            "loan_id": "VARCHAR",
            "payment_date": "DATE",
            "amount": "DECIMAL(14,2)",
            "payment_method": "VARCHAR",
            "source_extracted_at": "TIMESTAMP",
        },
    },
}


def files_for(table: str) -> list[Path]:
    found: list[Path] = []
    for pattern in RAW_TABLES[table]["files"]:
        found.extend(sorted(DATA_DIR.glob(pattern)))
    if not found:
        sys.exit(f"No files for {table} in {DATA_DIR}. Run data_generator/generate.py first.")
    return found


# ---------------------------------------------------------------------------
# DuckDB
# ---------------------------------------------------------------------------
def load_duckdb() -> None:
    import duckdb

    DUCKDB_PATH.parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(DUCKDB_PATH))
    con.execute("CREATE SCHEMA IF NOT EXISTS raw")
    for table, spec in RAW_TABLES.items():
        cols = spec["columns"]
        col_defs = ", ".join(f"{c} {t}" for c, t in cols.items())
        con.execute(f"DROP TABLE IF EXISTS raw.{table}")
        con.execute(f"CREATE TABLE raw.{table} ({col_defs}, _source_file VARCHAR, _loaded_at TIMESTAMPTZ)")
        file_list = [str(p) for p in files_for(table)]
        type_map = ", ".join(f"'{c}': '{t}'" for c, t in cols.items())
        con.execute(
            f"""
            INSERT INTO raw.{table}
            SELECT {", ".join(cols)}, filename, current_timestamp
            FROM read_csv(?, header = true, columns = {{{type_map}}}, filename = true)
            """,
            [file_list],
        )
        n = con.execute(f"SELECT count(*) FROM raw.{table}").fetchone()[0]
        log.info("duckdb raw.%s: %s rows from %s file(s)", table, f"{n:,}", len(file_list))
    con.close()


# ---------------------------------------------------------------------------
# Snowflake
# ---------------------------------------------------------------------------
def snowflake_connection():
    import snowflake.connector

    params = {
        "account": os.environ["SNOWFLAKE_ACCOUNT"],
        "user": os.environ["SNOWFLAKE_USER"],
        "role": os.getenv("SNOWFLAKE_ROLE", "LOADER"),
        "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE", "LOADING_WH"),
        "database": "LENDING",
        "schema": "RAW",
        "session_parameters": {"QUERY_TAG": "lending:load"},
    }
    key_path = os.getenv("SNOWFLAKE_PRIVATE_KEY_PATH")
    if key_path:
        params["private_key_file"] = key_path
        if os.getenv("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE"):
            params["private_key_file_pwd"] = os.environ["SNOWFLAKE_PRIVATE_KEY_PASSPHRASE"]
    else:
        params["password"] = os.environ["SNOWFLAKE_PASSWORD"]
    return snowflake.connector.connect(**params)


def copy_statements() -> list[str]:
    """COPY INTO statements from 03_copy_into.sql, in file order."""
    text = re.sub(r"--[^\n]*", "", COPY_SQL.read_text())
    return [s.strip() for s in text.split(";") if s.strip().upper().startswith("COPY INTO")]


def load_snowflake() -> None:
    con = snowflake_connection()
    cur = con.cursor()
    try:
        for table in RAW_TABLES:
            for path in files_for(table):
                # PUT skips a file whose compressed copy is already on the stage
                cur.execute(
                    f"PUT 'file://{path.as_posix()}' @LENDING_LANDING/{table}/ AUTO_COMPRESS = TRUE OVERWRITE = FALSE"
                )
            log.info("staged %s file(s) for %s", len(files_for(table)), table)

        for stmt in copy_statements():
            target = stmt.split()[2]
            cur.execute(stmt)
            results = cur.fetchall()
            loaded = [r for r in results if len(r) > 3 and r[1] in ("LOADED", "PARTIALLY_LOADED")]
            rows = sum(int(r[3]) for r in loaded)
            errors = [r for r in results if len(r) > 1 and r[1] != "LOADED"]
            log.info("COPY INTO %s: %s new file(s), %s rows", target, len(loaded), f"{rows:,}")
            for r in errors:
                log.warning("  %s", r)

        for table in RAW_TABLES:
            n = cur.execute(f"SELECT COUNT(*) FROM {table.upper()}").fetchone()[0]
            log.info("snowflake RAW.%s: %s rows", table.upper(), f"{n:,}")
    finally:
        cur.close()
        con.close()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--target", choices=["duckdb", "snowflake"], required=True)
    args = parser.parse_args()
    load_duckdb() if args.target == "duckdb" else load_snowflake()


if __name__ == "__main__":
    main()
