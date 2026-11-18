
/* ============================================================================
   1. DATA FIXES  (run once AFTER loading the data)
   Issues found in the workbook:
     - 'Yes,within 2 years'  (missing space) vs 'Yes, within 2 years'
     - 'Yes,have parking'    (missing space) vs 'Yes, have parking'
     - Source_of_EV_Awareness = 'have parking"'  (a value from another column)
   ============================================================================ */
SET SQL_SAFE_UPDATES = 0;

UPDATE survey_responses
SET    EV_Purchase_Intent = 'Yes, within 2 years'
WHERE  EV_Purchase_Intent = 'Yes,within 2 years';

UPDATE survey_responses
SET    Home_Charging_Feasibility = 'Yes, have parking'
WHERE  Home_Charging_Feasibility = 'Yes,have parking';

-- Stray value from the wrong column: blank it for manual review (do not guess)
UPDATE survey_responses
SET    Source_of_EV_Awareness = NULL
WHERE  Source_of_EV_Awareness = 'have parking"';

SET SQL_SAFE_UPDATES = 1;


/* ============================================================================
   2. VIEWS
   v_survey_master rebuilds the workbook's SQL_MasterView sheet in SQL:
     Top_Barrier        = barrier with the highest Barrier_Score per respondent
                          (ties broken by higher severity, then alphabetically)
     Chargers_In_Area   = number of stations in the respondent's area
   NOTE: the SQL_MasterView sheet in the workbook does NOT match these values
   for many rows (e.g. RESP_001 shows 7 chargers; Viman Nagar has 6 stations).
   This view recomputes both columns from the source tables, so use it instead
   of the sheet, and consider re-checking how the sheet was built.
   ============================================================================ */
CREATE OR REPLACE VIEW v_survey_master AS
WITH ranked AS (
    SELECT Respondent_ID, Barrier, Barrier_Score,
           ROW_NUMBER() OVER (
               PARTITION BY Respondent_ID
               ORDER BY Barrier_Score DESC, Severity_Rating_1to5 DESC, Barrier
           ) AS rn
    FROM   barrier_responses
),
zone AS (
    SELECT Zone_Pune, COUNT(*) AS n_stations
    FROM   charging_stations
    GROUP  BY Zone_Pune
)
SELECT s.*,
       r.Barrier               AS Top_Barrier,
       r.Barrier_Score         AS Top_Barrier_Score,
       COALESCE(z.n_stations, 0) AS Chargers_In_Area
FROM   survey_responses s
LEFT JOIN ranked r ON r.Respondent_ID = s.Respondent_ID AND r.rn = 1
LEFT JOIN zone   z ON z.Zone_Pune     = s.Area_in_Pune;


/* ============================================================================
   A. EXECUTIVE SUMMARY
   ============================================================================ */

-- A1. KPI cards
SELECT COUNT(*)                                             AS total_respondents,
       ROUND(100.0 * SUM(Intent_Binary)  / COUNT(*), 1)     AS pct_intend_to_buy,
       ROUND(100.0 * SUM(Policy_Binary)  / COUNT(*), 1)     AS pct_policy_aware,
       ROUND(100.0 * SUM(Subsidy_Binary) / COUNT(*), 1)     AS pct_subsidy_aware
FROM   survey_responses;

-- A2. EV purchase intent by occupation
SELECT Occupation,
       COUNT(*)                                          AS respondents,
       SUM(Intent_Binary)                                AS intend_within_2_years,
       ROUND(100.0 * SUM(Intent_Binary) / COUNT(*), 1)   AS pct_intent
FROM   survey_responses
GROUP  BY Occupation
ORDER  BY pct_intent DESC, respondents DESC;

-- A3. Purchase intent split (donut)
SELECT EV_Purchase_Intent,
       COUNT(*)                                                AS respondents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)      AS pct_of_total
FROM   survey_responses
GROUP  BY EV_Purchase_Intent
ORDER  BY respondents DESC;

