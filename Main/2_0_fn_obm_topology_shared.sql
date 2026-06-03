-- ============================================================================
-- 2_0_fn_obm_topology_shared.sql - Shared OBM Topology Helpers
-- ============================================================================
-- Shared read-only helpers used by OBM validation, autofix, and triggers.
-- ============================================================================

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

CREATE OR REPLACE FUNCTION get_obm_hole_candidates(p_id_rel_geo_verzija uuid)
RETURNS TABLE(
    hole_geom geometry,
    obseg double precision,
    povrsina double precision,
    kompaktnost double precision
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_slo_meja geometry;
    v_union_geom geometry;
    v_holes_geom geometry;
BEGIN
    SELECT geom INTO v_slo_meja FROM slo_meja LIMIT 1;

    IF v_slo_meja IS NULL THEN
        RAISE EXCEPTION 'Slovenia boundary (slo_meja) not found';
    END IF;

    SELECT ensure_snap_to_grid(ST_Union(ensure_snap_to_grid(obm.geom)))
    INTO v_union_geom
    FROM md_geo_obm obm
    WHERE obm.id_rel_geo_verzija = p_id_rel_geo_verzija
      AND obm.geom IS NOT NULL;

    IF v_union_geom IS NULL OR ST_IsEmpty(v_union_geom) THEN
        RETURN;
    END IF;

    v_slo_meja := ensure_snap_to_grid(v_slo_meja);
    v_holes_geom := ensure_snap_to_grid(ST_Difference(v_slo_meja, v_union_geom));

    IF v_holes_geom IS NULL OR ST_IsEmpty(v_holes_geom) THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        hole.geom,
        ST_Perimeter(hole.geom) AS obseg,
        ST_Area(hole.geom) AS povrsina,
        obm_topology_compactness(hole.geom) AS kompaktnost
    FROM (
        SELECT ensure_snap_to_grid((dump_result).geom) AS geom
        FROM (
            SELECT ST_Dump(v_holes_geom) AS dump_result
        ) dumps
    ) hole
    WHERE ST_GeometryType(hole.geom) IN ('ST_Polygon', 'ST_MultiPolygon')
      AND ST_Area(hole.geom) > 0;
END $$;

CREATE OR REPLACE FUNCTION get_obm_overflow_candidates(p_id_rel_geo_verzija uuid)
RETURNS TABLE(
    obm_id uuid,
    overflow_geom geometry,
    obseg double precision,
    povrsina double precision,
    kompaktnost double precision
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_slo_meja geometry;
BEGIN
    SELECT geom INTO v_slo_meja FROM slo_meja LIMIT 1;

    IF v_slo_meja IS NULL THEN
        RAISE EXCEPTION 'Slovenia boundary (slo_meja) not found';
    END IF;

    v_slo_meja := ensure_snap_to_grid(v_slo_meja);

    RETURN QUERY
    SELECT
        overflow.obm_id,
        overflow.geom,
        ST_Perimeter(overflow.geom) AS obseg,
        ST_Area(overflow.geom) AS povrsina,
        obm_topology_compactness(overflow.geom) AS kompaktnost
    FROM (
        SELECT
            obm.id AS obm_id,
            ensure_snap_to_grid(dump_result.geom) AS geom
        FROM md_geo_obm obm
        CROSS JOIN LATERAL ST_Dump(
            ensure_snap_to_grid(ST_Difference(ensure_snap_to_grid(obm.geom), v_slo_meja))
        ) AS dump_result
        WHERE obm.id_rel_geo_verzija = p_id_rel_geo_verzija
          AND obm.geom IS NOT NULL
          AND NOT ST_Covers(v_slo_meja, obm.geom)
    ) overflow
    WHERE ST_GeometryType(overflow.geom) IN ('ST_Polygon', 'ST_MultiPolygon')
      AND ST_Area(overflow.geom) > 0;
END $$;
