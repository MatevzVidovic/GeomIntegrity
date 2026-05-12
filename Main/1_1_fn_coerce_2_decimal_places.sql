DROP TRIGGER IF EXISTS trg_00_coerce_obm_geom_2_decimal_places ON md_geo_obm;
DROP TRIGGER IF EXISTS trg_000_coerce_obm_geom_2_decimal_places ON md_geo_obm;
DROP FUNCTION IF EXISTS coerce_obm_geom_to_2_decimal_places();
DROP FUNCTION IF EXISTS validate_2_decimal_places();
DROP FUNCTION IF EXISTS debug_2_decimal_places();
DROP FUNCTION IF EXISTS set_to_2_decimal_places();
DROP FUNCTION IF EXISTS geom_is_on_2_decimal_grid(geometry);

CREATE OR REPLACE FUNCTION geom_is_on_2_decimal_grid(p_geom geometry)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p_geom IS NULL
        OR NOT (ST_AsText(p_geom) ~ '\d+\.\d{3,}');
$$;

CREATE OR REPLACE FUNCTION validate_2_decimal_places()
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT 'md_geo_obm' AS source_table, id::text AS row_id, geom
        FROM md_geo_obm
        WHERE geom IS NOT NULL
        UNION ALL
        SELECT 'slo_meja' AS source_table, id::text AS row_id, geom
        FROM slo_meja
        WHERE geom IS NOT NULL
        UNION ALL
        SELECT 'md_topoloske_kontrole_obm' AS source_table, id::text AS row_id, geom
        FROM md_topoloske_kontrole_obm
        WHERE geom IS NOT NULL
    LOOP
        IF NOT geom_is_on_2_decimal_grid(rec.geom) THEN
            RAISE NOTICE 'Geometry is not on 0.01 grid: %.%', rec.source_table, rec.row_id;
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
BEGIN
    FOR rec IN
        SELECT 'md_geo_obm' AS source_table, id::text AS row_id, geom
        FROM md_geo_obm
        WHERE geom IS NOT NULL
        UNION ALL
        SELECT 'slo_meja' AS source_table, id::text AS row_id, geom
        FROM slo_meja
        WHERE geom IS NOT NULL
        UNION ALL
        SELECT 'md_topoloske_kontrole_obm' AS source_table, id::text AS row_id, geom
        FROM md_topoloske_kontrole_obm
        WHERE geom IS NOT NULL
        LIMIT 10
    LOOP
        IF NOT geom_is_on_2_decimal_grid(rec.geom) THEN
            RAISE NOTICE 'Table: %', rec.source_table;
            RAISE NOTICE 'ID: %', rec.row_id;
            RAISE NOTICE 'SRID: %', ST_SRID(rec.geom);
            RAISE NOTICE 'Original: %', LEFT(ST_AsText(rec.geom), 200);
            RAISE NOTICE 'Reduce precision: %', LEFT(ST_AsText(ST_ReducePrecision(rec.geom, 0.01)), 200);
            RAISE NOTICE 'Matches Original: %',
                (SELECT array_agg(m[1])::text
                 FROM regexp_matches(ST_AsText(rec.geom), '\d+\.\d{3,}', 'g') AS m);
        END IF;
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION set_to_2_decimal_places()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE md_geo_obm
    SET geom = ST_ReducePrecision(geom, 0.01);
    -- WHERE geom IS NOT NULL
    --   AND NOT geom_is_on_2_decimal_grid(geom);

    UPDATE slo_meja
    SET geom = ST_ReducePrecision(geom, 0.01);
    -- WHERE geom IS NOT NULL
    --   AND NOT geom_is_on_2_decimal_grid(geom);

    UPDATE md_topoloske_kontrole_obm
    SET geom = ST_ReducePrecision(geom, 0.01);
    -- WHERE geom IS NOT NULL
    --   AND NOT geom_is_on_2_decimal_grid(geom);
END $$;

CREATE OR REPLACE FUNCTION coerce_obm_geom_to_2_decimal_places()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.geom IS NOT NULL THEN
        NEW.geom := ST_ReducePrecision(NEW.geom, 0.01);
    END IF;

    RETURN NEW;
END $$;

CREATE TRIGGER trg_000_coerce_obm_geom_2_decimal_places
    BEFORE INSERT OR UPDATE OF geom ON md_geo_obm
    FOR EACH ROW
    EXECUTE FUNCTION coerce_obm_geom_to_2_decimal_places();
