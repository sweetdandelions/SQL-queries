WITH params AS (
	SELECT
			90 AS lookback_days,
			365 AS yearly_lookback,
			7 AS maturity_days,
			5 AS min_business_day_runs
),

-- Grab last 90 days of execution history with business day flag (for classification)
last_n_days AS (
	SELECT
		pkg_nm,
		load_dt,
		stop_dt,
		load_dt::date AS run_date,
		load_dt::time AS run_time,
		stop_dt::time AS stop_time,
		DAYNAME(run_date) AS day_name,
		CASE WHEN DAYOFWEEKISO(run_date) BETWEEN 1 AND 5 THEN 1 ELSE 0 END AS is_business_day
	FROM AUDIT.SL_EXEC_LOG, params
	WHERE load_dt >= CURRENT_DATE - lookback_days
),

-- Grab last 365 days for quarterly month aggregation
last_year_runs AS (
	SELECT
		pkg_nm,
		load_dt::date AS run_date
	FROM AUDIT.SL_EXEC_LOG, params
	WHERE load_dt >= CURRENT_DATE - yearly_lookback
),

-- Generate calendar for business day counting
date_series AS (
	SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY NULL) - 1, CURRENT_DATE - (SELECT lookback_days FROM params)) AS d
	FROM TABLE(GENERATOR(ROWCOUNT => (SELECT lookback_days FROM params)))
),

-- Aggregate: runs, distinct days, business day coverage, SLA time
job_calendar_analysis AS (
	SELECT
		pkg_nm,
		COUNT(*) AS total_runs,
		COUNT(DISTINCT run_date) AS distinct_run_days,
		SUM(is_business_day) AS business_day_runs,
		COUNT(DISTINCT CASE WHEN is_business_day = 1 THEN run_date END) AS business_days_with_runs,
		(SELECT COUNT(*) FROM date_series WHERE DAYOFWEEKISO(d) BETWEEN 1 AND 5) AS total_business_days_in_period,
		MAX(run_date) AS last_run_date,
		MIN(run_date) AS first_run_date,
		DATEDIFF('day', MIN(run_date), CURRENT_DATE) AS days_since_first_run,

		DATEADD('second',
			PERCENTILE_CONT(0.10) WITHIN GROUP (
				ORDER BY DATEDIFF('second', '00:00:00'::TIME, run_time)
			)::INT,
			'00:00:00'::TIME
		) AS inferred_start_time,

		DATEADD('second',
            PERCENTILE_CONT(0.70) WITHIN GROUP (
                ORDER BY CASE WHEN stop_dt IS NOT NULL AND load_dt IS NOT NULL
                    THEN DATEDIFF('second', load_dt, stop_dt)
                END
            )::INT, inferred_start_time
        ) AS inferred_stop_time
	FROM last_n_days
	GROUP BY pkg_nm
),

-- Calculate days between consecutive runs
run_gaps AS (
	SELECT
		pkg_nm,
		run_date,
		LAG(run_date) OVER (PARTITION BY pkg_nm ORDER BY run_date) AS prev_run_date,
		DATEDIFF('day', LAG(run_date) OVER (PARTITION BY pkg_nm ORDER BY run_date), run_date) AS gap_days
	FROM (SELECT DISTINCT pkg_nm, run_date FROM last_n_days)
),

-- Stats: avg/mode gaps, weekly/monthly pattern counts
gap_stats AS (
	SELECT
		pkg_nm,
		AVG(gap_days) AS avg_gap,
		MODE(gap_days) AS mode_gap,
		COUNT(CASE WHEN gap_days BETWEEN 6 AND 8 THEN 1 END) AS weekly_pattern_count,
		COUNT(CASE WHEN gap_days BETWEEN 28 AND 31 THEN 1 END) AS monthly_pattern_count,
		COUNT(*) AS total_gaps
	FROM run_gaps
	WHERE gap_days IS NOT NULL
	GROUP BY pkg_nm
),

-- Most common day of week
dow_analysis AS (
	SELECT
		pkg_nm,
		day_name,
		COUNT(*) AS cnt,
		COUNT(DISTINCT day_name) OVER (PARTITION BY pkg_nm) AS unique_days
	FROM last_n_days
	GROUP BY pkg_nm, day_name
	QUALIFY ROW_NUMBER() OVER (PARTITION BY pkg_nm ORDER BY cnt DESC) = 1
),

-- Most common day of month
dom_analysis AS (
	SELECT
		pkg_nm,
		DAYOFMONTH(run_date) AS dom,
		COUNT(*) AS cnt
	FROM last_n_days
	GROUP BY pkg_nm, DAYOFMONTH(run_date)
	QUALIFY ROW_NUMBER() OVER (PARTITION BY pkg_nm ORDER BY cnt DESC) = 1
),

