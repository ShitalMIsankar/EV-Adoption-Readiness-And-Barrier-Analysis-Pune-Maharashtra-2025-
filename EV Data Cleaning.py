"""
EV Data Pipeline: Extract -> Explore -> Clean -> Validate -> Load (MySQL)

Datasets (expected in ./datasets/):
    01_survey_responses.csv
    02_barrier_responses.csv
    04_charging_stations_pune.csv
    06_statewise_ev_sales.csv

Setup:
    pip install pandas numpy sqlalchemy pymysql

MySQL credentials are read from environment variables (never hard-code a password):
    MYSQL_HOST (default localhost), MYSQL_PORT (default 3306),
    MYSQL_USER (default root), MYSQL_PASSWORD, MYSQL_DB (default ev_analytics)
"""

import os
import re
import sys
from datetime import datetime
from urllib.parse import quote_plus

import numpy as np
import pandas as pd

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────
INPUT_DIR = "./datasets/"
OUTPUT_DIR = "./cleaned/"
LOG_FILE = "./cleaning_log.csv"

FILES = {
    "survey_responses":   "01_survey_responses.csv",
    "barrier_responses":  "02_barrier_responses.csv",
    "charging_stations":  "04_charging_stations_pune.csv",
    "statewise_ev_sales": "06_statewise_ev_sales.csv",
}

MYSQL = {
    "host":     os.getenv("MYSQL_HOST", "localhost"),
    "port":     os.getenv("MYSQL_PORT", "3306"),
    "user":     os.getenv("MYSQL_USER", "root"),
    "password": os.getenv("MYSQL_PASSWORD", ""),
    "database": os.getenv("MYSQL_DB", "ev_analytics"),
}

os.makedirs(OUTPUT_DIR, exist_ok=True)

log_entries = []


def log(dataset, column, issue, action, outcome):
    """Record one cleaning action in the audit trail."""
    log_entries.append({
        "Timestamp":    datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "Dataset":      dataset,
        "Column":       column,
        "Issue_Found":  issue,
        "Action_Taken": action,
        "Outcome":      outcome,
        "Tool":         "Python (Pandas)",
    })
    print(f"  [LOG] {dataset} | {column} | {action}")


def header(title):
    print("\n" + "=" * 60)
    print(title)
    print("=" * 60)


# ─────────────────────────────────────────────────────────────────────────────
# STAGE 1: DATA EXTRACTION
# ─────────────────────────────────────────────────────────────────────────────
def extract():
    header("STAGE 1: DATA EXTRACTION")
    raw = {}
    for name, filename in FILES.items():
        path = os.path.join(INPUT_DIR, filename)
        if not os.path.exists(path):
            sys.exit(f"  ERROR: file not found -> {path}")
        raw[name] = pd.read_csv(path)
        print(f"  Loaded {name:<20} {len(raw[name]):>6} rows, {raw[name].shape[1]} columns")
    return raw


# ─────────────────────────────────────────────────────────────────────────────
# STAGE 2: DATA EXPLORATION (read-only, nothing is changed)
# ─────────────────────────────────────────────────────────────────────────────
def explore(raw):
    header("STAGE 2: DATA EXPLORATION")
    for name, df in raw.items():
        print(f"\n--- {name} ---")
        print(f"  Shape            : {df.shape}")
        print(f"  Duplicate rows   : {df.duplicated().sum()}")
        print(f"  Fully empty rows : {df.isna().all(axis=1).sum()}")

        nulls = df.isna().sum()
        nulls = nulls[nulls > 0]
        if nulls.empty:
            print("  Missing values   : none")
        else:
            print("  Missing values per column:")
            for col, n in nulls.items():
                print(f"    {col:<30} {n:>5}  ({n / len(df) * 100:.1f}%)")

        print("  Data types:")
        for col, dtype in df.dtypes.items():
            print(f"    {col:<30} {dtype}")

        # Unique values for low-cardinality text columns (spot typos/mixed formats)
        for col in df.select_dtypes("object").columns:
            if df[col].nunique() <= 12:
                print(f"  Unique values in '{col}': {sorted(df[col].dropna().unique().tolist())}")

        num_cols = df.select_dtypes("number")
        if not num_cols.empty:
            print("  Numeric summary:")
            print(num_cols.describe().round(2).to_string())


