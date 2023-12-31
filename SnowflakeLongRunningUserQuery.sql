-- Current long running queries
SELECT
  USER_NAME AS "User",
  DATABASE_NAME AS "Database",
  WAREHOUSE_NAME AS "Warehouse",
  QUERY_TYPE AS "Operation",
  QUERY_TEXT AS "Query",
  TO_CHAR(START_TIME, 'HH:MI:SS AM') AS "Start Time",
  EXECUTION_STATUS AS "Status",
  DATEDIFF('seconds', START_TIME, CURRENT_TIMESTAMP()) AS "Duration"
FROM TABLE(snowflake.INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE EXECUTION_STATUS IN ('RUNNING', 'QUEUED', 'BLOCKED')
AND USER_NAME NOT IN ('SNAPLOGIC')
AND DATEDIFF('seconds', START_TIME, CURRENT_TIMESTAMP()) > 120
ORDER BY START_TIME DESC;


-- Retrieve user, warehouse, query, start time, and duration for queries running longer than 1 hour: HISTORY
SELECT
  USER_NAME AS "User",
  WAREHOUSE_NAME AS "Warehouse",
  QUERY_TEXT AS "Query",
  START_TIME AS "Start Time",
  END_TIME AS "End Time",
  DATEDIFF('hour', START_TIME, END_TIME) AS "Duration"
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE DATEDIFF('hour', START_TIME, END_TIME) > 1  -- Filter for queries longer than 1 hour
ORDER BY START_TIME DESC;

-- Retrieve user, warehouse, query, start time, and formatted duration for queries running longer than 1 hour: HISTORY
SELECT
  USER_NAME AS "User",
  WAREHOUSE_NAME AS "Warehouse",
  QUERY_TEXT AS "Query",
  START_TIME AS "Start Time",
  END_TIME AS "End Time",
  TO_VARIANT(DATE_PART('day', END_TIME - START_TIME)) || 'd ' ||
  TO_VARIANT(DATE_PART('hour', END_TIME - START_TIME) % 24) || 'h ' ||
  TO_VARIANT(DATE_PART('minute', END_TIME - START_TIME) % 60) || 'min ' ||
  TO_VARIANT(DATE_PART('second', END_TIME - START_TIME) % 60) || 'sec' AS "Duration"
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE DATEDIFF('hour', START_TIME, END_TIME) > 1  -- Filter for queries longer than 1 hour
ORDER BY START_TIME DESC;

-- HISTORY AGAIN
SELECT
  USER_NAME AS "User",
  DATABASE_NAME AS "Database",
  WAREHOUSE_NAME AS "Warehouse",
  QUERY_TYPE AS "Operation",
  QUERY_TEXT AS "Query",
  START_TIME AS "Start Time",
  EXECUTION_STATUS AS "Status",
  END_TIME AS "End Time",
  TOTAL_ELAPSED_TIME / 3600000 AS "Duration",
  --DATEDIFF('hour', START_TIME, END_TIME) AS "Duration"
FROM TABLE(snowflake.INFORMATION_SCHEMA.QUERY_HISTORY())
--WHERE DATEDIFF('hour', START_TIME, END_TIME) > 1
WHERE TOTAL_ELAPSED_TIME > 3600000
ORDER BY START_TIME DESC;
