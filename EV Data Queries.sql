CREATE DATABASE IF NOT EXISTS ev_pune_db;
USE ev_pune_db;

CREATE TABLE IF NOT EXISTS survey_responses (
    Respondent_ID              VARCHAR(10)  PRIMARY KEY,
    Occupation                 VARCHAR(50),
    Age_Group                  VARCHAR(10),
    Gender                     VARCHAR(20),
    Monthly_Income_Bracket     VARCHAR(20),
    Area_in_Pune               VARCHAR(30),
    Current_Vehicle_Type       VARCHAR(30),
    Daily_Commute_Distance     VARCHAR(15),
    Aware_of_MH_EV_Policy_2025 VARCHAR(10),
    Aware_of_EV_Subsidy_Benefits VARCHAR(5),
    EV_Purchase_Intent         VARCHAR(30),
    Preferred_EV_Type          VARCHAR(30),
    Willingness_To_Pay         VARCHAR(20),
    Home_Charging_Feasibility  VARCHAR(40),
    Charging_Infrastructure_Satisfaction VARCHAR(20),
    Source_of_EV_Awareness     VARCHAR(30)
);

CREATE TABLE IF NOT EXISTS barrier_responses (
    id                   INT AUTO_INCREMENT PRIMARY KEY,
    Respondent_ID        VARCHAR(10),
    Barrier              VARCHAR(60),
    Is_Major_Concern     VARCHAR(3),
    Severity_Rating_1to5 TINYINT,
    Barrier_Score        DECIMAL(4,2),
    FOREIGN KEY (Respondent_ID) REFERENCES survey_responses(Respondent_ID)
);

CREATE TABLE IF NOT EXISTS charging_stations (
    Station_ID                  VARCHAR(10) PRIMARY KEY,
    Zone_Pune                   VARCHAR(30),
    Operator                    VARCHAR(20),
    Station_Type                VARCHAR(30),
    Number_of_Ports             TINYINT,
    Location_Type               VARCHAR(30),
    Operational_Status          VARCHAR(20),
    Avg_Daily_Sessions          TINYINT,
    Monthly_Units_Dispensed_kWh INT,
    Installation_Year           YEAR,
    Utilization_Category        VARCHAR(20)
);

CREATE TABLE IF NOT EXISTS statewise_ev_sales (
    State                          VARCHAR(30) PRIMARY KEY,
    FY2024_25_EV_Registrations     INT,
    Public_Charging_Stations_2025  INT,
    National_Sales_Rank            TINYINT,
    Region                         VARCHAR(15),
    Charging_per_1000_EVs          DECIMAL(5,2),
    National_Share_Pct             DECIMAL(4,2)
);

CREATE TABLE IF NOT EXISTS mh_ev_registrations (
    id               INT AUTO_INCREMENT PRIMARY KEY,
    Month            VARCHAR(15),
    Year             YEAR,
    Vehicle_Category VARCHAR(20),
    Registrations    INT,
    MoM_Growth_Pct   DECIMAL(5,2)
);

-- Load CSVs (update path as needed)



-- SECTION 1 — SURVEY OVERVIEW & RESPONSE QUALITY
-- ------------------------------------------------------------

-- Q1.1: Total respondents and intent split
SELECT
    EV_Purchase_Intent,
    COUNT(*)                                        AS Respondents,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS Share_Pct
FROM survey_responses
GROUP BY EV_Purchase_Intent
ORDER BY Respondents DESC;


-- Q1.2: Policy awareness breakdown
SELECT
    Aware_of_MH_EV_Policy_2025  AS Policy_Awareness,
    Aware_of_EV_Subsidy_Benefits AS Subsidy_Awareness,
    COUNT(*)                     AS Respondents
FROM survey_responses
GROUP BY Aware_of_MH_EV_Policy_2025, Aware_of_EV_Subsidy_Benefits
ORDER BY Respondents DESC;


-- Q1.3: Survey coverage by area (geographic spread)
SELECT
    Area_in_Pune,
    COUNT(*) AS Respondents,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM survey_responses), 1) AS Coverage_Pct
FROM survey_responses
GROUP BY Area_in_Pune
ORDER BY Respondents DESC;



