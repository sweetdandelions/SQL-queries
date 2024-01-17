-- Snowflake
-- Generate a series of ALTER TABLE statements based on the conditions specified in the WHERE clause. 
-- The purpose of these statements is to alter the data type of specific columns ('column_name1' and 'column_name2') in certain database tables.

select 'ALTER TABLE IF EXISTS ' || t.table_schema || '.' || t.table_name || ' ALTER COLUMN ' || c.column_name || ' TYPE VARCHAR(100);'
from information_schema.columns c join
     information_schema.tables t on
     (
       t.table_schema = c.table_schema and
       t.table_name = c.table_name and
       t.table_type = 'BASE TABLE' -- table_type can be base table or view
     )
where c.column_name in ('column_name1', 'column_name2')
  and c.table_schema not in ('schema_name1', 'schema_name2')
  and c.character_maximum_length < 100
order by 1;
