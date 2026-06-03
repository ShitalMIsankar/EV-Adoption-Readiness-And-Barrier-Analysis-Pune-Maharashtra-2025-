import pandas as pd
import numpy as np
import re
import os
from datetime import datetime
 
# ──────────────────────────────────────────────────────────────────
INPUT_DIR  = "./datasets/"   # folder where raw datasets live
OUTPUT_DIR = "./cleaned/"    # folder for cleaned outputs
LOG_FILE   = "./cleaning_log.csv"
 
os.makedirs(OUTPUT_DIR, exist_ok=True)
 
log_entries = []
 
def log(dataset, column, issue, action, outcome):
    log_entries.append({
        "Timestamp"     : datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "Dataset"       : dataset,
        "Column"        : column,
        "Issue_Found"   : issue,
        "Action_Taken"  : action,
        "Outcome"       : outcome,
        "Tool"          : "Python (Pandas)"
    })
    print(f"  [LOG] {dataset} | {column} | {action}")
 

# ─────────────────────────────────────────────────────────────────────────────
print("\n" + "="*60)
print("CLEANING: 01_survey_responses.csv")
print("="*60)
 
df = pd.read_csv(f"{INPUT_DIR}01_survey_responses.csv")
print(f"  Loaded {len(df)} rows, {df.shape[1]} columns")
 
# Step 1 — Drop fully empty rows
before = len(df)
df.dropna(how="all", inplace=True)
dropped = before - len(df)
if dropped:
    log("survey_responses", "ALL", f"{dropped} fully empty rows", "dropna(how='all')", f"{dropped} rows removed")
 
# Step 2 — Handle missing Respondent_ID: assign sequential IDs
missing_ids = df["Respondent_ID"].isna().sum()
if missing_ids:
    df["Respondent_ID"] = df["Respondent_ID"].fillna(
        pd.Series([f"RESP_{str(i+1).zfill(3)}" for i in range(len(df))])
    )
    log("survey_responses", "Respondent_ID", f"{missing_ids} missing IDs",
        "Assigned sequential IDs RESP_001...", f"{missing_ids} values filled")
 
# Step 3 — Drop rows where EV_Purchase_Intent is blank (critical field)
before = len(df)
df.dropna(subset=["EV_Purchase_Intent"], inplace=True)
dropped = before - len(df)
if dropped:
    log("survey_responses", "EV_Purchase_Intent", f"{dropped} blank values (incomplete surveys)",
        "Dropped rows with null intent", f"{dropped} rows removed")
 
# Step 4 — Standardize Monthly_Income_Bracket
income_map = {
    r"below\s*3"          : "Below Rs3L",
    r"3\s*[-–]\s*6"       : "Rs3L-6L",
    r"6\s*[-–]\s*10"      : "Rs6L-10L",
    r"10\s*[-–]\s*15"     : "Rs10L-15L",
    r"above\s*15|15\+"    : "Above Rs15L",
}
def standardize_income(val):
    if pd.isna(val): return np.nan
    val_lower = str(val).lower().replace("lakh","l").replace("lakhs","l").replace(" ","")
    for pattern, replacement in income_map.items():
        if re.search(pattern, val_lower):
            return replacement
    return val  # return as-is if no match
 
original = df["Monthly_Income_Bracket"].copy()
df["Monthly_Income_Bracket"] = df["Monthly_Income_Bracket"].apply(standardize_income)
changed = (df["Monthly_Income_Bracket"] != original).sum()
if changed:
    log("survey_responses", "Monthly_Income_Bracket", "Mixed formats (3-6 lakh vs Rs3L-6L)",
        "Applied regex normalization", f"{changed} values standardized")
 
# Step 5 — Fix Area_in_Pune spelling inconsistencies
area_corrections = {
    "hadpsar"       : "Hadapsar",
    "hinjawadi"     : "Hinjewadi",
    "hinjwadi"      : "Hinjewadi",
    "pimpari"       : "Pimpri-Chinchwad",
    "chinchwad"     : "Pimpri-Chinchwad",
    "viman nagar"   : "Viman Nagar",
    "vimannagar"    : "Viman Nagar",
    "wakade"        : "Wakad",
    "katraj pune"   : "Katraj",
}
def fix_area(val):
    if pd.isna(val): return val
    return area_corrections.get(str(val).strip().lower(), str(val).strip().title())
 