-- SECTION 2 — SEGMENT-LEVEL PURCHASE INTENT ANALYSIS
-- -----------------------------------------------------------------------------------------------------

-- Q2.1: Intent rate by occupation (key insight for targeting)
SELECT
    Occupation,
    COUNT(*)                                                         AS Total,
    SUM(CASE WHEN EV_Purchase_Intent = 'Yes, within 2 years' THEN 1 ELSE 0 END) AS Intend_to_Buy,
    ROUND(
        SUM(CASE WHEN EV_Purchase_Intent = 'Yes, within 2 years' THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1
    )                                                                AS Intent_Pct
FROM survey_responses
GROUP BY Occupation
ORDER BY Intent_Pct DESC;


-- Q2.2: Intent by income bracket (willingness-to-pay correlation)
SELECT
    Monthly_Income_Bracket,
    EV_Purchase_Intent,
    COUNT(*) AS Count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(PARTITION BY Monthly_Income_Bracket), 1) AS Pct_Within_Bracket
FROM survey_responses
GROUP BY Monthly_Income_Bracket, EV_Purchase_Intent
ORDER BY Monthly_Income_Bracket, Count DESC;


-- Q2.3: Intent vs home charging feasibility (infrastructure readiness)
SELECT
    Home_Charging_Feasibility,
    SUM(CASE WHEN EV_Purchase_Intent = 'Yes, within 2 years' THEN 1 ELSE 0 END) AS Intend_Yes,
    COUNT(*)                                                                      AS Total,
    ROUND(
        SUM(CASE WHEN EV_Purchase_Intent = 'Yes, within 2 years' THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1
    )                                                                             AS Intent_Rate_Pct
FROM survey_responses
GROUP BY Home_Charging_Feasibility
ORDER BY Intent_Rate_Pct DESC;


-- Q2.4: Preferred EV type by age group (generational preferences)
SELECT
    Age_Group,
    Preferred_EV_Type,
    COUNT(*) AS Count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(PARTITION BY Age_Group), 1) AS Share_Pct
FROM survey_responses
GROUP BY Age_Group, Preferred_EV_Type
ORDER BY Age_Group, Count DESC;



-- SECTION 3 — BARRIER SEVERITY ANALYSIS
-- -------------------------------------------------------------------------------------------------------------------

-- Q3.1: Top barriers ranked by respondents calling them a major concern
SELECT
    Barrier,
    SUM(CASE WHEN Is_Major_Concern = 'Yes' THEN 1 ELSE 0 END)        AS Major_Concern_Count,
    COUNT(*)                                                           AS Total_Responses,
    ROUND(
        SUM(CASE WHEN Is_Major_Concern = 'Yes' THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1
    )                                                                  AS Severity_Pct,
    ROUND(AVG(Severity_Rating_1to5), 2)                               AS Avg_Severity_Score
FROM barrier_responses
WHERE Severity_Rating_1to5 IS NOT NULL
GROUP BY Barrier
ORDER BY Severity_Pct DESC;


-- Q3.2: Barrier score by occupation — who feels the most friction?
WITH barrier_agg AS (
    SELECT
        s.Occupation,
        b.Barrier,
        ROUND(AVG(b.Barrier_Score), 2) AS Avg_Barrier_Score
    FROM barrier_responses b
    JOIN survey_responses s ON b.Respondent_ID = s.Respondent_ID
    GROUP BY s.Occupation, b.Barrier
),
ranked AS (
    SELECT *,
        RANK() OVER(PARTITION BY Occupation ORDER BY Avg_Barrier_Score DESC) AS rnk
    FROM barrier_agg
)
SELECT Occupation, Barrier, Avg_Barrier_Score
FROM ranked
WHERE rnk = 1
ORDER BY Avg_Barrier_Score DESC;


-- Q3.3: Top 3 barriers per area (geographic barrier mapping)
WITH area_barrier AS (
    SELECT
        s.Area_in_Pune,
        b.Barrier,
        SUM(CASE WHEN b.Is_Major_Concern = 'Yes' THEN 1 ELSE 0 END) AS Concern_Count,
        RANK() OVER(
            PARTITION BY s.Area_in_Pune
            ORDER BY SUM(CASE WHEN b.Is_Major_Concern = 'Yes' THEN 1 ELSE 0 END) DESC
        ) AS rnk
    FROM barrier_responses b
    JOIN survey_responses s ON b.Respondent_ID = s.Respondent_ID
    GROUP BY s.Area_in_Pune, b.Barrier
)
SELECT Area_in_Pune, Barrier, Concern_Count
FROM area_barrier
WHERE rnk <= 3
ORDER BY Area_in_Pune, rnk;



-- SECTION 4 — CHARGING INFRASTRUCTURE ANALYSIS
-- --------------------------------------------------------------------------------------------------------------------------

-- Q4.1: Charging station distribution and utilization by zone
SELECT
    Zone_Pune,
    COUNT(*)                                                      AS Total_Stations,
    SUM(Number_of_Ports)                                          AS Total_Ports,
    ROUND(AVG(Avg_Daily_Sessions), 1)                             AS Avg_Sessions_Per_Day,
    SUM(Monthly_Units_Dispensed_kWh)                              AS Total_Monthly_kWh,
    SUM(CASE WHEN Operational_Status = 'Operational' THEN 1 ELSE 0 END) AS Operational_Count,
    ROUND(
        SUM(CASE WHEN Operational_Status = 'Operational' THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1
    )                                                             AS Operational_Rate_Pct
FROM charging_stations
GROUP BY Zone_Pune
ORDER BY Total_Stations DESC;


-- Q4.2: Station type breakdown and average utilization
SELECT
    Station_Type,
    COUNT(*)                               AS Station_Count,
    ROUND(AVG(Avg_Daily_Sessions), 1)      AS Avg_Daily_Sessions,
    ROUND(AVG(Monthly_Units_Dispensed_kWh)) AS Avg_Monthly_kWh,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM charging_stations), 1) AS Share_Pct