-- A4. Preferred EV type by income bracket
SELECT Monthly_Income_Bracket,
       COUNT(*)                                                                AS respondents,
       SUM(CASE WHEN Preferred_EV_Type = 'Electric 2-wheeler'   THEN 1 ELSE 0 END) AS electric_2_wheeler,
       SUM(CASE WHEN Preferred_EV_Type = 'Electric Car'         THEN 1 ELSE 0 END) AS electric_car,
       SUM(CASE WHEN Preferred_EV_Type = 'E-auto / 3-wheeler'   THEN 1 ELSE 0 END) AS e_auto_3_wheeler,
       SUM(CASE WHEN Preferred_EV_Type = 'E-cycle'              THEN 1 ELSE 0 END) AS e_cycle
FROM   survey_responses
GROUP  BY Monthly_Income_Bracket
ORDER  BY CASE Monthly_Income_Bracket
              WHEN 'Below Rs3L'  THEN 1 WHEN 'Rs3L-6L'    THEN 2
              WHEN 'Rs6L-10L'    THEN 3 WHEN 'Rs10L-15L'  THEN 4
              WHEN 'Above Rs15L' THEN 5 ELSE 6 END;


/* ============================================================================
   B. SURVEY INSIGHTS
   ============================================================================ */

-- B1. Home charging feasibility (funnel / donut)
SELECT Home_Charging_Feasibility,
       COUNT(*)                                               AS respondents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)     AS pct_of_total
FROM   survey_responses
GROUP  BY Home_Charging_Feasibility
ORDER  BY respondents DESC;

-- B2. Awareness vs intent by area (scatter)
SELECT Area_in_Pune,
       COUNT(*)                                                AS respondents,
       ROUND(100.0 * SUM(Policy_Binary)  / COUNT(*), 1)        AS pct_policy_aware,
       ROUND(100.0 * SUM(Subsidy_Binary) / COUNT(*), 1)        AS pct_subsidy_aware,
       ROUND(100.0 * SUM(Intent_Binary)  / COUNT(*), 1)        AS pct_intent
FROM   survey_responses
GROUP  BY Area_in_Pune
ORDER  BY pct_intent DESC;

-- B3. Willingness to pay by occupation (share within each occupation)
SELECT Occupation,
       Willingness_To_Pay,
       COUNT(*)                                                                     AS respondents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY Occupation), 1)   AS pct_within_occupation
FROM   survey_responses
GROUP  BY Occupation, Willingness_To_Pay
ORDER  BY Occupation, respondents DESC;

-- B4. Source of EV awareness, overall and for people who intend to buy
SELECT COALESCE(Source_of_EV_Awareness, 'Unknown')                  AS source_of_awareness,
       COUNT(*)                                                     AS respondents,
       SUM(Intent_Binary)                                           AS intend_to_buy,
       ROUND(100.0 * SUM(Intent_Binary) / COUNT(*), 1)              AS pct_intent
FROM   survey_responses
GROUP  BY COALESCE(Source_of_EV_Awareness, 'Unknown')
ORDER  BY respondents DESC;

-- B5. Charging infrastructure satisfaction vs intent
SELECT Charging_Infrastructure_Satisfaction,
       COUNT(*)                                          AS respondents,
       ROUND(100.0 * SUM(Intent_Binary) / COUNT(*), 1)   AS pct_intent
FROM   survey_responses
GROUP  BY Charging_Infrastructure_Satisfaction
ORDER  BY CASE Charging_Infrastructure_Satisfaction
              WHEN 'Very Dissatisfied' THEN 1 WHEN 'Dissatisfied' THEN 2
              WHEN 'Neutral'           THEN 3 WHEN 'Satisfied'    THEN 4
              WHEN 'Very Satisfied'    THEN 5 ELSE 6 END;

-- B6. Current vehicle type vs intent
SELECT Current_Vehicle_Type,
       COUNT(*)                                          AS respondents,
       ROUND(100.0 * SUM(Intent_Binary) / COUNT(*), 1)   AS pct_intent
FROM   survey_responses
GROUP  BY Current_Vehicle_Type
ORDER  BY pct_intent DESC;


