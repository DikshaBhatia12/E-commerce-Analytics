-- ─────────────────────────────────────────
-- M4.1  Category funnel — full conversion metrics
-- ─────────────────────────────────────────
SELECT
    category_code,
    SUM(event_type = 'view')                                    AS views,
    SUM(event_type = 'cart')                                    AS carts,
    SUM(event_type = 'purchase')                                AS purchases,
    ROUND(SUM(price * (event_type = 'purchase')), 2)            AS revenue,
    ROUND(
        SUM(event_type = 'cart') * 100.0
        / NULLIF(SUM(event_type = 'view'), 0), 2
    )                                                           AS view_to_cart_pct,
    ROUND(
        SUM(event_type = 'purchase') * 100.0
        / NULLIF(SUM(event_type = 'view'), 0), 2
    )                                                           AS view_to_purchase_pct,
    ROUND(
        SUM(event_type = 'purchase') * 100.0
        / NULLIF(SUM(event_type = 'cart'), 0), 2
    )                                                           AS cart_to_purchase_pct,
    ROUND(
        SUM(price * (event_type = 'purchase'))
        / NULLIF(SUM(event_type = 'view'), 0), 4
    )                                                           AS revenue_per_view
FROM events
WHERE category_code IS NOT NULL AND TRIM(category_code) != ''
GROUP BY category_code
HAVING views >= 100
ORDER BY views DESC;


-- ─────────────────────────────────────────
-- M4.2  Opportunity sizing
--       (if each category hit the median conversion rate,
--        how much extra revenue would be generated?)
--
--       FIX: the benchmark below used to be AVG(conversion_rate)
--       while being labeled/commented as a "median" — a plain
--       average and a median can differ a lot when a few
--       categories have unusually high or low conversion rates.
--       This version computes an actual median using the same
--       ROW_NUMBER technique already used for prices in
--       01_data_exploration.sql (M1.3), so the label now matches
--       the calculation.
-- ─────────────────────────────────────────
WITH category_metrics AS (
    SELECT
        category_code,
        SUM(event_type = 'view')                                AS views,
        SUM(event_type = 'purchase')                            AS purchases,
        ROUND(SUM(price * (event_type = 'purchase')), 2)        AS revenue,
        ROUND(AVG(CASE WHEN event_type = 'purchase'
                       THEN price END), 2)                      AS avg_purchase_price,
        SUM(event_type = 'purchase') * 1.0
        / NULLIF(SUM(event_type = 'view'), 0)                   AS conversion_rate
    FROM events
    WHERE category_code IS NOT NULL AND TRIM(category_code) != ''
    GROUP BY category_code
    HAVING views >= 100
),
ranked AS (
    SELECT
        conversion_rate,
        ROW_NUMBER() OVER (ORDER BY conversion_rate)      AS rn,
        COUNT(*)     OVER ()                              AS total
    FROM category_metrics
),
benchmark AS (
    SELECT AVG(conversion_rate) AS median_cvr
    FROM ranked
    WHERE rn IN (FLOOR((total + 1) / 2), CEIL((total + 1) / 2))
)
SELECT
    m.category_code,
    m.views,
    m.purchases,
    ROUND(m.conversion_rate * 100, 2)                           AS current_cvr_pct,
    ROUND(b.median_cvr * 100, 2)                                AS benchmark_cvr_pct,
    m.revenue                                                   AS current_revenue,
    -- if this category hit benchmark CVR, how many extra purchases?
    ROUND(
        (b.median_cvr - m.conversion_rate) * m.views
    )                                                           AS potential_extra_purchases,
    -- revenue upside
    ROUND(
        (b.median_cvr - m.conversion_rate)
        * m.views
        * m.avg_purchase_price, 2
    )                                                           AS revenue_upside
FROM category_metrics m
CROSS JOIN benchmark b
WHERE m.conversion_rate < b.median_cvr       -- only underperformers
ORDER BY revenue_upside DESC;


-- ─────────────────────────────────────────
-- M4.3  Category quadrant classification
--       High/Low traffic × High/Low conversion
--       This is what you'll visualise as a scatter in Power BI
--
--       NOTE: this one is correctly labeled avg_views/avg_cvr —
--       it genuinely computes an average, not a median, and the
--       naming already matched the math. No change needed here.
-- ─────────────────────────────────────────
WITH category_metrics AS (
    SELECT
        category_code,
        SUM(event_type = 'view')                                AS views,
        SUM(event_type = 'purchase') * 100.0
        / NULLIF(SUM(event_type = 'view'), 0)                   AS cvr
    FROM events
    WHERE category_code IS NOT NULL AND TRIM(category_code) != ''
    GROUP BY category_code
    HAVING views >= 100
),
medians AS (
    SELECT
        AVG(views) AS avg_views,
        AVG(cvr)   AS avg_cvr
    FROM category_metrics
)
SELECT
    c.category_code,
    c.views,
    ROUND(c.cvr, 2)                                             AS conversion_rate_pct,
    CASE
        WHEN c.views >= m.avg_views AND c.cvr >= m.avg_cvr
            THEN 'Star — high traffic, high CVR'
        WHEN c.views >= m.avg_views AND c.cvr < m.avg_cvr
            THEN 'Opportunity — high traffic, low CVR'
        WHEN c.views < m.avg_views  AND c.cvr >= m.avg_cvr
            THEN 'Niche — low traffic, high CVR'
        ELSE
            'Underdog — low traffic, low CVR'
    END                                                         AS quadrant
FROM category_metrics c
CROSS JOIN medians m
ORDER BY c.views DESC;
