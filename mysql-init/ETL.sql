-- ETL.sql
-- SE2025 Final Exam - M11405103 張梓榆
-- Purpose:
--  1. Create a normalized database schema for MMR data (3NF).
--  2. Load raw CSV data into staging tables (all VARCHAR for safety).
--  3. Transform and insert data into normalized tables.
--  4. Remove erroneous / invalid data during ETL.

-- =========================================================
-- 0. Create / use database
-- =========================================================
DROP DATABASE IF EXISTS mmr2025;
CREATE DATABASE mmr2025
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE mmr2025;

-- =========================================================
-- 1. Drop tables if they exist (correct dependency order)
-- =========================================================
DROP TABLE IF EXISTS MMRRECORD;
DROP TABLE IF EXISTS COUNTRY;
DROP TABLE IF EXISTS INTERMEDIATE_REGION;
DROP TABLE IF EXISTS SUBREGION;
DROP TABLE IF EXISTS REGION;
DROP TABLE IF EXISTS RAW_DATA1;
DROP TABLE IF EXISTS RAW_DATA2;

-- =========================================================
-- 2. Create staging tables for raw CSV data
--    *** All columns are VARCHAR to avoid load-time errors. ***
-- =========================================================

-- RAW_DATA1 corresponds to data1.csv (MMR facts)
CREATE TABLE RAW_DATA1 (
    entity    VARCHAR(255),
    code      VARCHAR(20),
    year_str  VARCHAR(10),
    mmr_str   VARCHAR(50)
);

-- RAW_DATA2 corresponds to data2.csv (countries / regions)
CREATE TABLE RAW_DATA2 (
    name                          VARCHAR(255),
    alpha2                        VARCHAR(10),
    alpha3                        VARCHAR(10),
    country_code_str              VARCHAR(20),
    iso_3166_2                    VARCHAR(50),
    region                        VARCHAR(100),
    sub_region                    VARCHAR(100),
    intermediate_region           VARCHAR(100),
    region_code_str               VARCHAR(20),
    sub_region_code_str           VARCHAR(20),
    intermediate_region_code_str  VARCHAR(20)
);

-- =========================================================
-- 3. Load CSV data into staging tables (server-side LOAD DATA)
--    Files must exist in /var/lib/mysql-files in Docker container.
-- =========================================================

LOAD DATA INFILE '/var/lib/mysql-files/data1.csv'
INTO TABLE RAW_DATA1
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(entity, code, year_str, mmr_str);

LOAD DATA INFILE '/var/lib/mysql-files/data2.csv'
INTO TABLE RAW_DATA2
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(name, alpha2, alpha3, country_code_str, iso_3166_2,
 region, sub_region, intermediate_region,
 region_code_str, sub_region_code_str, intermediate_region_code_str);

-- =========================================================
-- 4. Create normalized tables (3NF)
--    These correspond to the ER diagram in README.
-- =========================================================

-- REGION: top-level region (continent)
CREATE TABLE REGION (
    region_id   INT AUTO_INCREMENT PRIMARY KEY,
    region_name VARCHAR(100) NOT NULL,
    CONSTRAINT uq_region_name UNIQUE (region_name)
);

-- SUBREGION: sub-region belonging to a region
CREATE TABLE SUBREGION (
    subregion_id   INT AUTO_INCREMENT PRIMARY KEY,
    subregion_name VARCHAR(100) NOT NULL,
    region_id      INT NOT NULL,
    CONSTRAINT fk_subregion_region
        FOREIGN KEY (region_id) REFERENCES REGION(region_id),
    CONSTRAINT uq_subregion_name_region
        UNIQUE (subregion_name, region_id)
);

-- INTERMEDIATE_REGION: intermediate region (may be NULL for some countries)
CREATE TABLE INTERMEDIATE_REGION (
    intermediate_id   INT AUTO_INCREMENT PRIMARY KEY,
    intermediate_name VARCHAR(100) NOT NULL,
    subregion_id      INT NOT NULL,
    CONSTRAINT fk_intermediate_subregion
        FOREIGN KEY (subregion_id) REFERENCES SUBREGION(subregion_id),
    CONSTRAINT uq_intermediate_name_subregion
        UNIQUE (intermediate_name, subregion_id)
);

-- COUNTRY: country information + links to region hierarchy
CREATE TABLE COUNTRY (
    country_id      INT AUTO_INCREMENT PRIMARY KEY,
    name            VARCHAR(200) NOT NULL,
    alpha2          CHAR(2),
    alpha3          CHAR(3),
    country_code    INT,
    region_id       INT NOT NULL,
    subregion_id    INT NOT NULL,
    intermediate_id INT NULL,
    CONSTRAINT uq_country_alpha3 UNIQUE (alpha3),
    CONSTRAINT uq_country_code UNIQUE (country_code),
    CONSTRAINT fk_country_region
        FOREIGN KEY (region_id) REFERENCES REGION(region_id),
    CONSTRAINT fk_country_subregion
        FOREIGN KEY (subregion_id) REFERENCES SUBREGION(subregion_id),
    CONSTRAINT fk_country_intermediate
        FOREIGN KEY (intermediate_id) REFERENCES INTERMEDIATE_REGION(intermediate_id)
);

