-- SNOWFLAKE--
-- DAYS
SELECT * FROM (
  SELECT row_number() over (ORDER BY NULL)-1 AS rn
        ,dateadd('day', rn, '2019-01-01'::date) AS date_dt,
        WEEKOFYEAR(dateadd('day', rn, '2019-01-01'::date)) AS woy, 
        DAYOFWEEK(dateadd('day', rn, '2019-01-01'::date)) dow
FROM TABLE (generator(rowcount=>365)));


-- WEEKS
SELECT * FROM (
  SELECT row_number() over (ORDER BY NULL)-1 AS rn
        ,dateadd('week', rn, '2022-06-06'::date) AS date_dt,
        WEEKOFYEAR(dateadd('day', rn, '2022-06-06'::date)) AS woy, 
        DAYOFWEEK(dateadd('day', rn, '2022-06-06'::date)) dow
FROM TABLE(generator(rowcount=>365)))
LIMIT 170;

