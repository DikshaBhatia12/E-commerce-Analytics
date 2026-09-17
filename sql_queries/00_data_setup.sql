-- ============================================================
-- STEP 1: CREATE DATABASE + EVENTS TABLE
-- Run this ONCE, before loading any data.
-- Why: This just sets up the empty structure. The actual data
--      load happens via python/load_raw_data.py instead of
--      LOAD DATA INFILE — that avoids MySQL's secure_file_priv
--      restrictions and hardcoded file paths, so this works the
--      same regardless of where the project is downloaded to.
-- ============================================================

CREATE DATABASE IF NOT EXISTS ecommerce_analytics;
USE ecommerce_analytics;

-- event_type is VARCHAR(20), not VARCHAR(10): the raw dataset's 4th
-- event type is "remove_from_cart" (16 characters), which VARCHAR(10)
-- can't hold. This project's queries only use view/cart/purchase, but
-- remove_from_cart rows still need to load without erroring.
CREATE TABLE IF NOT EXISTS events (
    event_time      DATETIME,
    event_type      VARCHAR(20),
    product_id      INT,
    category_id     BIGINT,
    category_code   VARCHAR(100),
    brand           VARCHAR(50),
    price           DECIMAL(10, 2),
    user_id         INT,
    user_session    VARCHAR(50)
);

-- ============================================================
-- NEXT STEP: LOAD THE DATA
-- Run this from a terminal, NOT in a SQL client:
--
--   1. Download the raw dataset:
--      https://data.rees46.com/datasets/marketplace/2019-Oct.csv.gz
--      https://data.rees46.com/datasets/marketplace/2019-Nov.csv.gz
--   2. Drop the .gz file(s) into data/raw/ (no need to unzip first)
--   3. pip install pandas mysql-connector-python
--   4. Edit DB_CONFIG at the top of python/load_raw_data.py to match
--      your MySQL login
--   5. python python/load_raw_data.py
--
-- Once that finishes, run 00b_indexes_and_validation.sql (NOT this
-- file again) to build indexes and confirm the load worked.
-- ============================================================
