-- ============================================================
-- Run this ONCE, after python/load_raw_data.py has finished.
-- (Split out from 00_data_setup.sql so CREATE INDEX never
-- accidentally runs twice against the same table.)
-- ============================================================

USE ecommerce_analytics;

-- ─────────────────────────────────────────
-- INDEXES
-- ─────────────────────────────────────────

CREATE INDEX idx_event_type  ON events (event_type);
CREATE INDEX idx_session     ON events (user_session);   -- session-level funnel joins on this
CREATE INDEX idx_user        ON events (user_id);         -- cohort analysis groups by user
CREATE INDEX idx_category    ON events (category_code);   -- category analysis
CREATE INDEX idx_time        ON events (event_time);       -- time-based analysis

-- ─────────────────────────────────────────
-- VALIDATION
-- ─────────────────────────────────────────

-- 1. total rows — should be close to 600,000, but not exact.
--    (load_raw_data.py samples whole USERS, not individual rows, so the
--    final count depends on how many events each selected user happens
--    to have — see the script's docstring for why.)
SELECT COUNT(*) AS total_rows FROM events;

-- 2. event type distribution — should show view, cart, purchase
--    (the raw files also contain remove_from_cart rows, which is
--    expected — no query in this project currently uses that type)
SELECT event_type, COUNT(*) AS cnt,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct
FROM events
GROUP BY event_type;

-- 3. date range — should span Oct-Nov 2019
SELECT MIN(event_time) AS earliest, MAX(event_time) AS latest FROM events;

-- 4. null check — event_time/event_type/product_id/price/user_id/
--    user_session should all be 0; category_code and brand can be
--    non-zero, that's expected in the source data
SELECT
    SUM(event_time    IS NULL) AS null_event_time,
    SUM(event_type    IS NULL) AS null_event_type,
    SUM(product_id    IS NULL) AS null_product_id,
    SUM(price         IS NULL) AS null_price,
    SUM(user_id       IS NULL) AS null_user_id,
    SUM(user_session  IS NULL) AS null_session
FROM events;

-- 5. price sanity check — min should be > 0, max should be reasonable
SELECT
    MIN(price) AS min_price,
    MAX(price) AS max_price,
    ROUND(AVG(price), 2) AS avg_price
FROM events
WHERE event_type = 'purchase';

-- 6. unique counts — rough sense of scale
SELECT
    COUNT(DISTINCT user_id)       AS unique_users,
    COUNT(DISTINCT product_id)    AS unique_products,
    COUNT(DISTINCT user_session)  AS unique_sessions,
    COUNT(DISTINCT category_code) AS unique_categories
FROM events;

-- 7. top 5 categories by volume
SELECT category_code, COUNT(*) AS events
FROM events
WHERE category_code IS NOT NULL AND category_code != ''
GROUP BY category_code
ORDER BY events DESC
LIMIT 5;