-- All distinct months from PAST YEAR for quarterly jobs
all_quarterly_months AS (
	SELECT
		pkg_nm,
		LISTAGG(month_abbr, ' ') WITHIN GROUP (ORDER BY month_num) AS all_months
	FROM (
		SELECT 
			pkg_nm,
			TO_VARCHAR(run_date, 'Mon') AS month_abbr,
			MONTH(run_date) AS month_num
		FROM last_year_runs
		GROUP BY pkg_nm, TO_VARCHAR(run_date, 'Mon'), MONTH(run_date)
	)
	GROUP BY pkg_nm
),

-- Join all metrics together
classified_jobs_base AS (
	SELECT
		jca.pkg_nm,
		jca.total_runs,
		jca.distinct_run_days,
		jca.business_days_with_runs,
		jca.total_business_days_in_period,
		jca.business_days_with_runs::FLOAT / NULLIF(jca.total_business_days_in_period, 0) AS business_day_coverage,
		jca.first_run_date,
		jca.days_since_first_run,
		gs.avg_gap,
		gs.mode_gap,
		gs.weekly_pattern_count,
		gs.monthly_pattern_count,
		gs.total_gaps,
		dow.day_name AS most_common_dow,
		dow.unique_days,
		dom.dom AS most_common_dom,
		dom.cnt AS dom_cnt,
		qm.all_months AS all_run_months,
		jca.inferred_start_time,
		jca.inferred_stop_time,
		jca.last_run_date
	FROM job_calendar_analysis jca
	LEFT JOIN gap_stats gs ON jca.pkg_nm = gs.pkg_nm
	LEFT JOIN dow_analysis dow ON jca.pkg_nm = dow.pkg_nm
	LEFT JOIN dom_analysis dom ON jca.pkg_nm = dom.pkg_nm
	LEFT JOIN all_quarterly_months qm ON jca.pkg_nm = qm.pkg_nm
),

