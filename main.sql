

















































SELECT
    ST_GeometryType(slo.geom) as geom_type,
    ST_NumGeometries(slo.geom) as num_parts,
    ST_NumInteriorRings(slo.geom) as num_holes
FROM (SELECT
    uuid_generate_v4() AS id,
    ST_Union(
        ST_MakePolygon(
            ST_ExteriorRing((ST_Dump(ST_Union(kn_nep_rpe_obcine_h.geom))).geom)
        )
    )::geometry(Polygon,3794) AS geom
FROM kn_nep_rpe_obcine_h
WHERE kn_nep_rpe_obcine_h.postopek_id_do IS NULL) as slo;



SELECT
    ST_GeometryType(slo.geom) as geom_type,
    ST_NumGeometries(slo.geom) as num_parts,
    ST_NumInteriorRings(slo.geom) as num_holes
FROM (
    SELECT
        uuid_generate_v4() AS id,
        ST_Union(
            ST_MakePolygon(
                ST_ExteriorRing(geom)
            )
        )::geometry(Polygon,3794) AS geom
    FROM (
        SELECT (ST_Dump(ST_Union(kn_nep_rpe_obcine_h.geom))).geom
        FROM kn_nep_rpe_obcine_h
        WHERE kn_nep_rpe_obcine_h.postopek_id_do IS NULL
    ) AS dumped
) as slo;



SELECT
    ST_GeometryType(slo.geom) as geom_type,
    ST_NumGeometries(slo.geom) as num_parts,
    ST_NumInteriorRings(slo.geom) as num_holes
FROM (

SELECT
    uuid_generate_v4() AS id,
    ST_MakePolygon(
        ST_ExteriorRing(ST_Union(kn_nep_rpe_obcine_h.geom))
    )::geometry(Polygon,3794) AS geom
FROM kn_nep_rpe_obcine_h
WHERE kn_nep_rpe_obcine_h.postopek_id_do IS NULL

) as slo;







SELECT
    ST_GeometryType(slo.geom) as geom_type,
    ST_NumGeometries(slo.geom) as num_parts,
    ST_NumInteriorRings(slo.geom) as num_holes
FROM (

SELECT
    uuid_generate_v4() AS id,
    ST_MakePolygon(ST_ExteriorRing((dump).geom))::geometry(Polygon,3794) AS geom
FROM (
    SELECT ST_Dump(st_union(kn_nep_rpe_obcine_h.geom)) AS dump
    FROM kn_nep_rpe_obcine_h
    WHERE kn_nep_rpe_obcine_h.postopek_id_do IS NULL
) AS dumped

)    as slo;




SELECT
    uuid_generate_v4() AS id,
    ST_MakePolygon(ST_ExteriorRing((dump).geom))::geometry(Polygon,3794) AS geom
FROM (
    SELECT ST_Dump(st_union(kn_nep_rpe_obcine_h.geom)) AS dump
    FROM kn_nep_rpe_obcine_h
    WHERE kn_nep_rpe_obcine_h.postopek_id_do IS NULL
) AS dumped;

















































SELECT * FROM validate_overflows('20a6ad30-8457-41c9-8fbd-5423c15dae9b'::uuid);

SELECT * FROM validate_overflows('2647f13d-faea-4f37-9309-3ab8639457f1'::uuid);


SELECT * FROM validate_overflows('99d0e803-9ff2-40e3-822b-995289ee60d6'::uuid);

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


    -- ========================================================================
    -- STEP 3: Find and mark OVERFLOWS
    -- ========================================================================
    -- Overflow = areas that extend beyond Slovenia boundary

    SELECT ST_Union(geom) INTO v_union_geom
    FROM md_geo_obm
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija
      AND geom IS NOT NULL;

    RAISE NOTICE 'step 111 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
    v_step_time := clock_timestamp();


    v_overflow_geom := ST_Difference(v_union_geom, v_slo_meja);

    RAISE NOTICE 'step 222 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
    v_step_time := clock_timestamp();

    -- Reset all overflow flags for this version

    DELETE FROM md_topoloske_kontrole
    WHERE area_type = 'obm' and id_rel_geo_verzija = p_id_rel_geo_verzija and topology_problem_type = 'overflow';    -- Mark entries that overflow Slovenia boundary

    RAISE NOTICE 'notice';

    IF v_overflow_geom IS NOT NULL AND NOT ST_IsEmpty(v_overflow_geom) THEN

        v_intermediate_ids := ARRAY(
            SELECT id
            FROM md_geo_obm
            WHERE id_rel_geo_verzija = p_id_rel_geo_verzija
              AND ST_Intersects(geom, v_overflow_geom) AND NOT st_touches(geom, v_overflow_geom)
--             AND ST_Area(ST_Intersection(geom, v_overflow_geom)) > 1000;
        );


        RAISE NOTICE 'step 333 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
        v_step_time := clock_timestamp();

        RAISE NOTICE 'intermediate IDs: %', v_intermediate_ids;

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
                (single_overflow).geom as geom,
                ST_Perimeter((single_overflow).geom) as perimeter,
