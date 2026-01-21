--
--
--
-- in @-2topologyFixer.sql we will fix topologies in table md_geo_obm based on the
--   problems presented in md_topoloske_kontrole
--
--   For holes in md_topoloske_kontrole, we will find the geom in md_geo_obm that shares the largest border with them.
-- We will join the hole to it, and delete the holde from md_topoloske_kontrole.
--
-- For overflows in md_topoloske_kontrole, we will simply make the relevant geom in md_geo_obm lose the overflow,
-- and then we delete the overflow from md_topoloske_kontrole.
--
--
-- Data Source: localdb@localhost
-- Database: localdb
-- Schema: public
-- Table: md_geo_obm
--
--
-- -- auto-generated definition
-- create table md_geo_obm
-- (
--     id                 uuid,
--     created_at         timestamp,
--     updated_at         timestamp,
--     created_by         uuid,
--     updated_by         uuid,
--     gid                integer,
--     geom               geometry(MultiPolygon, 3794),
--     id_rel_geo_verzija uuid,
--     ime_obmocja        text,
--     gv_id              text,
--     zap_st_obm         integer,
--     split_group_id     uuid,
--     kopiran_id         uuid,
--     intersecting       boolean,
--     overflowing        boolean,
--     problem_topologija boolean
-- );
--
-- alter table md_geo_obm
--     owner to matevzvidovic;
-- Show table preview
--
--
--
--
--
--
--
--
--
--
--
--
--
--
--
-- Data Source: localdb@localhost
-- Database: localdb
-- Schema: public
-- Table: md_topoloske_kontrole
--
--
-- -- auto-generated definition
-- create table md_topoloske_kontrole
-- (
--     id                    uuid      not null
--         primary key,
--     created_at            timestamp not null,
--     updated_at            timestamp,
--     created_by            uuid      not null,
--     updated_by            uuid,
--     gid                   serial,
--     geom                  geometry(MultiPolygon, 3794),
--     area_type             text      not null
--         constraint check_area_type
--             check (area_type = ANY (ARRAY ['obm'::text, 'cona'::text])),
--     id_rel_geo_verzija    uuid,
--     id_rel_verzije_modela uuid,
--     id2                   uuid,
--     id1                   uuid,
--     area                  numeric,
--     perimeter             numeric,
--     compactness           numeric,
--     topology_problem_type text
--         constraint check_topology_problem_type
--             check (topology_problem_type = ANY (ARRAY ['intersection'::text, 'hole'::text, 'overflow'::text])),
--     constraint check_id1_less_than_id2
--         check ((id2 IS NULL) OR ((id1 IS NOT NULL) AND (id1 < id2)))
-- );
--
-- alter table md_topoloske_kontrole
--     owner to matevzvidovic;
--
-- create index md_topoloske_kontrole_geom_idx
--     on md_topoloske_kontrole using gist (geom);
--
-- create index idx_topoloske_kontrole
--     on md_topoloske_kontrole (area_type, id_rel_geo_verzija, id_rel_verzije_modela, topology_problem_type, id1, id2);
-- Show table preview


-- ============================================================================
-- TOPOLOGY FIXER IMPLEMENTATION
-- ============================================================================

-- ============================================================================
-- PART 1: FIX HOLES
-- ============================================================================
-- For each hole, find the geometry in md_geo_obm that shares the largest border
-- with it, union them together, and delete the hole from md_topoloske_kontrole

CREATE OR REPLACE FUNCTION fix_holes()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    hole_record RECORD;
    neighbor_record RECORD;
    max_shared_length NUMERIC;
    best_neighbor_id UUID;
BEGIN
    -- Loop through all holes in md_topoloske_kontrole
    FOR hole_record IN
        SELECT id, geom, area_type, id_rel_geo_verzija, id_rel_verzije_modela
        FROM md_topoloske_kontrole
        WHERE topology_problem_type = 'hole'
    LOOP
        max_shared_length := 0;
        best_neighbor_id := NULL;

        -- Find all geometries in md_geo_obm that share a border with this hole
        FOR neighbor_record IN
            SELECT
                obm.id,
