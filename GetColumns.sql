SELECT table_name, LISTAGG(column_name, ', ')
       WITHIN GROUP (ORDER BY ordinal_position)
FROM information_schema.columns
WHERE table_schema = 'schema'
AND table_name in('tableA', 'tableB') 
AND column_name NOT IN ('load_dt') group by table_name;