# ─────────────────────────────────────────────────────────────────────────────
# STAGE 3: DATA CLEANING
# ─────────────────────────────────────────────────────────────────────────────

# ---- 3.1 survey_responses ---------------------------------------------------
INCOME_MAP = {
    r"below\s*3":        "Below Rs3L",
    r"3\s*[-–]\s*6":     "Rs3L-6L",
    r"6\s*[-–]\s*10":    "Rs6L-10L",
    r"10\s*[-–]\s*15":   "Rs10L-15L",
    r"above\s*15|15\+":  "Above Rs15L",
}

AREA_CORRECTIONS = {
    "hadpsar":     "Hadapsar",
    "hinjawadi":   "Hinjewadi",
    "hinjwadi":    "Hinjewadi",
    "pimpari":     "Pimpri-Chinchwad",
    "chinchwad":   "Pimpri-Chinchwad",
    "viman nagar": "Viman Nagar",
    "vimannagar":  "Viman Nagar",
    "wakade":      "Wakad",
    "katraj pune": "Katraj",
}

CATEGORICAL_CHECKS = {
    "Gender":             ["Male", "Female", "Prefer not to say"],
    "Age_Group":          ["18-25", "26-35", "36-45", "46-55", "55+"],
    "EV_Purchase_Intent": ["Yes, within 2 years", "Maybe, 3-5 years", "No interest"],
}


def standardize_income(val):
    if pd.isna(val):
        return np.nan
    v = str(val).lower().replace("lakhs", "l").replace("lakh", "l").replace(" ", "")
    v = v.replace("rs", "").replace("\u20b9", "")   # drop "Rs" / rupee sign
    v = re.sub(r"(?<=\d)l", "", v)                  # drop the "L" that follows a number (6L-10L -> 6-10)
    for pattern, label in INCOME_MAP.items():
        if re.search(pattern, v):
            return label
    return val  # unknown format: keep as-is


def fix_area(val):
    if pd.isna(val):
        return val
    key = str(val).strip().lower()
    return AREA_CORRECTIONS.get(key, str(val).strip().title())


def clean_survey(df):
    header("CLEANING: survey_responses")
    name = "survey_responses"
    df = df.copy()

    # Trim whitespace first so later comparisons are reliable
    str_cols = df.select_dtypes("object").columns
    for c in str_cols:
        df[c] = df[c].apply(lambda x: x.strip() if isinstance(x, str) else x)
    log(name, "ALL string columns", "Possible leading/trailing whitespace",
        "Applied str.strip() across text columns", "Clean")

    # Drop fully empty rows
    before = len(df)
    df = df.dropna(how="all")
    dropped = before - len(df)
    if dropped:
        log(name, "ALL", f"{dropped} fully empty rows", "dropna(how='all')", f"{dropped} rows removed")

    # Fill missing Respondent_ID with sequential IDs
    df = df.reset_index(drop=True)
    missing_ids = int(df["Respondent_ID"].isna().sum())
    if missing_ids:
        generated = pd.Series([f"RESP_{str(i + 1).zfill(3)}" for i in range(len(df))], index=df.index)
        df["Respondent_ID"] = df["Respondent_ID"].fillna(generated)
        log(name, "Respondent_ID", f"{missing_ids} missing IDs",
            "Assigned sequential IDs RESP_001...", f"{missing_ids} values filled")

    # Standardize income brackets
    original = df["Monthly_Income_Bracket"].copy()
    df["Monthly_Income_Bracket"] = df["Monthly_Income_Bracket"].apply(standardize_income)
    changed = int((df["Monthly_Income_Bracket"].fillna("") != original.fillna("")).sum())
    if changed:
        log(name, "Monthly_Income_Bracket", "Mixed formats (3-6 lakh vs Rs3L-6L)",
            "Applied regex normalization", f"{changed} values standardized")

    # Fix area spellings
    original = df["Area_in_Pune"].copy()
    df["Area_in_Pune"] = df["Area_in_Pune"].apply(fix_area)
    changed = int((df["Area_in_Pune"].fillna("") != original.fillna("")).sum())
    if changed:
        log(name, "Area_in_Pune", "Spelling inconsistencies (Hadpsar, Hinjawadi etc.)",
            "Applied lookup table correction", f"{changed} values corrected")

    # Invalid categorical values -> NaN
    for col, valid in CATEGORICAL_CHECKS.items():
        if col not in df.columns:
            continue
        mask = ~df[col].isin(valid) & df[col].notna()
        count = int(mask.sum())
        if count:
            df.loc[mask, col] = np.nan
            log(name, col, f"{count} values not in allowed set",
                "Set to NaN for manual review", f"{count} values flagged")

    df["Data_Quality_Flag"] = "Cleaned"
    return df