/* ============================================================================
   C. BARRIER ANALYSIS
   ============================================================================ */

-- C1. Barrier league table
SELECT Barrier,
       COUNT(*)                                                                AS responses,
       SUM(CASE WHEN Is_Major_Concern = 'Yes' THEN 1 ELSE 0 END)               AS major_concern_count,
       ROUND(100.0 * SUM(CASE WHEN Is_Major_Concern = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_major_concern,
       ROUND(AVG(Severity_Rating_1to5), 2)                                     AS avg_severity,
       ROUND(AVG(Barrier_Score), 2)                                            AS avg_barrier_score,
       RANK() OVER (ORDER BY AVG(Barrier_Score) DESC)                          AS barrier_rank
FROM   barrier_responses
GROUP  BY Barrier
ORDER  BY barrier_rank;

-- C2. Severity PCT by barrier: share of ratings that are 4 or 5 (high severity)
SELECT Barrier,
       COUNT(Severity_Rating_1to5)                                                        AS rated_responses,
       SUM(CASE WHEN Severity_Rating_1to5 >= 4 THEN 1 ELSE 0 END)                         AS high_severity_count,
       ROUND(100.0 * SUM(CASE WHEN Severity_Rating_1to5 >= 4 THEN 1 ELSE 0 END)
                   / COUNT(Severity_Rating_1to5), 1)                                      AS pct_high_severity
FROM   barrier_responses
GROUP  BY Barrier
ORDER  BY pct_high_severity DESC;

-- C3. Barrier per area (pivot table): average barrier score
SELECT s.Area_in_Pune,
       b.Barrier,
       COUNT(*)                         AS responses,
       ROUND(AVG(b.Barrier_Score), 2)   AS avg_barrier_score
FROM   barrier_responses b
JOIN   survey_responses  s ON s.Respondent_ID = b.Respondent_ID
GROUP  BY s.Area_in_Pune, b.Barrier
ORDER  BY s.Area_in_Pune, avg_barrier_score DESC;

-- C4. Single top barrier in each area
WITH area_barrier AS (
    SELECT s.Area_in_Pune, b.Barrier, ROUND(AVG(b.Barrier_Score), 2) AS avg_score,
           ROW_NUMBER() OVER (PARTITION BY s.Area_in_Pune ORDER BY AVG(b.Barrier_Score) DESC, b.Barrier) AS rn
    FROM   barrier_responses b
    JOIN   survey_responses  s ON s.Respondent_ID = b.Respondent_ID
    GROUP  BY s.Area_in_Pune, b.Barrier
)
SELECT Area_in_Pune, Barrier AS top_barrier, avg_score
FROM   area_barrier
WHERE  rn = 1
ORDER  BY avg_score DESC;

-- C5. Do people who intend to buy see barriers differently?
SELECT b.Barrier,
       ROUND(AVG(CASE WHEN s.Intent_Binary = 1 THEN b.Barrier_Score END), 2) AS avg_score_intenders,
       ROUND(AVG(CASE WHEN s.Intent_Binary = 0 THEN b.Barrier_Score END), 2) AS avg_score_non_intenders
FROM   barrier_responses b
JOIN   survey_responses  s ON s.Respondent_ID = b.Respondent_ID
GROUP  BY b.Barrier
ORDER  BY avg_score_non_intenders DESC;

-- C6. Most common top barrier across respondents (uses the view)
SELECT Top_Barrier,
       COUNT(*)                                              AS respondents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)    AS pct_of_respondents
FROM   v_survey_master
GROUP  BY Top_Barrier
ORDER  BY respondents DESC;


/* ============================================================================
   D. INFRASTRUCTURE
   ============================================================================ */

-- D1. Number of stations by zone
SELECT Zone_Pune,
       COUNT(*)                                                          AS stations,
       SUM(Number_of_Ports)                                              AS total_ports,
       SUM(CASE WHEN Operational_Status = 'Operational' THEN 1 ELSE 0 END) AS operational_stations
FROM   charging_stations
GROUP  BY Zone_Pune
ORDER  BY stations DESC;

-- D2. Station utilization by zone
SELECT Zone_Pune,
       SUM(CASE WHEN Utilization_Category LIKE 'Low%'    THEN 1 ELSE 0 END)  AS low_util,
       SUM(CASE WHEN Utilization_Category LIKE 'Medium%' THEN 1 ELSE 0 END)  AS medium_util,
       SUM(CASE WHEN Utilization_Category LIKE 'High%'   THEN 1 ELSE 0 END)  AS high_util,
       ROUND(AVG(Avg_Daily_Sessions), 1)                                     AS avg_daily_sessions,
       SUM(Monthly_Units_Dispensed_kWh)                                      AS total_kwh_month
FROM   charging_stations
GROUP  BY Zone_Pune
ORDER  BY avg_daily_sessions DESC;

-- D3. Operational status mix
SELECT Operational_Status,
       COUNT(*)                                              AS stations,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)    AS pct_of_stations
