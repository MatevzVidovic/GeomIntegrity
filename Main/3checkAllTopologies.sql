
DROP FUNCTION IF EXISTS validate_holes(uuid);

CREATE OR REPLACE FUNCTION validate_holes(p_id_rel_geo_verzija uuid)
RETURNS TABLE(
    holes_found INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_slo_meja geometry;
    v_union_geom geometry;
    v_holes_geom geometry;
    v_holes_count INTEGER := 0;
BEGIN
    -- Get Slovenia boundary
    SELECT geom INTO v_slo_meja FROM slo_meja LIMIT 1;

    IF v_slo_meja IS NULL THEN
        RAISE EXCEPTION 'Slovenia boundary (slo_meja) not found';
    END IF;


    -- ========================================================================
    -- STEP 1: Calculate union of all geometries for this version
    -- ========================================================================
    SELECT ST_Union(geom) INTO v_union_geom
    FROM md_geo_obm
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija
      AND geom IS NOT NULL;

    -- ========================================================================
    -- STEP 2: Find and record HOLES
    -- ========================================================================
    -- Holes = areas within Slovenia that are not covered by any geometry
    v_holes_geom := ST_Difference(v_slo_meja, v_union_geom);

    -- Clear existing holes for this version
    DELETE FROM md_topoloske_kontrole
    WHERE area_type = 'obm' and id_rel_geo_verzija = p_id_rel_geo_verzija and topology_problem_type = 'hole';

    -- Insert new holes if they exist
    IF v_holes_geom IS NOT NULL AND NOT ST_IsEmpty(v_holes_geom) THEN
        -- Handle multipolygon case - insert each polygon separately
       INSERT INTO md_topoloske_kontrole (created_at, id, created_by, area_type, id_rel_geo_verzija, topology_problem_type, geom, perimeter, area, compactness)
        SELECT
            now()::timestamp,
            uuid_generate_v4(),
            '848956e8-d73e-11f0-9ff0-02420a000f64',
            'obm',
            p_id_rel_geo_verzija,
            'hole',
            geom,
            perimeter,
            area,
            4*pi()*area / NULLIF(perimeter * perimeter, 0)   -- (circle has it 0.08 (1/4*pi) and is most compact. Everything else is less compact.)
        FROM (
            SELECT
                geom,
                ST_Perimeter(geom) as perimeter,
                ST_Area(geom) as area
            FROM (
                SELECT st_reduceprecision((dump_result).geom, 0.01) as geom
                FROM (
                    SELECT ST_Dump(v_holes_geom) AS dump_result
                ) AS dumps
            ) as dumped_geoms
            WHERE ST_GeometryType(geom) in ('ST_Polygon', 'ST_MultiPolygon')
        ) AS calculated
        WHERE area > 0;

    END IF;
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
    v_slo_meja geometry;
    v_union_geom geometry;
    v_overflow_geom geometry;
    v_intermediate_ids uuid[];
    v_overflows_count INTEGER := 0;
    v_step_time timestamp;
BEGIN

    v_step_time := clock_timestamp();


    -- Get Slovenia boundary
    SELECT geom INTO v_slo_meja FROM slo_meja LIMIT 1;

    IF v_slo_meja IS NULL THEN
        RAISE EXCEPTION 'Slovenia boundary (slo_meja) not found';
    END IF;

    DELETE FROM md_topoloske_kontrole
    WHERE area_type = 'obm' and id_rel_geo_verzija = p_id_rel_geo_verzija and topology_problem_type = 'overflow';    -- Mark entries that overflow Slovenia boundary




    -- ========================================================================
    -- STEP 3: Find and mark OVERFLOWS
    -- ========================================================================
    -- Overflow = areas that extend beyond Slovenia boundary

        -- Create temporary table
    DROP TABLE IF EXISTS temp_overflows;
    CREATE TEMP TABLE IF NOT EXISTS temp_overflows (
        id uuid,
        overflow_geom geometry
    ) ON COMMIT DROP;

    INSERT INTO temp_overflows
--     SELECT id, (ST_Dump(st_difference(geom, v_slo_meja))).geom
    SELECT id, st_reduceprecision((ST_Dump(st_difference(geom, v_slo_meja))).geom, 0.01)

--     SELECT id, st_difference(geom, v_slo_meja)
    FROM md_geo_obm
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija
        AND geom IS NOT NULL
        AND NOT st_covers(v_slo_meja, geom);



    RAISE NOTICE 'step 111 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
    v_step_time := clock_timestamp();


--     RAISE NOTICE 'Overflows: %', (SELECT COUNT(*) FROM temp_overflows);
--
--     RAISE NOTICE 'Overflows: %', (
--         SELECT jsonb_pretty(jsonb_agg(row_to_json(t)))
-- --         FROM temp_overflows t
--         FROM (
--             SELECT id, ST_Area(overflow_geom) as area, ST_GeometryType(overflow_geom) as geom_type
--             FROM temp_overflows
--         ) t
--     );

    INSERT INTO md_topoloske_kontrole ( id, created_at, created_by, area_type, id_rel_geo_verzija, topology_problem_type, id1, geom, perimeter, area, compactness)
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '848956e8-d73e-11f0-9ff0-02420a000f64',
        'obm',
        p_id_rel_geo_verzija,
        'overflow',
        id,
        geom,
        perimeter,
        area,
        4*pi()*area / NULLIF(perimeter * perimeter, 0)   -- (circle has it 0.08 (1/4*pi) and is most compact. Everything else is less compact.)
    FROM (
        SELECT
            id,
            overflow_geom as geom,
            ST_Perimeter(overflow_geom) as perimeter,
--                 -1 AS perimeter,
            ST_Area(overflow_geom) as area
        FROM temp_overflows
        WHERE -- NOT ST_Contains(v_slo_meja, overflow_geom) AND
         ST_GeometryType(overflow_geom) in ('ST_Polygon', 'ST_MultiPolygon')
        ) AS calculated
    WHERE area > 0;

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

    DELETE FROM md_topoloske_kontrole
    WHERE area_type = 'obm' and id_rel_geo_verzija = p_id_rel_geo_verzija and topology_problem_type = 'intersection';


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
        st_reduceprecision((ST_Dump(ST_Intersection(a.geom, b.geom))).geom, 0.01) as intersection_geom
--         ST_Intersection(a.geom, b.geom) as intersection_geom
    FROM md_geo_obm a
    JOIN md_geo_obm b ON a.id_rel_geo_verzija = b.id_rel_geo_verzija
    WHERE a.id_rel_geo_verzija = p_id_rel_geo_verzija
      AND a.id < b.id
      AND ST_Intersects(a.geom, b.geom)
      AND NOT ST_Touches(a.geom, b.geom);

    INSERT INTO md_topoloske_kontrole ( id, created_at, created_by, area_type, id_rel_geo_verzija, topology_problem_type, id1, id2, geom, perimeter, area, compactness)
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '848956e8-d73e-11f0-9ff0-02420a000f64',
        'obm',
        p_id_rel_geo_verzija,
        'intersection',
        id_a,
        id_b,
        geom,
        perimeter,
        area,
        4*pi()*area / NULLIF(perimeter * perimeter, 0)   -- (circle has it 0.08 (1/4*pi) and is most compact. Everything else is less compact.)
    FROM (
        SELECT
            id_a,
            id_b,
            intersection_geom as geom,
            ST_Perimeter(intersection_geom) as perimeter,
--                 -1 AS perimeter,
            ST_Area(intersection_geom) as area
        FROM temp_intersections
        WHERE  ST_GeometryType(intersection_geom) in ('ST_Polygon', 'ST_MultiPolygon')
        ) AS calculated
    WHERE area > 0;

    GET DIAGNOSTICS v_intersections_count = ROW_COUNT;

    -- ========================================================================
    -- Return summary statistics
    -- ========================================================================
    RETURN QUERY SELECT
        v_intersections_count;
END;
$$;







DROP FUNCTION IF EXISTS validate_all(uuid);

CREATE OR REPLACE FUNCTION validate_all(p_id_rel_geo_verzija uuid)
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
        RETURN QUERY SELECT 0, 0, 0, 0;
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
        FROM validate_all(v_version);
    END LOOP;

END;
$$;