# ---- 3.2 barrier_responses --------------------------------------------------
def clean_barriers(df, valid_survey_ids):
    header("CLEANING: barrier_responses")
    name = "barrier_responses"
    df = df.copy()

    # Severity 0 is invalid on a 1-5 scale
    zero_mask = df["Severity_Rating_1to5"] == 0
    n = int(zero_mask.sum())
    if n:
        df.loc[zero_mask, "Severity_Rating_1to5"] = np.nan
        log(name, "Severity_Rating_1to5", f"{n} ratings entered as 0 (invalid for 1-5 scale)",
            "Replaced 0 with NaN, excluded from averages", f"{n} values treated")

    # Is_Major_Concern must be Yes/No
    bad = ~df["Is_Major_Concern"].isin(["Yes", "No"]) & df["Is_Major_Concern"].notna()
    n = int(bad.sum())
    if n:
        df.loc[bad, "Is_Major_Concern"] = np.nan
        log(name, "Is_Major_Concern", f"{n} unexpected values", "Set to NaN", f"{n} values flagged")

    # Orphan check against the cleaned survey IDs
    orphan = ~df["Respondent_ID"].isin(valid_survey_ids)
    n = int(orphan.sum())
    df["Orphan_Flag"] = np.where(orphan, "Orphan", "")
    if n:
        log(name, "Respondent_ID", f"{n} IDs not found in survey_responses",
            "Flagged in Orphan_Flag column for review", f"{n} rows flagged")

    # Derived barrier score
    concern_num = df["Is_Major_Concern"].map({"Yes": 1, "No": 0}).fillna(0)
    df["Barrier_Score"] = df["Severity_Rating_1to5"].fillna(0) * concern_num
    log(name, "Barrier_Score", "No combined barrier metric",
        "Derived severity x concern score", "New column added")
    return df


# ---- 3.3 charging_stations --------------------------------------------------
def utilization(sessions):
    if pd.isna(sessions):
        return "Unknown"
    if sessions <= 8:
        return "Low (<= 8/day)"
    if sessions <= 18:
        return "Medium (9-18/day)"
    return "High (> 18/day)"


def clean_stations(df):
    header("CLEANING: charging_stations")
    name = "charging_stations"
    df = df.copy()

    # Cap outlier sessions at 35
    mask = df["Avg_Daily_Sessions"] > 35
    n = int(mask.sum())
    if n:
        df.loc[mask, "Avg_Daily_Sessions"] = 35
        log(name, "Avg_Daily_Sessions", f"{n} values exceed 35 sessions/day (outliers)",
            "Capped at 35 based on operator benchmark", f"{n} values capped")

    # Missing status -> "Unknown"
    n = int(df["Operational_Status"].isna().sum())
    if n:
        df["Operational_Status"] = df["Operational_Status"].fillna("Unknown")
        log(name, "Operational_Status", f"{n} missing values",
            "Filled with 'Unknown' for tracking", f"{n} values imputed")

    # Installation year must be 2015-2025
    bad = (df["Installation_Year"] < 2015) | (df["Installation_Year"] > 2025)
    n = int(bad.sum())
    if n:
        df.loc[bad, "Installation_Year"] = np.nan
        log(name, "Installation_Year", f"{n} years outside 2015-2025 range",
            "Set to NaN, likely data entry error", f"{n} values flagged")

    df["Utilization_Category"] = df["Avg_Daily_Sessions"].apply(utilization)
    log(name, "Avg_Daily_Sessions", "No utilization tier column",
        "Derived Utilization_Category (Low/Medium/High)", "New column added")
    return df