--                 -1 AS perimeter,
                ST_Area((single_overflow).geom) as area
            FROM (
                SELECT id, ST_Dump(overflow) as single_overflow
                FROM (
                    SELECT id, ST_Intersection(geom, v_overflow_geom) as overflow
                    FROM md_geo_obm
                    WHERE id = ANY(v_intermediate_ids)
                ) AS dump_result
            ) AS dumps
            WHERE st_intersects(((single_overflow).geom), v_overflow_geom) and not st_touches(((single_overflow).geom), v_overflow_geom)
              AND ST_GeometryType((single_overflow).geom) in ('ST_Polygon', 'ST_MultiPolygon')  -- and ST_Area((single_overflow).geom) > 0
        ) AS calculated;

    GET DIAGNOSTICS v_overflows_count = ROW_COUNT;

    END IF;

    RETURN QUERY SELECT
        v_overflows_count;
END;
$$;
























Maybe?

-- Create spatial index
CREATE INDEX idx_slovenia_boundary_geom
ON slovenia_boundary
USING GIST(geom);






ALTER TABLE md_geo_obm
ADD COLUMN topology_problem text NULL;


-- Main validation function
CREATE OR REPLACE FUNCTION public.validate_topology()
RETURNS TRIGGER AS $$
-- RETURNS void as $--$
DECLARE
    slovenia_geom GEOMETRY;
        OLD RECORD;
    NEW RECORD;
    PG_OP sth;
    HOLE geometry;
--
--     areas_union GEOMETRY;
--     difference_geom GEOMETRY;
--     hole_geom GEOMETRY;
--     intersecting_record RECORD;
--     hole_record RECORD;
--     start_time TIMESTAMP;
BEGIN
    start_time := clock_timestamp();
    -- Get Slovenia boundary
    RAISE NOTICE 'Starting validation.';
    SELECT geom INTO slovenia_geom FROM slovenia_boundary LIMIT 1;
    RAISE NOTICE 'Joining Slovenia boundary took: %', (clock_timestamp() - start_time);

    IF slovenia_geom IS NULL THEN
        RAISE EXCEPTION 'Slovenia boundary not found. Create the materialized view first.';
    END IF;

    -- Reset all problematic flags before checking
    UPDATE md_geo_obm SET topology_problem = NULL;
    RAISE NOTICE 'topology_problem NULLified.';




-- - If there is an insert, does this new shape intersect any existing shape, or fall out of slovenia? (Also, problematically: Does it cover any hole and is it the neighbour to any hole?)
-- - If there is a delete, is there a hole there now? (Remove all existing areas from the lost area, then see what remains).
-- - If there is an update, does the new shape intersect any existing shape, or fall out of slovenia? The shape that is
-- now void: diff(old-new) has to be checked: take that shape and do: hole = hole - currArea. For all areas. Now we have
-- this hole multipolygon that overlaps with nothing.
-- We then see what that hole touches. (or maybe we add a small buffer and see what it intersects).
--

    IF PG_OP = INSERT or PG_OP = UPDATE


    -- 1. CHECK FOR INTERSECTIONS
    -- Find all pairs of intersecting polygons
    FOR intersecting_record IN
        SELECT DISTINCT
            a1.id as id1,
            a2.id as id2
        FROM md_geo_obm a1
        JOIN md_geo_obm a2 ON a1.id < a2.id
        WHERE ST_Intersects(a1.geom, a2.geom)
        AND NOT ST_Touches(a1.geom, a2.geom) -- Touching is OK, overlapping is not
        AND ST_Area(ST_Intersection(a1.geom, a2.geom)) > 0.0000001 -- Real overlap
    LOOP
        -- Flag both intersecting areas as problematic
        UPDATE md_geo_obm
        SET
            topology_problem = 'intersection'
        WHERE id IN (intersecting_record.id1, intersecting_record.id2);

        RAISE NOTICE 'Intersection found between area  (id: %) and area  (id: %)',
             intersecting_record.id1,
            intersecting_record.id2;
    END LOOP;

    -- 2. CHECK FOR HOLES (gaps in coverage)
    -- Create union of all analytical areas
    SELECT ST_Union(geom) INTO areas_union
    FROM md_geo_obm;

    -- Find the difference between Slovenia and the union of areas
    difference_geom := ST_Difference(slovenia_geom, areas_union);

    -- If there's a difference, we have holes
    IF difference_geom IS NOT NULL AND NOT ST_IsEmpty(difference_geom) THEN
        -- Process each hole (could be multiple disconnected holes)
        FOR hole_record IN
            SELECT (ST_Dump(difference_geom)).geom as hole_geom
        LOOP
            -- Find all areas that touch/neighbor this hole
            UPDATE md_geo_obm
            SET topology_problem = CASE
                    WHEN topology_problem = 'intersection' THEN 'intersection,hole_neighbor'
                    ELSE 'hole_neighbor'
                END
            WHERE ST_Intersects(geom, ST_Buffer(hole_record.hole_geom, 0.0001))
            AND id IN (
                SELECT id FROM md_geo_obm
                WHERE ST_Distance(geom, hole_record.hole_geom) < 0.0001
            );

            RAISE NOTICE 'Hole detected at location: %', ST_AsText(ST_Centroid(hole_record.hole_geom));
        END LOOP;
    END IF;

    -- 3. CHECK IF AREAS EXTEND BEYOND SLOVENIA
    FOR intersecting_record IN
        SELECT id, ime_obmocja
        FROM md_geo_obm
        WHERE NOT ST_Within(geom, slovenia_geom)
    LOOP
        UPDATE md_geo_obm
        SET
            topology_problem = CASE
                WHEN topology_problem IS NOT NULL THEN topology_problem || ',outside_slovenia'
                ELSE 'outside_slovenia'
            END
        WHERE id = intersecting_record.id;

        RAISE NOTICE 'Area % (id: %) extends beyond Slovenia boundary',
            intersecting_record.ime_obmocja, intersecting_record.id;
    END LOOP;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;




