FROM charging_stations
GROUP BY Station_Type
ORDER BY Station_Count DESC;


-- Q4.3: Infrastructure gap — zones with high survey intent but low charging coverage
WITH intent_by_zone AS (
    SELECT
        Area_in_Pune AS Zone,
        COUNT(*) AS Survey_Respondents,
        SUM(CASE WHEN EV_Purchase_Intent = 'Yes, within 2 years' THEN 1 ELSE 0 END) AS High_Intent_Count,
        ROUND(
            SUM(CASE WHEN EV_Purchase_Intent = 'Yes, within 2 years' THEN 1 ELSE 0 END)
            * 100.0 / COUNT(*), 1
        ) AS Intent_Pct
    FROM survey_responses
    GROUP BY Area_in_Pune
),
chargers_by_zone AS (
    SELECT
        Zone_Pune AS Zone,
        COUNT(*) AS Charger_Count,
        SUM(Number_of_Ports) AS Total_Ports
    FROM charging_stations
    WHERE Operational_Status = 'Operational'
    GROUP BY Zone_Pune
)
SELECT
    i.Zone,
    i.Survey_Respondents,
    i.Intent_Pct,
    COALESCE(c.Charger_Count, 0) AS Operational_Chargers,
    COALESCE(c.Total_Ports, 0)   AS Available_Ports,
    CASE
        WHEN i.Intent_Pct >= 60 AND COALESCE(c.Charger_Count, 0) < 5 THEN 'HIGH PRIORITY GAP'
        WHEN i.Intent_Pct >= 40 AND COALESCE(c.Charger_Count, 0) < 8 THEN 'MEDIUM PRIORITY'
        ELSE 'Adequate Coverage'
    END AS Infrastructure_Gap_Flag
FROM intent_by_zone i
LEFT JOIN chargers_by_zone c ON i.Zone = c.Zone
ORDER BY i.Intent_Pct DESC;



-- SECTION 5 — STATE BENCHMARKING (SECONDARY DATA)
-- -----------------------------------------------------------------------------------------------------------------------------

-- Q5.1: Maharashtra vs national peers — sales rank and charger density
SELECT
    State,
    FY2024_25_EV_Registrations,
    National_Sales_Rank,
    Public_Charging_Stations_2025,
    Charging_per_1000_EVs,
    National_Share_Pct,
    RANK() OVER(ORDER BY Charging_per_1000_EVs DESC) AS Charger_Density_Rank
