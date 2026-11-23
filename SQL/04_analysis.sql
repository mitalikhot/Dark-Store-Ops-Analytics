-- Q1. Where and when do we break our 10-minute promise? (city x hour, P90 delivery time)
SELECT city,
       order_hour,
       COUNT(*)                                     AS delivered_orders,
       ROUND(100.0 * AVG(sla_breached::INT), 1)     AS breach_pct,
       ROUND(quantile_cont(actual_minutes, 0.9), 1) AS p90_minutes
FROM mart.order_facts
WHERE status = 'delivered'
GROUP BY city, order_hour
HAVING COUNT(*) >= 100
ORDER BY breach_pct DESC
LIMIT 10;

-- Q2. Are any stores under-staffed at peak? (p95 orders per rider-hour)
WITH store_hour AS (
    SELECT store_id, order_date, order_hour, COUNT(*) AS orders
    FROM mart.order_facts
    WHERE status = 'delivered'
    GROUP BY ALL
)
SELECT sh.store_id,
       s.city,
       s.rider_count,
       ROUND(quantile_cont(sh.orders, 0.95), 1)                 AS p95_orders_per_hour,
       ROUND(quantile_cont(sh.orders, 0.95) / s.rider_count, 2) AS p95_orders_per_rider
FROM store_hour sh
JOIN raw.stores s USING (store_id)
GROUP BY sh.store_id, s.city, s.rider_count
ORDER BY p95_orders_per_rider DESC;

-- Q3. Do customers come back? (monthly cohorts, M1 and M2 retention)
-- Caveats: the window starts in August, so the August cohort also holds pre-existing customers.
-- Retention shows NULL when that month has not happened yet, so it is never reported as 0%.
WITH bounds AS (
    SELECT DATE_TRUNC('month', MAX(order_date)) AS last_month
    FROM mart.order_facts
),
first_order AS (
    SELECT customer_id,
           DATE_TRUNC('month', MIN(order_date)) AS cohort_month
    FROM mart.order_facts
    WHERE status = 'delivered'
    GROUP BY customer_id
),
active AS (
    SELECT DISTINCT customer_id,
           DATE_TRUNC('month', order_date) AS active_month
    FROM mart.order_facts
    WHERE status = 'delivered'
)
SELECT f.cohort_month,
       COUNT(DISTINCT f.customer_id) AS cohort_size,
       CASE WHEN f.cohort_month + INTERVAL 1 MONTH <= b.last_month THEN
           ROUND(100.0 * COUNT(DISTINCT CASE WHEN DATEDIFF('month', f.cohort_month, a.active_month) = 1
                                             THEN a.customer_id END)
                 / COUNT(DISTINCT f.customer_id), 1)
       END AS m1_retention_pct,
       CASE WHEN f.cohort_month + INTERVAL 2 MONTH <= b.last_month THEN
           ROUND(100.0 * COUNT(DISTINCT CASE WHEN DATEDIFF('month', f.cohort_month, a.active_month) = 2
                                             THEN a.customer_id END)
                 / COUNT(DISTINCT f.customer_id), 1)
       END AS m2_retention_pct
FROM first_order f
CROSS JOIN bounds b
LEFT JOIN active a USING (customer_id)
GROUP BY f.cohort_month, b.last_month
ORDER BY f.cohort_month;

-- Q4. Which products go out of stock most, per store? (window ranking)
WITH stockouts AS (
    SELECT store_id,
           sku,
           COUNT(*) FILTER (WHERE stock_qty = 0) AS stockout_days,
           COUNT(*)                              AS days_tracked
    FROM raw.inventory_snapshots
    GROUP BY ALL
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY store_id ORDER BY stockout_days DESC) AS rnk
    FROM stockouts
)
SELECT store_id,
       sku,
       stockout_days,
       days_tracked,
       ROUND(100.0 * stockout_days / days_tracked, 1) AS stockout_pct
FROM ranked
WHERE rnk <= 2
ORDER BY store_id, rnk;

-- Q5. Which categories are bought together? (lift: >1 means affinity, ~1 means chance)
WITH cat_orders AS (
    SELECT DISTINCT oi.order_id, p.category
    FROM raw.order_items oi
    JOIN raw.products p USING (sku)
),
totals AS (
    SELECT COUNT(DISTINCT order_id) AS n_orders FROM cat_orders
),
freq AS (
    SELECT category, COUNT(DISTINCT order_id) AS n FROM cat_orders GROUP BY category
),
pairs AS (
    SELECT a.category AS cat_a, b.category AS cat_b, COUNT(*) AS together
    FROM cat_orders a
    JOIN cat_orders b ON a.order_id = b.order_id AND a.category < b.category
    GROUP BY 1, 2
)
SELECT p.cat_a,
       p.cat_b,
       p.together,
       ROUND((p.together * 1.0 / t.n_orders)
             / ((fa.n * 1.0 / t.n_orders) * (fb.n * 1.0 / t.n_orders)), 2) AS lift
FROM pairs p
CROSS JOIN totals t
JOIN freq fa ON fa.category = p.cat_a
JOIN freq fb ON fb.category = p.cat_b
ORDER BY lift DESC
LIMIT 8;
