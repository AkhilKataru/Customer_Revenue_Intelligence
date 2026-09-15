/* ============================================================
   RETAIL SALES & CUSTOMER ANALYTICS
   Dataset: Online Retail II (UCI ML Repository), cleaned
   Table: transactions  (1,027,017 rows, Dec 2009 - Dec 2011)
   ============================================================ */

/* ---------- 1. BASIC: Total revenue, orders, customers ---------- */
SELECT
    ROUND(SUM(Revenue), 2)                         AS total_revenue,
    COUNT(DISTINCT Invoice)                        AS total_orders,
    COUNT(DISTINCT "Customer ID")                  AS total_customers,
    COUNT(DISTINCT Country)                        AS total_countries
FROM transactions
WHERE IsCancelled = 0;

/* ---------- 2. BASIC: Revenue by country (top 10) ---------- */
SELECT
    Country,
    ROUND(SUM(Revenue), 2) AS revenue,
    COUNT(DISTINCT Invoice) AS orders
FROM transactions
WHERE IsCancelled = 0
GROUP BY Country
ORDER BY revenue DESC
LIMIT 10;

/* ---------- 3. INTERMEDIATE: Monthly revenue trend ---------- */
SELECT
    InvoiceMonth,
    ROUND(SUM(Revenue), 2) AS monthly_revenue,
    COUNT(DISTINCT Invoice) AS orders
FROM transactions
WHERE IsCancelled = 0
GROUP BY InvoiceMonth
ORDER BY InvoiceMonth;

/* ---------- 4. INTERMEDIATE: Month-over-month growth using WINDOW FUNCTION (LAG) ---------- */
WITH monthly AS (
    SELECT InvoiceMonth, ROUND(SUM(Revenue), 2) AS revenue
    FROM transactions
    WHERE IsCancelled = 0
    GROUP BY InvoiceMonth
)
SELECT
    InvoiceMonth,
    revenue,
    LAG(revenue) OVER (ORDER BY InvoiceMonth)                       AS prev_month_revenue,
    ROUND( (revenue - LAG(revenue) OVER (ORDER BY InvoiceMonth))
            / LAG(revenue) OVER (ORDER BY InvoiceMonth) * 100, 1)   AS mom_growth_pct
FROM monthly
ORDER BY InvoiceMonth;

/* ---------- 5. INTERMEDIATE: Top 10 products by revenue ---------- */
SELECT
    StockCode,
    Description,
    SUM(Quantity) AS units_sold,
    ROUND(SUM(Revenue), 2) AS revenue
FROM transactions
WHERE IsCancelled = 0
GROUP BY StockCode, Description
ORDER BY revenue DESC
LIMIT 10;

/* ---------- 6. INTERMEDIATE: Discount/loss detector -- products sold below typical price ----------
   CASE WHEN price band segmentation                                                          */
SELECT
    CASE
        WHEN Price < 1  THEN 'Under £1'
        WHEN Price < 5  THEN '£1 - £5'
        WHEN Price < 20 THEN '£5 - £20'
        ELSE 'Over £20'
    END AS price_band,
    COUNT(*) AS line_items,
    ROUND(SUM(Revenue), 2) AS revenue
FROM transactions
WHERE IsCancelled = 0
GROUP BY price_band
ORDER BY revenue DESC;

/* ---------- 7. ADVANCED: RFM Segmentation (Recency, Frequency, Monetary) using CTEs + Window Functions ---------- */
WITH customer_base AS (
    SELECT
        "Customer ID"                                   AS customer_id,
        MAX(InvoiceDate)                                AS last_purchase_date,
        COUNT(DISTINCT Invoice)                         AS frequency,
        ROUND(SUM(Revenue), 2)                          AS monetary
    FROM transactions
    WHERE IsCancelled = 0 AND "Customer ID" IS NOT NULL
    GROUP BY "Customer ID"
),
scored AS (
    SELECT
        customer_id,
        frequency,
        monetary,
        julianday('2011-12-10') - julianday(last_purchase_date) AS recency_days,
        NTILE(4) OVER (ORDER BY julianday(last_purchase_date) DESC)  AS recency_score,
        NTILE(4) OVER (ORDER BY frequency)                            AS frequency_score,
        NTILE(4) OVER (ORDER BY monetary)                             AS monetary_score
    FROM customer_base
)
SELECT
    customer_id,
    ROUND(recency_days) AS recency_days,
    frequency,
    monetary,
    recency_score, frequency_score, monetary_score,
    (recency_score + frequency_score + monetary_score) AS rfm_total,
    CASE
        WHEN recency_score >= 3 AND frequency_score >= 3 AND monetary_score >= 3 THEN 'Champion'
        WHEN recency_score <= 2 AND frequency_score >= 3 THEN 'At Risk (was loyal)'
        WHEN recency_score >= 3 AND frequency_score <= 2 THEN 'New / Recent'
        ELSE 'Needs Attention'
    END AS segment