FROM statewise_ev_sales
ORDER BY FY2024_25_EV_Registrations DESC
LIMIT 10;


-- Q5.2: Regional EV performance summary
SELECT
    Region,
    COUNT(*)                                   AS States_Count,
    SUM(FY2024_25_EV_Registrations)            AS Total_EV_Sales,
    ROUND(AVG(Charging_per_1000_EVs), 2)       AS Avg_Charger_Density,
    ROUND(SUM(National_Share_Pct), 1)          AS Regional_Share_Pct
FROM statewise_ev_sales
GROUP BY Region
ORDER BY Total_EV_Sales DESC;


-- Q5.3: Maharashtra market context (single-row summary for reporting)
SELECT
    State,
    FY2024_25_EV_Registrations                          AS MH_EV_Sales_FY25,
    Public_Charging_Stations_2025                        AS MH_Chargers,
    Charging_per_1000_EVs                                AS Chargers_per_1000_EVs,
    National_Share_Pct                                   AS National_Share_Pct,
    National_Sales_Rank                                  AS Sales_Rank,
    (SELECT SUM(FY2024_25_EV_Registrations) FROM statewise_ev_sales) AS National_Total
FROM statewise_ev_sales
WHERE State = 'Maharashtra';



-- SECTION 6 — MH EV REGISTRATION TREND ANALYSIS
-- ------------------------------------------------------------------------------------------------------------------

-- Q6.1: Monthly trend with running total per vehicle category
SELECT
    Month, Year, Vehicle_Category, Registrations,
    MoM_Growth_Pct,
    SUM(Registrations) OVER(
        PARTITION BY Vehicle_Category
        ORDER BY Year, FIELD(Month,'January','February','March','April','May',
                              'June','July','August','September','October','November','December')
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS Cumulative_Registrations
FROM mh_ev_registrations
ORDER BY Year, FIELD(Month,'January','February','March','April'), Vehicle_Category;


-- Q6.2: Month with highest MoM growth per category
WITH ranked_growth AS (
    SELECT *,
        RANK() OVER(PARTITION BY Vehicle_Category ORDER BY MoM_Growth_Pct DESC) AS rnk
    FROM mh_ev_registrations
    WHERE MoM_Growth_Pct IS NOT NULL
)
SELECT Month, Year, Vehicle_Category, Registrations, MoM_Growth_Pct
FROM ranked_growth
WHERE rnk = 1;



-- SECTION 7 — CROSS-DATASET SUMMARY VIEW (FOR POWER BI)
-- -------------------------------------------------------------------------------------------------------------------------------

-- Q7.1: Full respondent profile with intent + top barrier + area charger count
WITH top_barrier AS (
    SELECT
        b.Respondent_ID,
        b.Barrier AS Top_Barrier,
        b.Barrier_Score
    FROM barrier_responses b
    JOIN (
        SELECT Respondent_ID, MAX(Barrier_Score) AS Max_Score
        FROM barrier_responses
        GROUP BY Respondent_ID
    ) mb ON b.Respondent_ID = mb.Respondent_ID AND b.Barrier_Score = mb.Max_Score
),
area_chargers AS (
    SELECT Zone_Pune AS Area, COUNT(*) AS Charger_Count
    FROM charging_stations
    WHERE Operational_Status = 'Operational'
    GROUP BY Zone_Pune
)
SELECT
    s.Respondent_ID,
    s.Occupation,
    s.Age_Group,
    s.Monthly_Income_Bracket,
    s.Area_in_Pune,
    s.EV_Purchase_Intent,
    s.Preferred_EV_Type,
    s.Aware_of_MH_EV_Policy_2025,
    s.Aware_of_EV_Subsidy_Benefits,
    tb.Top_Barrier,
    tb.Barrier_Score         AS Top_Barrier_Score,
    COALESCE(ac.Charger_Count, 0) AS Chargers_In_Area
FROM survey_responses s
LEFT JOIN top_barrier tb ON s.Respondent_ID = tb.Respondent_ID
LEFT JOIN area_chargers ac ON s.Area_in_Pune = ac.Area
ORDER BY s.Respondent_ID;
