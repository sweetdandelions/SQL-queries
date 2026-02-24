SELECT LISTAGG(column_name, ', '), table_name
FROM information_schema.columns
WHERE table_name in('tableA', 'tableB') 
AND column_name NOT IN ('load_dt') group by table_name;
