-- ─────────────────────────────────────────
-- M3.1  Price band funnel
--       (fixed bands: Low <= $15, Medium <= $65, High above)
--       These thresholds were reverse-engineered from the existing
--       m3_price_bands.csv output, since no SQL file previously
--       existed anywhere in this project to generate it.
-- ─────────────────────────────────────────
SELECT
    CASE
        WHEN price <= 15 THEN 'Low'
        WHEN price <= 65 THEN 'Medium'
        ELSE 'High'
    END                                                          AS price_band,
    MIN(price)                                                   AS min_price,
    MAX(price)                                                   AS max_price,
    SUM(event_type = 'view')                                     AS views,
    SUM(event_type = 'cart')                                     AS carts,
    SUM(event_type = 'purchase')                                 AS purchases,
    ROUND(
        SUM(event_type = 'purchase') * 100.0
        / NULLIF(SUM(event_type = 'view'), 0), 2
    )                                                             AS view_to_purchase_pct,
    ROUND(
        SUM(event_type = 'cart') * 100.0
        / NULLIF(SUM(event_type = 'view'), 0), 2
    )                                                             AS view_to_cart_pct,
    ROUND(
        SUM(event_type = 'purchase') * 100.0
        / NULLIF(SUM(event_type = 'cart'), 0), 2
    )                                                             AS cart_to_purchase_pct
FROM events
GROUP BY price_band
ORDER BY min_price;


-- ─────────────────────────────────────────
-- M3.2  Price elasticity — purchases bucketed into 10 price deciles
--       (decile 1 = cheapest 10% of purchases, 10 = most expensive)
--       Same reverse-engineering note as M3.1 above.
-- ─────────────────────────────────────────
WITH purchase_deciles AS (
    SELECT
        price,
        NTILE(10) OVER (ORDER BY price) AS price_decile
    FROM events
    WHERE event_type = 'purchase'
)
SELECT
    price_decile,
    MIN(price)             AS decile_min,
    MAX(price)              AS decile_max,
    COUNT(*)                AS purchases,
    ROUND(SUM(price), 2)    AS total_revenue,
    ROUND(AVG(price), 2)    AS avg_price
FROM purchase_deciles
GROUP BY price_decile
ORDER BY price_decile;