# ---- 3.4 statewise_ev_sales -------------------------------------------------
def clean_state_sales(df):
    header("CLEANING: statewise_ev_sales")
    name = "statewise_ev_sales"
    df = df.copy()

    # One row per state
    before = len(df)
    df = df.drop_duplicates(subset=["State"], keep="first")
    removed = before - len(df)
    if removed:
        log(name, "State", f"{removed} duplicate state entries",
            "drop_duplicates(subset='State', keep='first')", f"{removed} rows removed")

    # Recompute charging density from source columns
    computed = (df["Public_Charging_Stations_2025"] /
                df["FY2024_25_EV_Registrations"] * 1000).round(2)
    mismatch = int((abs(computed - df["Charging_per_1000_EVs"]) > 0.05).sum())
    if mismatch:
        df["Charging_per_1000_EVs"] = computed
        log(name, "Charging_per_1000_EVs", f"{mismatch} density values don't match computed",
            "Recalculated from source columns", f"{mismatch} values corrected")

    # National share
    total = df["FY2024_25_EV_Registrations"].sum()
    df["National_Share_Pct"] = (df["FY2024_25_EV_Registrations"] / total * 100).round(2)
    log(name, "FY2024_25_EV_Registrations", "No national share column",
        "Derived National_Share_Pct", "New column added")
    return df


def clean(raw):
    header("STAGE 3: DATA CLEANING")
    survey = clean_survey(raw["survey_responses"])
    barriers = clean_barriers(raw["barrier_responses"], set(survey["Respondent_ID"].dropna()))
    stations = clean_stations(raw["charging_stations"])
    states = clean_state_sales(raw["statewise_ev_sales"])
    return {
        "survey_responses":   survey,
        "barrier_responses":  barriers,
        "charging_stations":  stations,
        "statewise_ev_sales": states,
    }


# ─────────────────────────────────────────────────────────────────────────────
# STAGE 4: DATA VALIDATION (runs on CLEANED data, blocks the load on failure)
# ─────────────────────────────────────────────────────────────────────────────
def validate(clean_dfs):
    header("STAGE 4: DATA VALIDATION")
    results = []  # (dataset, check, passed)

    def check(dataset, description, passed):
        results.append((dataset, description, bool(passed)))
        print(f"  [{'PASS' if passed else 'FAIL'}] {dataset:<20} {description}")

    s = clean_dfs["survey_responses"]
    check("survey_responses", "Respondent_ID has no nulls", s["Respondent_ID"].notna().all())
    check("survey_responses", "Respondent_ID is unique", s["Respondent_ID"].is_unique)
    for col, valid in CATEGORICAL_CHECKS.items():
        check("survey_responses", f"{col} only contains allowed values",
              s[col].dropna().isin(valid).all())
    check("survey_responses", "No leading/trailing whitespace in text columns",
          all((s[c].dropna().astype(str) == s[c].dropna().astype(str).str.strip()).all()
              for c in s.select_dtypes("object").columns))

    b = clean_dfs["barrier_responses"]
    check("barrier_responses", "Severity rating within 1-5 (nulls allowed)",
          b["Severity_Rating_1to5"].dropna().between(1, 5).all())
    check("barrier_responses", "Is_Major_Concern only Yes/No (nulls allowed)",
          b["Is_Major_Concern"].dropna().isin(["Yes", "No"]).all())
    check("barrier_responses", "Barrier_Score within 0-5", b["Barrier_Score"].between(0, 5).all())
    orphans = int((b["Orphan_Flag"] == "Orphan").sum())
    print(f"  [INFO] barrier_responses   {orphans} orphan rows flagged (kept for review)")

    c = clean_dfs["charging_stations"]
    check("charging_stations", "Avg_Daily_Sessions <= 35", (c["Avg_Daily_Sessions"].dropna() <= 35).all())
    check("charging_stations", "Installation_Year within 2015-2025",
          c["Installation_Year"].dropna().between(2015, 2025).all())
    check("charging_stations", "Operational_Status has no nulls", c["Operational_Status"].notna().all())
    check("charging_stations", "Utilization_Category has no nulls", c["Utilization_Category"].notna().all())

    e = clean_dfs["statewise_ev_sales"]
    check("statewise_ev_sales", "State is unique", e["State"].is_unique)
    check("statewise_ev_sales", "National_Share_Pct sums to ~100",
          abs(e["National_Share_Pct"].sum() - 100) < 0.5)
    check("statewise_ev_sales", "Registrations are non-negative",
          (e["FY2024_25_EV_Registrations"].dropna() >= 0).all())

    failed = [r for r in results if not r[2]]
    print(f"\n  Checks passed: {len(results) - len(failed)}/{len(results)}")
    return len(failed) == 0