-- MMRRECORD: MMR per country per year
CREATE TABLE MMRRECORD (
    record_id  INT AUTO_INCREMENT PRIMARY KEY,
    country_id INT NOT NULL,
    year       INT NOT NULL,
    mmr        DECIMAL(10,2) NOT NULL,
    CONSTRAINT fk_mmr_country
        FOREIGN KEY (country_id) REFERENCES COUNTRY(country_id),
    CONSTRAINT uq_mmr_country_year
        UNIQUE (country_id, year)
);

-- =========================================================
-- 5. Populate normalized tables from staging tables
-- =========================================================

-- 5.1 Insert regions (distinct non-empty region names)
INSERT INTO REGION (region_name)
SELECT DISTINCT TRIM(region)
FROM RAW_DATA2
WHERE region IS NOT NULL
  AND TRIM(region) <> '';

-- 5.2 Insert subregions, linked to regions
INSERT INTO SUBREGION (subregion_name, region_id)
SELECT DISTINCT
       TRIM(d.sub_region)    AS subregion_name,
       r.region_id
FROM RAW_DATA2 d
JOIN REGION r
  ON r.region_name = TRIM(d.region)
WHERE d.sub_region IS NOT NULL
  AND TRIM(d.sub_region) <> '';

-- 5.3 Insert intermediate regions, linked to subregions
INSERT INTO INTERMEDIATE_REGION (intermediate_name, subregion_id)
SELECT DISTINCT
       TRIM(d.intermediate_region) AS intermediate_name,
       s.subregion_id
FROM RAW_DATA2 d
JOIN REGION r
  ON r.region_name = TRIM(d.region)
JOIN SUBREGION s
  ON s.subregion_name = TRIM(d.sub_region)
 AND s.region_id      = r.region_id
WHERE d.intermediate_region IS NOT NULL
  AND TRIM(d.intermediate_region) <> ''
  AND TRIM(d.intermediate_region) <> 'NaN';

-- 5.4 Insert countries, linked to region / subregion / intermediate region
INSERT INTO COUNTRY (
    name, alpha2, alpha3, country_code,
    region_id, subregion_id, intermediate_id
)
SELECT DISTINCT
    TRIM(d.name)                              AS name,
    d.alpha2,
    d.alpha3,
    CASE
        WHEN d.country_code_str IS NULL OR TRIM(d.country_code_str) = '' THEN NULL
        ELSE CAST(d.country_code_str AS UNSIGNED)
    END                                       AS country_code,
    r.region_id,
    s.subregion_id,
    ir.intermediate_id
FROM RAW_DATA2 d
JOIN REGION r
  ON r.region_name = TRIM(d.region)
JOIN SUBREGION s
  ON s.subregion_name = TRIM(d.sub_region)
 AND s.region_id      = r.region_id
LEFT JOIN INTERMEDIATE_REGION ir
  ON ir.intermediate_name = TRIM(d.intermediate_region)
 AND ir.subregion_id      = s.subregion_id
WHERE d.name IS NOT NULL
  AND TRIM(d.name) <> '';

-- 5.5 Insert MMR records
--     - Join RAW_DATA1 with COUNTRY using alpha3/code
--     - Ignore rows with NULL / empty / non-numeric MMR or year
INSERT INTO MMRRECORD (country_id, year, mmr)
SELECT
    c.country_id,
    CAST(d.year_str AS SIGNED)                    AS year,
    CAST(d.mmr_str  AS DECIMAL(10,2))             AS mmr
FROM RAW_DATA1 d
JOIN COUNTRY c
  ON c.alpha3 = d.code
WHERE d.mmr_str IS NOT NULL
  AND TRIM(d.mmr_str) <> ''
  AND d.year_str IS NOT NULL
  AND TRIM(d.year_str) <> '';

-- =========================================================
-- 6. Row count sanity check (optional)
-- =========================================================

SELECT 'REGION' AS table_name, COUNT(*) AS row_count FROM REGION
UNION ALL
SELECT 'SUBREGION', COUNT(*) FROM SUBREGION
UNION ALL
SELECT 'INTERMEDIATE_REGION', COUNT(*) FROM INTERMEDIATE_REGION
UNION ALL
SELECT 'COUNTRY', COUNT(*) FROM COUNTRY
UNION ALL
SELECT 'MMRRECORD', COUNT(*) FROM MMRRECORD;