DROP FUNCTION IF EXISTS public.validate_topology();

DROP TRIGGER IF EXISTS trg_validate_areas ON md_geo_obm;







SELECT uuid_generate_v4() id, ST_Union(geom)::geometry(Polygon, 3794)  geom
FROM kn_nep_rpe_obcine_h
WHERE postopek_id_do is NULL;






-- Method 1: Check the column definition
SELECT Find_SRID('public', 'md_geo_obm', 'geom');





select id_rel_geo_verzija, count(*) from md_geo_obm
                group by id_rel_geo_verzija;





SELECT ST_Union(geom)::geometry(Polygon, 3794)  geom
FROM md_geo_obm

where id_rel_geo_verzija = '05c23679-1f97-403e-9344-ba65b20a9d9b';
where id_rel_geo_verzija = '99d0e803-9ff2-40e3-822b-995289ee60d6';



WHERE postopek_id_do is NULL;



SELECT uuid_generate_v4() id, ST_Union(geom)::geometry(Polygon, 3794)  geom
FROM kn_nep_rpe_obcine_h
WHERE postopek_id_do is NULL;



-- Table structure for analytical areas
-- Assumes you have a table like this:
-- CREATE TABLE analytical_areas (
--     id SERIAL PRIMARY KEY,
--     name VARCHAR(255),
--     geom GEOMETRY(POLYGON, 4326), -- or your SRID
--     is_problematic BOOLEAN DEFAULT FALSE,
--     problem_type TEXT, -- 'intersection', 'hole_neighbor', or NULL
--     last_checked TIMESTAMP
-- );

-- -- Table for Slovenia municipalities union (create once)
-- CREATE TABLE IF NOT EXISTS slovenia_boundary (
--     id SERIAL PRIMARY KEY,
--     geom GEOMETRY(MULTIPOLYGON, 3794),
--     created_at TIMESTAMP DEFAULT NOW()
-- );
--
-- -- Function to initialize/update Slovenia boundary from municipalities
-- CREATE OR REPLACE FUNCTION update_slovenia_boundary()
-- RETURNS void AS $$
-- BEGIN
--     DELETE FROM slovenia_boundary;
--
--     INSERT INTO slovenia_boundary (geom)
--     SELECT ST_Union(geom)
--     FROM kn_nep_rpe_obcine_h
--     WHERE postopek_id_do is NULL;
--
-- END;
-- $$ LANGUAGE plpgsql;






CREATE OR REPLACE VIEW slovenia_boundary AS
SELECT
--     1 as id,
    ST_Union(geom) as geom,
    NOW() as created_at
FROM kn_nep_rpe_obcine_h
WHERE postopek_id_do IS NULL;

SELECT * from slovenia_boundary;

3 sec. So maybe no need to move to materialized view + trigger?



ALTER TABLE md_geo_obm
DROP COLUMN topology_problem;



ALTER TABLE md_geo_obm
ADD COLUMN topology_problem text NULL;


-- Main validation function
CREATE OR REPLACE FUNCTION public.validate_topology()
RETURNS TRIGGER AS $$
-- RETURNS void as $--$
DECLARE
    slovenia_geom GEOMETRY;
    areas_union GEOMETRY;
    difference_geom GEOMETRY;
    hole_geom GEOMETRY;
    intersecting_record RECORD;
    hole_record RECORD;
    start_time TIMESTAMP;