-- Classify frequency based on patterns
classified_jobs AS (
	SELECT
		pkg_nm,
		total_runs,
		distinct_run_days,
		business_days_with_runs,
		total_business_days_in_period,
		business_day_coverage,
		avg_gap,
		mode_gap,
		weekly_pattern_count,
		monthly_pattern_count,
		total_gaps,
		most_common_dow,
		unique_days,
		most_common_dom,
		dom_cnt,
		inferred_start_time,
		inferred_stop_time,
		last_run_date,
		CASE
			-- FREQUENT
			WHEN total_runs / 90.0 > 10 THEN 'Frequent'
			-- DAILY
			WHEN distinct_run_days / 90.0 >= 0.6 THEN 'Daily'
			-- MULTIPLE DAILY
			WHEN total_runs / 90.0 > 1.5 THEN 'Multiple Daily'
			-- MONDAY TO FRIDAY - WEEKDAYS
			WHEN business_day_coverage >= 0.6
				AND business_days_with_runs >= (SELECT min_business_day_runs FROM params)
				AND distinct_run_days / 90.0 < 0.6
				THEN 'Mon-Fri'
			-- WEEKLY
			WHEN (weekly_pattern_count::FLOAT / NULLIF(total_gaps, 0) >= 0.7)
				OR (total_runs >= 8 AND mode_gap BETWEEN 6 AND 8)
				OR (total_runs BETWEEN 8 AND 15 AND unique_days = 1)
				THEN 'Weekly ' || most_common_dow
			-- BI-WEEKLY
			WHEN mode_gap BETWEEN 13 AND 15
				AND (total_gaps >= 2 OR total_runs >= 3)
				THEN 'Bi-Weekly'
			-- MONTHLY
			WHEN (monthly_pattern_count::FLOAT / NULLIF(total_gaps, 0) >= 0.6)
				OR (mode_gap BETWEEN 28 AND 31 AND total_gaps >= 2)
				OR (total_runs BETWEEN 2 AND 5 AND dom_cnt >= 2)
				THEN 'Monthly ' ||
					CASE
						WHEN most_common_dom IN (11, 12, 13) THEN most_common_dom::VARCHAR || 'th'
						WHEN most_common_dom % 10 = 1 THEN most_common_dom::VARCHAR || 'st'
						WHEN most_common_dom % 10 = 2 THEN most_common_dom::VARCHAR || 'nd'
						WHEN most_common_dom % 10 = 3 THEN most_common_dom::VARCHAR || 'rd'
						ELSE most_common_dom::VARCHAR || 'th'
					END
			-- QUERTERLY
			WHEN total_runs <= 3 OR (avg_gap >= 60 OR mode_gap >= 60)
				THEN 'Quarterly ' ||
					COALESCE(all_run_months || ' ', '') ||
					CASE
						WHEN most_common_dom IN (11, 12, 13) THEN most_common_dom::VARCHAR || 'th'
						WHEN most_common_dom % 10 = 1 THEN most_common_dom::VARCHAR || 'st'
						WHEN most_common_dom % 10 = 2 THEN most_common_dom::VARCHAR || 'nd'
						WHEN most_common_dom % 10 = 3 THEN most_common_dom::VARCHAR || 'rd'
						ELSE most_common_dom::VARCHAR || 'th'
					END

			-- Maturity fallback with proper ratio checks
			WHEN (days_since_first_run >= (SELECT maturity_days FROM params) OR total_runs >= 4)
				AND avg_gap IS NOT NULL
				THEN
					CASE
						-- Daily: ran on >= 85% of days since first run
						WHEN distinct_run_days::FLOAT / NULLIF(days_since_first_run + 1, 0) >= 0.85
							THEN 'Daily'

						-- Mon-Fri: ran on >= 45% of all days since first run
						-- AND most runs are on business days (not weekends)
						WHEN distinct_run_days::FLOAT / NULLIF(days_since_first_run + 1, 0) >= 0.45
							AND business_days_with_runs::FLOAT / NULLIF(distinct_run_days, 0) >= 0.75
							THEN 'Mon-Fri'

						-- Very frequent (avg gap < 2 days) but not daily coverage
						-- This catches Mon-Fri jobs with some gaps
						WHEN avg_gap < 2
							THEN 'Mon-Fri'

						-- Weekly: gap around 2-10 days
						WHEN avg_gap < 10
							THEN 'Weekly ' || COALESCE(most_common_dow, 'Mon')

						-- Bi-Weekly: gap around 10-20 days
						WHEN avg_gap < 20
							THEN 'Bi-Weekly'

						-- Monthly: gap around 20-45 days
						WHEN avg_gap < 45
							THEN 'Monthly ' ||
								CASE
									WHEN most_common_dom IN (11, 12, 13) THEN most_common_dom::VARCHAR || 'th'
									WHEN most_common_dom % 10 = 1 THEN most_common_dom::VARCHAR || 'st'
									WHEN most_common_dom % 10 = 2 THEN most_common_dom::VARCHAR || 'nd'
									WHEN most_common_dom % 10 = 3 THEN most_common_dom::VARCHAR || 'rd'
									ELSE most_common_dom::VARCHAR || 'th'
								END

						-- Quarterly: gap >= 45 days
						WHEN avg_gap >= 45
							THEN 'Quarterly ' ||
								COALESCE(all_run_months || ' ', '') ||
								CASE
									WHEN most_common_dom IN (11, 12, 13) THEN most_common_dom::VARCHAR || 'th'
									WHEN most_common_dom % 10 = 1 THEN most_common_dom::VARCHAR || 'st'
									WHEN most_common_dom % 10 = 2 THEN most_common_dom::VARCHAR || 'nd'
									WHEN most_common_dom % 10 = 3 THEN most_common_dom::VARCHAR || 'rd'
									ELSE most_common_dom::VARCHAR || 'th'
								END

						ELSE 'Adhoc/New ' ||
							CASE
								WHEN most_common_dom IN (11, 12, 13) THEN most_common_dom::VARCHAR || 'th'
								WHEN most_common_dom % 10 = 1 THEN most_common_dom::VARCHAR || 'st'
								WHEN most_common_dom % 10 = 2 THEN most_common_dom::VARCHAR || 'nd'
								WHEN most_common_dom % 10 = 3 THEN most_common_dom::VARCHAR || 'rd'
								ELSE most_common_dom::VARCHAR || 'th'
							END
					END

			ELSE 'Adhoc/New ' ||
				CASE
					WHEN most_common_dom IN (11, 12, 13) THEN most_common_dom::VARCHAR || 'th'
					WHEN most_common_dom % 10 = 1 THEN most_common_dom::VARCHAR || 'st'
					WHEN most_common_dom % 10 = 2 THEN most_common_dom::VARCHAR || 'nd'
					WHEN most_common_dom % 10 = 3 THEN most_common_dom::VARCHAR || 'rd'
					ELSE most_common_dom::VARCHAR || 'th'
				END
		END AS occurrence
FROM classified_jobs_base
),

-- P90 runtime for zombie detection
runtime_stats AS (
	SELECT
		pkg_nm,
		PERCENTILE_CONT(0.90) WITHIN GROUP (
			ORDER BY DATEDIFF('second', start_dt, stop_dt)
		) AS p90_runtime_seconds
	FROM AUDIT.SL_EXEC_LOG, params
	WHERE stop_dt IS NOT NULL
		AND start_dt IS NOT NULL
		AND load_dt >= CURRENT_DATE - lookback_days
	GROUP BY pkg_nm
),

