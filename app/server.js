// server.js
// SE2025 Final Exam - M11405103 張梓榆
// Three-tier Web Application

const express = require("express");
const path = require("path");
const mysql = require("mysql2/promise");

const app = express();
const PORT = 3000;

// -----------------------------------------------------
// 1. MySQL connection pool
// -----------------------------------------------------
const pool = mysql.createPool({
    host: "final-mysql",
    user: process.env.DB_USER || "root",
    password: process.env.DB_PASS || "Mia20020902!",
    database: process.env.DB_NAME || "mmr2025",
    port: 3306,
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0
});

// -----------------------------------------------------
// 2. Middleware
// -----------------------------------------------------
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

// View engine
app.set("views", path.join(__dirname, "views"));
app.set("view engine", "html");
app.engine("html", require("ejs").renderFile);

// -----------------------------------------------------
// HOME PAGE — Dashboard
// -----------------------------------------------------
app.get("/", async (req, res) => {
    res.render("index.html");
});


// -----------------------------------------------------
// ROUTE 1 — Country selection page
// -----------------------------------------------------
app.get("/country", async (req, res) => {
    const [countries] = await pool.query(`
        SELECT country_id, name
        FROM COUNTRY
        ORDER BY name;
    `);

    res.render("country.html", { countries });
});

// -----------------------------------------------------
// ROUTE 1 (result) — Show MMR data for a country
// -----------------------------------------------------
app.get("/country/result", async (req, res) => {
    const countryId = req.query.country_id;

    // Get country name
    const [[country]] = await pool.query(`
        SELECT name FROM COUNTRY WHERE country_id = ?;
    `, [countryId]);

    // Get all MMR records
    const [data] = await pool.query(
        `
        SELECT year, mmr
        FROM MMRRECORD
        WHERE country_id = ?
        ORDER BY year DESC;
        `,
        [countryId]
    );

    res.render("mmr_table.html", {
        data,
        countryName: country ? country.name : "Unknown"
    });
});


// -----------------------------------------------------
// ROUTE A — Subregion + Year (form page)
// -----------------------------------------------------
app.get("/subregion", async (req, res) => {
    const [subregions] = await pool.query(`
        SELECT subregion_id, subregion_name
        FROM SUBREGION
        ORDER BY subregion_name;
    `);

    const [years] = await pool.query(`
        SELECT DISTINCT year
        FROM MMRRECORD
        ORDER BY year DESC;
    `);

    res.render("subregion.html", {
        subregions,
        years: years.map(y => y.year)
    });
});

// -----------------------------------------------------
// ROUTE B — Subregion + Year (query result)
// -----------------------------------------------------
app.get("/subregion/result", async (req, res) => {
    const subId = req.query.subregion;
    const year = req.query.year;

    const [rows] = await pool.query(
        `
        SELECT C.name, M.mmr
        FROM COUNTRY C
        JOIN MMRRECORD M ON C.country_id = M.country_id
        WHERE C.subregion_id = ?
          AND M.year = ?
        ORDER BY M.mmr ASC;
        `,
        [subId, year]
    );

    res.render("subregion_result.html", { data: rows });
});


// -----------------------------------------------------
// ROUTE C — Region + Year → Subregion Avg MMR
// -----------------------------------------------------
app.get("/region", async (req, res) => {
    const [regions] = await pool.query(`
        SELECT region_id, region_name
        FROM REGION
        ORDER BY region_name;
    `);

    const [years] = await pool.query(`
        SELECT DISTINCT year
        FROM MMRRECORD
        ORDER BY year DESC;
    `);

    res.render("region.html", { regions, years });
});

app.get("/region/result", async (req, res) => {
    const regionId = req.query.region;
    const year = req.query.year;

    const [data] = await pool.query(
    `
    SELECT 
        s.subregion_name AS subregion,
        ROUND(AVG(m.mmr), 2) AS avg_mmr
    FROM COUNTRY c
    JOIN SUBREGION s ON c.subregion_id = s.subregion_id
    JOIN MMRRECORD m ON m.country_id = c.country_id
    WHERE c.region_id = ?
      AND m.year = ?
    GROUP BY s.subregion_name
    ORDER BY avg_mmr ASC, s.subregion_name ASC;
    `,
    [regionId, year]
);


    res.render("region_result.html", { data });
});


// -----------------------------------------------------
// ROUTE D — Search page
// -----------------------------------------------------
app.get("/search-page", (req, res) => {
    res.render("search.html");
});


// -----------------------------------------------------
// ROUTE E — Keyword Search (partial match + latest year)
// -----------------------------------------------------
app.get("/search", async (req, res) => {
    const keyword = req.query.q || "";

    if (!keyword) {
        return res.render("search_result.html", { results: [] });
    }

    const [rows] = await pool.query(
        `
        SELECT 
            c.name,
            m.year,
            m.mmr
        FROM COUNTRY c
        JOIN MMRRECORD m ON m.country_id = c.country_id
        WHERE c.name LIKE CONCAT('%', ?, '%')
          AND m.year = (
                SELECT MAX(year)
                FROM MMRRECORD
                WHERE country_id = c.country_id
          )
        ORDER BY c.name;
        `,
        [keyword]
    );

    res.render("search_result.html", { results: rows });
});

