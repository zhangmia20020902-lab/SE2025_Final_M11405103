# SE2025 Final Exam - M11405103 張梓榆

This repository contains all required files for the final exam of  
**Software Engineering in Construction Information Systems 2025**.

---

# 📌 ER Model (Mermaid)

```mermaid
erDiagram

    REGION {
        int region_id PK
        varchar region_name
    }

    SUBREGION {
        int subregion_id PK
        varchar subregion_name
        int region_id FK
    }

    INTERMEDIATE_REGION {
        int intermediate_id PK
        varchar intermediate_name
        int subregion_id FK
    }

    COUNTRY {
        int country_id PK
        varchar name
        char alpha2
        char alpha3
        int country_code
        int region_id FK
        int subregion_id FK
        int intermediate_id FK
    }

    MMRRECORD {
        int record_id PK
        int country_id FK
        int year
        float mmr
    }

    REGION ||--o{ SUBREGION : contains
    SUBREGION ||--o{ INTERMEDIATE_REGION : contains
    INTERMEDIATE_REGION ||--o{ COUNTRY : includes
    COUNTRY ||--o{ MMRRECORD : has
```

## Student Info
- Student ID: M11405103  
- Name: 張梓榆


## Contents
- ER Model
- ETL.sql
- Three-tier Web Application (Express + HTML + CSS + HTMX)
- Docker Compose file
- Documentation

## Student Info
- Student ID: M11405103
- Name: 張梓榆