FROM   charging_stations
GROUP  BY Operational_Status
ORDER  BY stations DESC;

-- D4. Operator market share
SELECT Operator,
       COUNT(*)                                              AS stations,
       SUM(Number_of_Ports)                                  AS ports,
       ROUND(AVG(Avg_Daily_Sessions), 1)                     AS avg_daily_sessions,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)    AS pct_of_stations
FROM   charging_stations
GROUP  BY Operator
ORDER  BY stations DESC;

-- D5. Intent vs infrastructure gap: PRIORITY ZONES
--     demand = survey respondents who intend to buy, supply = stations in that area
WITH demand AS (
    SELECT Area_in_Pune AS area,
           COUNT(*)           AS respondents,
           SUM(Intent_Binary) AS intenders,
           ROUND(100.0 * SUM(Intent_Binary) / COUNT(*), 1) AS pct_intent
    FROM   survey_responses
    GROUP  BY Area_in_Pune
),
supply AS (
    SELECT Zone_Pune AS area,
           COUNT(*)                                                             AS stations,
           SUM(Number_of_Ports)                                                 AS ports,
           SUM(CASE WHEN Operational_Status = 'Operational' THEN 1 ELSE 0 END)  AS operational
    FROM   charging_stations
    GROUP  BY Zone_Pune
)
SELECT d.area,
       d.respondents,
       d.pct_intent,
       COALESCE(s.stations, 0)    AS stations,
       COALESCE(s.operational, 0) AS operational_stations,
       ROUND(d.intenders / NULLIF(s.operational, 0), 2) AS intenders_per_operational_station,
       RANK() OVER (ORDER BY d.intenders / NULLIF(s.operational, 0) DESC) AS gap_rank
FROM   demand d
LEFT JOIN supply s ON s.area = d.area
ORDER  BY gap_rank;

-- D6. Average daily sessions: station type x location type
SELECT Station_Type, Location_Type,
       COUNT(*)                          AS stations,
       ROUND(AVG(Avg_Daily_Sessions), 1) AS avg_daily_sessions
FROM   charging_stations
GROUP  BY Station_Type, Location_Type
ORDER  BY Station_Type, avg_daily_sessions DESC;

-- D7. Installations per year and cumulative stations
SELECT Installation_Year,
       COUNT(*)                                         AS new_stations,
       SUM(COUNT(*)) OVER (ORDER BY Installation_Year)  AS cumulative_stations
FROM   charging_stations
WHERE  Installation_Year IS NOT NULL
GROUP  BY Installation_Year
ORDER  BY Installation_Year;

-- D8. Energy dispensed per port by station type
SELECT Station_Type,
       SUM(Monthly_Units_Dispensed_kWh)                                  AS total_kwh,
       SUM(Number_of_Ports)                                              AS total_ports,
       ROUND(SUM(Monthly_Units_Dispensed_kWh) / SUM(Number_of_Ports), 0) AS kwh_per_port
FROM   charging_stations
GROUP  BY Station_Type
ORDER  BY kwh_per_port DESC;


