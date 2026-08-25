

-- ============================================================================
-- 3_1_trg_obm_geom_trigger.sql - Incremental OBM Topology Trigger
-- ============================================================================
-- Requires:
--   2_0_fn_obm_topology_shared.sql
--   2_1_autofix_small_violations.sql
--   3_0_fn_obm_geom_check_all.sql
-- ============================================================================

DROP TRIGGER IF EXISTS trg_validate_topology_incremental ON md_geo_obm;

DROP FUNCTION IF EXISTS validate_topology_incremental();

CREATE OR REPLACE FUNCTION validate_topology_incremental()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_grid_size CONSTANT double precision := 0.01;
    v_slo_meja geometry;
    v_hole_geom geometry;
    v_single_hole_geom geometry;
    v_component_geom geometry;
    v_component_overlap_geom geometry;
    v_component_piece_geom geometry;
    v_possible_new_geom geometry;
    v_insertion_geom geometry;
    v_insertion_hole_union_geom geometry;
    v_small_intersections_geom geometry;
    v_id_rel_geo_verzija UUID;
    v_best_neighbor_id UUID;
    v_updated_rows integer;
    v_replacement_is_safe boolean;
BEGIN
    IF current_setting('geom_integrity.skip_obm_topology_trigger', true) = 'on' THEN
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;

        RETURN NEW;
    END IF;

    -- UPDATE OF fires when a column is named in SET, even if its value does not
    -- actually change. Avoid rebuilding topology controls for such no-op updates.
    IF TG_OP = 'UPDATE'
       AND NEW.geom IS NOT DISTINCT FROM OLD.geom
       AND NEW.id_rel_geo_verzija IS NOT DISTINCT FROM OLD.id_rel_geo_verzija THEN
        RETURN NEW;
    END IF;

    -- Rows without a version do not participate in topology. A later
    -- NULL-to-UUID update will process the existing geometry as an addition.
    IF (TG_OP = 'INSERT' AND NEW.id_rel_geo_verzija IS NULL)
       OR (TG_OP = 'DELETE' AND OLD.id_rel_geo_verzija IS NULL)
       OR (TG_OP = 'UPDATE'
           AND OLD.id_rel_geo_verzija IS NULL
           AND NEW.id_rel_geo_verzija IS NULL) THEN
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;

        RETURN NEW;
    END IF;

    -- to prevent bogus holes we do this at the start of insert/update part
    -- v_insertion_geom := ensure_snap_to_grid(NEW.geom);
    -- and at the end of that part we do:
    -- NEW.geom := v_insertion_geom;
    -- which we are certain happens correctly, because overflows we try to create actually get cut off
    

    -- Explanation of protocol:
    -- On delete:
    -- OLD.geom is now a potential hole. Snap it to the 0.01 grid.
    -- OLD.geom might be part of some intersections. If so, remove them.
    -- Remove from it the union of all obm that intersect it.
    -- If it isn't covered by the boundary, then remove the overflow from the hole.
    -- Now go see if any existing hole intersects it, and join them together if so.
    --
    -- On insert:
    -- NEW.geom is a potential new area. Snap it to the 0.01 grid.
    -- if not covered by border, remove the overflow.
    -- if intersects with anyone, create a new intersection

    -- With holes, we take all holes that intersect our insertion geom, we union them into a var,
    -- we delete them from md_topoloske_kontrole_obm, we remove the inserting geom from the union
    -- we then ST_Dump the union and insert new holes.
    -- This is necessary to handle cases where holes get split into 2 by the insertion.

    -- Fixed-precision overlays require every input on the same grid. OBMs and
    -- controls are normalized when stored; normalize the external boundary here.
    SELECT ensure_snap_to_grid(geom) INTO v_slo_meja FROM slo_meja LIMIT 1;

    IF v_slo_meja IS NULL THEN
        RAISE EXCEPTION 'Slovenia boundary (slo_meja) not found';
    END IF;

    -- ========================================================================
    -- PHASE 1: HANDLE REMOVAL (DELETE or UPDATE)
    -- ========================================================================
    IF (TG_OP = 'DELETE' OR TG_OP = 'UPDATE')
       AND OLD.id_rel_geo_verzija IS NOT NULL THEN
        v_id_rel_geo_verzija := OLD.id_rel_geo_verzija;

        -- OLD.geom might be part of some intersections. If so, remove them.
        DELETE FROM md_topoloske_kontrole_obm
        WHERE tip_topoloskega_problema = 'prekrivanje'
          and id_rel_geo_verzija = v_id_rel_geo_verzija
            and (OLD.id = id1 or OLD.id = id2);

        -- Start with the removed geometry as potential hole
        v_hole_geom := ensure_snap_to_grid(OLD.geom);

        -- Remove from it the union of all obm that intersect it.
        SELECT ensure_snap_to_grid(ST_Difference(
            v_hole_geom, (
                SELECT ST_Union(geom, v_grid_size)
                FROM md_geo_obm
                WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
                    AND ST_Intersects(geom, v_hole_geom) AND NOT ST_Touches(geom, v_hole_geom)
                    AND id != OLD.id
            ), v_grid_size
        )) INTO v_possible_new_geom;

        -- is null when no intersections
        if v_possible_new_geom is not null then
            v_hole_geom := v_possible_new_geom;
        end if;

        -- If it isn't ST_Covers(v_slo_meja, v_hole_geom), then remove the overflow from the hole.
        if not ST_Covers(v_slo_meja, v_hole_geom) then
            v_hole_geom := ST_CollectionExtract(
                ST_Intersection(v_hole_geom, v_slo_meja, v_grid_size),
                3
            );
        end if;

        IF TG_OP = 'UPDATE' THEN
            v_insertion_geom := ensure_snap_to_grid(NEW.geom);
            v_insertion_geom := ensure_snap_to_grid(ST_Intersection(v_insertion_geom, v_slo_meja, v_grid_size));
            v_hole_geom := ensure_snap_to_grid(ST_Difference(v_hole_geom, v_insertion_geom, v_grid_size));
        END IF;

        -- Go see if any existing hole intersects it, and join them together if so.
        DROP TABLE IF EXISTS intersecting_holes;
        CREATE TEMP TABLE intersecting_holes ON COMMIT DROP AS (
            SELECT id, geom
            FROM md_topoloske_kontrole_obm
            WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
              AND tip_topoloskega_problema = 'luknja'
              AND ST_Intersects(geom, v_hole_geom)
        );

        SELECT ensure_snap_to_grid(ST_Union(
            ST_Union(geom, v_grid_size),
            v_hole_geom,
            v_grid_size
        ))
        INTO v_possible_new_geom
        FROM intersecting_holes;

        -- is null when intersecting_holes is empty
        if v_possible_new_geom is not null then
            v_hole_geom := v_possible_new_geom;
        end if;

        -- Merged controls may include old border debris. Clip again so only
        -- the part that can actually be a hole is processed.
        v_hole_geom := ST_CollectionExtract(
            ST_Intersection(v_hole_geom, v_slo_meja, v_grid_size),
            3
        );

        SELECT NOT EXISTS (
            SELECT 1
            FROM ST_Dump(v_hole_geom) dumped
            WHERE NOT obm_geom_has_no_area_outside(
                dumped.geom,
                v_slo_meja,
                v_grid_size
            )
        ) INTO v_replacement_is_safe;

        IF v_replacement_is_safe THEN
            DELETE FROM md_topoloske_kontrole_obm
            WHERE id IN (select id from intersecting_holes);

            IF v_hole_geom IS NOT NULL AND NOT ST_IsEmpty(v_hole_geom) THEN
                FOR v_single_hole_geom IN
                    SELECT (ST_Dump(v_hole_geom)).geom
                LOOP
                    IF v_single_hole_geom IS NULL OR ST_IsEmpty(v_single_hole_geom) OR ST_Area(v_single_hole_geom) <= 0 THEN
                        CONTINUE;
                    END IF;

                    IF TG_OP = 'UPDATE'
                       AND obm_small_topology_autofix_enabled()
                       AND is_small_obm_topology_problem(v_single_hole_geom) THEN
                        v_best_neighbor_id := find_best_obm_neighbor_for_hole(
                            v_id_rel_geo_verzija,
                            v_single_hole_geom,
                            OLD.id,
                            true
                        );

                        IF v_best_neighbor_id IS NOT NULL THEN
                            SELECT ST_Multi(ensure_snap_to_grid(
                                ST_Union(geom, v_single_hole_geom, v_grid_size)
                            ))::geometry(MultiPolygon, 3794)
                            INTO v_possible_new_geom
                            FROM md_geo_obm
                            WHERE id = v_best_neighbor_id;

                            IF obm_geom_has_no_area_outside(
                                v_possible_new_geom,
                                v_slo_meja,
                                v_grid_size
                            ) THEN
                                PERFORM set_config('geom_integrity.skip_obm_topology_trigger', 'on', true);

                                UPDATE md_geo_obm
                                SET geom = v_possible_new_geom
                                WHERE id = v_best_neighbor_id;

                                GET DIAGNOSTICS v_updated_rows = ROW_COUNT;
                                PERFORM set_config('geom_integrity.skip_obm_topology_trigger', 'off', true);

                                IF v_updated_rows = 1 THEN
                                    CONTINUE;
                                END IF;
                            END IF;
                        END IF;
                    END IF;

                    INSERT INTO md_topoloske_kontrole_obm (
                        id,
                        created_at,
                        created_by,
                        geom,
                        id_rel_geo_verzija,
                        povrsina,
                        obseg,
                        kompaktnost,
                        tip_topoloskega_problema
                    )
                    VALUES (
                        uuid_generate_v4(),
                        now()::timestamp,
                        '00000000-0000-0000-0000-000000000000'::uuid,
                        v_single_hole_geom,
                        v_id_rel_geo_verzija,
                        ST_Area(v_single_hole_geom),
                        ST_Perimeter(v_single_hole_geom),
                        obm_topology_compactness(v_single_hole_geom),
                        'luknja'
                    );
                END LOOP;
            END IF;
        END IF;
    END IF;


    -- ========================================================================
    -- PHASE 2: HANDLE ADDITION (INSERT or UPDATE)
    -- ========================================================================
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE')
       AND NEW.id_rel_geo_verzija IS NOT NULL THEN
        v_id_rel_geo_verzija := NEW.id_rel_geo_verzija;

        -- NEW.geom is a potential new area. Snap it to the 0.01 grid.
        v_insertion_geom := ensure_snap_to_grid(NEW.geom);

        -- if not covered by border, remove the overflow.
        v_insertion_geom := ensure_snap_to_grid(ST_Intersection(v_insertion_geom, v_slo_meja, v_grid_size));

        IF v_insertion_geom IS NULL THEN
            RAISE EXCEPTION 'OBM geometry collapsed after clipping to slo_meja';
        END IF;


        -- if intersects with anyone, create a new intersection
        DROP TABLE IF EXISTS new_intersections;
        CREATE TEMP TABLE new_intersections ON COMMIT DROP AS (
            SELECT 
                id as other_id, 
                ensure_snap_to_grid((ST_Dump(ST_Intersection(geom, v_insertion_geom, v_grid_size))).geom) as intersection_geom
            FROM md_geo_obm
            WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
              AND id != NEW.id
              AND ST_Intersects(geom, v_insertion_geom)
              AND NOT ST_Touches(geom, v_insertion_geom)

        );

        -- autofix small - intersections
        IF obm_small_topology_autofix_enabled() THEN
            SELECT ensure_snap_to_grid(ST_Union(intersection_geom, v_grid_size))
            INTO v_small_intersections_geom
            FROM new_intersections
            WHERE ST_GeometryType(intersection_geom) in ('ST_Polygon', 'ST_MultiPolygon')
              AND is_small_obm_topology_problem(intersection_geom);
        END IF;

        IF obm_small_topology_autofix_enabled()
           AND v_small_intersections_geom IS NOT NULL
           AND NOT ST_IsEmpty(v_small_intersections_geom) THEN
            v_insertion_geom := ensure_snap_to_grid(ST_Difference(
                v_insertion_geom,
                v_small_intersections_geom,
                v_grid_size
            ));
        END IF;

        -- With holes, we take all holes that intersect our insertion geom, we union them into a var,
        -- we delete them from md_topoloske_kontrole_obm, we remove the inserting geom from the union
        -- we then ST_Dump the union and insert new holes.
        -- This is necessary to handle cases where holes get split into 2 by the insertion.

        DROP TABLE IF EXISTS intersecting_holes;
        CREATE TEMP TABLE intersecting_holes ON COMMIT DROP AS (
          SELECT id
          FROM md_topoloske_kontrole_obm
          WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
            AND tip_topoloskega_problema = 'luknja'
            AND ST_Intersects(v_insertion_geom, geom)
        );

        v_insertion_hole_union_geom := (SELECT ensure_snap_to_grid(ST_Union(geom, v_grid_size))
                                        from md_topoloske_kontrole_obm
                                        where id in (select id from intersecting_holes));
        v_insertion_hole_union_geom := ensure_snap_to_grid(ST_Difference(
            v_insertion_hole_union_geom,
            v_insertion_geom,
            v_grid_size
        ));
        v_insertion_hole_union_geom := ST_CollectionExtract(
            ST_Intersection(v_insertion_hole_union_geom, v_slo_meja, v_grid_size),
            3
        );

        SELECT NOT EXISTS (
            SELECT 1
            FROM ST_Dump(v_insertion_hole_union_geom) dumped
            WHERE NOT obm_geom_has_no_area_outside(
                dumped.geom,
                v_slo_meja,
                v_grid_size
            )
        ) INTO v_replacement_is_safe;

        IF v_replacement_is_safe THEN
            DELETE FROM md_topoloske_kontrole_obm
            WHERE id IN (select id from intersecting_holes);

            IF v_insertion_hole_union_geom IS NOT NULL AND NOT ST_IsEmpty(v_insertion_hole_union_geom) THEN
                FOR v_single_hole_geom IN
                    SELECT (ST_Dump(v_insertion_hole_union_geom)).geom
                LOOP
                    IF v_single_hole_geom IS NULL OR ST_IsEmpty(v_single_hole_geom) OR ST_Area(v_single_hole_geom) <= 0 THEN
                        CONTINUE;
                    END IF;

                    -- autofix small - holes
                    IF obm_small_topology_autofix_enabled()
                       AND is_small_obm_topology_problem(v_single_hole_geom) THEN
                        v_possible_new_geom := ensure_snap_to_grid(ST_Union(
                            v_insertion_geom,
                            v_single_hole_geom,
                            v_grid_size
                        ));

                        IF obm_geom_has_no_area_outside(
                            v_possible_new_geom,
                            v_slo_meja,
                            v_grid_size
                        ) THEN
                            v_insertion_geom := v_possible_new_geom;
                            CONTINUE;
                        END IF;
                    END IF;

                    INSERT INTO md_topoloske_kontrole_obm (
                        id,
                        created_at,
                        created_by,
                        geom,
                        id_rel_geo_verzija,
                        povrsina,
                        obseg,
                        kompaktnost,
                        tip_topoloskega_problema
                    )
                    VALUES (
                        uuid_generate_v4(),
                        now()::timestamp,
                        '00000000-0000-0000-0000-000000000000'::uuid,
                        v_single_hole_geom,
                        v_id_rel_geo_verzija,
                        ST_Area(v_single_hole_geom),
                        ST_Perimeter(v_single_hole_geom),
                        obm_topology_compactness(v_single_hole_geom),
                        'luknja'
                    );
                END LOOP;
            END IF;
        END IF;

        -- Keep the main inserted area, but return tiny detached pieces to a
        -- neighbor when they share an edge.
        IF obm_small_topology_autofix_enabled() THEN
            FOR v_component_geom IN
                SELECT component
                FROM (
                    SELECT (ST_Dump(v_insertion_geom)).geom AS component
                ) components
                ORDER BY ST_Area(component) DESC, ST_AsEWKB(component)
                OFFSET 1
            LOOP
                IF NOT is_small_obm_topology_problem(v_component_geom) THEN
                    CONTINUE;
                END IF;

                SELECT ensure_snap_to_grid(ST_Union(
                    ST_Intersection(geom, v_component_geom, v_grid_size),
                    v_grid_size
                ))
                INTO v_component_overlap_geom
                FROM md_geo_obm
                WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
                  AND id <> NEW.id
                  AND ST_Intersects(geom, v_component_geom)
                  AND ST_Area(ST_Intersection(geom, v_component_geom, v_grid_size)) > 0;

                IF v_component_overlap_geom IS NOT NULL THEN
                    v_insertion_geom := ensure_snap_to_grid(
                        ST_Difference(v_insertion_geom, v_component_overlap_geom, v_grid_size)
                    );
                    v_component_geom := ensure_snap_to_grid(
                        ST_Difference(v_component_geom, v_component_overlap_geom, v_grid_size)
                    );
                END IF;

                IF v_component_geom IS NULL OR ST_IsEmpty(v_component_geom) THEN
                    CONTINUE;
                END IF;

                FOR v_component_piece_geom IN
                    SELECT (ST_Dump(v_component_geom)).geom
                LOOP
                    v_best_neighbor_id := find_best_obm_neighbor_for_hole(
                        v_id_rel_geo_verzija,
                        v_component_piece_geom,
                        NEW.id
                    );

                    IF v_best_neighbor_id IS NULL THEN
                        CONTINUE;
                    END IF;

                    PERFORM set_config('geom_integrity.skip_obm_topology_trigger', 'on', true);

                    UPDATE md_geo_obm
                    SET geom = ST_Multi(ensure_snap_to_grid(
                        ST_Union(geom, v_component_piece_geom, v_grid_size)
                    ))::geometry(MultiPolygon, 3794)
                    WHERE id = v_best_neighbor_id;

                    GET DIAGNOSTICS v_updated_rows = ROW_COUNT;
                    PERFORM set_config('geom_integrity.skip_obm_topology_trigger', 'off', true);

                    IF v_updated_rows = 1 THEN
                        v_insertion_geom := ensure_snap_to_grid(
                            ST_Difference(v_insertion_geom, v_component_piece_geom, v_grid_size)
                        );
                    END IF;
                END LOOP;
            END LOOP;
        END IF;

        -- Report intersections only after all corrections to NEW.geom.
        DROP TABLE IF EXISTS new_intersections;
        CREATE TEMP TABLE new_intersections ON COMMIT DROP AS (
            SELECT
                id AS other_id,
                ensure_snap_to_grid((ST_Dump(ST_Intersection(
                    geom,
                    v_insertion_geom,
                    v_grid_size
                ))).geom) AS intersection_geom
            FROM md_geo_obm
            WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
              AND id <> NEW.id
              AND ST_Intersects(geom, v_insertion_geom)
              AND NOT ST_Touches(geom, v_insertion_geom)
        );

        INSERT INTO md_topoloske_kontrole_obm (
            id,
            created_at,
            created_by,
            geom,
            id_rel_geo_verzija,
            id1,
            id2,
            povrsina,
            obseg,
            kompaktnost,
            tip_topoloskega_problema
        )
        SELECT
            uuid_generate_v4(),
            now()::timestamp,
            '00000000-0000-0000-0000-000000000000'::uuid,
            geom,
            v_id_rel_geo_verzija,
            LEAST(NEW.id, other_id),
            GREATEST(NEW.id, other_id),
            povrsina,
            obseg,
            obm_topology_compactness(geom),
            'prekrivanje'
        FROM (
            SELECT
                other_id,
                intersection_geom AS geom,
                ST_Perimeter(intersection_geom) AS obseg,
                ST_Area(intersection_geom) AS povrsina
            FROM new_intersections
            WHERE ST_GeometryType(intersection_geom) IN ('ST_Polygon', 'ST_MultiPolygon')
        ) calculated
        WHERE povrsina > 0
          AND (
              NOT obm_small_topology_autofix_enabled()
              OR NOT is_small_obm_topology_problem(geom)
          );

        -- make sure the geom we are inserting is what we actually snapped here (important for cutting overflows as we did at the start)
        NEW.geom := ST_Multi(v_insertion_geom)::geometry(MultiPolygon, 3794);

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
    BEFORE INSERT OR UPDATE OF geom, id_rel_geo_verzija OR DELETE ON md_geo_obm
    FOR EACH ROW
    EXECUTE FUNCTION validate_topology_incremental();













