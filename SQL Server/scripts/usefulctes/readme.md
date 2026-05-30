# Reusable CTE Templates for SQL Reporting

This repository note collects five practical Common Table Expression (CTE) patterns that are useful in day-to-day SQL reporting, database administration, and data engineering work.

The examples are written mainly in **SQL Server / T-SQL** style, with PostgreSQL notes where the syntax differs. The table and column names are intentionally generic so the queries can be adapted quickly to real reporting use cases.

## Contents

1. [Running Total and Period Comparison](#1-running-total-and-period-comparison)
2. [Top N per Group](#2-top-n-per-group)
3. [Year-over-Year and Month-over-Month Comparison](#3-year-over-year-and-month-over-month-comparison)
4. [Finding Gaps in Dates or Sequences](#4-finding-gaps-in-dates-or-sequences)
5. [Sessionization: Grouping Consecutive Events](#5-sessionization-grouping-consecutive-events)
6. [Quick Reference](#quick-reference)

---

## Why CTEs are useful for reporting

CTEs make reporting queries easier to read, test, and maintain by breaking the logic into named steps. They are especially useful when a report needs:

- pre-aggregation before window functions
- ranking inside groups
- period-over-period comparison
- gap detection
- event grouping or session logic

In many reporting tasks, the goal is not to write the shortest possible query. The goal is to write a query that another DBA, data engineer, analyst, or future version of yourself can understand quickly.

---

## 1. Running Total and Period Comparison

**Use case:** sales reports, KPI dashboards, revenue tracking, cumulative metrics.

```sql
WITH daily_stats AS (
    SELECT
        CAST(order_date AS DATE) AS report_date,
        COUNT(*)                 AS total_orders,
        SUM(amount)              AS daily_revenue
    FROM orders
    GROUP BY CAST(order_date AS DATE)
),
with_running AS (
    SELECT
        report_date,
        total_orders,
        daily_revenue,
        SUM(daily_revenue) OVER (
            ORDER BY report_date
            ROWS UNBOUNDED PRECEDING
        ) AS cumulative_revenue,
        LAG(daily_revenue, 1) OVER (
            ORDER BY report_date
        ) AS previous_day_revenue
    FROM daily_stats
)
SELECT
    report_date,
    total_orders,
    daily_revenue,
    cumulative_revenue,
    ROUND(
        (daily_revenue - previous_day_revenue)
        / NULLIF(previous_day_revenue, 0) * 100.0,
        2
    ) AS pct_change_vs_previous_day
FROM with_running
ORDER BY report_date;
```

### Notes

- `SUM() OVER (ORDER BY ...)` calculates a running total.
- `LAG()` compares the current row with a previous row.
- `NULLIF(previous_day_revenue, 0)` prevents division-by-zero errors.
- `100.0` helps avoid integer-division issues in SQL Server.

---

## 2. Top N per Group

**Use case:** top customers per region, best-selling products per category, highest-cost queries per database.

```sql
WITH ranked AS (
    SELECT
        region,
        customer_name,
        SUM(revenue) AS total_revenue,
        RANK() OVER (
            PARTITION BY region
            ORDER BY SUM(revenue) DESC
        ) AS revenue_rank
    FROM sales
    GROUP BY region, customer_name
)
SELECT
    region,
    customer_name,
    total_revenue,
    revenue_rank
FROM ranked
WHERE revenue_rank <= 3
ORDER BY region, revenue_rank;
```

### Notes

- `RANK()` keeps ties. If two customers have the same revenue, they receive the same rank.
- Use `ROW_NUMBER()` when you need exactly N rows per group, regardless of ties.
- Use `DENSE_RANK()` when you want ties without gaps in the ranking sequence.

---

## 3. Year-over-Year and Month-over-Month Comparison

**Use case:** monthly management reports, growth analysis, financial dashboards.

```sql
WITH monthly AS (
    SELECT
        YEAR(order_date)  AS report_year,
        MONTH(order_date) AS report_month,
        COUNT(*)          AS orders,
        SUM(amount)       AS revenue
    FROM orders
    GROUP BY
        YEAR(order_date),
        MONTH(order_date)
),
with_lag AS (
    SELECT
        report_year,
        report_month,
        orders,
        revenue,
        LAG(revenue, 12) OVER (
            ORDER BY report_year, report_month
        ) AS revenue_last_year,
        LAG(revenue, 1) OVER (
            ORDER BY report_year, report_month
        ) AS revenue_last_month
    FROM monthly
)
SELECT
    CONCAT(
        report_year,
        '-',
        RIGHT('0' + CAST(report_month AS VARCHAR(2)), 2)
    ) AS report_period,
    orders,
    revenue,
    revenue_last_year,
    ROUND(
        (revenue - revenue_last_year)
        / NULLIF(revenue_last_year, 0) * 100.0,
        2
    ) AS yoy_pct,
    revenue_last_month,
    ROUND(
        (revenue - revenue_last_month)
        / NULLIF(revenue_last_month, 0) * 100.0,
        2
    ) AS mom_pct
FROM with_lag
ORDER BY report_year, report_month;
```

### Notes

- `LAG(revenue, 12)` compares the current month with the same month in the previous year.
- `LAG(revenue, 1)` compares the current month with the previous month.
- This approach assumes that every month exists in the aggregated result.
- If some months are missing, build a calendar/month table first and left join the facts to it.

---

## 4. Finding Gaps in Dates or Sequences

**Use case:** missing invoice numbers, missing reporting days, audit checks, data quality validation.

### SQL Server example: missing dates

```sql
WITH date_bounds AS (
    SELECT
        MIN(CAST(order_date AS DATE)) AS start_date,
        MAX(CAST(order_date AS DATE)) AS end_date
    FROM orders
),
numbers AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM sys.all_objects
),
all_dates AS (
    SELECT
        DATEADD(DAY, n, start_date) AS report_date
    FROM date_bounds
    CROSS JOIN numbers
    WHERE DATEADD(DAY, n, start_date) <= end_date
),
active_dates AS (
    SELECT DISTINCT
        CAST(order_date AS DATE) AS report_date
    FROM orders
)
SELECT
    all_dates.report_date AS missing_date
FROM all_dates
LEFT JOIN active_dates
    ON all_dates.report_date = active_dates.report_date
WHERE active_dates.report_date IS NULL
ORDER BY all_dates.report_date;
```

### PostgreSQL version

```sql
WITH date_bounds AS (
    SELECT
        MIN(order_date::DATE) AS start_date,
        MAX(order_date::DATE) AS end_date
    FROM orders
),
all_dates AS (
    SELECT
        generate_series(start_date, end_date, INTERVAL '1 day')::DATE AS report_date
    FROM date_bounds
),
active_dates AS (
    SELECT DISTINCT
        order_date::DATE AS report_date
    FROM orders
)
SELECT
    all_dates.report_date AS missing_date
FROM all_dates
LEFT JOIN active_dates
    ON all_dates.report_date = active_dates.report_date
WHERE active_dates.report_date IS NULL
ORDER BY all_dates.report_date;
```

### Notes

- The idea is simple: generate the full expected range, then left join actual data.
- This pattern is useful for operational reporting and data-quality checks.
- For production SQL Server workloads, consider using a permanent calendar table or numbers table instead of generating dates dynamically.

---

## 5. Sessionization: Grouping Consecutive Events

**Use case:** user sessions, consecutive logins, clickstream analysis, streak detection.

```sql
WITH ordered_events AS (
    SELECT
        user_id,
        login_time,
        LAG(login_time) OVER (
            PARTITION BY user_id
            ORDER BY login_time
        ) AS previous_login_time
    FROM user_logins
),
session_flags AS (
    SELECT
        user_id,
        login_time,
        previous_login_time,
        DATEDIFF(MINUTE, previous_login_time, login_time) AS gap_minutes,
        CASE
            WHEN previous_login_time IS NULL THEN 1
            WHEN DATEDIFF(MINUTE, previous_login_time, login_time) > 30 THEN 1
            ELSE 0
        END AS is_new_session
    FROM ordered_events
),
session_groups AS (
    SELECT
        user_id,
        login_time,
        previous_login_time,
        gap_minutes,
        SUM(is_new_session) OVER (
            PARTITION BY user_id
            ORDER BY login_time
            ROWS UNBOUNDED PRECEDING
        ) AS session_id
    FROM session_flags
)
SELECT
    user_id,
    session_id,
    MIN(login_time) AS session_start,
    MAX(login_time) AS session_end,
    COUNT(*)        AS events_in_session
FROM session_groups
GROUP BY
    user_id,
    session_id
ORDER BY
    user_id,
    session_start;
```

### Notes

- `LAG()` finds the previous event for the same user.
- A new session starts when the time gap is greater than the chosen threshold.
- `SUM(is_new_session) OVER (...)` converts session-start flags into session groups.
- Change the `> 30` threshold based on your business definition of a session.

---

## Quick Reference

| Pattern | Main Technique | Typical Use |
| --- | --- | --- |
| Running total | `SUM() OVER (ORDER BY ...)` | Dashboards and cumulative KPIs |
| Period comparison | `LAG()` | Day-over-day, month-over-month, year-over-year reports |
| Top N per group | `RANK()`, `DENSE_RANK()`, `ROW_NUMBER()` | Leaderboards and grouped rankings |
| Gap detection | Generated range + `LEFT JOIN` | Audit checks and data-quality validation |
| Sessionization | `LAG()` + conditional running `SUM()` | User sessions and event grouping |

---

## Practical customization checklist

Before using these templates in a real project, adjust:

- table names
- date/time columns
- metric columns
- grouping columns
- ranking criteria
- session timeout threshold
- database-specific date functions

---

## Final note

These patterns cover many recurring reporting problems. They are not meant to replace proper data modeling, indexing, or semantic-layer design, but they are useful building blocks for fast, readable, and maintainable SQL reports.
