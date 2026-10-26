# Kickstarter: 3,082 Campaigns Were Funded by Nobody

SQL analysis of 378,661 Kickstarter campaigns. Dataquest guided project, *Analyzing Kickstarter Projects*, SQLite.

The brief asks for patterns in failed campaigns. Before looking for any, this checks whether the table is internally consistent. It is not, and the inconsistency has a shape that identifies what broke.

## Findings

### 1. Money pledged by zero backers

| Check | Rows |
|---|---|
| **pledged > 0 but backers = 0** | **3,082** |
| backers > 0 but pledged = 0 | **0** |
| state = successful but pledged < goal | 5 |
| state = failed but pledged >= goal | 6 |
| goal >= $10,000,000 | 209 |

**3,082 campaigns record money arriving from nobody, totalling $11,479,556.** The largest is SCiO, the pocket molecular sensor, which raised **$2,762,571.78** and is recorded with **0 backers**.

The mirror check returns **zero rows**. No campaign has backers but no money. That asymmetry is the diagnosis: this is not random corruption, it is a `backers` field that failed to populate. Every one of the 3,562 rows in the `undefined` state has zero backers, so most of the damage is concentrated there, with the rest spilling into other states.

Any analysis using `backers` must exclude these rows, and that includes the per-backer averages this project invites.

The state labels themselves are sound. Only 11 rows of 378,661 disagree with their own pledged-versus-goal arithmetic, and all 11 sit exactly on the boundary.

Two smaller problems: **209 campaigns have a goal of $10,000,000 or more**, up to a round $100,000,000, which are jokes or tests rather than campaigns. And the text is mojibake in places (`2.ForsÃ¸k`, `adjÃ¸ tristesse`), UTF-8 having been read as Latin-1 somewhere upstream.

### 2. Success falls steadily with goal size

Settled outcomes only, with a floor of $100 on the goal to remove 316 "successful" campaigns with a goal of a dollar or less.

| Goal | n | Success rate |
|---|---|---|
| under $1k | 39,237 | **55.0%** |
| $1k to $2.5k | 51,487 | 50.0% |
| $2.5k to $5k | 49,454 | 47.6% |
| $5k to $10k | 62,020 | 40.3% |
| $10k to $25k | 66,455 | 35.0% |
| $25k to $50k | 28,002 | 27.3% |
| $50k to $100k | 17,397 | 19.6% |
| $100k+ | 14,068 | **11.6%** |

Clean and monotonic, from 55% down to 11.6%.

### 3. The obvious inference from that is wrong

If small goals succeed more often, the tempting advice is to set a low goal and let the overshoot take care of itself. The mean ratio of pledged to goal among winners is 1.7 to 3.6, which seems to support it.

Medians say otherwise:

| Goal | Successful campaigns | Median raised |
|---|---|---|
| under $1k | 21,583 | **$706** |
| $1k to $2.5k | 25,724 | $2,010 |
| $2.5k to $5k | 23,536 | $3,871 |
| $5k to $10k | 25,019 | $7,470 |
| $10k to $25k | 23,239 | $16,657 |
| $25k to $50k | 7,637 | $38,389 |
| $50k to $100k | 3,410 | $80,416 |
| $100k+ | 1,633 | **$225,740** |

**The median successful campaign raises approximately its goal, not a multiple of it.** The 2x and 3x mean ratios are a handful of runaway campaigns pulling the average.

So lowering the goal raises the chance of success and lowers the amount raised, roughly in proportion. There is no free lunch in the goal field.

Multiplying the two columns, expected money raised *rises* with goal size across every band. That does not mean raising your goal gets you more money: campaigns with large goals are different campaigns, run by teams with audiences and budgets. The goal is a symptom of the project, not a lever on it. This is the single biggest limit on what this table can say.

### 4. Category matters independently of goal size

Raw success rates run from Dance at 65.5% to Technology at 23.6%, but the average Technology goal is twelve times the average Dance goal, so that ranking is partly a ranking of ambition. Holding goal size constant:

| Category | under $2.5k | $2.5k-$10k | $10k-$50k | over $50k |
|---|---|---|---|---|
| Dance | 70.8% | **69.5%** | 49.5% | 11.4% |
| Theater | 75.1% | 65.9% | 44.1% | 19.6% |
| Comics | 70.4% | 55.6% | 46.2% | **24.1%** |
| Music | 58.6% | 55.3% | 43.3% | 13.0% |
| Games | 57.2% | 48.1% | 37.3% | 21.4% |
| Design | 56.3% | 45.2% | 38.7% | **24.2%** |
| Technology | 39.7% | 25.7% | 22.6% | 16.7% |
| Crafts | 35.4% | **20.2%** | 14.1% | 4.6% |

The effect survives the control: a 49-point spread between Dance and Crafts within the same goal band.

**The ranking also inverts at scale.** Dance leads small campaigns at 69.5% and collapses to 11.4% above $50k. Design, Comics and Games hold up best at the top. A category that is easy to fund at $5,000 is not necessarily one that can be funded at $100,000.

## What I would not claim

- **Nothing here is causal.** Goal size and category are chosen by the creator, alongside everything not in this table: the pitch, the video, the prototype, the existing audience. A campaign with a $100k goal differs from a $1k campaign in every one of those.
- **This table has no dates.** Kickstarter's overall success rate changed substantially over the decade this covers, and none of that is visible here, so every figure is an average across a shifting platform.
- **No currency column.** Goal and pledged are bare numbers. If this is the common Kaggle dump, the amounts are mixed currencies, which would distort the goal buckets.
- **`undefined`, `live` and `suspended` are excluded** from every success-rate calculation, which is right, but `canceled` is excluded too. A cancelled campaign is usually a failing one, so counting cancellations as failures would lower every success rate in section 2.
- **The $100 goal floor is a judgement call.** It removes trivially-succeedable campaigns; a different floor moves the smallest bucket.
- **Medians in section 3 are computed with a window function** because SQLite has no percentile function. The `ROW_NUMBER IN ((c+1)/2, (c+2)/2)` construction is exact for both odd and even counts.

## Files

- `queries.sql`: all 9 queries, commented, in the order the analysis runs.
- `README.md`: this write-up.

## Tools

SQLite, run in Dataquest's in-browser SQL environment. Window functions for medians, conditional aggregation for the pivot in section 4.
