
-- ============================================================================
-- 3_0_fn_obm_geom_check_all.sql - OBM Topology Validation Functions
-- ============================================================================

DROP FUNCTION IF EXISTS validate_holes(uuid);

CREATE OR REPLACE FUNCTION validate_holes(p_id_rel_geo_verzija uuid)
RETURNS TABLE(
    holes_found INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_holes_count INTEGER := 0;
BEGIN
    -- Clear existing holes for this version
    DELETE FROM md_topoloske_kontrole_obm
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija AND tip_topoloskega_problema = 'luknja';

    INSERT INTO md_topoloske_kontrole_obm (created_at, id, created_by, id_rel_geo_verzija, tip_topoloskega_problema, geom, obseg, povrsina, kompaktnost)
    SELECT
        now()::timestamp,
        uuid_generate_v4(),
        '00000000-0000-0000-0000-000000000000'::uuid,
        p_id_rel_geo_verzija,
        'luknja',
        candidates.hole_geom,
        candidates.obseg,
        candidates.povrsina,
        candidates.kompaktnost
    FROM get_obm_hole_candidates(p_id_rel_geo_verzija) candidates;

    GET DIAGNOSTICS v_holes_count = ROW_COUNT;

    RETURN QUERY SELECT v_holes_count;
END;
$$;




DROP FUNCTION IF EXISTS validate_overflows(uuid);

CREATE OR REPLACE FUNCTION validate_overflows(p_id_rel_geo_verzija uuid)
RETURNS TABLE(
    overflows_found INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_overflows_count INTEGER := 0;
BEGIN
    DELETE FROM md_topoloske_kontrole_obm
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija AND tip_topoloskega_problema = 'preliv';    -- Mark entries that overflow Slovenia boundary

    INSERT INTO md_topoloske_kontrole_obm ( id, created_at, created_by, id_rel_geo_verzija, tip_topoloskega_problema, id1, geom, obseg, povrsina, kompaktnost)
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '00000000-0000-0000-0000-000000000000'::uuid,
        p_id_rel_geo_verzija,
        'preliv',
        candidates.obm_id,
        candidates.overflow_geom,
        candidates.obseg,
        candidates.povrsina,
        candidates.kompaktnost
    FROM get_obm_overflow_candidates(p_id_rel_geo_verzija) candidates
    WHERE NOT preprocessing_is_small_obm_topology_problem(candidates.overflow_geom);

    GET DIAGNOSTICS v_overflows_count = ROW_COUNT;


    RETURN QUERY SELECT
        v_overflows_count;
END;
$$;




DROP FUNCTION IF EXISTS validate_intersections(uuid);

CREATE OR REPLACE FUNCTION validate_intersections(p_id_rel_geo_verzija uuid)
RETURNS TABLE(
    intersections_found INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_intersections_count INTEGER := 0;
BEGIN


    -- ========================================================================
    -- STEP 4: Find and mark INTERSECTIONS
    -- ========================================================================
    -- Reset all existing intersections

    DELETE FROM md_topoloske_kontrole_obm
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija AND tip_topoloskega_problema = 'prekrivanje';


    -- Find all pairs of intersecting geometries
    -- Use a.id < b.id to avoid checking each pair twice

    -- Create temporary table
    DROP TABLE IF EXISTS temp_intersections;
    CREATE TEMP TABLE IF NOT EXISTS temp_intersections (
        id_a uuid,
        id_b uuid,
        intersection_geom geometry
    ) ON COMMIT DROP;

    -- Insert the intersecting pairs with their intersection geometry
    INSERT INTO temp_intersections (id_a, id_b, intersection_geom)
    SELECT
        a.id,
        b.id,
        ensure_snap_to_grid((ST_Dump(ST_Intersection(a.geom, b.geom))).geom) as intersection_geom
--         ST_Intersection(a.geom, b.geom) as intersection_geom
    FROM md_geo_obm a
    JOIN md_geo_obm b ON a.id_rel_geo_verzija = b.id_rel_geo_verzija
    WHERE a.id_rel_geo_verzija = p_id_rel_geo_verzija
      AND a.id < b.id
      AND ST_Intersects(a.geom, b.geom)
      AND NOT ST_Touches(a.geom, b.geom);

    INSERT INTO md_topoloske_kontrole_obm ( id, created_at, created_by, id_rel_geo_verzija, tip_topoloskega_problema, id1, id2, geom, obseg, povrsina, kompaktnost)
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '00000000-0000-0000-0000-000000000000'::uuid,
        p_id_rel_geo_verzija,
        'prekrivanje',
        id_a,
        id_b,
        geom,
        obseg,
        povrsina,
        4*pi()*povrsina / NULLIF(obseg * obseg, 0)   -- (circle has it 0.08 (1/4*pi) and is most compact. Everything else is less compact.)
    FROM (
        SELECT
            id_a,
            id_b,
            intersection_geom as geom,
            ST_Perimeter(intersection_geom) as obseg,
--                 -1 AS obseg,
            ST_Area(intersection_geom) as povrsina
        FROM temp_intersections
        WHERE  ST_GeometryType(intersection_geom) in ('ST_Polygon', 'ST_MultiPolygon')
        ) AS calculated
    WHERE povrsina > 0;

    GET DIAGNOSTICS v_intersections_count = ROW_COUNT;

    -- ========================================================================
    -- Return summary statistics
    -- ========================================================================
    RETURN QUERY SELECT
        v_intersections_count;
END;
$$;







DROP FUNCTION IF EXISTS validate_all(uuid);
DROP FUNCTION IF EXISTS validate_all_single_geo_version(uuid);
DROP FUNCTION IF EXISTS validate_all_topologies_single_geo_version(uuid);

CREATE OR REPLACE FUNCTION validate_all_topologies_single_geo_version(p_id_rel_geo_verzija uuid)
RETURNS TABLE(
    chosen_id_rel_geo_verzija uuid,
    holes_found INTEGER,
    overflows_found INTEGER,
    intersections_found INTEGER,
    total_entries INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_count INTEGER := 0;
BEGIN
    -- Get count of entries for this version
    SELECT COUNT(*)
    INTO v_total_count
    FROM md_geo_obm
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija;

    IF v_total_count = 0 THEN
        RAISE NOTICE 'No entries found for version %', p_id_rel_geo_verzija;

        RETURN QUERY SELECT p_id_rel_geo_verzija, 0, 0, 0, 0;
        RETURN;
    END IF;

    holes_found := validate_holes(p_id_rel_geo_verzija);
    overflows_found := validate_overflows(p_id_rel_geo_verzija);
    intersections_found := validate_intersections(p_id_rel_geo_verzija);

    RETURN QUERY SELECT
                     p_id_rel_geo_verzija,
                     holes_found,
                     overflows_found,
                     intersections_found,
                     v_total_count;
END;
$$;

DROP FUNCTION IF EXISTS validate_all_topologies();

CREATE OR REPLACE FUNCTION validate_all_topologies()
RETURNS TABLE(
    chosen_id_rel_geo_verzija uuid,
    holes_found INTEGER,
    overflows_found INTEGER,
    intersections_found INTEGER,
    total_entries INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_version uuid;
BEGIN
    -- Process each version
    FOR v_version IN
        SELECT DISTINCT md_geo_obm.id_rel_geo_verzija
        FROM md_geo_obm
        ORDER BY md_geo_obm.id_rel_geo_verzija
    LOOP
        RETURN QUERY
        SELECT *
        FROM validate_all_topologies_single_geo_version(v_version);
    END LOOP;

END;
$$;
