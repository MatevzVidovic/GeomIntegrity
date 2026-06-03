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
DROP FUNCTION IF EXISTS autofix_overflows_for_version_with_stats(uuid);

-- ########################################
-- Autofixing everything at once - for after validate_all_topologies:
-- ########################################

-- Clips OBMs to slo_meja for one OBM version.
-- Returns how many OBM rows were changed and how many reportable overflows remain.
-- Does not fix holes or intersections.
CREATE OR REPLACE FUNCTION autofix_overflows_for_version_with_stats(p_id_rel_geo_verzija uuid)
RETURNS TABLE(
    clipped_rows integer,
    reportable_overflows integer
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_slo_meja geometry;
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

    GET DIAGNOSTICS clipped_rows = ROW_COUNT;

    SELECT COUNT(*)
    INTO reportable_overflows
    FROM get_obm_overflow_candidates(p_id_rel_geo_verzija) candidates
    WHERE NOT preprocessing_is_small_obm_topology_problem(candidates.overflow_geom);

    RETURN NEXT;
END $$;

-- Compatibility wrapper for callers that only need remaining reportable overflows.
CREATE OR REPLACE FUNCTION autofix_overflows_for_version(p_id_rel_geo_verzija uuid)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_reportable_overflows integer := 0;
BEGIN
    SELECT stats.reportable_overflows
    INTO v_reportable_overflows
    FROM autofix_overflows_for_version_with_stats(p_id_rel_geo_verzija) stats;

    RETURN v_reportable_overflows;
END $$;

-- Manual/debug helper for clipping overflows in all OBM versions.
-- This is not the full setup autofix path because it skips small holes/intersections.
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

-- Fixes preprocessing-small holes for one OBM version.
-- Each current hole is assigned to the best neighboring OBM and unioned into it.
-- Holes are recomputed after every changed geometry to avoid stale candidates.
-- Returns actual changed md_geo_obm row count.
CREATE OR REPLACE FUNCTION autofix_small_holes_for_version(p_id_rel_geo_verzija uuid)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_hole_geom geometry;
    v_neighbor record;
    v_fixed_geom geometry;
    v_fixed_count integer := 0;
    v_row_count integer := 0;
    v_iteration integer := 0;
    v_changed boolean := false;
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

        v_changed := false;

        FOR v_neighbor IN
            SELECT
                obm.id,
                ST_Area(ST_Intersection(ST_Buffer(v_hole_geom, 1), obm.geom)) AS shared_score
            FROM md_geo_obm obm
            WHERE obm.id_rel_geo_verzija = p_id_rel_geo_verzija
              AND obm.geom IS NOT NULL
              AND ST_Intersects(ST_Buffer(v_hole_geom, 10), obm.geom)
            ORDER BY shared_score DESC, obm.id
        LOOP
            SELECT ensure_snap_to_grid(ST_Union(obm.geom, v_hole_geom))
            INTO v_fixed_geom
            FROM md_geo_obm obm
            WHERE obm.id = v_neighbor.id;

            IF v_fixed_geom IS NULL THEN
                CONTINUE;
            END IF;

            UPDATE md_geo_obm
            SET geom = ST_Multi(v_fixed_geom)::geometry(MultiPolygon, 3794)
            WHERE id = v_neighbor.id
              AND (
                  NOT ST_Equals(geom, v_fixed_geom)
                  OR ST_AsEWKB(geom) <> ST_AsEWKB(ST_Multi(v_fixed_geom)::geometry(MultiPolygon, 3794))
              );

            GET DIAGNOSTICS v_row_count = ROW_COUNT;

            IF v_row_count > 0 THEN
                v_changed := true;
                EXIT;
            END IF;
        END LOOP;

        IF NOT v_changed THEN
            RAISE WARNING
                'Small OBM hole autofix could not change any neighboring OBM for version %. Area %, perimeter %, compactness %.',
                p_id_rel_geo_verzija,
                ST_Area(v_hole_geom),
                ST_Perimeter(v_hole_geom),
                obm_topology_compactness(v_hole_geom);
            EXIT;
        END IF;

        v_fixed_count := v_fixed_count + 1;

        -- Runaway safety guard only. Normal setup can legitimately fix many small holes.
        IF v_iteration >= 10000 THEN
            RAISE EXCEPTION
                'Small OBM hole autofix reached iteration guard for version %. Fixed % holes in this call.',
                p_id_rel_geo_verzija,
                v_fixed_count;
        END IF;
    END LOOP;

    RETURN v_fixed_count;
END $$;

-- Fixes preprocessing-small pairwise OBM overlaps for one OBM version.
-- The overlap is subtracted from one side of each pair/group.
-- Intersections are recomputed after every iteration to avoid stale candidates.
-- Returns actual changed md_geo_obm row count, not candidate count.
CREATE OR REPLACE FUNCTION autofix_small_intersections_for_version(p_id_rel_geo_verzija uuid)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_target record;
    v_target_id uuid;
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
            ensure_snap_to_grid(dump_result.geom)
        FROM md_geo_obm a
        JOIN md_geo_obm b ON a.id_rel_geo_verzija = b.id_rel_geo_verzija
        CROSS JOIN LATERAL ST_Dump(
            ensure_snap_to_grid(ST_Intersection(a.geom, b.geom))
        ) AS dump_result
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
                id_a,
                id_b,
                intersection_geom AS geom_to_remove
            FROM temp_autofix_small_intersections
            WHERE ST_GeometryType(intersection_geom) IN ('ST_Polygon', 'ST_MultiPolygon')
              AND ST_Area(intersection_geom) > 0
              AND preprocessing_is_small_obm_topology_problem(intersection_geom)
            ORDER BY ST_Area(intersection_geom) DESC, id_a, id_b
        LOOP
            FOR v_target_id IN
                SELECT target_id
                FROM (VALUES (v_target.id_b), (v_target.id_a)) AS targets(target_id)
            LOOP
                SELECT ensure_snap_to_grid(ST_Difference(obm.geom, v_target.geom_to_remove))
                INTO v_fixed_geom
                FROM md_geo_obm obm
                WHERE obm.id = v_target_id;

                IF v_fixed_geom IS NULL THEN
                    CONTINUE;
                END IF;

                UPDATE md_geo_obm
                SET geom = ST_Multi(v_fixed_geom)::geometry(MultiPolygon, 3794)
                WHERE id = v_target_id
                  AND (
                      NOT ST_Equals(geom, v_fixed_geom)
                      OR ST_AsEWKB(geom) <> ST_AsEWKB(ST_Multi(v_fixed_geom)::geometry(MultiPolygon, 3794))
                  );

                GET DIAGNOSTICS v_row_count = ROW_COUNT;
                v_iteration_changed := v_iteration_changed + v_row_count;

                EXIT WHEN v_row_count > 0;
            END LOOP;

            EXIT WHEN v_iteration_changed > 0;
        END LOOP;

        IF v_iteration_changed = 0 THEN
            RAISE WARNING
                'Small OBM intersection autofix found % candidates but made no geometry changes for version %.',
                v_candidate_count,
                p_id_rel_geo_verzija;
            EXIT;
        END IF;

        v_fixed_count := v_fixed_count + v_iteration_changed;

        -- Runaway safety guard only. Normal setup can legitimately fix many small intersections.
        IF v_iteration >= 10000 THEN
            RAISE EXCEPTION
                'Small OBM intersection autofix reached iteration guard for version %. Last candidate count %, fixed % rows in this call.',
                p_id_rel_geo_verzija,
                v_candidate_count,
                v_fixed_count;
        END IF;
    END LOOP;

    RETURN v_fixed_count;
END $$;

-- Convenience wrapper for small topology only.
-- Runs small-hole and small-intersection fixes for one version.
-- Does not clip overflows and does not run the full convergence loop.
-- Use autofix_overflows_and_maybe_autofix_small_napake_for_version for setup.
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

-- Main per-version setup/autofix orchestrator.
-- Runs overflow clipping, optional small hole/intersection autofix, then overflow clipping again.
-- Repeats because clipping and small topology fixes can expose each other's remaining problems.
-- This is the function to use when one OBM version should converge before final validation.
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
    v_pre_overflow_clipped_rows integer := 0;
    v_post_overflow_clipped_rows integer := 0;
    v_no_progress boolean := false;
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

        SELECT
            stats.clipped_rows,
            stats.reportable_overflows
        INTO
            v_pre_overflow_clipped_rows,
            v_reportable_overflows
        FROM autofix_overflows_for_version_with_stats(p_id_rel_geo_verzija) stats;

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

        SELECT
            stats.clipped_rows,
            stats.reportable_overflows
        INTO
            v_post_overflow_clipped_rows,
            v_reportable_overflows
        FROM autofix_overflows_for_version_with_stats(p_id_rel_geo_verzija) stats;

        v_total_holes_fixed := v_total_holes_fixed + COALESCE(v_holes_fixed, 0);
        v_total_intersections_fixed := v_total_intersections_fixed + COALESCE(v_intersections_fixed, 0);

        IF obm_small_topology_autofix_enabled() THEN
            SELECT COUNT(*)
            INTO v_remaining_small_holes
            FROM get_obm_hole_candidates(p_id_rel_geo_verzija) candidates
            WHERE preprocessing_is_small_obm_topology_problem(candidates.hole_geom);

            WITH small_intersections AS (
                SELECT ensure_snap_to_grid(dump_result.geom) AS geom
                FROM md_geo_obm a
                JOIN md_geo_obm b ON a.id_rel_geo_verzija = b.id_rel_geo_verzija
                CROSS JOIN LATERAL ST_Dump(
                    ensure_snap_to_grid(ST_Intersection(a.geom, b.geom))
                ) AS dump_result
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
        v_no_progress := COALESCE(v_pre_overflow_clipped_rows, 0) = 0
            AND COALESCE(v_post_overflow_clipped_rows, 0) = 0
            AND COALESCE(v_holes_fixed, 0) = 0
            AND COALESCE(v_intersections_fixed, 0) = 0;

        RAISE NOTICE
            'OBM topology autofix pass %, version %, pre-clipped %, post-clipped %, fixed holes %, fixed intersections %, remaining reportable overflows %, remaining small holes %, remaining small intersections %.',
            v_pass,
            p_id_rel_geo_verzija,
            v_pre_overflow_clipped_rows,
            v_post_overflow_clipped_rows,
            v_holes_fixed,
            v_intersections_fixed,
            v_reportable_overflows,
            v_remaining_small_holes,
            v_remaining_small_intersections;

        EXIT WHEN v_last_pass_total = 0 OR v_no_progress OR v_pass >= 10;
    END LOOP;

    IF v_last_pass_total > 0 AND v_no_progress THEN
        RAISE WARNING
            'OBM topology autofix stopped for version % because the last pass made no geometry changes. Last pass left % reportable overflows, % small holes, % small intersections.',
            p_id_rel_geo_verzija,
            v_reportable_overflows,
            v_remaining_small_holes,
            v_remaining_small_intersections;
    ELSIF v_last_pass_total > 0 AND v_pass >= 10 THEN
        RAISE WARNING
            'OBM topology autofix reached pass limit for version %. Last pass pre-clipped %, post-clipped %, left % reportable overflows, % small holes, % small intersections; fixed % holes and % intersections.',
            p_id_rel_geo_verzija,
            v_pre_overflow_clipped_rows,
            v_post_overflow_clipped_rows,
            v_reportable_overflows,
            v_remaining_small_holes,
            v_remaining_small_intersections,
            v_holes_fixed,
            v_intersections_fixed;
    END IF;

    RAISE NOTICE
        'Version % took % passes. Last pass pre-clipped %, post-clipped %, left % reportable overflows and fixed % holes and % intersections.',
        p_id_rel_geo_verzija,
        v_pass,
        v_pre_overflow_clipped_rows,
        v_post_overflow_clipped_rows,
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

-- All-version setup entrypoint used by 1_0_setup.sql.
-- Calls the per-version orchestrator for every OBM version.
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

-- Manual/debug helper only.
-- Runs only small topology fixes for all versions.
-- Not equivalent to full setup because it skips overflow clipping and convergence orchestration.
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
