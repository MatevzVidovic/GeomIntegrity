


SELECT PostGIS_Full_Version();


select * from validate_2_decimal_places();

DROP FUNCTION IF EXISTS validate_2_decimal_places();

CREATE OR REPLACE FUNCTION validate_2_decimal_places()
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR  rec IN
--         SELECT 1 as id, geom
--         FROM slo_meja
        SELECT id, geom
        FROM md_topoloske_kontrole
--         FROM md_geo_obm
        ORDER BY random()
    LOOP
        IF
            'NULL' != (SELECT array_agg(m[1])::text
           FROM regexp_matches(st_astext(rec.geom), '\d+\.\d{3,}', 'g') AS m)

        THEN
        RAISE NOTICE 'ID: %', rec.id;
        RETURN FALSE;
        END IF;
    END LOOP;
    RETURN TRUE;
END $$;


CREATE OR REPLACE FUNCTION debug_2_decimal_places()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
    view_name TEXT;
BEGIN
    FOR  rec IN
        SELECT id, geom
        FROM md_geo_obm
        ORDER BY random()
        LIMIT 10
    LOOP

        IF
            'NULL' != (SELECT array_agg(m[1])::text
           FROM regexp_matches(st_astext(st_snaptogrid(rec.geom, 0.01)), '\d+\.\d{3,}', 'g') AS m)
            OR
           'NULL' != (SELECT array_agg(m[1])::text
           FROM regexp_matches(st_astext(st_reduceprecision(rec.geom, 0.01)), '\d+\.\d{3,}', 'g') AS m)

        THEN

        RAISE NOTICE 'SRID: %', ST_SRID(rec.geom);
        RAISE NOTICE 'ID: %', rec.id;
        RAISE NOTICE 'GEOM: %', rec.geom;
        RAISE NOTICE 'Original: %', LEFT(st_astext(rec.geom), 200);
        RAISE NOTICE 'Snap to grid: %', LEFT(st_astext(st_snaptogrid(rec.geom, 0.01)), 200);
        RAISE NOTICE 'Reduce precision: %', LEFT(st_astext(st_reduceprecision(rec.geom, 0.01)), 200);

        -- match nums with more than 3 decimals:
        RAISE NOTICE 'Matches Original: %',
          (SELECT array_agg(m[1])::text
           FROM regexp_matches(st_astext(rec.geom), '\d+\.\d{3,}', 'g') AS m);

        RAISE NOTICE 'Matches Snap to grid: %',
          (SELECT array_agg(m[1])::text
           FROM regexp_matches(st_astext(st_snaptogrid(rec.geom, 0.01)), '\d+\.\d{3,}', 'g') AS m);

        RAISE NOTICE 'Matches Reduce precision: %',
          LEFT((SELECT array_agg(m[1])::text
           FROM regexp_matches(st_astext(st_reduceprecision(rec.geom, 0.01)), '\d+\.\d{3,}', 'g') AS m), 200);

        END IF;




    END LOOP;
END $$;




SELECT * FROM set_to_2_decimal_places();

CREATE OR REPLACE FUNCTION set_to_2_decimal_places()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
BEGIN
    UPDATE md_geo_obm
    SET geom = st_reduceprecision(geom, 0.01);

END $$;