BEGIN
    start_time := clock_timestamp();
    -- Get Slovenia boundary
    RAISE NOTICE 'Starting validation.';
    SELECT geom INTO slovenia_geom FROM slovenia_boundary LIMIT 1;
    RAISE NOTICE 'Joining Slovenia boundary took: %', (clock_timestamp() - start_time);

    IF slovenia_geom IS NULL THEN
        RAISE EXCEPTION 'Slovenia boundary not found. Run update_slovenia_boundary() first.';
    END IF;

    -- Reset all problematic flags before checking
    UPDATE md_geo_obm SET topology_problem = NULL;
    RAISE NOTICE 'topology_problem NULLified.';

    -- 1. CHECK FOR INTERSECTIONS
    -- Find all pairs of intersecting polygons
    FOR intersecting_record IN
        SELECT DISTINCT
            a1.id as id1,
            a2.id as id2
        FROM md_geo_obm a1
        JOIN md_geo_obm a2 ON a1.id < a2.id
        WHERE ST_Intersects(a1.geom, a2.geom)
        AND NOT ST_Touches(a1.geom, a2.geom) -- Touching is OK, overlapping is not
        AND ST_Area(ST_Intersection(a1.geom, a2.geom)) > 0.0000001 -- Real overlap
    LOOP
        -- Flag both intersecting areas as problematic
        UPDATE md_geo_obm
        SET
            topology_problem = 'intersection'
        WHERE id IN (intersecting_record.id1, intersecting_record.id2);

        RAISE NOTICE 'Intersection found between area  (id: %) and area  (id: %)',
             intersecting_record.id1,
            intersecting_record.id2;
    END LOOP;

    -- 2. CHECK FOR HOLES (gaps in coverage)
    -- Create union of all analytical areas
    SELECT ST_Union(geom) INTO areas_union
    FROM md_geo_obm;

    -- Find the difference between Slovenia and the union of areas
    difference_geom := ST_Difference(slovenia_geom, areas_union);

    -- If there's a difference, we have holes
    IF difference_geom IS NOT NULL AND NOT ST_IsEmpty(difference_geom) THEN
        -- Process each hole (could be multiple disconnected holes)
        FOR hole_record IN
            SELECT (ST_Dump(difference_geom)).geom as hole_geom
        LOOP
            -- Find all areas that touch/neighbor this hole
            UPDATE md_geo_obm
            SET topology_problem = CASE
                    WHEN topology_problem = 'intersection' THEN 'intersection,hole_neighbor'
                    ELSE 'hole_neighbor'
                END
            WHERE ST_Intersects(geom, ST_Buffer(hole_record.hole_geom, 0.0001))
            AND id IN (
                SELECT id FROM md_geo_obm
                WHERE ST_Distance(geom, hole_record.hole_geom) < 0.0001
            );

            RAISE NOTICE 'Hole detected at location: %', ST_AsText(ST_Centroid(hole_record.hole_geom));
        END LOOP;
    END IF;

    -- 3. CHECK IF AREAS EXTEND BEYOND SLOVENIA
    FOR intersecting_record IN
        SELECT id, ime_obmocja
        FROM md_geo_obm
        WHERE NOT ST_Within(geom, slovenia_geom)
    LOOP
        UPDATE md_geo_obm
        SET
            topology_problem = CASE
                WHEN topology_problem IS NOT NULL THEN topology_problem || ',outside_slovenia'
                ELSE 'outside_slovenia'
            END
        WHERE id = intersecting_record.id;

        RAISE NOTICE 'Area % (id: %) extends beyond Slovenia boundary',
            intersecting_record.ime_obmocja, intersecting_record.id;
    END LOOP;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;






EXPLAIN
SELECT DISTINCT
    a1.id as id1,
    a2.id as id2
FROM md_geo_obm a1
JOIN md_geo_obm a2 ON a1.id < a2.id
WHERE ST_Intersects(a1.geom, a2.geom)
AND NOT ST_Touches(a1.geom, a2.geom) -- Touching is OK, overlapping is not
AND ST_Area(ST_Intersection(a1.geom, a2.geom)) > 0.0000001; -- Real overlap





SELECT PostGIS_Version();

SELECT PostGIS_Full_Version();



-- Find ALL overlaps and gaps automatically!
SELECT * FROM ST_CoverageInvalidEdges(
    (SELECT array_agg(geom) FROM md_geo_obm)
);


SELECT * FROM ST_CoverageInvalidEdges(
    ARRAY(SELECT geom FROM md_geo_obm)
);


SELECT * FROM ST_CoverageInvalidEdges(
    (SELECT array_agg(geom)::geometry[] FROM md_geo_obm)
);

-- Check what ST_Coverage* functions exist
SELECT
    proname,
    pg_get_function_arguments(oid) as arguments
FROM pg_proc
WHERE proname LIKE 'st_coverage%'
ORDER BY proname;


-- Convert your polygons to a GeometryCollection first
SELECT * FROM ST_CoverageInvalidEdges(
    ST_Collect(j.geom)  -- Collects all geometries into onea
) FROM md_geo_obm as j;

-- Using subquery
SELECT * FROM ST_CoverageInvalidEdges(
    (SELECT ST_Collect(geom) FROM md_geo_obm)
);




-- Find all invalid edges
SELECT ST_CoverageInvalidEdges(geom) OVER () as invalid_edge
FROM md_geo_obm;









CREATE OR REPLACE FUNCTION validate_topology()
RETURNS TRIGGER AS $$
DECLARE
    slovenia_geom GEOMETRY;
    areas_union GEOMETRY;
    difference_geom GEOMETRY;
    intersecting_record NUMERIC;
    start_time TIMESTAMP;
    step_time TIMESTAMP;
