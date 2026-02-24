


DROP FUNCTION validate_topology_incremental();

CREATE OR REPLACE FUNCTION validate_topology_incremental()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_slo_meja geometry;
    v_hole_geom geometry;
    v_possible_new_geom geometry;
    v_insertion_geom geometry;
    v_insertion_hole_union_geom geometry;
    v_id_rel_geo_verzija UUID;
BEGIN
    -- Explanation of protocol:
    -- On delete:
    -- OLD.geom is now a potential hole. ST_ReducePrecision.
    -- OLD.geom might be part of some intersections. If so, remove them.
    -- Remove from it the union of all obm that intersect it.
    -- If it isn't covered by the boundary, then remove the overflow from the hole.
    -- Now go see if any existing hole intersects it, and join them together if so.
    --
    -- On insert:
    -- NEW.geom is a potential new area. ST_ReducePrecision.
    -- if not covered by border, remove the overflow.
    -- if intersects with anyone, create a new intersection

    -- With holes, we take all holes that intersect our insertion geom, we union them into a var,
    -- we delete them from md_topoloske_kontrole, we remove the inserting geom from the union
    -- we then ST_Dump the union and insert new holes.
    -- This is necessary to handle cases where holes get split into 2 by the insertion.

    -- Get Slovenia boundary
    SELECT geom INTO v_slo_meja FROM slo_meja LIMIT 1;

    IF v_slo_meja IS NULL THEN
        RAISE EXCEPTION 'Slovenia boundary (slo_meja) not found';
    END IF;

    -- ========================================================================
    -- PHASE 1: HANDLE REMOVAL (DELETE or UPDATE)
    -- ========================================================================
    IF (TG_OP = 'DELETE' OR TG_OP = 'UPDATE') THEN
        v_id_rel_geo_verzija := OLD.id_rel_geo_verzija;

        -- OLD.geom might be part of some intersections. If so, remove them.
        DELETE FROM md_topoloske_kontrole
        WHERE topology_problem_type = 'intersection'
          and id_rel_geo_verzija = v_id_rel_geo_verzija
            and area_type = 'obm'
            and (OLD.id = id1 or OLD.id = id2);

        -- Start with the removed geometry as potential hole
        v_hole_geom := st_reduceprecision(OLD.geom, 0.01);

        -- Remove from it the union of all obm that intersect it.
        SELECT ST_Difference(
            v_hole_geom, (
                SELECT ST_Union(geom)
                FROM md_geo_obm
                WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
                    AND ST_Intersects(geom, v_hole_geom) AND NOT ST_Touches(geom, v_hole_geom)
                    AND id != OLD.id
            )
        ) INTO v_possible_new_geom;

        -- is null when no intersections
        if v_possible_new_geom is not null then
            v_hole_geom := v_possible_new_geom;
        end if;

        -- If it isn't ST_Covers(v_slo_meja, v_hole_geom), then remove the overflow from the hole.
        if not ST_Covers(v_slo_meja, v_hole_geom) then
            v_hole_geom := ST_Intersection(v_hole_geom, v_slo_meja);
        end if;

        -- Go see if any existing hole intersects it, and join them together if so.
        DROP TABLE IF EXISTS intersecting_holes;
        CREATE TEMP TABLE intersecting_holes ON COMMIT DROP AS (
            SELECT id, geom
            FROM md_topoloske_kontrole
            WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
              AND area_type = 'obm'
              AND topology_problem_type = 'hole'
              AND ST_Intersects(geom, v_hole_geom)
        );

        SELECT ST_Union(ST_Union(geom), v_hole_geom)
        INTO v_possible_new_geom
        FROM intersecting_holes;

        -- is null when intersecting_holes is empty
        if v_possible_new_geom is not null then
            v_hole_geom := v_possible_new_geom;
        end if;

        -- Delete overlapping holes (we'll insert the merged one)
        DELETE FROM md_topoloske_kontrole
        WHERE id IN (select id from intersecting_holes);

        -- Insert the merged hole(s)
        IF v_hole_geom IS NOT NULL AND NOT ST_IsEmpty(v_hole_geom) THEN

            INSERT INTO md_topoloske_kontrole (
                id,
                created_at,
                created_by,
                geom,
                area_type,
                id_rel_geo_verzija,
                area,
                perimeter,
                topology_problem_type
            )
            SELECT
                uuid_generate_v4(),
                now()::timestamp,
                '848956e8-d73e-11f0-9ff0-02420a000f64',
                hole_geom,
                'obm',
                v_id_rel_geo_verzija,
                ST_Area(hole_geom),
           st_perimeter(hole_geom),
                'hole'
            FROM (SELECT (ST_Dump(v_hole_geom)).geom AS hole_geom) AS dump
            WHERE ST_Area(hole_geom) > 0;

        END IF;
    END IF;


    -- ========================================================================
    -- PHASE 2: HANDLE ADDITION (INSERT or UPDATE)
    -- ========================================================================
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        v_id_rel_geo_verzija := NEW.id_rel_geo_verzija;

        -- NEW.geom is a potential new area. ST_ReducePrecision.
        v_insertion_geom := st_reduceprecision(NEW.geom, 0.01);

        -- if not covered by border, remove the overflow.
        v_insertion_geom := st_intersection(v_insertion_geom, v_slo_meja);


        -- if intersects with anyone, create a new intersection
        DROP TABLE IF EXISTS new_intersections;
        CREATE TEMP TABLE new_intersections ON COMMIT DROP AS (
            SELECT id as other_id, st_reduceprecision((ST_Dump(st_intersection(geom, v_insertion_geom))).geom, 0.01) as intersection_geom
            FROM md_geo_obm
            WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
              AND id != NEW.id
              AND ST_Intersects(geom, v_insertion_geom)
              AND NOT ST_Touches(geom, v_insertion_geom)

        );

        INSERT INTO md_topoloske_kontrole (
            id,
            created_at,
            created_by,
            geom,
            area_type,
            id_rel_geo_verzija,
            id1,
            id2,
            area,
            perimeter,
           compactness,
            topology_problem_type
        )
        SELECT
            uuid_generate_v4(),
            now()::timestamp,
            '848956e8-d73e-11f0-9ff0-02420a000f64',
            geom,
            'obm',
            v_id_rel_geo_verzija,
            LEAST(NEW.id, other_id),
            GREATEST(NEW.ID, other_id),
            area,
            perimeter,
        4*pi()*area / NULLIF(perimeter * perimeter, 0),   -- (circle has it 0.08 (1/4*pi) and is most compact. Everything else is less compact.)
            'intersection'
        FROM (
            SELECT
                other_id,
                n.intersection_geom AS geom,
                ST_Perimeter(intersection_geom) as perimeter,
                ST_Area(intersection_geom) as area
            FROM new_intersections as n
--             WHERE  ST_GeometryType(intersection_geom) not in ('ST_LineString')
            WHERE  ST_GeometryType(intersection_geom) in ('ST_Polygon', 'ST_MultiPolygon')
            ) AS calculated
            WHERE area > 0;


        -- With holes, we take all holes that intersect our insertion geom, we union them into a var,
        -- we delete them from md_topoloske_kontrole, we remove the inserting geom from the union
        -- we then ST_Dump the union and insert new holes.
        -- This is necessary to handle cases where holes get split into 2 by the insertion.

        DROP TABLE IF EXISTS intersecting_holes;
        CREATE TEMP TABLE intersecting_holes ON COMMIT DROP AS (
          SELECT id
          FROM md_topoloske_kontrole
          WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
            AND area_type = 'obm'
            AND topology_problem_type = 'hole'
            AND ST_Intersects(v_insertion_geom, geom)
        );

        v_insertion_hole_union_geom := (SELECT st_union(geom)
                                        from md_topoloske_kontrole
                                        where id in (select id from intersecting_holes));
        v_insertion_hole_union_geom := st_difference(v_insertion_hole_union_geom, v_insertion_geom);

        DELETE FROM md_topoloske_kontrole
        WHERE id IN (select id from intersecting_holes);

        INSERT INTO md_topoloske_kontrole (
            id,
            created_at,
            created_by,
            geom,
            area_type,
            id_rel_geo_verzija,
            area,
            perimeter,
            topology_problem_type
        )
        SELECT
            uuid_generate_v4(),
            now()::timestamp,
            '848956e8-d73e-11f0-9ff0-02420a000f64',
            hole_geom,
            'obm',
            v_id_rel_geo_verzija,
            ST_Area(hole_geom),
       st_perimeter(hole_geom),
            'hole'
        FROM (SELECT st_reduceprecision((ST_Dump(v_insertion_hole_union_geom)).geom, 0.01) AS hole_geom) AS dump
        WHERE ST_Area(hole_geom) > 0;

        -- make sure the geom we are inserting is what we actually reduced here (important for cutting overflows as we did at the start)
        NEW.geom = v_insertion_geom;

    END IF;

    -- Return appropriate value
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_topology_incremental ON md_geo_obm;

CREATE TRIGGER trg_validate_topology_incremental
    BEFORE INSERT OR UPDATE OF geom OR DELETE ON md_geo_obm
    FOR EACH ROW
    EXECUTE FUNCTION validate_topology_incremental();

















































