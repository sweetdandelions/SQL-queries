SELECT table_name
FROM INFORMATION_SCHEMA.COLUMNS
WHERE column_name = 'column_name';

SELECT table_name, column_name, data_type, character_maximum_length
FROM INFORMATION_SCHEMA.COLUMNS
WHERE column_name = 'column_name';