BEGIN
    start_time := clock_timestamp();
    RAISE NOTICE '========== VALIDATION STARTED ==========';

    -- Get Slovenia boundary
    SELECT geom INTO slovenia_geom FROM slovenia_boundary LIMIT 1;

    IF slovenia_geom IS NULL THEN
        RAISE EXCEPTION 'Slovenia boundary not found';
    END IF;

    -- Reset all flags
    UPDATE md_geo_obm SET topology_problem = NULL;
    RAISE NOTICE '[Step 1] Reset flags: %ms',
        EXTRACT(milliseconds FROM (clock_timestamp() - start_time));

    -- 1. CHECK FOR OVERLAPS (optimized with ST_Overlaps)
    step_time := clock_timestamp();

    WITH overlapping_pairs AS (
        SELECT DISTINCT
            a1.id as id1,
            a2.id as id2
        FROM md_geo_obm a1
        JOIN md_geo_obm a2 ON a1.id < a2.id
        WHERE ST_Overlaps(a1.geom, a2.geom)  -- Much simpler!
    ),
    all_overlapping_ids AS (
        SELECT id1 as id FROM overlapping_pairs
        UNION
        SELECT id2 as id FROM overlapping_pairs
    )
    UPDATE md_geo_obm
    SET topology_problem = 'intersection'
    WHERE id IN (SELECT id FROM all_overlapping_ids);

    GET DIAGNOSTICS intersecting_record = ROW_COUNT;

    RAISE NOTICE '[Step 2] Overlap check: %ms, flagged % areas',
        EXTRACT(milliseconds FROM (clock_timestamp() - step_time)),
        intersecting_record;

    -- 2. CHECK FOR HOLES (gaps in coverage)
    step_time := clock_timestamp();

    SELECT ST_Union(geom) INTO areas_union FROM md_geo_obm;
    difference_geom := ST_Difference(slovenia_geom, areas_union);

    IF difference_geom IS NOT NULL AND NOT ST_IsEmpty(difference_geom) THEN
        -- Flag all areas neighboring the holes
        UPDATE md_geo_obm
        SET topology_problem = CASE
                WHEN topology_problem = 'intersection' THEN 'intersection,hole_neighbor'
                ELSE 'hole_neighbor'
            END
        WHERE ST_Distance(geom, difference_geom) < 0.0001;

        RAISE NOTICE '[Step 3] Gap check: %ms, gaps detected!',
            EXTRACT(milliseconds FROM (clock_timestamp() - step_time));
    ELSE
        RAISE NOTICE '[Step 3] Gap check: %ms, no gaps',
            EXTRACT(milliseconds FROM (clock_timestamp() - step_time));
    END IF;

    -- 3. CHECK IF AREAS EXTEND BEYOND SLOVENIA
    step_time := clock_timestamp();

    UPDATE md_geo_obm
    SET topology_problem = CASE
            WHEN topology_problem IS NOT NULL THEN topology_problem || ',outside_slovenia'
            ELSE 'outside_slovenia'
        END
    WHERE NOT ST_Within(geom, slovenia_geom);

    GET DIAGNOSTICS intersecting_record = ROW_COUNT;

    RAISE NOTICE '[Step 4] Boundary check: %ms, flagged % areas',
        EXTRACT(milliseconds FROM (clock_timestamp() - step_time)),
        intersecting_record;

    RAISE NOTICE '[TOTAL] Validation completed in: %ms',
        EXTRACT(milliseconds FROM (clock_timestamp() - start_time));
    RAISE NOTICE '========================================';

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;



EXPLAIN
SELECT COUNT(*)
FROM md_geo_obm a1
JOIN md_geo_obm a2 ON a1.id < a2.id;
WHERE ST_Overlaps(a1.geom, a2.geom);  -- Much simpl


SELECT COUNT(*) FROM md_geo_obm;

2822
3980431

-- Get the ID at exactly the 2nd percentile
SELECT id
FROM md_geo_obm
ORDER BY id
LIMIT 1 OFFSET (
    SELECT FLOOR(COUNT(*) * 0.02)::INTEGER
    FROM md_geo_obm
);

04699411-fac7-4fa9-8f6c-ae89ccaa7c63



SELECT COUNT(*)
FROM md_geo_obm a1
JOIN md_geo_obm a2 ON a1.id < a2.id
WHERE a2.id <= '04699411-fac7-4fa9-8f6c-ae89ccaa7c63'   -- 2nd percentile id.
--   and ST_Area(ST_Intersection(a1.geom, a2.geom)) > 0.01; --result: 14    --560ms     Estimated for full: 11.6min
  and ST_Overlaps(a1.geom, a2.geom);  -- 327ms    6,8min




-- Get the ID at exactly the 2nd percentile
SELECT id
FROM md_geo_obm
ORDER BY id
LIMIT 1 OFFSET (
    SELECT FLOOR(COUNT(*) * 0.1)::INTEGER
    FROM md_geo_obm
);

19cc94f4-7cac-44ed-859c-3ec06ff43511



SELECT COUNT(*)
FROM md_geo_obm a1
JOIN md_geo_obm a2 ON a1.id < a2.id
WHERE a2.id <= '19cc94f4-7cac-44ed-859c-3ec06ff43511'
--     and ST_Area(ST_Intersection(a1.geom, a2.geom)) > 0.01; --result: 411    --4315ms     Estimated for full:   3.6min
--         and ST_Area(ST_Intersection(a1.geom, a2.geom)) > 100000000; --result: 10    --roughly the same time
  and ST_Overlaps(a1.geom, a2.geom); -- result 374     -- 1550ms  -- estimated for full: 1,3 min



SELECT COUNT(*)
FROM md_geo_obm a1
JOIN md_geo_obm a2 ON a1.id < a2.id
--     and ST_Area(ST_Intersection(a1.geom, a2.geom)) > 0.01;
--         and ST_Area(ST_Intersection(a1.geom, a2.geom)) > 100000000;
  and ST_Overlaps(a1.geom, a2.geom); -- result 38349     -- 1m 43sec





