CREATE OR REPLACE VIEW mart.order_facts AS
WITH basket AS (
    SELECT order_id,
           SUM(qty)              AS units,
           SUM(qty * unit_price) AS gross_value
    FROM raw.order_items
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.customer_id,
    o.store_id,
    s.city,
    o.placed_at,
    CAST(o.placed_at AS DATE)                        AS order_date,
    EXTRACT(hour FROM o.placed_at)                   AS order_hour,
    o.status,
    b.units,
    b.gross_value,
    d.rider_id,
    date_diff('minute', o.placed_at, d.delivered_at) AS actual_minutes,
    d.promised_minutes,
    date_diff('minute', o.placed_at, d.delivered_at) > d.promised_minutes AS sla_breached
FROM raw.orders o
JOIN raw.stores s          USING (store_id)
LEFT JOIN basket b         USING (order_id)
LEFT JOIN raw.deliveries d USING (order_id);

CREATE OR REPLACE TABLE mart.store_daily AS
SELECT
    store_id,
    city,
    order_date,
    COUNT(*) FILTER (WHERE status = 'delivered')                      AS delivered_orders,
    COUNT(*) FILTER (WHERE status = 'cancelled')                      AS cancelled_orders,
    ROUND(AVG(actual_minutes) FILTER (WHERE status = 'delivered'), 1) AS avg_delivery_min,
    ROUND(100.0 * AVG(CASE WHEN sla_breached THEN 1 ELSE 0 END)
          FILTER (WHERE status = 'delivered'), 2)                     AS sla_breach_pct,
    ROUND(SUM(gross_value) FILTER (WHERE status = 'delivered'), 2)    AS gmv
FROM mart.order_facts
GROUP BY ALL;
