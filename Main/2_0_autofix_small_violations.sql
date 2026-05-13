-- ============================================================================
-- 2_0_autofix_small_violations.sql - OBM Topology Autofix Helpers
-- ============================================================================
-- Overflow preprocessing clips OBM geometry to slo_meja before batch validation.
-- Small violations are geometry slivers we fix immediately instead of writing
-- them into md_topoloske_kontrole_obm.
--
-- Live trigger rule:
--   ST_Area(geom) < 10 OR (ST_Area(geom) < 100 AND compactness < 0.01)
--
-- Preprocessing/full-validation rule:
--   ST_Area(geom) < 10 OR (ST_Area(geom) < 1000 AND compactness < 0.01)
--
-- These helpers are used by the OBM incremental trigger. They are intentionally
-- not implemented as triggers on md_topoloske_kontrole_obm, because that would
-- update md_geo_obm while the md_geo_obm trigger is already running.
-- ============================================================================

DROP FUNCTION IF EXISTS autofix_small_obm_topology_all_versions();
DROP FUNCTION IF EXISTS autofix_small_obm_topology_for_version(uuid);
DROP FUNCTION IF EXISTS autofix_small_intersections_for_version(uuid);
DROP FUNCTION IF EXISTS autofix_small_holes_for_version(uuid);
DROP FUNCTION IF EXISTS autofix_overflows_all_versions();
DROP FUNCTION IF EXISTS autofix_overflows_for_version(uuid);
DROP FUNCTION IF EXISTS find_best_obm_neighbor_for_hole(uuid, geometry, uuid);
DROP FUNCTION IF EXISTS preprocessing_is_small_obm_topology_problem(geometry);
DROP FUNCTION IF EXISTS is_small_obm_topology_problem(geometry);
DROP FUNCTION IF EXISTS obm_topology_compactness(geometry);
DROP FUNCTION IF EXISTS obm_small_topology_autofix_enabled();

CREATE OR REPLACE FUNCTION obm_small_topology_autofix_enabled()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT true
$$;

CREATE OR REPLACE FUNCTION obm_topology_compactness(p_geom geometry)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_geom IS NULL OR ST_IsEmpty(p_geom) OR ST_Perimeter(p_geom) = 0 THEN NULL
        ELSE 4 * pi() * ST_Area(p_geom) / (ST_Perimeter(p_geom) * ST_Perimeter(p_geom))
    END;
$$;

CREATE OR REPLACE FUNCTION is_small_obm_topology_problem(p_geom geometry)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
    WITH metrics AS (
        SELECT
            ST_Area(p_geom) AS area,
            obm_topology_compactness(p_geom) AS compactness
        WHERE p_geom IS NOT NULL
        AND NOT ST_IsEmpty(p_geom)
    )
    SELECT COALESCE(
        EXISTS (
            SELECT 1
            FROM metrics
            WHERE area < 10
                OR (
                    area < 100
                    AND compactness < 0.01
                )
        ),
        false
    );
$$;

CREATE OR REPLACE FUNCTION preprocessing_is_small_obm_topology_problem(p_geom geometry)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
    WITH metrics AS (
        SELECT
            ST_Area(p_geom) AS area,
            obm_topology_compactness(p_geom) AS compactness
        WHERE p_geom IS NOT NULL
        AND NOT ST_IsEmpty(p_geom)
    )
    SELECT COALESCE(
        EXISTS (
            SELECT 1
            FROM metrics
            WHERE area < 10
                OR (
                    area < 1000
                    AND compactness < 0.01
                )
        ),
        false
    );
$$;