WITH overlapping_pairs AS (
    SELECT DISTINCT
        a1.id as id1,
        a2.id as id2
    FROM md_geo_obm a1
    JOIN md_geo_obm a2 ON a1.id < a2.id
    WHERE ST_Overlaps(a1.geom, a2.geom)  -- Much simpler!
),
all_overlapping_ids AS (
    SELECT id1 as id FROM overlapping_pairs
    UNION
    SELECT id2 as id FROM overlapping_pairs
)
UPDATE md_geo_obm
SET topology_problem = 'intersection'
WHERE id IN (SELECT id FROM all_overlapping_ids);




-- Trigger that runs after INSERT or UPDATE
CREATE OR REPLACE TRIGGER trg_validate_areas
AFTER INSERT OR DELETE OR UPDATE OF geom ON md_geo_obm
FOR EACH STATEMENT
EXECUTE FUNCTION validate_topology();






select * from public.md_geo_obm where id = 'fff5a2ed-44dc-4569-9b00-288e7cd1bce8';

orig geom:
0106000020D20E000001000000010300000001000000460000008195430B27E11F41BE9F1A2F05FAFF40FCA9F152E1E11F4139B4C87694F6FF408716D9CE95E01F4121B0726839EAFF40B81E856B5DE11F41894160E5B0DEFF4010583934FFE31F41378941607FD6FF4075931804F5E41F41FED478E9D0C9FF407D3F35DEB4E41F419A99999987BFFF40666666E67AE21F415C8FC2F532B1FF40BA490C8241E41F411B2FDD24DCA2FF40F0A7C64BF0E51F4139B4C876D29BFF4000000000CBE71F4196438B6C2990FF405839B448D4EA1F41AAF1D24DD289FF40A8C64BB714F11F41B4C876BE438DFF404260E5D03FF41F4148E17A14F290FF40E7FBA9F173F51F4139B4C876C092FF4060E5D0A244FA1F41CDCCCCCC188DFF4014AE47E1B1FE1F41F6285C8FB680FF40713D0A579BFC1F4179E926310A7EFF40CBA145B6A5FA1F41AAF1D24DA87AFF402506811552FB1F41E5D022DB5174FF405C8FC2F5BCEF1F41022B87165D68FF408716D9CE37E91F4196438B6CB16BFF406ABC749324E81F41F4FDD4781D67FF404A0C022BEDE61F412FDD24063165FF40D34D629015E61F41C1CAA1454068FF40D7A370BD1FE41F412DB29DEF1B70FF40B81E85EB77E21F417D3F355E4676FF401283C0CA27E11F4121B07268C17BFF40D34D62107DE01F41C3F5285C2B7FFF407368916D78E01F41D9CEF753B181FF40B0726891C8E11F411F85EB51B085FF403F355EBA9CE11F41378941603388FF40713D0A570AE21F4114AE47E17489FF40B072689186E21F41B81E85EB7B8AFF408D976E9286E21F417D3F355E328CFF40508D976EF4E11F411904560E0592FF40FED478E970E11F41105839B4D096FF405EBA498C17E11F41BC7493180E98FF4017D9CE7723E01F41D9CEF7538999FF40E926310873DF1F41AE47E17AF29BFF400E2DB21D9EDE1F4146B6F3FD529EFF40F6285C8F90DD1F418716D9CE23A0FF40736891ED3DDD1F41C976BE9F6CA3FF40EE7C3F35FFDC1F412FDD24060FA4FF40B29DEF27BCDA1F4100000000DCA2FF402731082CC7D71F41CFF753E30FA8FF40D578E926B9D71F41894160E558ABFF4008AC1CDAC2D61F4177BE9F1A9BACFF404A0C02ABDAD31F4117D9CEF7DFB5FF40CBA145B6F7D21F418195438BE2B7FF400E2DB21DE5D21F4106819543E5B9FF409A9999998DD31F41EE7C3F3536BBFF4091ED7C3F2FD41F41A01A2FDDEEBDFF403789416037D41F41DD240681FBC0FF409CC42030CDD31F415C8FC2F51CC5FF40E92631085CD31F41D122DBF9F4C7FF40CDCCCCCC06D41F4160E5D02275CAFF404A0C022B41D41F410E2DB29DBDCCFF405EBA498CE5D41F41FA7E6ABC30D2FF40448B6C6783D51F418FC2F5288CDAFF406891EDFCDDD51F419A9999992DE1FF40CBA145368BD51F41A245B6F3FDE9FF400AD7A3F0C8D61F411B2FDD24DEEBFF40355EBAC9E3D61F413333333349EFFF4023DBF9FED7D81F412FDD240611F0FF40448B6C67D9D81F411283C0CA57F2FF4017D9CE7799DD1F419EEFA7C691FAFF403108AC9C42E01F41F0A7C64BEDFAFF401D5A64BBBFE01F41560E2DB217FBFF408195430B27E11F41BE9F1A2F05FAFF40