-- Filter monitored recurring jobs
expected_packages AS (
	SELECT
		pkg_nm,
		occurrence,
		inferred_start_time AS expected_start,
		COALESCE(inferred_stop_time, inferred_start_time) AS expected_stop
	FROM classified_jobs, params
	WHERE (occurrence ILIKE 'Daily%'
			OR occurrence ILIKE 'Mon-Fri%'
			OR occurrence ILIKE 'Weekly%'
			OR occurrence ILIKE 'Bi-Weekly%'
			OR occurrence ILIKE 'Monthly%'
			OR occurrence ILIKE 'Quarterly%'
			OR occurrence ILIKE 'Adhoc/New%'
		)
		AND last_run_date >= CURRENT_DATE - lookback_days
		AND pkg_nm NOT ILIKE '%Manual%'
		AND pkg_nm NOT ILIKE '%Reload%'
		AND pkg_nm NOT IN (
			'DL.Job'
		)
),

-- Today's most recent execution per job
today_exec AS (
	SELECT
		pkg_nm,
		load_dt,
		start_dt,
		stop_dt,
		sts_cd
	FROM AUDIT.SL_EXEC_LOG
	WHERE load_dt::date = CURRENT_DATE
	QUALIFY ROW_NUMBER() OVER (PARTITION BY pkg_nm ORDER BY load_dt DESC) = 1
)

-- Final output
SELECT
	e.pkg_nm,
	CASE
		WHEN t.pkg_nm IS NULL THEN 'Waiting'
		WHEN t.sts_cd = -1 THEN 'Failed'
		WHEN t.sts_cd = 1 THEN 'Completed'
		WHEN t.sts_cd = 0 AND t.stop_dt IS NULL AND t.start_dt IS NOT NULL
			AND (
				(r.p90_runtime_seconds IS NOT NULL AND CURRENT_TIMESTAMP() > DATEADD(SECOND, r.p90_runtime_seconds, t.start_dt))
					OR
				(r.p90_runtime_seconds IS NULL AND CURRENT_TIMESTAMP() > TO_TIMESTAMP_NTZ(TO_CHAR(t.load_dt::DATE,'YYYY-MM-DD') || ' ' || e.expected_stop, 'YYYY-MM-DD HH24:MI:SS'))
			)
		THEN 'No data'
		WHEN t.sts_cd = 0 AND t.stop_dt IS NULL THEN 'Running'
		ELSE 'Unknown'
	END AS status,
	e.occurrence,
	TO_TIME(CONVERT_TIMEZONE('UTC', 'Europe/Berlin', TO_TIMESTAMP_NTZ(TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD') || ' ' || e.expected_start::VARCHAR, 'YYYY-MM-DD HH24:MI:SS'))) AS expected_start,
	TO_TIME(CONVERT_TIMEZONE('UTC', 'Europe/Berlin', TO_TIMESTAMP_NTZ(TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD') || ' ' || e.expected_stop::VARCHAR, 'YYYY-MM-DD HH24:MI:SS'))) AS expected_completion,
	TO_CHAR(CONVERT_TIMEZONE('Europe/Berlin', TO_TIMESTAMP_TZ(TO_CHAR(CURRENT_DATE,'YYYY-MM-DD') || ' ' || e.expected_start::VARCHAR || ' +00:00', 'YYYY-MM-DD HH24:MI:SS TZH:TZM')), 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM') AS expected_start_sla_dt,
	TO_CHAR(CONVERT_TIMEZONE('Europe/Berlin', TO_TIMESTAMP_TZ(TO_CHAR(CURRENT_DATE,'YYYY-MM-DD') || ' ' || e.expected_stop::VARCHAR || ' +00:00', 'YYYY-MM-DD HH24:MI:SS TZH:TZM')), 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM') AS expected_stop_sla_dt
FROM expected_packages e
LEFT JOIN today_exec t ON e.pkg_nm = t.pkg_nm
LEFT JOIN runtime_stats r ON e.pkg_nm = r.pkg_nm
ORDER BY
	CASE
		WHEN e.occurrence = 'Daily' THEN 0
		WHEN e.occurrence = 'Mon-Fri' THEN 1
		WHEN e.occurrence ILIKE 'Weekly%' THEN 2
		WHEN e.occurrence ILIKE 'Bi-Weekly%' THEN 2
		WHEN e.occurrence ILIKE 'Monthly%' THEN 3
		WHEN e.occurrence ILIKE 'Quarterly%' THEN 4
		ELSE 5
	END,
	CASE
		WHEN e.occurrence ILIKE 'Weekly%'
		THEN DAYOFWEEKISO(NEXT_DAY(CURRENT_DATE, TRIM(SUBSTR(e.occurrence, 8))))
		ELSE TRY_CAST(REGEXP_REPLACE(e.occurrence, '[^0-9]', '') AS INTEGER)
	END DESC,
e.expected_start::TIME DESC,
e.pkg_nm;
e.expected_start::TIME DESC,
e.pkg_nm;