/* ============================================================================
   E. MARKET ANALYSIS
   ============================================================================ */

-- E1. Top 10 states by EV sales FY2024-25
SELECT State,
       FY2024_25_EV_Registrations   AS registrations,
       National_Share_Pct,
       National_Sales_Rank
FROM   statewise_ev_sales
ORDER  BY FY2024_25_EV_Registrations DESC
LIMIT  10;

-- E2. Charger density vs national share (scatter)
SELECT State, Region,
       Charging_per_1000_EVs,
       National_Share_Pct,
       Public_Charging_Stations_2025 AS stations
FROM   statewise_ev_sales
ORDER  BY Charging_per_1000_EVs DESC;

-- E3. Region summary
SELECT Region,
       COUNT(*)                                                                      AS states,
       SUM(FY2024_25_EV_Registrations)                                               AS registrations,
       SUM(Public_Charging_Stations_2025)                                            AS stations,
       ROUND(1000.0 * SUM(Public_Charging_Stations_2025) / SUM(FY2024_25_EV_Registrations), 2) AS stations_per_1000_evs,
       ROUND(SUM(National_Share_Pct), 2)                                             AS pct_national_share
FROM   statewise_ev_sales
GROUP  BY Region
ORDER  BY registrations DESC;

-- E4. States with high sales but below-average charger density (infrastructure lag)
SELECT State, FY2024_25_EV_Registrations AS registrations,
       Charging_per_1000_EVs,
       ROUND((SELECT AVG(Charging_per_1000_EVs) FROM statewise_ev_sales), 2) AS avg_density
FROM   statewise_ev_sales
WHERE  National_Sales_Rank <= 10
  AND  Charging_per_1000_EVs < (SELECT AVG(Charging_per_1000_EVs) FROM statewise_ev_sales)
ORDER  BY registrations DESC;

-- E5. Maharashtra's position nationally
SELECT State, National_Sales_Rank, FY2024_25_EV_Registrations AS registrations,
       National_Share_Pct, Charging_per_1000_EVs
FROM   statewise_ev_sales
WHERE  State = 'Maharashtra';

-- E6. MH monthly registrations by vehicle category (line chart) with recomputed MoM %
SELECT `Month`, Vehicle_Category, Registrations,
       ROUND(100.0 * (Registrations - LAG(Registrations) OVER w)
                   / LAG(Registrations) OVER w, 1) AS mom_growth_pct_calc,
       MoM_Growth_Pct                               AS mom_growth_pct_source
FROM   mh_registrations
WINDOW w AS (
    PARTITION BY Vehicle_Category
    ORDER BY CASE `Month` WHEN 'January' THEN 1 WHEN 'February' THEN 2 WHEN 'March' THEN 3
                          WHEN 'April'   THEN 4 WHEN 'May'      THEN 5 WHEN 'June'  THEN 6
                          ELSE 12 END
)
ORDER  BY Vehicle_Category,
          CASE `Month` WHEN 'January' THEN 1 WHEN 'February' THEN 2 WHEN 'March' THEN 3
                       WHEN 'April'   THEN 4 ELSE 12 END;

-- E7. MH total registrations per month and category mix
SELECT `Month`,
       SUM(Registrations) AS total_registrations,
       SUM(CASE WHEN Vehicle_Category = '2-Wheeler' THEN Registrations ELSE 0 END) AS two_wheeler,
       SUM(CASE WHEN Vehicle_Category = '4-Wheeler' THEN Registrations ELSE 0 END) AS four_wheeler,
       SUM(CASE WHEN Vehicle_Category = '3-Wheeler' THEN Registrations ELSE 0 END) AS three_wheeler,
       SUM(CASE WHEN Vehicle_Category = 'E-Bus'     THEN Registrations ELSE 0 END) AS e_bus
FROM   mh_registrations
GROUP  BY `Month`
ORDER  BY CASE `Month` WHEN 'January' THEN 1 WHEN 'February' THEN 2 WHEN 'March' THEN 3
                       WHEN 'April'   THEN 4 ELSE 12 END;

