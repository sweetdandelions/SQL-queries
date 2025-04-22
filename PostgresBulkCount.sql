DO $$
DECLARE
    table_rec RECORD;
    row_count BIGINT;
BEGIN
    FOR table_rec IN (
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public'
        AND table_type = 'BASE TABLE'
    ) 
    LOOP
        EXECUTE 'SELECT COUNT(*) FROM ' || quote_ident(table_rec.table_name) INTO row_count;
        RAISE NOTICE 'Table: % has % rows', table_rec.table_name, row_count;
    END LOOP;
END $$;