CREATE OR REPLACE FUNCTION find_best_obm_neighbor_for_hole(
    p_id_rel_geo_verzija uuid,
    p_hole_geom geometry,
    p_excluded_obm_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT obm.id
    FROM md_geo_obm obm
    WHERE obm.id_rel_geo_verzija = p_id_rel_geo_verzija
      AND obm.geom IS NOT NULL
      AND (p_excluded_obm_id IS NULL OR obm.id <> p_excluded_obm_id)
      AND ST_Intersects(ST_Buffer(p_hole_geom, 10), obm.geom)
    ORDER BY
      ST_Area(ST_Intersection(ST_Buffer(p_hole_geom, 1), obm.geom)) DESC,
      obm.id
    LIMIT 1;
$$;


-- ########################################
-- Autofixing everything at once - for after validate_all_topologies:
-- ########################################

CREATE OR REPLACE FUNCTION autofix_overflows_for_version(p_id_rel_geo_verzija uuid)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_slo_meja geometry;
    v_fixed_count integer := 0;
BEGIN
    SELECT geom INTO v_slo_meja FROM slo_meja LIMIT 1;

    IF v_slo_meja IS NULL THEN
        RAISE EXCEPTION 'Slovenia boundary (slo_meja) not found';
    END IF;

    WITH clipped AS (
        SELECT
            obm.id,
            ST_Multi(ST_ReducePrecision(
                ST_CollectionExtract(
                    ST_MakeValid(
                        ST_ReducePrecision(
                            ST_Intersection(ST_ReducePrecision(obm.geom, 0.01), v_slo_meja),
                            0.01
                        )
                    ),
                    3
                ),
                0.01
            ))::geometry(MultiPolygon, 3794) AS geom
        FROM md_geo_obm obm
        WHERE obm.id_rel_geo_verzija = p_id_rel_geo_verzija
          AND obm.geom IS NOT NULL
          AND NOT ST_Covers(v_slo_meja, obm.geom)
    )
    UPDATE md_geo_obm obm
    SET geom = clipped.geom
    FROM clipped
    WHERE obm.id = clipped.id
      AND clipped.geom IS NOT NULL
      AND NOT ST_IsEmpty(clipped.geom);

    GET DIAGNOSTICS v_fixed_count = ROW_COUNT;

    RETURN v_fixed_count;
END $$;

CREATE OR REPLACE FUNCTION autofix_overflows_all_versions()
RETURNS TABLE(
    chosen_id_rel_geo_verzija uuid,
    overflows_fixed integer
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_version uuid;
    v_trigger_existed boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        WHERE t.tgname = 'trg_validate_topology_incremental'
          AND c.relname = 'md_geo_obm'
    ) INTO v_trigger_existed;

    IF v_trigger_existed THEN
        EXECUTE 'DROP TRIGGER IF EXISTS trg_validate_topology_incremental ON md_geo_obm';
    END IF;

    FOR v_version IN
        SELECT DISTINCT obm.id_rel_geo_verzija
        FROM md_geo_obm obm
        WHERE obm.id_rel_geo_verzija IS NOT NULL
        ORDER BY obm.id_rel_geo_verzija
    LOOP
        chosen_id_rel_geo_verzija := v_version;
        overflows_fixed := autofix_overflows_for_version(v_version);
        RETURN NEXT;
    END LOOP;

    IF v_trigger_existed AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'validate_topology_incremental') THEN
        EXECUTE '
            CREATE TRIGGER trg_validate_topology_incremental
            BEFORE INSERT OR UPDATE OF geom OR DELETE ON md_geo_obm
            FOR EACH ROW
            EXECUTE FUNCTION validate_topology_incremental()';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION autofix_small_holes_for_version(p_id_rel_geo_verzija uuid)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_slo_meja geometry;
    v_union_geom geometry;
    v_holes_geom geometry;
    v_hole_geom geometry;
    v_best_neighbor_id uuid;
    v_fixed_geom geometry;
    v_fixed_count integer := 0;
BEGIN
    SELECT geom INTO v_slo_meja FROM slo_meja LIMIT 1;

    IF v_slo_meja IS NULL THEN
        RAISE EXCEPTION 'Slovenia boundary (slo_meja) not found';
    END IF;

    SELECT ST_Union(geom)
    INTO v_union_geom
    FROM md_geo_obm
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija
      AND geom IS NOT NULL;

    IF v_union_geom IS NULL OR ST_IsEmpty(v_union_geom) THEN
        RETURN 0;
    END IF;

    v_holes_geom := ST_ReducePrecision(ST_Difference(v_slo_meja, v_union_geom), 0.01);

    IF v_holes_geom IS NULL OR ST_IsEmpty(v_holes_geom) THEN
        RETURN 0;
    END IF;

    FOR v_hole_geom IN
        SELECT ST_ReducePrecision((ST_Dump(v_holes_geom)).geom, 0.01)
    LOOP
        IF v_hole_geom IS NULL
           OR ST_IsEmpty(v_hole_geom)
           OR ST_Area(v_hole_geom) <= 0
           OR ST_GeometryType(v_hole_geom) NOT IN ('ST_Polygon', 'ST_MultiPolygon')
           OR NOT preprocessing_is_small_obm_topology_problem(v_hole_geom) THEN
            CONTINUE;
        END IF;

        v_best_neighbor_id := find_best_obm_neighbor_for_hole(
            p_id_rel_geo_verzija,
            v_hole_geom,
            NULL
        );

        IF v_best_neighbor_id IS NULL THEN
            CONTINUE;
        END IF;

        SELECT ST_ReducePrecision(ST_Union(obm.geom, v_hole_geom), 0.01)
        INTO v_fixed_geom
        FROM md_geo_obm obm
        WHERE obm.id = v_best_neighbor_id;

        UPDATE md_geo_obm
        SET geom = ST_Multi(ST_ReducePrecision(v_fixed_geom, 0.01))
        WHERE id = v_best_neighbor_id;

        v_fixed_count := v_fixed_count + 1;
    END LOOP;

    RETURN v_fixed_count;