FROM scored
ORDER BY rfm_total DESC
LIMIT 20;

/* ---------- 8. ADVANCED: Customer segment summary (aggregated RFM) ---------- */
WITH customer_base AS (
    SELECT
        "Customer ID" AS customer_id,
        MAX(InvoiceDate) AS last_purchase_date,
        COUNT(DISTINCT Invoice) AS frequency,
        SUM(Revenue) AS monetary
    FROM transactions
    WHERE IsCancelled = 0 AND "Customer ID" IS NOT NULL
    GROUP BY "Customer ID"
),
scored AS (
    SELECT *,
        NTILE(4) OVER (ORDER BY julianday(last_purchase_date) DESC) AS recency_score,
        NTILE(4) OVER (ORDER BY frequency) AS frequency_score,
        NTILE(4) OVER (ORDER BY monetary) AS monetary_score
    FROM customer_base
),
segmented AS (
    SELECT *,
        CASE
            WHEN recency_score >= 3 AND frequency_score >= 3 AND monetary_score >= 3 THEN 'Champion'
            WHEN recency_score <= 2 AND frequency_score >= 3 THEN 'At Risk (was loyal)'
            WHEN recency_score >= 3 AND frequency_score <= 2 THEN 'New / Recent'
            ELSE 'Needs Attention'
        END AS segment
    FROM scored
)
SELECT
    segment,
    COUNT(*) AS customer_count,
    ROUND(AVG(monetary), 2) AS avg_customer_value,
    ROUND(SUM(monetary), 2) AS total_segment_revenue
FROM segmented
GROUP BY segment
ORDER BY total_segment_revenue DESC;

/* ---------- 9. ADVANCED: Ranking top product per country (RANK / PARTITION BY) ---------- */
WITH product_country AS (
    SELECT
        Country, StockCode, Description,
        SUM(Revenue) AS revenue
    FROM transactions
    WHERE IsCancelled = 0
    GROUP BY Country, StockCode, Description
),
ranked AS (
    SELECT *,
        RANK() OVER (PARTITION BY Country ORDER BY revenue DESC) AS rnk
    FROM product_country
)
SELECT Country, StockCode, Description, ROUND(revenue,2) AS revenue
FROM ranked
WHERE rnk = 1
ORDER BY revenue DESC
LIMIT 15;

/* ---------- 10. ADVANCED: Running total of revenue by month (window function) ---------- */
WITH monthly AS (
    SELECT InvoiceMonth, SUM(Revenue) AS revenue
    FROM transactions
    WHERE IsCancelled = 0
    GROUP BY InvoiceMonth
)
SELECT
    InvoiceMonth,
    ROUND(revenue, 2) AS revenue,
    ROUND(SUM(revenue) OVER (ORDER BY InvoiceMonth), 2) AS running_total_revenue
FROM monthly
ORDER BY InvoiceMonth;

/* ---------- 11. ADVANCED: Cancellation rate by country (business risk signal) ---------- */
SELECT
    Country,
    COUNT(DISTINCT Invoice) AS total_invoices,
    COUNT(DISTINCT CASE WHEN IsCancelled = 1 THEN Invoice END) AS cancelled_invoices,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN IsCancelled = 1 THEN Invoice END)
          / COUNT(DISTINCT Invoice), 1) AS cancellation_rate_pct
FROM transactions
GROUP BY Country
HAVING total_invoices >= 50
ORDER BY cancellation_rate_pct DESC
LIMIT 10;

/* ---------- 12. ADVANCED: Best hour/day of week to send campaigns (sales pattern) ---------- */
SELECT
    DayOfWeek,
    Hour,
    ROUND(SUM(Revenue), 2) AS revenue,
    COUNT(DISTINCT Invoice) AS orders
FROM transactions
WHERE IsCancelled = 0
GROUP BY DayOfWeek, Hour
ORDER BY revenue DESC
LIMIT 10;
