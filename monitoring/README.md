# Job Execution Monitoring — Documentation

## Overview

The system consists of two parts:

1. **Snowflake SQL Query** — analyses 90 days of historical job execution data to classify each job's schedule, infer its expected start/stop times, and determine its current execution status for today.
2. **XSLT Stylesheet** — transforms the SQL output (XML) into a formatted HTML report, grouping jobs by status and highlighting SLA breaches.

---

## Part 1: Snowflake SQL Query

### `params`
Defines two global constants used throughout the query:
- `lookback_days = 90` — how far back to look for historical runs
- `min_business_day_runs = 5` — minimum number of business day runs required to classify a job as Mon-Fri

---

### `last_n_days`
Pulls all raw execution records from the last 90 days from `SL_EXEC_LOG`. For each record it extracts:
- The run date and time (from `load_dt`)
- The stop time (from `stop_dt`)
- The day name (Monday, Tuesday, etc.)
- A flag indicating whether the run was on a business day (Mon–Fri)

---

### `date_series`
Generates a calendar of every date in the 90-day lookback window. This is used purely for counting how many business days exist in the period — necessary to calculate business day coverage for Mon-Fri detection.

---

### `job_calendar_analysis`
Aggregates execution history per job to produce key metrics:
- `total_runs` — total number of executions in the period
- `distinct_run_days` — how many unique calendar days the job ran on
- `business_days_with_runs` — how many unique business days the job ran on
- `total_business_days_in_period` — total business days available in the window (from `date_series`)
- `last_run_date` — most recent run date
- `inferred_start_time` — **P10 of historical start times**: the time by which the earliest 10% of runs have started; used as the expected start / "should have started by" threshold
- `inferred_stop_time` — **P90 of historical stop times**: the time by which 90% of runs have completed; used as the SLA completion deadline

---

### `run_gaps`
For each job, calculates the number of days between consecutive runs using `LAG()`. This produces a gap series per job (e.g. 7, 7, 7 days for a weekly job).

---

### `gap_stats`
Aggregates the gap series per job:
- `avg_gap` / `mode_gap` — average and most common gap between runs
- `weekly_pattern_count` — how many gaps fall between 6–8 days
- `monthly_pattern_count` — how many gaps fall between 28–31 days
- `total_gaps` — total number of gaps (runs minus 1)

---

### `dow_analysis`
Finds the most common day of the week each job runs on. Used to label weekly jobs (e.g. "Weekly Wed"). Also counts how many distinct days of the week the job has run on (`unique_days`).

---

### `dom_analysis`
Finds the most common day of the month each job runs on. Used to label monthly jobs (e.g. "Monthly 15th").

---

### `classified_jobs_base`
Joins all the above CTEs together into a single flat row per job, combining run statistics, gap statistics, day-of-week, and day-of-month information.

---

### `classified_jobs`
Applies classification logic to assign each job a frequency label (`occurrence`) based on its run patterns:

| Label | Condition |
|---|---|
| `Frequent` | More than 10 runs per day on average |
| `Daily` | Ran on 85%+ of all calendar days |
| `Mon-Fri` | Ran on 80%+ of business days with at least 5 business day runs |
| `Multiple Daily` | More than 1.5 runs per day on average |
| `Weekly {Day}` | Clear 7-day gap pattern, or consistent single day of week |
| `Bi-Weekly` | Mode gap of ~14 days |
| `Monthly {Nth}` | Mode gap of ~30 days, or consistent day-of-month |
| `Quarterly` | Very sparse runs or gaps of 60+ days |
| `Adhoc/New` | Everything else |

---

### `runtime_stats`
Calculates the P90 runtime in seconds per job (i.e. 90% of runs complete within this many seconds). Used for zombie/stuck job detection — if a job has been running longer than its P90 runtime, it is considered stuck.

---

### `expected_packages`
Filters down to only the jobs that should be monitored (excludes manual, reload, and specifically blacklisted jobs). For each monitored job it defines:
- `expected_start` — P10 start time (inferred from history)
- `expected_stop` — P90 stop time, falling back to P10 start time if no stop time history exists

---

### `today_exec`
Retrieves the most recent execution record for today for each job. If a job has run multiple times today, only the latest record is kept.

---

### Final `SELECT`
Joins `expected_packages`, `today_exec`, and `runtime_stats` to produce the final output with one row per monitored job:

**Status logic:**

| Status | Condition |
|---|---|
| `Waiting` | No execution record exists for today |
| `Failed` | `sts_cd = -1` |
| `Completed` | `sts_cd = 1` |
| `No data` | `sts_cd = 0`, no stop time, and either P90 runtime has been exceeded or expected stop time has passed — job is considered zombie/stuck |
| `Running` | `sts_cd = 0`, no stop time, within normal runtime bounds |
| `Unknown` | Any other case |

**Timezone handling:** `expected_start` and `expected_completion` are displayed in CET/CEST (Europe/Berlin). `expected_start_sla_dt` and `expected_stop_sla_dt` are emitted as ISO 8601 timestamps with the correct dynamic UTC offset (`+01:00` in winter, `+02:00` in summer) for use in XSLT datetime comparisons — DST-safe because Snowflake resolves the `Europe/Berlin` timezone rules at query time.

---

## Part 2: XSLT Stylesheet

### Purpose
Transforms the XML output of the SQL query into a styled HTML report for daily job monitoring. Jobs are grouped by status, sorted by severity, and rendered as colour-coded tables.

---

### Date Display
The report header shows today's date in a human-readable format (e.g. `2026-03-23 (Monday)`) using `format-date(current-date(), ...)`.

---

### Grouping Logic (`xsl:for-each-group`)
Each job is assigned to a group based on the following priority logic:

1. **Failed** — if `status = 'Failed'`
2. **SLA Breach** — if the job is `Running` or `Waiting`, is scheduled to run today (based on its occurrence pattern and today's date), and has exceeded its relevant SLA threshold:
   - `Waiting` jobs breach if current time > `expected_start_sla_dt` (should have started by now)
   - `Running` jobs breach if current time > `expected_stop_sla_dt` (should have finished by now)
3. **Running / Completed / Waiting** — normal status pass-through
4. **Other** — anything else

The "scheduled to run today" check filters out weekly/monthly jobs that are not due today, so they don't falsely appear as SLA breaches on off-days.

---

### Group Sort Order
Groups are rendered in this order to surface the most critical issues first:

| Order | Group |
|---|---|
| 1 | Failed |
| 2 | SLA Breach |
| 3 | Running |
| 4 | Completed |
| 5 | Waiting |
| 6 | Other |

---

### Table Rendering
Each group gets a section header showing the group name and job count, followed by a table with columns: **Pipeline Name**, **Occurrence**, **Status**, **Starts At**, **Completes By**.

---

### Status Colour Coding

| Status | Colour |
|---|---|
| Waiting | Yellow |
| Running | Blue |
| Completed | Green |
| Failed | Red |
| No data (zombie) | Dark red |
| SLA Breach | Salmon/orange |

---

### DST Safety
`expected_start_sla_dt` and `expected_stop_sla_dt` are full ISO 8601 timestamps with correct UTC offsets emitted from Snowflake. The XSLT casts them with `xs:dateTime()` and compares against `current-dateTime()` (which SnapLogic provides in UTC). Because the offset is embedded in the timestamp itself, the comparison is always timezone-correct regardless of DST.