--                 ST_Length(
--                         st_perimeter(
                st_area(
                    ST_Intersection(
                        st_buffer(hole_record.geom, 1),
                        obm.geom
                    )
                ) as shared_length
            FROM md_geo_obm obm
            WHERE obm.id_rel_geo_verzija = hole_record.id_rel_geo_verzija
                AND ST_Intersects(
                    st_buffer(hole_record.geom, 10),
                    obm.geom
                )
        LOOP
            -- Track the neighbor with the longest shared boundary
            IF neighbor_record.shared_length > max_shared_length THEN
                max_shared_length := neighbor_record.shared_length;
                best_neighbor_id := neighbor_record.id;
            END IF;
        END LOOP;

        -- If we found a neighbor, union the hole with it
        IF best_neighbor_id IS NOT NULL THEN
            UPDATE md_geo_obm
            SET geom = ST_Union(
                        geom,
                        (SELECT geom FROM md_topoloske_kontrole WHERE id = hole_record.id)
                    )
            WHERE id = best_neighbor_id;

            -- Delete the hole from md_topoloske_kontrole
            DELETE FROM md_topoloske_kontrole WHERE id = hole_record.id;

--             RAISE NOTICE 'Fixed hole % by merging with neighbor %', hole_record.id, best_neighbor_id;
        ELSE
            RAISE WARNING 'No neighbor found for hole %', hole_record.id;
        END IF;
    END LOOP;
END $$;


-- ============================================================================
-- PART 2: FIX OVERFLOWS
-- ============================================================================
-- For each overflow, subtract it from the relevant geometry in md_geo_obm
-- and delete the overflow from md_topoloske_kontrole

CREATE OR REPLACE FUNCTION fix_overflows()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    overflow_record RECORD;
BEGIN
    -- Loop through all overflows in md_topoloske_kontrole
    FOR overflow_record IN
        SELECT id, geom, area_type, id_rel_geo_verzija, id_rel_verzije_modela, id1
        FROM md_topoloske_kontrole
        WHERE topology_problem_type = 'overflow'
    LOOP
        -- Subtract the overflow from the geometry in md_geo_obm
        -- The id1 field should reference the geometry that has the overflow
        IF overflow_record.id1 IS NOT NULL THEN
            UPDATE md_geo_obm
            SET geom = ST_Multi(
                    ST_Difference(
                        geom,
                        (SELECT geom FROM md_topoloske_kontrole WHERE id = overflow_record.id)
                    )
                )
            WHERE id = overflow_record.id1;

            -- Delete the overflow from md_topoloske_kontrole
            DELETE FROM md_topoloske_kontrole WHERE id = overflow_record.id;

--             RAISE NOTICE 'Fixed overflow % by subtracting from geometry %', overflow_record.id, overflow_record.id1;
        ELSE
            RAISE WARNING 'No id1 found for overflow %', overflow_record.id;
        END IF;
    END LOOP;
END $$;


-- ============================================================================
-- PART 3: FIX INTERSECTIONS
-- ============================================================================
-- For each intersection, subtract it from the geometry with id2 (keeping id1 intact)
-- and delete the intersection from md_topoloske_kontrole

CREATE OR REPLACE FUNCTION fix_intersections()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    intersection_record RECORD;
BEGIN
    -- Loop through all intersections in md_topoloske_kontrole
    FOR intersection_record IN
        SELECT id, geom, area_type, id_rel_geo_verzija, id_rel_verzije_modela, id1, id2
        FROM md_topoloske_kontrole
        WHERE topology_problem_type = 'intersection'
    LOOP
        -- Subtract the intersection from the geometry with id2
        -- We keep id1 intact and remove the overlap from id2
        IF intersection_record.id1 IS NOT NULL AND intersection_record.id2 IS NOT NULL THEN
            UPDATE md_geo_obm
            SET geom = ST_Multi(
                    ST_Difference(
                        geom,
                        (SELECT geom FROM md_topoloske_kontrole WHERE id = intersection_record.id)
                    )
                )
            WHERE id = intersection_record.id2;

            -- Delete the intersection from md_topoloske_kontrole
            DELETE FROM md_topoloske_kontrole WHERE id = intersection_record.id;

--             RAISE NOTICE 'Fixed intersection % by subtracting from geometry %', intersection_record.id, intersection_record.id2;
        ELSE
            RAISE WARNING 'Missing id1 or id2 for intersection %', intersection_record.id;
        END IF;
    END LOOP;
END $$;
--
--
