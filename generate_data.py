"""Generate synthetic quick-commerce data: 12 dark stores, 90 days, ~40k orders.

Planted realism:
- Demand peaks at lunch and 7-10 pm, with weekend and growth uplift.
- Delivery time = dispatch lag + travel + an overload penalty when a store
  gets more orders in an hour than its riders can absorb.
- Perishables stock out more often than shelf-stable goods.
- Some products are bought together (milk -> bread, chips -> cola).
"""
from pathlib import Path

import numpy as np
import pandas as pd

rng = np.random.default_rng(42)
OUT = Path("data/raw")
OUT.mkdir(parents=True, exist_ok=True)
START, DAYS = pd.Timestamp("2026-08-01"), 90
PROMISED_MINUTES = 10

# ---------- stores
stores = []
for city, n in {"Bhopal": 4, "Indore": 4, "Jabalpur": 2, "Gwalior": 2}.items():
    for i in range(1, n + 1):
        stores.append({
            "store_id": f"{city[:3].upper()}-{i:02d}",
            "city": city,
            "opened_on": START - pd.Timedelta(days=int(rng.integers(90, 600))),
            "rider_count": int(rng.integers(6, 14)),
        })
stores = pd.DataFrame(stores)

# ---------- products
products = pd.DataFrame([
    ("P001", "Toned Milk 1L", "Dairy", 68, True, 3),
    ("P002", "Paneer 200g", "Dairy", 95, True, 1),
    ("P003", "Curd 400g", "Dairy", 45, True, 2),
    ("P004", "Bread Loaf", "Bakery", 45, True, 2),
    ("P005", "Eggs (6 pack)", "Dairy", 72, True, 2),
    ("P006", "Instant Noodles 70g", "Packaged", 14, False, 3),
    ("P007", "Potato Chips", "Snacks", 20, False, 3),
    ("P008", "Cola 750ml", "Beverages", 40, False, 2),
    ("P009", "Mineral Water 1L", "Beverages", 20, False, 2),
    ("P010", "Atta 5kg", "Staples", 260, False, 1),
    ("P011", "Toor Dal 1kg", "Staples", 165, False, 1),
    ("P012", "Onion 1kg", "Fresh", 40, True, 3),
    ("P013", "Tomato 1kg", "Fresh", 35, True, 3),
    ("P014", "Banana Dozen", "Fresh", 60, True, 2),
    ("P015", "Ice Cream Tub 500ml", "Frozen", 180, True, 1),
], columns=["sku", "product_name", "category", "unit_price", "is_perishable", "pop_weight"])
prod_p = products.pop_weight / products.pop_weight.sum()
prices = products.set_index("sku").unit_price

# ---------- customers (heavy-tailed activity: a few very frequent buyers)
N_CUST = 6000
customers = pd.DataFrame({
    "customer_id": [f"C{i:05d}" for i in range(1, N_CUST + 1)],
    "signup_date": START + pd.to_timedelta(rng.integers(-180, DAYS, N_CUST), unit="D"),
    "acquisition_channel": rng.choice(
        ["organic", "paid_social", "referral", "push_campaign"], N_CUST, p=[.4, .3, .2, .1]),
})
activity = rng.gamma(0.4, 1.0, N_CUST)

# ---------- orders
HOUR_W = np.array([1, .5, .2, .1, .1, .2, .5, 1, 1.2, 1, 1, 1.4, 2.5, 2.2, 1.4, 1.2,
                   1.3, 1.6, 2.2, 3.2, 3.6, 3.4, 2.6, 1.6])
HOUR_P = HOUR_W / HOUR_W.sum()
sku_ids = products.sku.to_numpy()
signup = customers.signup_date.to_numpy()
cust_ids = customers.customer_id.to_numpy()
store_ids = stores.store_id.to_numpy()
store_p = rng.uniform(0.5, 1.6, len(store_ids))  # some stores are busier than others
store_p = store_p / store_p.sum()

