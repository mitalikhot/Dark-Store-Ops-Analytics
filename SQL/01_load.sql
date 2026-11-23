CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS mart;

CREATE OR REPLACE TABLE raw.stores              AS SELECT * FROM read_csv_auto('data/raw/stores.csv');
CREATE OR REPLACE TABLE raw.products            AS SELECT * FROM read_csv_auto('data/raw/products.csv');
CREATE OR REPLACE TABLE raw.customers           AS SELECT * FROM read_csv_auto('data/raw/customers.csv');
CREATE OR REPLACE TABLE raw.orders              AS SELECT * FROM read_csv_auto('data/raw/orders.csv');
CREATE OR REPLACE TABLE raw.order_items         AS SELECT * FROM read_csv_auto('data/raw/order_items.csv');
CREATE OR REPLACE TABLE raw.deliveries          AS SELECT * FROM read_csv_auto('data/raw/deliveries.csv');
CREATE OR REPLACE TABLE raw.inventory_snapshots AS SELECT * FROM read_csv_auto('data/raw/inventory_snapshots.csv');