new geom:
0106000020D20E00000100000001030000000100000046000000A4703D0A27E11F41EC51B81E05FAFF401F85EB51E1E11F41AE47E17A94F6FF40CDCCCCCC95E01F410AD7A37039EAFF400AD7A3705DE11F415C8FC2F5B0DEFF4033333333FFE31F41C3F5285C7FD6FF4000000000F5E41F415C8FC2F5D0C9FF4015AE47E1B4E41F41E17A14AE87BFFF40B91E85EB7AE21F41A4703D0A33B1FF4052B81E8541E41F4190C2F528DCA2FF407B14AE47F0E51F4167666666D29BFF4000000000CBE71F410AD7A3702990FF407B14AE47D4EA1F41D7A3703DD289FF4085EB51B814F11F41E17A14AE438DFF40CDCCCCCC3FF41F4148E17A14F290FF405C8FC2F573F51F41AE47E17AC092FF403E0AD7A344FA1F41CDCCCCCC188DFF4052B81E8598FA1F4148E17A145281FF40C3F5285C9BFC1F41D7A3703D0A7EFF4085EB51B8A5FA1F411F85EB51A87AFF4048E17A1452FB1F41B91E85EB5174FF405C8FC2F5BCEF1F41EC51B81E5D68FF40CDCCCCCC37E91F410AD7A370B16BFF40F6285C8F24E81F410AD7A3701D67FF4090C2F528EDE61F415C8FC2F53065FF40F6285C8F15E61F411F85EB514068FF40295C8FC21FE41F41000000001C70FF40B91E85EB77E21F41676666664676FF40CDCCCCCC27E11F410AD7A370C17BFF4048E17A147DE01F41C3F5285C2B7FFF400AD7A37078E01F417B14AE47B181FF40F6285C8FC8E11F411F85EB51B085FF4085EB51B89CE11F41C3F5285C3388FF40C3F5285C0AE21F415C8FC2F57489FF40F6285C8F86E21F41000000007C8AFF40F6285C8F86E21F4167666666328CFF400AD7A370F4E11F41EC51B81E0592FF40B91E85EB70E11F413E0AD7A3D096FF40F6285C8F17E11F4148E17A140E98FF40AE47E17A23E01F417B14AE478999FF40A4703D0A73DF1F41F6285C8FF29BFF40EC51B81E9EDE1F41A4703D0A539EFF40F6285C8F90DD1F41713D0AD723A0FF40B91E85EB3DDD1F413E0AD7A36CA3FF4033333333FFDC1F41A4703D0A0FA4FF4090C2F528BCDA1F4100000000DCA2FF4090C2F528C7D71F41713D0AD70FA8FF4090C2F528B9D71F415C8FC2F558ABFF40713D0AD7C2D61F41A4703D0A9BACFF40E17A14AEDAD31F4100000000E0B5FF4085EB51B8F7D21F41F6285C8FE2B7FF40EC51B81EE5D21F417B14AE47E5B9FF409A9999998DD31F41D7A3703D36BBFF40D7A3703D2FD41F4115AE47E1EEBDFF40C3F5285C37D41F4152B81E85FBC0FF4033333333CDD31F415C8FC2F51CC5FF40A4703D0A5CD31F415C8FC2F5F4C7FF40CDCCCCCC06D41F41EC51B81E75CAFF4090C2F52841D41F419A999999BDCCFF40F6285C8FE5D41F41CDCCCCCC30D2FF406766666683D51F4190C2F5288CDAFF4000000000DED51F419A9999992DE1FF40333333338BD51F41B91E85EBFDE9FF405C8FC2F5C8D61F4148E17A14DEEBFF40CDCCCCCCE3D61F417B14AE4749EFFF4000000000D8D81F415C8FC2F510F0FF4067666666D9D81F41713D0AD757F2FF40AE47E17A99DD1F41295C8FC291FAFF409A99999942E01F417B14AE47EDFAFF4085EB51B8BFE01F41E17A14AE17FBFF40A4703D0A27E11F41EC51B81E05FAFF40