orders, items = [], []
for d in range(DAYS):
    day = START + pd.Timedelta(days=d)
    eligible = np.flatnonzero(signup <= np.datetime64(day))
    w = activity[eligible] / activity[eligible].sum()
    weekend = 1.25 if day.dayofweek >= 5 else 1.0
    n_orders = rng.poisson(420 * weekend * (1 + 0.004 * d))
    chosen = rng.choice(eligible, size=n_orders, p=w)
    picks = rng.choice(store_ids, size=n_orders, p=store_p)
    for k, ci in enumerate(chosen):
        oid = f"O{len(orders) + 1:07d}"
        placed = day + pd.Timedelta(hours=int(rng.choice(24, p=HOUR_P)),
                                    minutes=int(rng.integers(0, 60)))
        store = picks[k]
        status = "cancelled" if rng.random() < 0.04 else "delivered"
        orders.append((oid, cust_ids[ci], store, placed, status))

        k = int(rng.integers(1, 5))
        skus = set(rng.choice(sku_ids, size=k, replace=False, p=prod_p))
        if "P001" in skus and rng.random() < 0.35:
            skus.add("P004")  # milk -> bread affinity
        if "P007" in skus and rng.random() < 0.30:
            skus.add("P008")  # chips -> cola affinity
        for sku in skus:
            items.append((oid, sku, int(rng.integers(1, 4)), float(prices[sku])))

orders = pd.DataFrame(orders, columns=["order_id", "customer_id", "store_id", "placed_at", "status"])
order_items = pd.DataFrame(items, columns=["order_id", "sku", "qty", "unit_price"])

# ---------- deliveries (store-hour load drives overload delay)
orders["hour_bucket"] = orders.placed_at.dt.floor("h")
load = orders.groupby(["store_id", "hour_bucket"]).order_id.transform("count").to_numpy()
rc = orders.store_id.map(stores.set_index("store_id").rider_count).to_numpy()
n = len(orders)
lag = rng.uniform(1, 4, n)
travel = rng.lognormal(np.log(5.5), 0.3, n)
overload = 1.5 * np.maximum(0, load - rc / 3)
placed = orders.placed_at.to_numpy()
delivered_flag = (orders.status == "delivered").to_numpy()
riders = rng.integers(1, rc + 1)

deliveries = pd.DataFrame({
    "order_id": orders.order_id[delivered_flag],
    "rider_id": orders.store_id[delivered_flag] + "-R" + pd.Series(riders[delivered_flag]).astype(str).str.zfill(2).to_numpy(),
    "dispatched_at": pd.to_datetime(placed[delivered_flag]) + pd.to_timedelta(lag[delivered_flag], unit="m"),
    "delivered_at": pd.to_datetime(placed[delivered_flag])
    + pd.to_timedelta((lag + travel + overload)[delivered_flag], unit="m"),
    "promised_minutes": PROMISED_MINUTES,
})
deliveries["delivered_at"] = deliveries.delivered_at.dt.round("s")
deliveries["dispatched_at"] = deliveries.dispatched_at.dt.round("s")

# ---------- daily inventory snapshots (perishables stock out more)
dates = pd.date_range(START, periods=DAYS, freq="D")
inv = pd.MultiIndex.from_product([dates, store_ids, sku_ids],
                                 names=["snapshot_date", "store_id", "sku"]).to_frame(index=False)
perish = inv.sku.map(products.set_index("sku").is_perishable).to_numpy()
stock = rng.poisson(np.where(perish, 12, 25))
stock[rng.random(len(inv)) < np.where(perish, 0.08, 0.02)] = 0
inv["stock_qty"] = stock

# ---------- write CSVs
customers_out = customers.drop(columns=[]).copy()
orders_out = orders.drop(columns=["hour_bucket"])
stores.to_csv(OUT / "stores.csv", index=False)
products.drop(columns=["pop_weight"]).to_csv(OUT / "products.csv", index=False)
customers_out.to_csv(OUT / "customers.csv", index=False)
orders_out.to_csv(OUT / "orders.csv", index=False)
order_items.to_csv(OUT / "order_items.csv", index=False)
deliveries.to_csv(OUT / "deliveries.csv", index=False)
inv.to_csv(OUT / "inventory_snapshots.csv", index=False)

print(f"orders={len(orders):,} items={len(order_items):,} deliveries={len(deliveries):,} "
      f"inventory_rows={len(inv):,}")
