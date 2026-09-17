#!/usr/bin/env python
"""
load_raw_data.py
=================
Drop the raw Kaggle "eCommerce behavior data" CSV(s) into data/raw/,
then run this script from anywhere. It will:

  1. Find every CSV sitting in data/raw/
  2. Sample whole USERS (not individual rows) until roughly
     TARGET_SAMPLE_SIZE total events are collected
  3. Load them straight into the MySQL `events` table

No hardcoded file paths, no LOAD DATA INFILE, no secure_file_priv
headaches. This works the same regardless of where you clone/download
the project, as long as the raw CSV(s) are placed in data/raw/.

WHY SAMPLE BY USER AND NOT BY ROW:
This is clickstream data — a single session can contain 10-20+ rows
(views, then a cart add, then a purchase). If you randomly pick
individual ROWS at a ~1.4% rate (600K out of 42M+), most sessions lose
almost all of their events independently, which silently breaks every
session-level and repeat-purchase metric downstream (a user who
genuinely bought twice can easily have one of those purchase rows
simply not survive the sample, making them look like a one-time buyer).
Sampling whole users instead keeps every row for anyone selected, so
their session structure and purchase history stay intact — the numbers
this project computes (funnel, cohort retention, RFM, purchase
frequency) actually mean what they claim to mean.

One consequence: because we keep or drop entire users rather than
picking an exact row count, the final total will be CLOSE to
TARGET_SAMPLE_SIZE but not exactly equal to it — that's expected.

Source dataset:
https://www.kaggle.com/datasets/mkechinov/ecommerce-behavior-data-from-multi-category-store
(The Kaggle download comes as separate monthly files, e.g. "2019-Oct.csv" —
you can drop one or several into data/raw/, this script handles either.)

One-time setup:
    pip install pandas mysql-connector-python --break-system-packages
    Edit the DB_CONFIG block below to match your local MySQL login.
    Run 00_data_setup.sql first (creates the database + events table).

Usage:
    python python/load_raw_data.py
"""

import glob
import random
import sys
from collections import defaultdict
from pathlib import Path

import pandas as pd
import mysql.connector
from mysql.connector import Error

# ─────────────────────────────────────────
# CONFIG — the two things you may need to edit
# ─────────────────────────────────────────

# Paths are relative to THIS script's own location, not your current
# folder or the OS — so it works no matter where the project sits.
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
RAW_DIR = PROJECT_ROOT / "data" / "raw"

TARGET_SAMPLE_SIZE = 600_000   # matches the published analysis
RANDOM_SEED = 42               # fixed seed -> same sample every time you run this

DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "YOUR_PASSWORD_HERE",   # <-- change this
    "database": "ecommerce_analytics",
}

CHUNK_SIZE = 200_000  # rows read into memory at a time, safe for multi-GB raw files

EXPECTED_COLUMNS = [
    "event_time", "event_type", "product_id", "category_id",
    "category_code", "brand", "price", "user_id", "user_session",
]


def find_raw_files():
    files = sorted(glob.glob(str(RAW_DIR / "*.csv"))) + sorted(glob.glob(str(RAW_DIR / "*.csv.gz")))
    if not files:
        sys.exit(
            f"\nNo CSV files found in:\n  {RAW_DIR}\n\n"
            f"Download 2019-Oct.csv.gz and 2019-Nov.csv.gz and drop them there "
            f"(no need to unzip them first — this script reads .gz directly), "
            f"then re-run this script."
        )
    print(f"Found {len(files)} raw file(s) in {RAW_DIR}:")
    for f in files:
        print(f"  - {Path(f).name}")
    return files


def count_rows_per_user(files):
    """
    PASS 1: stream through every raw file just to count how many rows
    belong to each user_id. We only load the user_id column, so this
    is cheap even on multi-GB files.
    """
    print("\nPass 1/2 — counting rows per user (can take a minute)...")
    user_counts = defaultdict(int)

    for f in files:
        print(f"  Scanning {Path(f).name}...")
        for chunk in pd.read_csv(f, usecols=["user_id"], chunksize=CHUNK_SIZE):
            vc = chunk["user_id"].value_counts()
            for uid, cnt in vc.items():
                user_counts[uid] += int(cnt)

    total_rows = sum(user_counts.values())
    total_users = len(user_counts)
    if total_rows == 0 or total_users == 0:
        sys.exit("Raw file(s) appear to be empty or missing a user_id column.")

    print(f"  Total raw rows: {total_rows:,}  |  Total unique users: {total_users:,}")
    return user_counts, total_rows


