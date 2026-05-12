-- ============================================================================
-- 2_0_autofix_small_violations.sql - Small OBM Topology Autofix Helpers
-- ============================================================================
-- Small violations are geometry slivers we fix immediately instead of writing
-- into md_topoloske_kontrole_obm.
--
-- Rule:
--   ST_Area(geom) < 100 AND compactness < 0.01
--
-- These helpers are used by the OBM incremental trigger. They are intentionally
-- not implemented as triggers on md_topoloske_kontrole_obm, because that would
-- update md_geo_obm while the md_geo_obm trigger is already running.
-- ============================================================================

DROP FUNCTION IF EXISTS autofix_small_obm_topology_for_version(uuid);
DROP FUNCTION IF EXISTS autofix_small_intersections_for_version(uuid);
DROP FUNCTION IF EXISTS autofix_small_holes_for_version(uuid);
DROP FUNCTION IF EXISTS find_best_obm_neighbor_for_hole(uuid, geometry, uuid);
DROP FUNCTION IF EXISTS is_small_obm_topology_problem(geometry);
DROP FUNCTION IF EXISTS obm_topology_compactness(geometry);
DROP FUNCTION IF EXISTS obm_small_topology_autofix_enabled();

CREATE OR REPLACE FUNCTION obm_small_topology_autofix_enabled()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT false
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
    SELECT p_geom IS NOT NULL
       AND NOT ST_IsEmpty(p_geom)
       AND ST_Area(p_geom) < 100
       AND obm_topology_compactness(p_geom) < 0.01;
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
           OR NOT is_small_obm_topology_problem(v_hole_geom) THEN
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
      AND is_small_obm_topology_problem(intersection_geom);

    FOR v_target IN
        SELECT
            id_b,
            ST_ReducePrecision(ST_Union(intersection_geom), 0.01) AS geom_to_remove
        FROM temp_autofix_small_intersections
        WHERE ST_GeometryType(intersection_geom) IN ('ST_Polygon', 'ST_MultiPolygon')
          AND ST_Area(intersection_geom) > 0
          AND is_small_obm_topology_problem(intersection_geom)
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
