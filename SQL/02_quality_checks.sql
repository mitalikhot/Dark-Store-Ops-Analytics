CREATE OR REPLACE TABLE dq_results AS
SELECT 'orders: duplicate order_id' AS check_name,
       COUNT(*) - COUNT(DISTINCT order_id) AS failing_rows
FROM raw.orders
UNION ALL
SELECT 'orders: store_id not in stores', COUNT(*)
FROM raw.orders o
WHERE NOT EXISTS (SELECT 1 FROM raw.stores s WHERE s.store_id = o.store_id)
UNION ALL
SELECT 'orders: customer_id not in customers', COUNT(*)
FROM raw.orders o
WHERE NOT EXISTS (SELECT 1 FROM raw.customers c WHERE c.customer_id = o.customer_id)
UNION ALL
SELECT 'orders: placed before customer signup', COUNT(*)
FROM raw.orders o
JOIN raw.customers c USING (customer_id)
WHERE CAST(o.placed_at AS DATE) < c.signup_date
UNION ALL
SELECT 'delivered orders with no delivery row', COUNT(*)
FROM raw.orders o
WHERE o.status = 'delivered'
  AND NOT EXISTS (SELECT 1 FROM raw.deliveries d WHERE d.order_id = o.order_id)
UNION ALL
SELECT 'cancelled orders that have a delivery row', COUNT(*)
FROM raw.orders o
WHERE o.status = 'cancelled'
  AND EXISTS (SELECT 1 FROM raw.deliveries d WHERE d.order_id = o.order_id)
UNION ALL
SELECT 'deliveries: delivered_at before dispatched_at', COUNT(*)
FROM raw.deliveries
WHERE delivered_at < dispatched_at
UNION ALL
SELECT 'order_items: qty or price <= 0', COUNT(*)
FROM raw.order_items
WHERE qty <= 0 OR unit_price <= 0
UNION ALL
SELECT 'inventory: negative stock_qty', COUNT(*)
FROM raw.inventory_snapshots
WHERE stock_qty < 0;
