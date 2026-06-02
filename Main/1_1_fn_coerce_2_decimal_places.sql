DROP TRIGGER IF EXISTS trg_00_coerce_obm_geom_2_decimal_places ON md_geo_obm;
DROP TRIGGER IF EXISTS trg_000_coerce_obm_geom_2_decimal_places ON md_geo_obm;
DROP FUNCTION IF EXISTS coerce_obm_geom_to_2_decimal_places();
DROP FUNCTION IF EXISTS validate_2_decimal_places();
DROP FUNCTION IF EXISTS debug_2_decimal_places();
DROP FUNCTION IF EXISTS set_to_2_decimal_places();
DROP FUNCTION IF EXISTS geom_is_on_2_decimal_grid(geometry);
DROP FUNCTION IF EXISTS ensure_snap_to_grid(geometry, float8);

CREATE OR REPLACE FUNCTION ensure_snap_to_grid(
    p_geom geometry,
    gridsize float8 DEFAULT 0.01
)
RETURNS geometry
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
    cleaned geometry;
BEGIN

    -- ST_ReducePrecision forces valid geom. 
    -- It can let things go to empty if all vertices of a polygon are inside one grid cell (still valid); 
    -- but especially for long, thin polygons (slivers) it will try to inflate them.
    -- -- I suspect ST_Difference also has small rounding errors which cause 
    -- extremely tiny slivers that ST_ReducePrecision would then inflate.

    -- ST_ReducePrecision wont let polygons become invalid.
    -- ST_SnapToGrid still has very small float errors in GEOSS 3.9
    -- Combine both so things actually work.

    IF p_geom IS NULL OR ST_IsEmpty(p_geom) THEN
        RETURN NULL;
    END IF;

    -- Collapse tiny slivers to the target grid and repair invalid debris.
    cleaned := ST_CollectionExtract(ST_MakeValid(ST_SnapToGrid(p_geom, gridsize)), 3);

    IF cleaned IS NULL OR ST_IsEmpty(cleaned) OR ST_Area(cleaned) = 0 THEN
        RETURN NULL;
    END IF;

    -- Dissolve internal polygon boundaries before final fixed-precision cleanup.
    cleaned := ST_UnaryUnion(cleaned);

    -- Final operation must enforce precision. Do not call ST_MakeValid after this.
    cleaned := ST_CollectionExtract(ST_ReducePrecision(cleaned, gridsize), 3);

    IF cleaned IS NULL OR ST_IsEmpty(cleaned) OR ST_Area(cleaned) = 0 THEN
        RETURN NULL;
    END IF;

    RETURN cleaned;
END;
$$;

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
            RAISE NOTICE 'Snap to grid: %', LEFT(ST_AsText(ensure_snap_to_grid(rec.geom)), 200);
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
    IF EXISTS (
        SELECT 1
        FROM slo_meja
        WHERE geom IS NOT NULL
          AND ensure_snap_to_grid(geom) IS NULL
    ) THEN
        RAISE EXCEPTION 'Snapping slo_meja to 0.01 grid collapsed a boundary geometry';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM md_geo_obm
        WHERE geom IS NOT NULL
          AND ensure_snap_to_grid(geom) IS NULL
    ) THEN
        RAISE EXCEPTION 'Snapping md_geo_obm to 0.01 grid collapsed an OBM geometry';
    END IF;

    -- slo_meja is the canonical clipping/check boundary. Snap it first so all
    -- following OBM topology operations use a 0.01-grid boundary.
    UPDATE slo_meja
    SET geom = ST_Multi(ensure_snap_to_grid(geom))::geometry(MultiPolygon, 3794);

    UPDATE md_geo_obm
    SET geom = ST_Multi(ensure_snap_to_grid(geom))::geometry(MultiPolygon, 3794);
    -- WHERE geom IS NOT NULL
    --   AND NOT geom_is_on_2_decimal_grid(geom);

    UPDATE md_topoloske_kontrole_obm
    SET geom = ensure_snap_to_grid(geom);
    -- WHERE geom IS NOT NULL
    --   AND NOT geom_is_on_2_decimal_grid(geom);
END $$;

CREATE OR REPLACE FUNCTION coerce_obm_geom_to_2_decimal_places()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_snapped_geom geometry;
BEGIN
    IF NEW.geom IS NOT NULL THEN
        v_snapped_geom := ensure_snap_to_grid(NEW.geom);

        IF v_snapped_geom IS NULL THEN
            RAISE EXCEPTION 'Snapping md_geo_obm geometry to 0.01 grid collapsed it';
        END IF;

        NEW.geom := ST_Multi(v_snapped_geom)::geometry(MultiPolygon, 3794);
    END IF;

    RETURN NEW;
END $$;

CREATE TRIGGER trg_000_coerce_obm_geom_2_decimal_places
    BEFORE INSERT OR UPDATE OF geom ON md_geo_obm
    FOR EACH ROW
    EXECUTE FUNCTION coerce_obm_geom_to_2_decimal_places();
