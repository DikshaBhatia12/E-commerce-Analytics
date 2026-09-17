# E-Commerce User Behaviour Analytics
### Diagnosing a conversion and retention crisis across 88,000 users

> **Tools:** MySQL · Python · Power BI · pandas · seaborn

---

## The Business Problem

An e-commerce platform with 88,000+ monthly active users
and $1.68M in revenue is failing to convert browsers into
buyers — and failing to bring buyers back for a second purchase.

This project investigates:
- Where exactly the funnel breaks and why
- Which categories represent the highest recovery opportunity
- Why retention is near-zero and how to fix it
- Which customer segments drive disproportionate revenue

---

## Dashboard

**Page 1 — Executive Summary**
![Executive Summary](images/Executive%20summary%28Page%201%29.png)

**Page 2 — Funnel & Pricing**
![Funnel and Pricing](images/Funnel%20and%20pricing%28page%202%29.png)

**Page 3 — Retention & RFM**
![Retention and RFM](images/Retention%28Page%203%29.png)

🔗 [Open the Power BI file](dashboard/product_funnel.pbix)

---

## Key Findings

> ⚠️ **These findings reflect the original analysis run.** The data pipeline
> has since been corrected (see "How to Build This From Scratch" and Data
> Limitations below) — most notably, the way the 42M+ row dataset gets
> sampled down. That fix has **not yet been re-validated against a fresh
> end-to-end run of the real data**, so treat the specific numbers below as
> not-yet-reconfirmed until that happens. The methodology and direction of
> each finding are still reasonable; the exact percentages may move.

### 1. 93.2% of sessions never add to cart
101,061 of 108,458 sessions end without a single cart addition.
The bottleneck is at the view stage — not checkout.
Cart-to-purchase behaviour is healthy, meaning users with
buying intent follow through. This is a discovery problem,
not a checkout problem.

### 2. Month-1 retention is 1.2% vs 8–15% industry benchmark
Only 28 of 2,434 first-month buyers returned to purchase again
the following month. The platform has no meaningful re-engagement
mechanism. Fixing retention from 1.2% to 5% would compound revenue
growth beyond what funnel optimisation alone can achieve.

### 3. Notebooks (computers.notebook) — biggest single opportunity
16,916 views at a 1.0% conversion rate, against a platform-median
benchmark of 1.19% — high traffic with room to convert better.
Closing that gap alone represents an estimated **$14,782 in recoverable
revenue**, the largest upside of any category in the opportunity-sizing
analysis. (Smartphones, by contrast, are already a strong performer —
149,078 views at a 3.43% CVR, the platform's best-converting high-traffic
category — and are not a growth opportunity in this dataset.)

### 4. Champions generate 14.3% of revenue from 5.6% of users
268 Champion users average $1,793 revenue each.
Loyal customers generate the highest total revenue ($1.038M)
but Champions lead on per-user value.
These two segments require completely different retention strategies.

---

## Recommendations

| Priority | Recommendation | Metric it moves | Effort |
|---|---|---|---|
| 1 | Add social proof + bundle/upsell prompts to notebook category pages | View-to-cart CVR | Low |
| 2 | 3-email re-engagement sequence for Month-1 churned buyers | Month-1 retention | Medium |
| 3 | VIP programme for Champions segment | Champion retention rate | Low |
| 4 | Schedule promotions at peak conversion hour | Overall CVR | Low |
| 5 | SEO + marketing investment in niche high-CVR categories | Traffic volume | High |

**Revenue opportunity:** Targeting the 2,434 buyers in the churned
first-purchase cohort with a re-engagement campaign at 5% conversion =
~120 additional purchases × $300 AOV = **$36,000 recovered revenue
from a single campaign.**

---

## Project Structure

```
├── sql_queries/
│   ├── 00_data_setup.sql               # creates the database + empty table only
│   ├── 00b_indexes_and_validation.sql  # run once, after load_raw_data.py finishes
│   ├── 01_data_exploration.sql
│   ├── 02_funnel_analysis.sql
│   ├── 02b_price_bands_and_elasticity.sql  # M3 — previously missing entirely, see note below
│   ├── 03_category_performance.sql
│   ├── 04_cohort_retention.sql
│   └── 05_rfm_segmentation.sql
├── python/
│   ├── load_raw_data.py               # samples the raw Kaggle/REES46 files and loads them into MySQL
│   └── product_funnel_analysis.py     # reads the SQL output CSVs and draws the 7 charts
├── data/
│   ├── raw/                            # <- put the downloaded 2019-Oct / 2019-Nov files here (not committed)
│   └── *.csv                           # module outputs feeding the charts & dashboard
├── images/
│   ├── Executive summary(Page 1).png
│   ├── Funnel and pricing(page 2).png
│   ├── Retention(Page 3).png
│   └── python_charts/
│       ├── 01_funnel_waterfall.png
│       ├── 02_cohort_retention_heatmap.png
│       ├── 03_category_quadrant.png
│       ├── 04_rfm_segments.png
│       ├── 05_hourly_conversion.png
│       ├── 06_price_elasticity.png
│       └── 07_cart_abandonment.png
└── dashboard/
    └── product_funnel.pbix
```