original_areas = df["Area_in_Pune"].copy()
df["Area_in_Pune"] = df["Area_in_Pune"].apply(fix_area)
changed = (df["Area_in_Pune"] != original_areas).sum()
if changed:
    log("survey_responses", "Area_in_Pune", "Spelling inconsistencies (Hadpsar, Hinjawadi etc.)",
        "Applied lookup table correction", f"{changed} values corrected")
 
# Step 6 — Validate categorical columns
categorical_checks = {
    "Gender"       : ["Male","Female","Prefer not to say"],
    "Age_Group"    : ["18-25","26-35","36-45","46-55","55+"],
    "EV_Purchase_Intent": ["Yes, within 2 years","Maybe, 3-5 years","No interest"],
}
for col, valid_vals in categorical_checks.items():
    invalid_mask = ~df[col].isin(valid_vals) & df[col].notna()
    count = invalid_mask.sum()
    if count:
        df.loc[invalid_mask, col] = np.nan
        log("survey_responses", col, f"{count} values not in allowed set",
            "Set to NaN for manual review", f"{count} values flagged")
 
# Step 7 — Trim whitespace from all string columns
str_cols = df.select_dtypes("object").columns
df[str_cols] = df[str_cols].apply(lambda c: c.str.strip() if c.dtype == "object" else c)
log("survey_responses", "ALL string columns", "Possible leading/trailing whitespace",
    "Applied str.strip() across all object columns", "Clean")
 
# Step 8 — Add cleaned flag and export
df["Data_Quality_Flag"] = "Cleaned"
df.to_csv(f"{OUTPUT_DIR}01_survey_responses_clean.csv", index=False)
print(f"  Exported {len(df)} cleaned rows → cleaned/01_survey_responses_clean.csv")
 

# ─────────────────────────────────────────────────────────────────────────────
print("\n" + "="*60)
print("CLEANING: 02_barrier_responses.csv")
print("="*60)
 
df2 = pd.read_csv(f"{INPUT_DIR}02_barrier_responses.csv")
print(f"  Loaded {len(df2)} rows, {df2.shape[1]} columns")
 
# Step 1 — Replace severity rating of 0 with NaN (invalid — scale is 1–5)
invalid_sev = (df2["Severity_Rating_1to5"] == 0).sum()
if invalid_sev:
    df2.loc[df2["Severity_Rating_1to5"] == 0, "Severity_Rating_1to5"] = np.nan
    log("barrier_responses", "Severity_Rating_1to5", f"{invalid_sev} ratings entered as 0 (invalid for 1-5 scale)",
        "Replaced 0 with NaN — excluded from averages", f"{invalid_sev} values treated")
 
# Step 2 — Validate Is_Major_Concern values
valid_concern = ["Yes","No"]
invalid_concern = ~df2["Is_Major_Concern"].isin(valid_concern) & df2["Is_Major_Concern"].notna()
count = invalid_concern.sum()
if count:
    df2.loc[invalid_concern, "Is_Major_Concern"] = np.nan
    log("barrier_responses", "Is_Major_Concern", f"{count} unexpected values",
        "Set to NaN", f"{count} values flagged")
 
# Step 3 — Verify Respondent_IDs are consistent with survey file
survey_ids = pd.read_csv(f"{INPUT_DIR}01_survey_responses.csv")["Respondent_ID"].tolist()
orphan_ids = ~df2["Respondent_ID"].isin(survey_ids)
orphan_count = orphan_ids.sum()
if orphan_count:
    log("barrier_responses", "Respondent_ID", f"{orphan_count} IDs not found in survey_responses",
        "Flagged in Orphan_Flag column for review", f"{orphan_count} rows flagged")
    df2["Orphan_Flag"] = orphan_ids.map({True: "Orphan", False: ""})
 
# Step 4 — Compute per-respondent barrier score (useful for Power BI)
df2["Barrier_Score"] = df2["Severity_Rating_1to5"].fillna(0) * df2["Is_Major_Concern"].map({"Yes":1,"No":0}).fillna(0)
 
df2.to_csv(f"{OUTPUT_DIR}02_barrier_responses_clean.csv", index=False)
print(f"  Exported {len(df2)} cleaned rows → cleaned/02_barrier_responses_clean.csv")
 

# ─────────────────────────────────────────────────────────────────────────────
print("\n" + "="*60)
print("CLEANING: 04_charging_stations_pune.csv")
print("="*60)
 
df4 = pd.read_csv(f"{INPUT_DIR}04_charging_stations_pune.csv")
print(f"  Loaded {len(df4)} rows, {df4.shape[1]} columns")
 
