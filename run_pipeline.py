"""Run the whole pipeline: load -> quality checks -> marts -> analysis -> export.

Usage:
    python generate_data.py   # once, creates data/raw/*.csv
    python run_pipeline.py    # rebuilds warehouse.duckdb from scratch
"""
import os

import duckdb

DB = "warehouse.duckdb"
if os.path.exists(DB):
    os.remove(DB)
con = duckdb.connect(DB)

for step in ["sql/01_load.sql", "sql/02_quality_checks.sql", "sql/03_marts.sql"]:
    with open(step) as f:
        con.execute(f.read())
    print(f"ran {step}")

print("\n=== Data quality (0 = pass) ===")
print(con.sql("SELECT * FROM dq_results ORDER BY failing_rows DESC").df().to_string(index=False))

print("\n=== Analysis ===")
with open("sql/04_analysis.sql") as f:
    queries = [q.strip() for q in f.read().split(";") if q.strip()]
for i, q in enumerate(queries, 1):
    print(f"\n--- query {i} ---")
    print(con.sql(q).df().to_string(index=False))

os.makedirs("exports", exist_ok=True)
con.execute("COPY mart.store_daily TO 'exports/store_daily.csv' (HEADER, DELIMITER ',')")
print("\nexported exports/store_daily.csv for Power BI")
con.close()