update "md_geo_obm" set "geom" = '0106000020D20E00000100000001030000000100000046000000A4703D0A27E11F41EC51B81E05FAFF401F85EB51E1E11F41AE47E17A94F6FF40CDCCCCCC95E01F410AD7A37039EAFF400AD7A3705DE11F415C8FC2F5B0DEFF4033333333FFE31F41C3F5285C7FD6FF4000000000F5E41F415C8FC2F5D0C9FF4015AE47E1B4E41F41E17A14AE87BFFF40B91E85EB7AE21F41A4703D0A33B1FF4052B81E8541E41F4190C2F528DCA2FF407B14AE47F0E51F4167666666D29BFF4000000000CBE71F410AD7A3702990FF407B14AE47D4EA1F41D7A3703DD289FF4085EB51B814F11F41E17A14AE438DFF40CDCCCCCC3FF41F4148E17A14F290FF405C8FC2F573F51F41AE47E17AC092FF403E0AD7A344FA1F41CDCCCCCC188DFF4052B81E8598FA1F4148E17A145281FF40C3F5285C9BFC1F41D7A3703D0A7EFF4085EB51B8A5FA1F411F85EB51A87AFF4048E17A1452FB1F41B91E85EB5174FF405C8FC2F5BCEF1F41EC51B81E5D68FF40CDCCCCCC37E91F410AD7A370B16BFF40F6285C8F24E81F410AD7A3701D67FF4090C2F528EDE61F415C8FC2F53065FF40F6285C8F15E61F411F85EB514068FF40295C8FC21FE41F41000000001C70FF40B91E85EB77E21F41676666664676FF40CDCCCCCC27E11F410AD7A370C17BFF4048E17A147DE01F41C3F5285C2B7FFF400AD7A37078E01F417B14AE47B181FF40F6285C8FC8E11F411F85EB51B085FF4085EB51B89CE11F41C3F5285C3388FF40C3F5285C0AE21F415C8FC2F57489FF40F6285C8F86E21F41000000007C8AFF40F6285C8F86E21F4167666666328CFF400AD7A370F4E11F41EC51B81E0592FF40B91E85EB70E11F413E0AD7A3D096FF40F6285C8F17E11F4148E17A140E98FF40AE47E17A23E01F417B14AE478999FF40A4703D0A73DF1F41F6285C8FF29BFF40EC51B81E9EDE1F41A4703D0A539EFF40F6285C8F90DD1F41713D0AD723A0FF40B91E85EB3DDD1F413E0AD7A36CA3FF4033333333FFDC1F41A4703D0A0FA4FF4090C2F528BCDA1F4100000000DCA2FF4090C2F528C7D71F41713D0AD70FA8FF4090C2F528B9D71F415C8FC2F558ABFF40713D0AD7C2D61F41A4703D0A9BACFF40E17A14AEDAD31F4100000000E0B5FF4085EB51B8F7D21F41F6285C8FE2B7FF40EC51B81EE5D21F417B14AE47E5B9FF409A9999998DD31F41D7A3703D36BBFF40D7A3703D2FD41F4115AE47E1EEBDFF40C3F5285C37D41F4152B81E85FBC0FF4033333333CDD31F415C8FC2F51CC5FF40A4703D0A5CD31F415C8FC2F5F4C7FF40CDCCCCCC06D41F41EC51B81E75CAFF4090C2F52841D41F419A999999BDCCFF40F6285C8FE5D41F41CDCCCCCC30D2FF406766666683D51F4190C2F5288CDAFF4000000000DED51F419A9999992DE1FF40333333338BD51F41B91E85EBFDE9FF405C8FC2F5C8D61F4148E17A14DEEBFF40CDCCCCCCE3D61F417B14AE4749EFFF4000000000D8D81F415C8FC2F510F0FF4067666666D9D81F41713D0AD757F2FF40AE47E17A99DD1F41295C8FC291FAFF409A99999942E01F417B14AE47EDFAFF4085EB51B8BFE01F41E17A14AE17FBFF40A4703D0A27E11F41EC51B81E05FAFF40',
"updated_at" = '2026-01-06T09:02:30+00:00', "updated_by" = '848956e8-d73e-11f0-9ff0-02420a000f64' where "id" = 'fff5a2ed-44dc-4569-9b00-288e7cd1bce8';











SELECT
COUNT(*) FILTER (WHERE topology_problem is not NULL) as problematic_count,
COUNT(*) FILTER (WHERE topology_problem LIKE '%intersection%') as intersection_count,
COUNT(*) FILTER (WHERE topology_problem LIKE '%hole_neighbor%') as hole_neighbor_count,
COUNT(*) FILTER (WHERE topology_problem LIKE '%outside_slovenia%') as outside_slovenia_count
FROM md_geo_obm;



-- Helper function to manually run validation
CREATE OR REPLACE FUNCTION run_area_validation()
RETURNS TABLE(
    problematic_count BIGINT,
    intersection_count BIGINT,
    hole_neighbor_count BIGINT,
    outside_slovenia_count BIGINT
) AS $$
BEGIN
    PERFORM validate_topology();

    RETURN QUERY
    SELECT
        COUNT(*) FILTER (WHERE topology_problem is not NULL) as problematic_count,
        COUNT(*) FILTER (WHERE topology_problem LIKE '%intersection%') as intersection_count,
        COUNT(*) FILTER (WHERE topology_problem LIKE '%hole_neighbor%') as hole_neighbor_count,
        COUNT(*) FILTER (WHERE topology_problem LIKE '%outside_slovenia%') as outside_slovenia_count
    FROM md_geo_obm;
END;
$$ LANGUAGE plpgsql;






-- Query to view all problematic areas
CREATE OR REPLACE VIEW v_problematic_areas AS
SELECT
    id,
    name,
    is_problematic,
    problem_type,
    last_checked,
    ST_AsText(ST_Centroid(geom)) as centroid_location
FROM analytical_areas
WHERE is_problematic = TRUE
ORDER BY problem_type, id;

-- Usage examples:
--
-- 1. Initialize Slovenia boundary (run once, or when municipalities change):
-- SELECT update_slovenia_boundary();
--
-- 2. Manually run validation:
-- SELECT * FROM run_area_validation();
--
-- 3. View problematic areas:
-- SELECT * FROM v_problematic_areas;
--
-- 4. Get specific intersection details:
-- SELECT
--     a1.id as area1_id, a1.name as area1_name,
--     a2.id as area2_id, a2.name as area2_name,
--     ST_Area(ST_Intersection(a1.geom, a2.geom)) as overlap_area
-- FROM analytical_areas a1
-- JOIN analytical_areas a2 ON a1.id < a2.id
-- WHERE a1.is_problematic AND a1.problem_type LIKE '%intersection%'
-- AND ST_Intersects(a1.geom, a2.geom)
-- AND NOT ST_Touches(a1.geom, a2.geom);