# Step 1 — Cap Avg_Daily_Sessions outliers (>35 flagged as data entry errors)
outlier_mask = df4["Avg_Daily_Sessions"] > 35
count = outlier_mask.sum()
if count:
    df4.loc[outlier_mask, "Avg_Daily_Sessions"] = 35
    log("charging_stations", "Avg_Daily_Sessions", f"{count} values exceed 35 sessions/day (outliers)",
        "Capped at 35 based on operator benchmark", f"{count} values capped")
 
# Step 2 — Fill missing Operational_Status
missing_status = df4["Operational_Status"].isna().sum()
if missing_status:
    df4["Operational_Status"].fillna("Unknown", inplace=True)
    log("charging_stations", "Operational_Status", f"{missing_status} missing values",
        "Filled with 'Unknown' for tracking", f"{missing_status} values imputed")
 
# Step 3 — Validate Installation_Year range (EVs not common before 2015 in Pune)
invalid_yr = (df4["Installation_Year"] < 2015) | (df4["Installation_Year"] > 2025)
count = invalid_yr.sum()
if count:
    df4.loc[invalid_yr, "Installation_Year"] = np.nan
    log("charging_stations", "Installation_Year", f"{count} years outside 2015–2025 range",
        "Set to NaN — likely data entry error", f"{count} values flagged")
 
# Step 4 — Derive Utilization_Category from sessions
def utilization(sessions):
    if pd.isna(sessions): return "Unknown"
    if sessions <= 8:  return "Low (<= 8/day)"
    if sessions <= 18: return "Medium (9-18/day)"
    return "High (> 18/day)"
 
df4["Utilization_Category"] = df4["Avg_Daily_Sessions"].apply(utilization)
log("charging_stations", "Avg_Daily_Sessions", "No utilization tier column",
    "Derived Utilization_Category (Low/Medium/High)", "New column added")
 
df4.to_csv(f"{OUTPUT_DIR}04_charging_stations_clean.csv", index=False)
print(f"  Exported {len(df4)} cleaned rows → cleaned/04_charging_stations_clean.csv")
 

# ─────────────────────────────────────────────────────────────────────────────
print("\n" + "="*60)
print("CLEANING: 06_statewise_ev_sales.csv")
print("="*60)
 
df6 = pd.read_csv(f"{INPUT_DIR}06_statewise_ev_sales.csv")
print(f"  Loaded {len(df6)} rows, {df6.shape[1]} columns")
 
# Step 1 — Remove duplicate rows
before = len(df6)
df6.drop_duplicates(subset=["State"], keep="first", inplace=True)
removed = before - len(df6)
if removed:
    log("statewise_ev_sales", "State", f"{removed} duplicate state entries",
        "drop_duplicates(subset='State', keep='first')", f"{removed} rows removed")
 
# Step 2 — Validate charging station density (sanity check)
df6["Computed_Density"] = (df6["Public_Charging_Stations_2025"] /
                            df6["FY2024_25_EV_Registrations"] * 1000).round(2)
mismatch = (abs(df6["Computed_Density"] - df6["Charging_per_1000_EVs"]) > 0.05).sum()
if mismatch:
    df6["Charging_per_1000_EVs"] = df6["Computed_Density"]
    log("statewise_ev_sales", "Charging_per_1000_EVs", f"{mismatch} density values don't match computed",
        "Recalculated from source columns", f"{mismatch} values corrected")
df6.drop(columns=["Computed_Density"], inplace=True)
 
# Step 3 — Add national share column
total_ev = df6["FY2024_25_EV_Registrations"].sum()
df6["National_Share_Pct"] = (df6["FY2024_25_EV_Registrations"] / total_ev * 100).round(2)
log("statewise_ev_sales", "FY2024_25_EV_Registrations", "No national share column",
    "Derived National_Share_Pct", "New column added")
 
df6.to_csv(f"{OUTPUT_DIR}06_statewise_ev_sales_clean.csv", index=False)
print(f"  Exported {len(df6)} cleaned rows → cleaned/06_statewise_ev_sales_clean.csv")
 

# ─────────────────────────────────────────────────────────────────────────────
print("\n" + "="*60)
print("EXPORTING CLEANING LOG")
print("="*60)
 
pd.DataFrame(log_entries).to_csv(LOG_FILE, index=False)
print(f"  Cleaning log saved → {LOG_FILE}")
print(f"  Total steps logged : {len(log_entries)}")
print("\nPipeline complete.")
 
