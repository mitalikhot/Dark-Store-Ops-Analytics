# Dark-Store Ops Analytics: SQL Project for Quick-Commerce Delivery

A SQL-first analytics project that models the operations of a quick-commerce company running 12 dark stores across four Madhya Pradesh cities (Bhopal, Indore, Jabalpur, Gwalior). It answers the questions an operations lead would ask: where the 10-minute delivery promise breaks, whether stores are staffed for peak hours, whether customers come back, which products run out of stock, and which categories are bought together.

> **Data note:** the dataset is synthetic. `generate_data.py` simulates 90 days of orders, deliveries, and inventory with a fixed random seed, so results are reproducible. The findings demonstrate the method; they are not real business conclusions.

## Business questions

| # | Question | SQL techniques |
|---|----------|----------------|
| Q1 | Where and when do we break the 10-minute promise? | Aggregation, `quantile_cont` (P90), `HAVING` |
| Q2 | Which stores are under-staffed at peak? | CTE, percentiles, join to store dimension |
| Q3 | Do customers come back? (monthly cohorts) | Cohort logic, `DATEDIFF`, `CROSS JOIN`, conditional `CASE` |
| Q4 | Which products go out of stock most, per store? | Window function (`RANK() OVER PARTITION BY`) |
| Q5 | Which categories are bought together? | Self-join, lift calculation |

## Tech stack

- **DuckDB**: embedded analytical SQL engine
- **SQL**: data loading, quality checks, transformations, analysis
- **Python** (pandas, NumPy): data generation and pipeline runner only
- **Power BI** (optional): reads the exported mart for dashboards

## Project structure

```
dark-store-analytics/
├── generate_data.py        # Simulates raw CSV data (run once)
├── run_pipeline.py         # Rebuilds the warehouse and runs all SQL
├── sql/
│   ├── 01_load.sql         # Loads raw CSVs into the raw schema
│   ├── 02_quality_checks.sql  # Nine data-quality checks (0 = pass)
│   ├── 03_marts.sql        # order_facts view and store_daily table
│   └── 04_analysis.sql     # Five business questions
├── data/raw/               # Generated CSVs
└── exports/                # store_daily.csv for Power BI
```

## Data model

- `stores`, `products`, `customers`: dimension tables
- `orders`, `order_items`, `deliveries`: fact tables, one delivery per delivered order
- `inventory_snapshots`: daily stock per store and product

The layers are:

1. **raw**: CSVs loaded unchanged
2. **dq_results**: quality checks on the raw layer
3. **mart**: `order_facts` (one row per order, with SLA flag) and `store_daily` (one row per store per day)

## How to run

```bash
pip install duckdb pandas numpy
python generate_data.py     # creates data/raw/*.csv (skip if the folder is already there)
python run_pipeline.py      # builds warehouse.duckdb, prints checks and analysis, exports CSV
```

The runner rebuilds `warehouse.duckdb` from scratch on each run. It prints the data-quality table, the output of each analysis query, and writes `exports/store_daily.csv`.

## Key definitions

- **Delivery time** = `delivered_at` − `placed_at`, in minutes
- **SLA breach** = delivery time greater than the promised 10 minutes
- **Lift** = P(A and B) ÷ (P(A) × P(B)). Values above 1 mean two categories are bought together more often than chance predicts.
- **Cohort** = customers grouped by the month of their first delivered order. The first month of data also contains customers who ordered earlier, so the August cohort is the largest.

## Key results (seed 42)

- The highest SLA breach rates occur in the 7–9 pm window in Gwalior and Jabalpur, the cities with fewer stores.
- Beverages and Snacks show the strongest affinity (lift ≈ 1.36), followed by Bakery and Dairy (≈ 1.19).
- Perishable products such as bread, paneer, and onions stock out most often.

## What I'd add next

- Replace the synthetic data with a public e-commerce or delivery dataset
- Convert the SQL layers to dbt models with schema tests
- Build a Power BI dashboard on `exports/store_daily.csv`
- Add GitHub Actions to run the pipeline on every push

## Skills demonstrated

Data modeling, data-quality testing, window functions, cohort and retention analysis, percentile metrics, self-joins for affinity analysis, reproducible pipelines.

## License

MIT