def choose_users_to_keep(user_counts):
    """
    Randomly shuffles all user_ids (fixed seed = reproducible), then
    keeps adding whole users until we're at/near TARGET_SAMPLE_SIZE
    total rows. Every kept user contributes ALL of their rows — no
    row-level sampling — so sessions and purchase histories stay
    intact for anyone selected.
    """
    all_users = list(user_counts.keys())
    rng = random.Random(RANDOM_SEED)
    rng.shuffle(all_users)

    selected_users = set()
    rows_so_far = 0
    for uid in all_users:
        if rows_so_far >= TARGET_SAMPLE_SIZE:
            break
        selected_users.add(uid)
        rows_so_far += user_counts[uid]

    print(
        f"  Selected {len(selected_users):,} users "
        f"-> approximately {rows_so_far:,} rows "
        f"(target was {TARGET_SAMPLE_SIZE:,})"
    )
    return selected_users


def extract_selected_users(files, selected_users):
    """
    PASS 2: stream through the raw file(s) again, this time keeping
    every row that belongs to a selected user.
    """
    print("\nPass 2/2 — extracting all rows for selected users...")
    collected_chunks = []
    rows_collected = 0

    for f in files:
        print(f"  Reading {Path(f).name}...")
        for chunk in pd.read_csv(f, chunksize=CHUNK_SIZE):
            filtered = chunk[chunk["user_id"].isin(selected_users)]
            if not filtered.empty:
                collected_chunks.append(filtered)
                rows_collected += len(filtered)

    if not collected_chunks:
        sys.exit("No rows matched the selected users — something went wrong.")

    df = pd.concat(collected_chunks, ignore_index=True)
    print(f"\nFinal sample size: {len(df):,} rows from {len(selected_users):,} users")
    return df


def sample_raw_files(files):
    user_counts, _ = count_rows_per_user(files)
    selected_users = choose_users_to_keep(user_counts)
    return extract_selected_users(files, selected_users)


def clean_for_mysql(df):
    missing = set(EXPECTED_COLUMNS) - set(df.columns)
    if missing:
        sys.exit(f"Raw file is missing expected columns: {missing}")

    df = df[EXPECTED_COLUMNS].copy()

    # Kaggle's export looks like "2019-10-01 00:00:00 UTC". MySQL's
    # DATETIME type doesn't store timezone info, so parse it then drop
    # the timezone rather than leaving the literal "UTC" text in there.
    df["event_time"] = pd.to_datetime(df["event_time"], utc=True).dt.tz_localize(None)

    # category_code / brand / user_session are genuinely blank for some
    # rows in the source data — store real NULLs, not the string "nan".
    for col in ["category_code", "brand", "user_session"]:
        df[col] = df[col].where(df[col].notna(), None)

    return df


def load_to_mysql(df):
    print("\nConnecting to MySQL...")
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
    except Error as e:
        sys.exit(
            f"Could not connect to MySQL — check the DB_CONFIG block "
            f"at the top of this script.\n{e}"
        )

    cursor = conn.cursor()

    insert_sql = """
        INSERT INTO events
            (event_time, event_type, product_id, category_id,
             category_code, brand, price, user_id, user_session)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
    """

    rows = [tuple(row) for row in df.itertuples(index=False, name=None)]

    print(f"Inserting {len(rows):,} rows into `events` (this may take a minute)...")
    batch_size = 5000
    for i in range(0, len(rows), batch_size):
        cursor.executemany(insert_sql, rows[i:i + batch_size])
        conn.commit()
        done = min(i + batch_size, len(rows))
        print(f"  {done:,} / {len(rows):,} rows inserted", end="\r")

    print(f"\nDone — {len(rows):,} rows loaded into ecommerce_analytics.events")
    cursor.close()
    conn.close()


if __name__ == "__main__":
    raw_files = find_raw_files()
    sampled_df = sample_raw_files(raw_files)
    clean_df = clean_for_mysql(sampled_df)
    load_to_mysql(clean_df)
