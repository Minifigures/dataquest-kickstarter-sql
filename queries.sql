-- ============================================================================
-- Analyzing Kickstarter Projects
-- Dataquest guided project, SQLite, single table `ksprojects`
--
-- 378,661 Kickstarter campaigns with columns:
--   ID, name, category, main_category, goal, pledged, state, backers
--
-- The brief asks for patterns in failed campaigns. Before looking for any,
-- this checks whether the table is internally consistent. It is not: 3,082
-- rows record money pledged by zero backers.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 0. SCHEMA AND SHAPE
-- ----------------------------------------------------------------------------

-- 0a. What is in the database at all.
SELECT name, sql
FROM sqlite_master
WHERE type = 'table';

-- 0b. Outcome distribution. Note that 'undefined', 'live' and 'suspended'
--     are not settled outcomes and should not sit alongside the other three
--     in any success-rate calculation.
SELECT
    state,
    COUNT(*)                                                      AS n,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM ksprojects), 2) AS pct,
    ROUND(AVG(goal), 0)                                           AS avg_goal,
    ROUND(AVG(pledged), 0)                                        AS avg_pledged,
    ROUND(AVG(backers), 1)                                        AS avg_backers
FROM ksprojects
GROUP BY state
ORDER BY n DESC;


-- ----------------------------------------------------------------------------
-- 1. DATA QUALITY AUDIT
-- ----------------------------------------------------------------------------

-- 1a. Zero-value counts per state. The 'undefined' row is the tell: every one
--     of its 3,562 records has zero backers, but only 683 have zero pledged.
SELECT
    state,
    COUNT(*)                                             AS n,
    SUM(CASE WHEN backers = 0 THEN 1 ELSE 0 END)         AS zero_backers,
    SUM(CASE WHEN pledged = 0 THEN 1 ELSE 0 END)         AS zero_pledged,
    SUM(CASE WHEN goal <= 1 THEN 1 ELSE 0 END)           AS goal_le_1,
    MAX(goal)                                            AS max_goal,
    MAX(pledged)                                         AS max_pledged
FROM ksprojects
GROUP BY state
ORDER BY n DESC;

-- 1b. Five impossibility checks in one result set.
--
--     The first is the important one: money cannot be pledged by nobody.
--     The second is its mirror and returns zero rows, which tells us the
--     corruption is one-directional and therefore looks like a backers field
--     that failed to populate rather than random noise.
--
--     The third and fourth confirm that the state labels themselves are sound:
--     only 11 rows in 378,661 disagree with their own pledged-versus-goal
--     arithmetic, and all of those sit on the boundary.
SELECT 'pledged > 0 but backers = 0' AS problem,
       COUNT(*)                      AS n,
       ROUND(MIN(pledged), 2)        AS min_val,
       ROUND(MAX(pledged), 2)        AS max_val,
       ROUND(SUM(pledged), 0)        AS total_phantom_money
FROM ksprojects
WHERE pledged > 0 AND backers = 0

UNION ALL
SELECT 'backers > 0 but pledged = 0',
       COUNT(*), MIN(backers), MAX(backers), SUM(backers)
FROM ksprojects
WHERE backers > 0 AND pledged = 0

UNION ALL
SELECT 'state = successful but pledged < goal',
       COUNT(*), ROUND(MIN(pledged / goal), 3), ROUND(MAX(pledged / goal), 3), NULL
FROM ksprojects
WHERE state = 'successful' AND pledged < goal

UNION ALL
SELECT 'state = failed but pledged >= goal',
       COUNT(*), ROUND(MIN(pledged / goal), 3), ROUND(MAX(pledged / goal), 3), NULL
FROM ksprojects
WHERE state = 'failed' AND pledged >= goal AND goal > 0

UNION ALL
SELECT 'goal >= 10 million',
       COUNT(*), ROUND(MIN(goal), 0), ROUND(MAX(goal), 0), NULL
FROM ksprojects
WHERE goal >= 10000000;

-- 1c. The worst individual offenders: large sums attributed to no one.
SELECT
    name,
    main_category,
    state,
    goal,
    pledged,
    backers
FROM ksprojects
WHERE pledged > 0 AND backers = 0
ORDER BY pledged DESC
LIMIT 10;


-- ----------------------------------------------------------------------------
-- 2. GOAL SIZE AND SUCCESS
-- ----------------------------------------------------------------------------

-- Scope for everything below: settled outcomes only, and a floor of 100 on the
-- goal. The floor removes 316 "successful" campaigns with a goal of one dollar
-- or less, which succeed trivially and would flatter the smallest bucket.

