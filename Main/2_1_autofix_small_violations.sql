-- ============================================================================
-- 2_1_autofix_small_violations.sql - OBM Topology Autofix Helpers
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

DROP FUNCTION IF EXISTS autofix_overflows_and_maybe_autofix_small_napake();
DROP FUNCTION IF EXISTS autofix_overflows_and_maybe_autofix_small_napake_for_version(uuid);
DROP FUNCTION IF EXISTS autofix_small_obm_topology_all_versions();
DROP FUNCTION IF EXISTS autofix_small_obm_topology_for_version(uuid);
DROP FUNCTION IF EXISTS autofix_small_intersections_for_version(uuid);
DROP FUNCTION IF EXISTS autofix_small_holes_for_version(uuid);
DROP FUNCTION IF EXISTS autofix_overflows_all_versions();
DROP FUNCTION IF EXISTS autofix_overflows_for_version(uuid);

-- ########################################
-- Autofixing everything at once - for after validate_all_topologies:
-- ########################################

CREATE OR REPLACE FUNCTION autofix_overflows_for_version(p_id_rel_geo_verzija uuid)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_slo_meja geometry;
    v_remaining_count integer := 0;
BEGIN
    SELECT geom INTO v_slo_meja FROM slo_meja LIMIT 1;

    IF v_slo_meja IS NULL THEN
        RAISE EXCEPTION 'Slovenia boundary (slo_meja) not found';
    END IF;

    WITH clipped AS (
        SELECT
            obm.id,
            ST_Multi(ensure_snap_to_grid(
                ST_Intersection(ensure_snap_to_grid(obm.geom), v_slo_meja)
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
      AND NOT ST_IsEmpty(clipped.geom)
      AND NOT ST_Equals(obm.geom, clipped.geom);

    SELECT COUNT(*)
    INTO v_remaining_count
    FROM get_obm_overflow_candidates(p_id_rel_geo_verzija) candidates
    WHERE NOT preprocessing_is_small_obm_topology_problem(candidates.overflow_geom);

    RETURN v_remaining_count;
END $$;

CREATE OR REPLACE FUNCTION autofix_overflows_all_versions()
RETURNS TABLE(
    chosen_id_rel_geo_verzija uuid,
    reportable_overflows integer
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
        reportable_overflows := autofix_overflows_for_version(v_version);
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
    v_hole_geom geometry;
    v_best_neighbor_id uuid;
    v_fixed_geom geometry;
    v_fixed_count integer := 0;
    v_row_count integer := 0;
    v_iteration integer := 0;
BEGIN
    LOOP
        v_iteration := v_iteration + 1;
        v_hole_geom := NULL;

        SELECT candidates.hole_geom
        INTO v_hole_geom
        FROM get_obm_hole_candidates(p_id_rel_geo_verzija) candidates
        WHERE preprocessing_is_small_obm_topology_problem(candidates.hole_geom)
        ORDER BY candidates.povrsina DESC, candidates.obseg DESC
        LIMIT 1;

        EXIT WHEN v_hole_geom IS NULL;

        v_best_neighbor_id := find_best_obm_neighbor_for_hole(
            p_id_rel_geo_verzija,
            v_hole_geom,
            NULL
        );

        IF v_best_neighbor_id IS NULL THEN
            RAISE WARNING
                'Small OBM hole autofix found no neighbor for version %.',
                p_id_rel_geo_verzija;
            EXIT;
        END IF;

        SELECT ensure_snap_to_grid(ST_Union(obm.geom, v_hole_geom))
        INTO v_fixed_geom
        FROM md_geo_obm obm
        WHERE obm.id = v_best_neighbor_id;

        IF v_fixed_geom IS NULL THEN
            RAISE WARNING
                'Small OBM hole autofix produced empty geometry for version %, OBM %.',
                p_id_rel_geo_verzija,
                v_best_neighbor_id;
            EXIT;
        END IF;

        UPDATE md_geo_obm
        SET geom = ST_Multi(v_fixed_geom)::geometry(MultiPolygon, 3794)
        WHERE id = v_best_neighbor_id
          AND NOT ST_Equals(geom, v_fixed_geom);

        GET DIAGNOSTICS v_row_count = ROW_COUNT;

        IF v_row_count = 0 THEN
            RAISE WARNING
                'Small OBM hole autofix made no geometry change for version %, OBM %.',
                p_id_rel_geo_verzija,
                v_best_neighbor_id;
            EXIT;
        END IF;

        v_fixed_count := v_fixed_count + 1;

        IF v_iteration >= 1000 THEN
            RAISE WARNING
                'Small OBM hole autofix reached iteration guard for version %.',
                p_id_rel_geo_verzija;
            EXIT;
        END IF;
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
    v_iteration integer := 0;
    v_iteration_changed integer := 0;
    v_row_count integer := 0;
    v_candidate_count integer := 0;
BEGIN
    IF to_regclass('pg_temp.temp_autofix_small_intersections') IS NULL THEN
        CREATE TEMP TABLE temp_autofix_small_intersections (
            id_a uuid,
            id_b uuid,
            intersection_geom geometry
        ) ON COMMIT DROP;
    ELSE
        TRUNCATE temp_autofix_small_intersections;
    END IF;

    LOOP
        v_iteration := v_iteration + 1;
        v_iteration_changed := 0;

        TRUNCATE temp_autofix_small_intersections;

        INSERT INTO temp_autofix_small_intersections (id_a, id_b, intersection_geom)
        SELECT
            a.id,
            b.id,
            ensure_snap_to_grid((ST_Dump(ST_Intersection(a.geom, b.geom))).geom)
        FROM md_geo_obm a
        JOIN md_geo_obm b ON a.id_rel_geo_verzija = b.id_rel_geo_verzija
        WHERE a.id_rel_geo_verzija = p_id_rel_geo_verzija
          AND a.id < b.id
          AND ST_Intersects(a.geom, b.geom)
          AND NOT ST_Touches(a.geom, b.geom);

        SELECT COUNT(*)
        INTO v_candidate_count
        FROM temp_autofix_small_intersections
        WHERE ST_GeometryType(intersection_geom) IN ('ST_Polygon', 'ST_MultiPolygon')
          AND ST_Area(intersection_geom) > 0
          AND preprocessing_is_small_obm_topology_problem(intersection_geom);

        EXIT WHEN v_candidate_count = 0;

        FOR v_target IN
            SELECT
                id_b,
                ensure_snap_to_grid(ST_Union(intersection_geom)) AS geom_to_remove
            FROM temp_autofix_small_intersections
            WHERE ST_GeometryType(intersection_geom) IN ('ST_Polygon', 'ST_MultiPolygon')
              AND ST_Area(intersection_geom) > 0
              AND preprocessing_is_small_obm_topology_problem(intersection_geom)
            GROUP BY id_b
        LOOP
            SELECT ensure_snap_to_grid(ST_Difference(obm.geom, v_target.geom_to_remove))
            INTO v_fixed_geom
            FROM md_geo_obm obm
            WHERE obm.id = v_target.id_b;

            IF v_fixed_geom IS NULL THEN
                CONTINUE;
            END IF;

            UPDATE md_geo_obm
            SET geom = ST_Multi(v_fixed_geom)::geometry(MultiPolygon, 3794)
            WHERE id = v_target.id_b
              AND NOT ST_Equals(geom, v_fixed_geom);

            GET DIAGNOSTICS v_row_count = ROW_COUNT;
            v_iteration_changed := v_iteration_changed + v_row_count;
        END LOOP;

        IF v_iteration_changed = 0 THEN
            RAISE WARNING
                'Small OBM intersection autofix found % candidates but made no geometry changes for version %.',
                v_candidate_count,
                p_id_rel_geo_verzija;
            EXIT;
        END IF;

        v_fixed_count := v_fixed_count + v_iteration_changed;

        IF v_iteration >= 1000 THEN
            RAISE WARNING
                'Small OBM intersection autofix reached iteration guard for version %.',
                p_id_rel_geo_verzija;
            EXIT;
        END IF;
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

CREATE OR REPLACE FUNCTION autofix_overflows_and_maybe_autofix_small_napake_for_version(p_id_rel_geo_verzija uuid)
RETURNS TABLE(
    chosen_id_rel_geo_verzija uuid,
    passes integer,
    reportable_overflows integer,
    holes_fixed integer,
    intersections_fixed integer,
    total_fixed integer
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_pass integer := 0;
    v_reportable_overflows integer := 0;
    v_holes_fixed integer := 0;
    v_intersections_fixed integer := 0;
    v_last_pass_total integer := 0;
    v_total_holes_fixed integer := 0;
    v_total_intersections_fixed integer := 0;
    v_remaining_small_holes integer := 0;
    v_remaining_small_intersections integer := 0;
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

    LOOP
        v_pass := v_pass + 1;

        PERFORM autofix_overflows_for_version(p_id_rel_geo_verzija);

        IF obm_small_topology_autofix_enabled() THEN
            SELECT
                fixes.holes_fixed,
                fixes.intersections_fixed
            INTO
                v_holes_fixed,
                v_intersections_fixed
            FROM autofix_small_obm_topology_for_version(p_id_rel_geo_verzija) fixes;
        ELSE
            v_holes_fixed := 0;
            v_intersections_fixed := 0;
        END IF;

        v_reportable_overflows := autofix_overflows_for_version(p_id_rel_geo_verzija);
        v_total_holes_fixed := v_total_holes_fixed + COALESCE(v_holes_fixed, 0);
        v_total_intersections_fixed := v_total_intersections_fixed + COALESCE(v_intersections_fixed, 0);

        IF obm_small_topology_autofix_enabled() THEN
            SELECT COUNT(*)
            INTO v_remaining_small_holes
            FROM get_obm_hole_candidates(p_id_rel_geo_verzija) candidates
            WHERE preprocessing_is_small_obm_topology_problem(candidates.hole_geom);

            WITH small_intersections AS (
                SELECT ensure_snap_to_grid((ST_Dump(ST_Intersection(a.geom, b.geom))).geom) AS geom
                FROM md_geo_obm a
                JOIN md_geo_obm b ON a.id_rel_geo_verzija = b.id_rel_geo_verzija
                WHERE a.id_rel_geo_verzija = p_id_rel_geo_verzija
                  AND a.id < b.id
                  AND ST_Intersects(a.geom, b.geom)
                  AND NOT ST_Touches(a.geom, b.geom)
            )
            SELECT COUNT(*)
            INTO v_remaining_small_intersections
            FROM small_intersections
            WHERE ST_GeometryType(geom) IN ('ST_Polygon', 'ST_MultiPolygon')
              AND ST_Area(geom) > 0
              AND preprocessing_is_small_obm_topology_problem(geom);
        ELSE
            v_remaining_small_holes := 0;
            v_remaining_small_intersections := 0;
        END IF;

        v_last_pass_total := COALESCE(v_remaining_small_holes, 0)
            + COALESCE(v_remaining_small_intersections, 0)
            + COALESCE(v_reportable_overflows, 0);

        EXIT WHEN v_last_pass_total = 0 OR v_pass >= 7;
    END LOOP;

    IF v_last_pass_total > 0 AND v_pass >= 7 THEN
        RAISE WARNING
            'OBM topology autofix reached pass limit for version %.',
            p_id_rel_geo_verzija;
    END IF;

    RAISE NOTICE
        'Version % took % passes. Last pass left % reportable overflows and fixed % holes and % intersections.',
        p_id_rel_geo_verzija,
        v_pass,
        v_reportable_overflows,
        v_holes_fixed,
        v_intersections_fixed;

    IF v_trigger_existed AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'validate_topology_incremental') THEN
        EXECUTE '
            CREATE TRIGGER trg_validate_topology_incremental
            BEFORE INSERT OR UPDATE OF geom OR DELETE ON md_geo_obm
            FOR EACH ROW
            EXECUTE FUNCTION validate_topology_incremental()';
    END IF;

    RETURN QUERY SELECT
        p_id_rel_geo_verzija,
        v_pass,
        v_reportable_overflows,
        v_total_holes_fixed,
        v_total_intersections_fixed,
        v_total_holes_fixed + v_total_intersections_fixed + v_reportable_overflows;
END $$;

CREATE OR REPLACE FUNCTION autofix_overflows_and_maybe_autofix_small_napake()
RETURNS TABLE(
    chosen_id_rel_geo_verzija uuid,
    passes integer,
    reportable_overflows integer,
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
        SELECT *
        FROM autofix_overflows_and_maybe_autofix_small_napake_for_version(v_version);
    END LOOP;

    IF v_trigger_existed AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'validate_topology_incremental') THEN
        EXECUTE '
            CREATE TRIGGER trg_validate_topology_incremental
            BEFORE INSERT OR UPDATE OF geom OR DELETE ON md_geo_obm
            FOR EACH ROW
            EXECUTE FUNCTION validate_topology_incremental()';
    END IF;
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