---

## How to Build This From Scratch

This section is written so you can go from an empty folder to a working
dashboard with no prior context beyond "I have MySQL and Python installed."

### 1. Prerequisites
- MySQL 8.0+ (needed for window functions like `NTILE`, `ROW_NUMBER`) —
  MariaDB 10.2+ also works, since that's what this pipeline was tested against
- Python 3.9+
- ~20GB of free disk space (the two raw files total roughly 12-15GB
  compressed; loading and sampling needs headroom beyond that)

```bash
pip install pandas mysql-connector-python matplotlib seaborn numpy
```

### 2. Download the raw data
This project uses two consecutive months of the REES46 marketplace
clickstream dataset — the same dataset that's mirrored on Kaggle as
["eCommerce behavior data from multi-category store"](https://www.kaggle.com/datasets/mkechinov/ecommerce-behavior-data-from-multi-category-store).
You can download it either from the original host directly (no account
needed) or via Kaggle:

**Direct from the source (recommended, no account required):**
```
https://data.rees46.com/datasets/marketplace/2019-Oct.csv.gz
https://data.rees46.com/datasets/marketplace/2019-Nov.csv.gz
```

**Or via Kaggle**, if you'd rather use their file browser or CLI:
```bash
kaggle datasets download -d mkechinov/ecommerce-behavior-data-from-multi-category-store -f 2019-Oct.csv
kaggle datasets download -d mkechinov/ecommerce-behavior-data-from-multi-category-store -f 2019-Nov.csv
```

Either way, drop the downloaded file(s) into `data/raw/` at the project
root. **You don't need to unzip the `.gz` files first** — the loader
script below reads gzip-compressed CSVs directly.

Why both months: the cohort/retention analysis specifically measures
whether October buyers came back in November. One month alone can't
answer that question.

### 3. Create the database and table
```bash
mysql -u root -p < sql_queries/00_data_setup.sql
```
This creates the `ecommerce_analytics` database and the empty `events`
table. **Run this file exactly once** — it only builds the structure;
the data-loading step happens separately in the next step, and indexes
are built afterward in step 5 by a different file.

### 4. Load and sample the raw data
Open `python/load_raw_data.py` and edit the `DB_CONFIG` block near the
top to match your MySQL login (host/user/password). Then run:
```bash
python python/load_raw_data.py
```
This script:
- Finds whichever raw file(s) you placed in `data/raw/`
- Counts rows per user across the full 40M+ row files (without loading
  everything into memory at once)
- Randomly selects whole **users** (not individual rows) until it
  collects roughly 600,000 events total, so complete sessions and
  complete purchase histories are preserved (see Data Limitations below
  for why this matters)
- Inserts the sampled rows directly into MySQL over a normal database
  connection — no file-path or server permission setup required

Expect this to take a few minutes given the size of the raw files.

### 5. Build the indexes and validate the load
```bash
mysql -u root -p ecommerce_analytics < sql_queries/00b_indexes_and_validation.sql
```
This is a **separate file from step 3** on purpose — `CREATE INDEX`
isn't safe to run twice against the same table, so indexing is split
out into its own script that only ever needs to run once, right after
the load finishes. Check the validation output: total row count should
be close to 600,000 (not exact — see Data Limitations), and the
null-check query should show all zeros for the required fields.

### 6. Run the analysis queries
Run each file in order and export the result of each `SELECT` to the
matching CSV name in `data/` (e.g. the M2.2 result in
`02_funnel_analysis.sql` → `data/m2_session_funnel.csv`). Most SQL
clients (MySQL Workbench, DBeaver, etc.) let you right-click a result
grid and "Export to CSV."
```bash
mysql -u root -p ecommerce_analytics < sql_queries/01_data_exploration.sql
mysql -u root -p ecommerce_analytics < sql_queries/02_funnel_analysis.sql
mysql -u root -p ecommerce_analytics < sql_queries/02b_price_bands_and_elasticity.sql
mysql -u root -p ecommerce_analytics < sql_queries/03_category_performance.sql
mysql -u root -p ecommerce_analytics < sql_queries/04_cohort_retention.sql
mysql -u root -p ecommerce_analytics < sql_queries/05_rfm_segmentation.sql
```
Match each numbered query in the file's comments (M1.1, M1.2, ...) to
its corresponding CSV in `data/` — the filenames follow the same
numbering. **Note on `02b`:** this file (M3 — price bands and price
elasticity) didn't exist anywhere in the original project despite its
two output files (`m3_price_bands.csv`, `m3_price_elasticity.csv`)
being present in `data/` and required by the chart script below — it's
been reconstructed to match those files' existing structure exactly
and verified end-to-end.

### 7. Generate the charts
```bash
python python/product_funnel_analysis.py
```
This reads the CSVs from `data/` and writes 7 charts to
`images/python_charts/`. The script locates its own file path
automatically, so it works from any folder location.

### 8. Refresh the Power BI dashboard
Open `dashboard/product_funnel.pbix`, update the data source connection
to point at your local MySQL instance, and refresh. The three
dashboard pages pull from the same CSVs/tables built in the steps above.

---

## Technical Approach

### SQL (MySQL)
- Session-level funnel using CTEs and CASE WHEN
- Cohort retention with TIMESTAMPDIFF and DATE_FORMAT
- RFM segmentation using NTILE window functions
- Price elasticity via NTILE price decile bucketing
- Category opportunity sizing with revenue upside calculation
- Window functions: ROW_NUMBER, LAG, PERCENT_RANK

### Python
- pandas for data manipulation and sampling
- matplotlib + seaborn for 7 analytical charts
- Cohort heatmap, funnel waterfall, category quadrant scatter,
  RFM bubble chart, hourly conversion dual-axis,
  price elasticity curve, cart abandonment chart
- Script uses paths relative to its own location, so it runs on
  any machine with no manual edits — just `python python/product_funnel_analysis.py`

### Power BI
- 3-page interactive dashboard
- Live DAX measures responding to category, month, price slicers
- Cohort retention matrix with conditional colour formatting
- Cross-filtering across all visuals from events table

---

## Dataset

| Field | Detail |
|---|---|
| Source | [REES46 marketplace clickstream data](https://data.rees46.com/datasets/marketplace/) — also mirrored on [Kaggle](https://www.kaggle.com/datasets/mkechinov/ecommerce-behavior-data-from-multi-category-store) as "eCommerce behavior data from multi-category store" |
| Raw files used | `2019-Oct.csv.gz` and `2019-Nov.csv.gz` (~42M and ~67M rows respectively before sampling) |
| Sample size | ~600,000 events, sampled by user (see "How to Build This From Scratch," step 4) |
| Columns | event_time, event_type, product_id, category_id, category_code, brand, price, user_id, user_session |
| Event types | view, cart, purchase (the raw files also contain a 4th type, `remove_from_cart`, which this project's queries don't currently use) |
| Time span | Two consecutive months of clickstream activity (October–November 2019) |

---

## Data Limitations

- Hourly analysis covers roughly a third of the day due to sampling distribution
- Cohort analysis limited to a first-purchase month and the following month
- `cart_to_purchase_pct` excluded — sampling artifact caused
  purchase events to outnumber cart events
- 600K sample from 42M+ rows — findings are directionally
  valid, percentages may shift ±1–2% on the full dataset
- RFM scores based on a 2-month window vs the recommended 12 months
- **RFM segment rule-order bug (fixed in code, not yet re-run):** the original
  `CASE` statement in `05_rfm_segmentation.sql` checked broader conditions
  before narrower ones, so two segments — "Cannot lose them" and "Needs
  attention" — could never actually be assigned; every user who should have
  landed there was caught by an earlier, looser rule first. The SQL has been
  corrected (narrower conditions now checked first, and "Needs attention" has
  a genuine, reachable definition), but the CSVs/dashboard in this repo still
  reflect the original 5-segment output. Re-running `05_rfm_segmentation.sql`
  against the raw data will split some users currently shown under "At-risk"
  and "Loyal customers" into these two segments instead.
- **Sampling method corrected, not yet re-run:** the original sample was
  built by randomly selecting individual *rows* out of the 42M+ row dataset.
  Because this is clickstream data (one session can contain 10-20+ rows),
  row-level sampling can silently break sessions apart — a user who
  genuinely purchased in two different months could easily have one of
  those purchase rows fail to survive the random sample, making real
  repeat customers look like one-time buyers. This is a plausible
  contributor to the unusually low 1.2% month-1 retention figure above.
  `load_raw_data.py` now samples whole users instead, so every selected
  user's full session and purchase history is preserved intact. This has
  been tested end-to-end against synthetic data and runs without errors,
  but has not yet been run against the real dataset — so the Key Findings
  above should be treated as pending reconfirmation, not final.
- **Median vs. average, fixed:** the opportunity-sizing query
  (`03_category_performance.sql`, M4.2) was labeled and commented as using
  a "median" conversion-rate benchmark but was actually computing a plain
  average — the two can differ meaningfully when a few categories have
  unusually high or low conversion. This now computes a genuine median.

---

## Possible Next Steps

Ideas worth exploring if this project gets a v2:
- **Streamlit/Plotly Dash app** — a lightweight interactive version of the
  funnel + RFM views that doesn't require Power BI Desktop to explore
- **Market-basket / cross-sell analysis** — which categories get bought together,
  to turn "opportunity" categories into bundle recommendations
- **Cohort forecasting** — project what Month-1 retention would need to be to
  hit a target LTV, rather than just reporting the current 1.2%
- **Drop:** the hourly-conversion view could be folded into the Funnel & Pricing
  page as a toggle instead of a separate chart, since it's a secondary insight
- **Re-run the full pipeline** against the real 2019-Oct + 2019-Nov data with
  the corrected sampling method and RFM logic, then update Key Findings above
  with the reconfirmed numbers

---

## Author

**Diksha Bhatia**