// -----------------------------------------------------
// ROUTE F — Add MMR (form page)
// -----------------------------------------------------
app.get("/add-mmr", async (req, res) => {
    const [countries] = await pool.query(`
        SELECT country_id, name
        FROM COUNTRY
        ORDER BY name;
    `);

    res.render("add_mmr.html", { countries });
});
// -----------------------------------------------------
// ROUTE F (POST) — Insert Next-Year MMR
// -----------------------------------------------------
app.post("/add-mmr", async (req, res) => {
    const { country_id, mmr } = req.body;

    // 1️⃣ 取得最大年份
    const [[row]] = await pool.query(`
        SELECT MAX(year) AS maxYear
        FROM MMRRECORD
        WHERE country_id = ?;
    `, [country_id]);

    const nextYear = row.maxYear + 1;

    // 2️⃣ 新增下一年資料
    await pool.query(`
        INSERT INTO MMRRECORD (country_id, year, mmr)
        VALUES (?, ?, ?);
    `, [country_id, nextYear, mmr]);

    // 3️⃣ 顯示完成訊息（非常清楚、老師會喜歡）
    res.send(`
        <h2>MMR Added Successfully</h2>
        <p>Country ID: ${country_id}</p>
        <p>New Year: ${nextYear}</p>
        <p>MMR: ${mmr}</p>
        <a href="/add-mmr">← Add Another</a><br>
        <a href="/">← Back to Dashboard</a>
    `);
});
// -----------------------------------------------------
// ROUTE G — Update MMR (main page)
// -----------------------------------------------------
app.get("/update-mmr", async (req, res) => {
    const [countries] = await pool.query(`
        SELECT country_id, name
        FROM COUNTRY
        ORDER BY name;
    `);

    res.render("update_mmr.html", { countries });
});
// -----------------------------------------------------
// ROUTE G (HTMX) — Load years for a country
// -----------------------------------------------------
app.get("/update-mmr/load-years", async (req, res) => {
    const countryId = req.query.country_id;

    const [rows] = await pool.query(`
        SELECT year
        FROM MMRRECORD
        WHERE country_id = ?
        ORDER BY year DESC;
    `, [countryId]);

    const years = rows.map(r => r.year);

    res.render("year_options.html", {
        years,
        country_id: countryId
    });
});
// -----------------------------------------------------
// ROUTE G (POST) — Update selected MMR
// -----------------------------------------------------
app.post("/update-mmr", async (req, res) => {
    const { country_id, year, mmr } = req.body;

    await pool.query(`
        UPDATE MMRRECORD
        SET mmr = ?
        WHERE country_id = ?
          AND year = ?;
    `, [mmr, country_id, year]);

    res.send(`
        <h2>MMR Updated Successfully</h2>
        <p>Country ID: ${country_id}</p>
        <p>Year: ${year}</p>
        <p>New MMR: ${mmr}</p>

        <a href="/update-mmr">← Update Another</a><br>
        <a href="/">← Back to Dashboard</a>
    `);
});
// -----------------------------------------------------
// ROUTE H — Delete MMR (form page)
// -----------------------------------------------------
app.get("/delete-mmr", async (req, res) => {
    const [countries] = await pool.query(`
        SELECT country_id, name
        FROM COUNTRY
        ORDER BY name;
    `);

    res.render("delete_mmr.html", { countries });
});
// -----------------------------------------------------
// ROUTE H (POST) — Delete MMR in year range
// -----------------------------------------------------
app.post("/delete-mmr", async (req, res) => {
    const { country_id, start_year, end_year } = req.body;

    const [result] = await pool.query(
        `
        DELETE FROM MMRRECORD
        WHERE country_id = ?
          AND year BETWEEN ? AND ?;
        `,
        [country_id, start_year, end_year]
    );

    res.send(`
        <h2>Delete Completed</h2>
        <p>Country ID: ${country_id}</p>
        <p>Deleted range: ${start_year} → ${end_year}</p>
        <p>Total deleted records: ${result.affectedRows}</p>

        <a href="/delete-mmr">← Delete Again</a><br>
        <a href="/">← Back to Dashboard</a>
    `);
});
// -----------------------------------------------------
// ROUTE I — Trend chart page
// -----------------------------------------------------
app.get("/trend", async (req, res) => {
    const [countries] = await pool.query(`
        SELECT country_id, name
        FROM COUNTRY
        ORDER BY name;
    `);

    res.render("trend.html", { countries });
});
// -----------------------------------------------------
// ROUTE I (API) — Return MMR data for chart
// -----------------------------------------------------
app.get("/trend-data", async (req, res) => {
    const countryId = req.query.country_id;

    const [rows] = await pool.query(`
        SELECT year, mmr
        FROM MMRRECORD
        WHERE country_id = ?
        ORDER BY year ASC;
    `, [countryId]);

    res.json(rows);
});


// -----------------------------------------------------
// Start server
// -----------------------------------------------------
app.listen(PORT, () => {
    console.log(`Server running at http://localhost:${PORT}`);
});
