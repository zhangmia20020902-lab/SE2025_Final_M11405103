-- ==========================================================
--  ETL.sql  
--  Final Exam - Software Engineering in Construction IS
--  Student: M11405103 張梓榆
--  Purpose: Create database tables (3NF) and import cleaned
--           data from data1.csv (facts) and data2.csv (regions)
-- ==========================================================

-- ----------------------------------------------------------
-- 0. Create database (optional but recommended)
-- ----------------------------------------------------------
DROP DATABASE IF EXISTS mmr2025;
CREATE DATABASE mmr2025;
USE mmr2025;

-- ----------------------------------------------------------
-- 1. Drop tables in correct dependency order
-- ----------------------------------------------------------
DROP TABLE IF EXISTS MMRRECORD;
DROP TABLE IF EXISTS COUNTRY;
DROP TABLE IF EXISTS SUBREGION;
DROP TABLE IF EXISTS REGION;

-- ----------------------------------------------------------
-- 2. Create REGION table
-- ----------------------------------------------------------
CREATE TABLE REGION (
    region_id INT AUTO_INCREMENT PRIMARY KEY,
    region_name VARCHAR(100) NOT NULL
);

-- ----------------------------------------------------------
-- 3. Create SUBREGION table
-- ----------------------------------------------------------
CREATE TABLE SUBREGION (
    subregion_id INT AUTO_INCREMENT PRIMARY KEY,
    subregion_name VARCHAR(100) NOT NULL,
    region_id INT NOT NULL,
    FOREIGN KEY (region_id) REFERENCES REGION(region_id)
);

-- ----------------------------------------------------------
-- 4. Create COUNTRY table
-- ----------------------------------------------------------
CREATE TABLE COUNTRY (
    country_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    alpha2 CHAR(2),
    alpha3 CHAR(3),
    country_code INT,
    subregion_id INT NOT NULL,
    FOREIGN KEY (subregion_id) REFERENCES SUBREGION(subregion_id)
);

-- ----------------------------------------------------------
-- 5. Create MMRRECORD table
-- ----------------------------------------------------------
CREATE TABLE MMRRECORD (
    record_id INT AUTO_INCREMENT PRIMARY KEY,
    country_id INT NOT NULL,
    year INT NOT NULL,
    mmr FLOAT,
    FOREIGN KEY (country_id) REFERENCES COUNTRY(country_id)
);

-- ==========================================================
-- SECTION B: ETL FOR REGION + SUBREGION + COUNTRY
-- Using data2.csv
-- ==========================================================

-- ----------------------------------------------------------
-- 6. Load raw data2.csv into a temporary staging table
-- ----------------------------------------------------------
DROP TABLE IF EXISTS staging_data2;

CREATE TABLE staging_data2 (
    name VARCHAR(200),
    alpha2 VARCHAR(10),
    alpha3 VARCHAR(10),
    country_code VARCHAR(20),
    iso3166 VARCHAR(20),
    region VARCHAR(200),
    subregion VARCHAR(200),
    intermediate_region VARCHAR(200),
    region_code VARCHAR(20),
    subregion_code VARCHAR(20),
    intermediate_code VARCHAR(20)
);

-- ----------------------------------------------------------
-- 7. Import CSV into staging table  
-- ⚠️ 注意：你的 CSV 路徑需依照 MySQL Docker 的資料夾調整
-- ----------------------------------------------------------
LOAD DATA LOCAL INFILE 'data2.csv'
INTO TABLE staging_data2
FIELDS TERMINATED BY ',' 
OPTIONALLY ENCLOSED BY '"'
IGNORE 1 ROWS;

-- ----------------------------------------------------------
-- 8. Insert REGION (distinct regions)
-- ----------------------------------------------------------
INSERT INTO REGION (region_name)
SELECT DISTINCT region
FROM staging_data2
WHERE region IS NOT NULL AND region != '';

-- ----------------------------------------------------------
-- 9. Insert SUBREGION + connect to REGION
-- ----------------------------------------------------------
INSERT INTO SUBREGION (subregion_name, region_id)
SELECT DISTINCT s.subregion,
       r.region_id
FROM staging_data2 s
JOIN REGION r ON s.region = r.region_name
WHERE s.subregion IS NOT NULL AND s.subregion != '';

-- ----------------------------------------------------------
-- 10. Insert COUNTRY, linked to SUBREGION
-- ----------------------------------------------------------
INSERT INTO COUNTRY (name, alpha2, alpha3, country_code, subregion_id)
SELECT 
    s.name,
    s.alpha2,
    s.alpha3,
    CAST(s.country_code AS UNSIGNED),
    sub.subregion_id
FROM staging_data2 s
JOIN SUBREGION sub ON s.subregion = sub.subregion_name
WHERE s.name IS NOT NULL AND s.name != '';

-- ==========================================================
-- SECTION C: ETL FOR MMR RECORDS
-- Using data1.csv
-- ==========================================================

-- ----------------------------------------------------------
-- 11. Load raw data1.csv into staging table
-- ----------------------------------------------------------
DROP TABLE IF EXISTS staging_data1;

CREATE TABLE staging_data1 (
    Entity VARCHAR(200),
    Code VARCHAR(10),
    Year INT,
    MMR FLOAT
);

LOAD DATA LOCAL INFILE 'data1.csv'
INTO TABLE staging_data1
FIELDS TERMINATED BY ',' 
OPTIONALLY ENCLOSED BY '"'
IGNORE 1 ROWS;

-- ----------------------------------------------------------
-- 12. Insert cleaned MMR records
--     Remove rows that:
--       • do not match a country in COUNTRY table
--       • have NULL or invalid MMR
-- ----------------------------------------------------------
INSERT INTO MMRRECORD (country_id, year, mmr)
SELECT 
    c.country_id,
    s.Year,
    s.MMR
FROM staging_data1 s
JOIN COUNTRY c ON c.alpha3 = s.Code
WHERE s.MMR IS NOT NULL AND s.MMR >= 0;

-- ==========================================================
-- COMPLETED
-- Your normalized database (3NF) is now fully loaded.
-- ==========================================================