END $$;

CREATE OR REPLACE FUNCTION autofix_small_intersections_for_version(p_id_rel_geo_verzija uuid)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_target record;
    v_fixed_geom geometry;
    v_fixed_count integer := 0;
BEGIN
    DROP TABLE IF EXISTS temp_autofix_small_intersections;
    CREATE TEMP TABLE temp_autofix_small_intersections (
        id_a uuid,
        id_b uuid,
        intersection_geom geometry
    ) ON COMMIT DROP;

    INSERT INTO temp_autofix_small_intersections (id_a, id_b, intersection_geom)
    SELECT
        a.id,
        b.id,
        ST_ReducePrecision((ST_Dump(ST_Intersection(a.geom, b.geom))).geom, 0.01)
    FROM md_geo_obm a
    JOIN md_geo_obm b ON a.id_rel_geo_verzija = b.id_rel_geo_verzija
    WHERE a.id_rel_geo_verzija = p_id_rel_geo_verzija
      AND a.id < b.id
      AND ST_Intersects(a.geom, b.geom)
      AND NOT ST_Touches(a.geom, b.geom);

    SELECT COUNT(*)
    INTO v_fixed_count
    FROM temp_autofix_small_intersections
    WHERE ST_GeometryType(intersection_geom) IN ('ST_Polygon', 'ST_MultiPolygon')
      AND ST_Area(intersection_geom) > 0
      AND preprocessing_is_small_obm_topology_problem(intersection_geom);

    FOR v_target IN
        SELECT
            id_b,
            ST_ReducePrecision(ST_Union(intersection_geom), 0.01) AS geom_to_remove
        FROM temp_autofix_small_intersections
        WHERE ST_GeometryType(intersection_geom) IN ('ST_Polygon', 'ST_MultiPolygon')
          AND ST_Area(intersection_geom) > 0
          AND preprocessing_is_small_obm_topology_problem(intersection_geom)
        GROUP BY id_b
    LOOP
        SELECT ST_ReducePrecision(ST_Difference(obm.geom, v_target.geom_to_remove), 0.01)
        INTO v_fixed_geom
        FROM md_geo_obm obm
        WHERE obm.id = v_target.id_b;

        UPDATE md_geo_obm
        SET geom = ST_Multi(ST_ReducePrecision(v_fixed_geom, 0.01))
        WHERE id = v_target.id_b;

    END LOOP;

    RETURN v_fixed_count;
END $$;

CREATE OR REPLACE FUNCTION autofix_small_obm_topology_for_version(p_id_rel_geo_verzija uuid)
RETURNS TABLE(
    holes_fixed integer,
    intersections_fixed integer,
    total_fixed integer
)
LANGUAGE plpgsql
AS $$
BEGIN
    holes_fixed := autofix_small_holes_for_version(p_id_rel_geo_verzija);
    intersections_fixed := autofix_small_intersections_for_version(p_id_rel_geo_verzija);
    total_fixed := holes_fixed + intersections_fixed;

    RETURN NEXT;
END $$;

-- only meant for manual running .The validate_all_topologies fn does what this fn does by itself already
CREATE OR REPLACE FUNCTION autofix_small_obm_topology_all_versions()
RETURNS TABLE(
    chosen_id_rel_geo_verzija uuid,
    holes_fixed integer,
    intersections_fixed integer,
    total_fixed integer
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_version uuid;
    v_trigger_existed boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        WHERE t.tgname = 'trg_validate_topology_incremental'
          AND c.relname = 'md_geo_obm'
    ) INTO v_trigger_existed;

    IF v_trigger_existed THEN
        EXECUTE 'DROP TRIGGER IF EXISTS trg_validate_topology_incremental ON md_geo_obm';
    END IF;

    FOR v_version IN
        SELECT DISTINCT obm.id_rel_geo_verzija
        FROM md_geo_obm obm
        WHERE obm.id_rel_geo_verzija IS NOT NULL
        ORDER BY obm.id_rel_geo_verzija
    LOOP
        RETURN QUERY
        SELECT
            v_version,
            fixes.holes_fixed,
            fixes.intersections_fixed,
            fixes.total_fixed
        FROM autofix_small_obm_topology_for_version(v_version) fixes;
    END LOOP;

    IF v_trigger_existed AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'validate_topology_incremental') THEN
        EXECUTE '
            CREATE TRIGGER trg_validate_topology_incremental
            BEFORE INSERT OR UPDATE OF geom OR DELETE ON md_geo_obm
            FOR EACH ROW
            EXECUTE FUNCTION validate_topology_incremental()';
    END IF;
END $$;