# ─────────────────────────────────────────────────────────────────────────────
# STAGE 5: LOAD INTO MYSQL
# ─────────────────────────────────────────────────────────────────────────────
def get_engine(with_db=True):
    try:
        from sqlalchemy import create_engine
        import pymysql  # noqa: F401  (driver must be installed)
    except ImportError as exc:
        raise ImportError("Missing package for MySQL. Run: pip install sqlalchemy pymysql") from exc
    pwd = quote_plus(MYSQL["password"])
    base = f"mysql+pymysql://{MYSQL['user']}:{pwd}@{MYSQL['host']}:{MYSQL['port']}"
    return create_engine(f"{base}/{MYSQL['database']}" if with_db else base)


def load_to_mysql(clean_dfs, log_df):
    header("STAGE 5: LOAD INTO MYSQL")
    from sqlalchemy import text

    # Create the database if needed
    server = get_engine(with_db=False)
    with server.begin() as conn:
        conn.execute(text(f"CREATE DATABASE IF NOT EXISTS `{MYSQL['database']}`"))
    server.dispose()

    engine = get_engine()
    tables = dict(clean_dfs)
    tables["cleaning_log"] = log_df

    for table, df in tables.items():
        df.to_sql(table, engine, if_exists="replace", index=False, chunksize=500)
        print(f"  Loaded {len(df):>6} rows -> {MYSQL['database']}.{table}")

    # Verify row counts in the database match what we sent
    with engine.connect() as conn:
        for table, df in tables.items():
            db_count = conn.execute(text(f"SELECT COUNT(*) FROM `{table}`")).scalar()
            status = "OK" if db_count == len(df) else "MISMATCH"
            print(f"  [{status}] {table}: dataframe={len(df)}, mysql={db_count}")
    engine.dispose()


# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────
def main():
    raw = extract()
    explore(raw)
    cleaned = clean(raw)

    # Save cleaned CSV copies + audit log
    header("SAVING CLEANED FILES")
    for name, df in cleaned.items():
        path = os.path.join(OUTPUT_DIR, f"{name}_clean.csv")
        df.to_csv(path, index=False)
        print(f"  Exported {len(df)} rows -> {path}")
    log_df = pd.DataFrame(log_entries)
    log_df.to_csv(LOG_FILE, index=False)
    print(f"  Cleaning log saved -> {LOG_FILE} ({len(log_df)} entries)")

    if not validate(cleaned):
        sys.exit("\n  Validation failed: MySQL load skipped. Fix the issues above and re-run.")

    try:
        load_to_mysql(cleaned, log_df)
    except Exception as exc:
        sys.exit(f"\n  MySQL load failed: {exc}\n  Check MYSQL_* environment variables and that the server is running.")

    print("\nPipeline complete.")


if __name__ == "__main__":
    main()