-- E8. Growth from first to last month, by category
WITH first_last AS (
    SELECT Vehicle_Category,
           MAX(CASE WHEN `Month` = 'January' THEN Registrations END) AS jan,
           MAX(CASE WHEN `Month` = 'April'   THEN Registrations END) AS apr
    FROM   mh_registrations
    GROUP  BY Vehicle_Category
)
SELECT Vehicle_Category, jan, apr,
       apr - jan                                  AS absolute_growth,
       ROUND(100.0 * (apr - jan) / jan, 1)        AS pct_growth_jan_to_apr
FROM   first_last
ORDER  BY pct_growth_jan_to_apr DESC;


/* ============================================================================
   F. VALIDATION / DATA-QUALITY CHECKS  (each query should return 0 rows,
      or the expected value, when the data is healthy)
   ============================================================================ */

-- F1. Row counts per table
SELECT 'survey_responses' AS tbl, COUNT(*) AS row_count FROM survey_responses
UNION ALL SELECT 'barrier_responses',  COUNT(*) FROM barrier_responses
UNION ALL SELECT 'charging_stations',  COUNT(*) FROM charging_stations
UNION ALL SELECT 'statewise_ev_sales', COUNT(*) FROM statewise_ev_sales
UNION ALL SELECT 'mh_registrations',   COUNT(*) FROM mh_registrations;

-- F2. Orphan barrier rows (respondent not in survey)
SELECT b.Respondent_ID
FROM   barrier_responses b
LEFT JOIN survey_responses s ON s.Respondent_ID = b.Respondent_ID
WHERE  s.Respondent_ID IS NULL;

-- F3. Respondents that do not have exactly 9 barrier rows
SELECT s.Respondent_ID, COUNT(b.Barrier) AS barrier_rows
FROM   survey_responses s
LEFT JOIN barrier_responses b ON b.Respondent_ID = s.Respondent_ID
GROUP  BY s.Respondent_ID
HAVING COUNT(b.Barrier) <> 9;

-- F4. Severity outside 1-5
SELECT * FROM barrier_responses
WHERE  Severity_Rating_1to5 IS NOT NULL
  AND  Severity_Rating_1to5 NOT BETWEEN 1 AND 5;

-- F5. Barrier_Score that does not equal severity x (concern = Yes)
SELECT *
FROM   barrier_responses
WHERE  Barrier_Score <> COALESCE(Severity_Rating_1to5, 0) * CASE WHEN Is_Major_Concern = 'Yes' THEN 1 ELSE 0 END;

-- F6. Text intent and Intent_Binary disagree
SELECT Respondent_ID, EV_Purchase_Intent, Intent_Binary
FROM   survey_responses
WHERE  (EV_Purchase_Intent LIKE 'Yes%' AND Intent_Binary <> 1)
   OR  (EV_Purchase_Intent NOT LIKE 'Yes%' AND Intent_Binary <> 0);

-- F7. Survey areas with no charging stations at all
SELECT DISTINCT s.Area_in_Pune
FROM   survey_responses s
LEFT JOIN charging_stations c ON c.Zone_Pune = s.Area_in_Pune
WHERE  c.Station_ID IS NULL;

-- F8. Stations with a missing installation year
SELECT Station_ID, Zone_Pune, Operator
FROM   charging_stations
WHERE  Installation_Year IS NULL;

-- F9. National share should add up to about 100
SELECT ROUND(SUM(National_Share_Pct), 2) AS total_share_pct FROM statewise_ev_sales;

-- F10. Stored charger density vs recomputed (tolerance 0.05)
SELECT State, Charging_per_1000_EVs,
       ROUND(1000.0 * Public_Charging_Stations_2025 / FY2024_25_EV_Registrations, 2) AS recomputed
FROM   statewise_ev_sales
WHERE  ABS(Charging_per_1000_EVs - 1000.0 * Public_Charging_Stations_2025 / FY2024_25_EV_Registrations) > 0.05;