-- 2a. Success rate by goal size. A clean monotonic decline from 55% to 11.6%.
WITH settled AS (
    SELECT *
    FROM ksprojects
    WHERE state IN ('successful', 'failed')
      AND goal >= 100
),
bucketed AS (
    SELECT
        CASE
            WHEN goal <   1000 THEN '1  under 1k'
            WHEN goal <   2500 THEN '2  1k-2.5k'
            WHEN goal <   5000 THEN '3  2.5k-5k'
            WHEN goal <  10000 THEN '4  5k-10k'
            WHEN goal <  25000 THEN '5  10k-25k'
            WHEN goal <  50000 THEN '6  25k-50k'
            WHEN goal < 100000 THEN '7  50k-100k'
            ELSE                    '8  100k+'
        END AS bucket,
        state, goal, pledged, backers
    FROM settled
)
SELECT
    bucket,
    COUNT(*)                                                               AS n,
    ROUND(100.0 * SUM(CASE WHEN state = 'successful' THEN 1 ELSE 0 END)
          / COUNT(*), 1)                                                   AS success_pct,
    ROUND(AVG(backers), 0)                                                 AS avg_backers,
    ROUND(AVG(CASE WHEN state = 'successful' THEN pledged / goal END), 2)  AS avg_ratio_if_success
FROM bucketed
GROUP BY bucket
ORDER BY bucket;

-- 2b. The question 2a raises: if a smaller goal is easier to clear, does it
--     also cap what you raise? Medians, because the mean ratio in 2a is pulled
--     around by a handful of runaway campaigns.
--
--     Median is computed with a window function rather than a percentile
--     function, which SQLite does not provide. The ROW_NUMBER IN ((c+1)/2,
--     (c+2)/2) trick picks the middle row for odd counts and both middle rows
--     for even ones, and averaging them gives the median either way.
WITH winners AS (
    SELECT
        CASE
            WHEN goal <   1000 THEN '1  under 1k'
            WHEN goal <   2500 THEN '2  1k-2.5k'
            WHEN goal <   5000 THEN '3  2.5k-5k'
            WHEN goal <  10000 THEN '4  5k-10k'
            WHEN goal <  25000 THEN '5  10k-25k'
            WHEN goal <  50000 THEN '6  25k-50k'
            WHEN goal < 100000 THEN '7  50k-100k'
            ELSE                    '8  100k+'
        END AS bucket,
        goal, pledged, backers
    FROM ksprojects
    WHERE state = 'successful'
      AND goal >= 100
),
ranked AS (
    SELECT
        bucket, pledged, backers,
        ROW_NUMBER() OVER (PARTITION BY bucket ORDER BY pledged) AS rn,
        COUNT(*)    OVER (PARTITION BY bucket)                   AS c
    FROM winners
)
SELECT
    bucket,
    c                                                                  AS n_successful,
    ROUND(AVG(CASE WHEN rn IN ((c + 1) / 2, (c + 2) / 2) THEN pledged END), 0) AS median_pledged,
    ROUND(AVG(CASE WHEN rn IN ((c + 1) / 2, (c + 2) / 2) THEN backers END), 0) AS median_backers
FROM ranked
GROUP BY bucket, c
ORDER BY bucket;


-- ----------------------------------------------------------------------------
-- 3. CATEGORY
-- ----------------------------------------------------------------------------

-- 3a. Raw success rate by category. Heavily confounded with goal size: the
--     average Technology goal is twelve times the average Dance goal, so this
--     ranking is partly a ranking of how ambitious each category is.
SELECT
    main_category,
    COUNT(*)                                                             AS n,
    ROUND(100.0 * SUM(CASE WHEN state = 'successful' THEN 1 ELSE 0 END)
          / COUNT(*), 1)                                                 AS success_pct,
    ROUND(AVG(goal), 0)                                                  AS avg_goal,
    ROUND(AVG(CASE WHEN state = 'successful' THEN backers END), 0)       AS avg_backers_if_win
FROM ksprojects
WHERE state IN ('successful', 'failed')
  AND goal >= 100
GROUP BY main_category
ORDER BY success_pct DESC;

-- 3b. The same comparison holding goal size constant, by pivoting success rate
--     across four goal bands. This separates "this category attracts backers"
--     from "this category asks for less money".
WITH banded AS (
    SELECT
        main_category,
        state,
        CASE
            WHEN goal <  2500 THEN 1
            WHEN goal < 10000 THEN 2
            WHEN goal < 50000 THEN 3
            ELSE                   4
        END AS band
    FROM ksprojects
    WHERE state IN ('successful', 'failed')
      AND goal >= 100
)
SELECT
    main_category,
    ROUND(100.0 * SUM(CASE WHEN state = 'successful' AND band = 1 THEN 1 ELSE 0 END)
          / NULLIF(SUM(CASE WHEN band = 1 THEN 1 ELSE 0 END), 0), 1) AS under_2500,
    ROUND(100.0 * SUM(CASE WHEN state = 'successful' AND band = 2 THEN 1 ELSE 0 END)
          / NULLIF(SUM(CASE WHEN band = 2 THEN 1 ELSE 0 END), 0), 1) AS from_2500_to_10k,
    ROUND(100.0 * SUM(CASE WHEN state = 'successful' AND band = 3 THEN 1 ELSE 0 END)
          / NULLIF(SUM(CASE WHEN band = 3 THEN 1 ELSE 0 END), 0), 1) AS from_10k_to_50k,
    ROUND(100.0 * SUM(CASE WHEN state = 'successful' AND band = 4 THEN 1 ELSE 0 END)
          / NULLIF(SUM(CASE WHEN band = 4 THEN 1 ELSE 0 END), 0), 1) AS over_50k
FROM banded
GROUP BY main_category
ORDER BY from_2500_to_10k DESC;
