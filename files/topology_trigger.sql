-- ============================================================================
-- PART 1: Incremental Validation Trigger
-- ============================================================================
-- This trigger maintains topology validation incrementally on each INSERT,
-- UPDATE, or DELETE operation on the md_geo_obm table.
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_topology_incremental()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_slo_meja geometry;
    v_overflow_geom geometry;
    v_hole_geom geometry;
    v_intersecting_ids INTEGER[];
    v_id_rel_geo_verzija INTEGER;
BEGIN
    -- Get Slovenia boundary
    SELECT geom INTO v_slo_meja FROM slo_meja LIMIT 1;
    
    IF v_slo_meja IS NULL THEN
        RAISE EXCEPTION 'Slovenia boundary (slo_meja) not found';
    END IF;
    
    -- ========================================================================
    -- HANDLE DELETE OPERATION
    -- ========================================================================
    IF (TG_OP = 'DELETE') THEN
        v_id_rel_geo_verzija := OLD.id_rel_geo_verzija;
        
        -- --------------------------------------------------------------------
        -- Check if deletion creates a HOLE
        -- --------------------------------------------------------------------
        -- Start with the deleted geometry as potential hole
        v_hole_geom := OLD.geom;
        
        -- Remove all remaining geometries from this potential hole
        SELECT ST_Difference(v_hole_geom, COALESCE(ST_Union(geom), ST_GeomFromText('GEOMETRYCOLLECTION EMPTY')))
        INTO v_hole_geom
        FROM md_geo_obm
        WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
          AND id != OLD.id
          AND geom IS NOT NULL;
        
        -- Ensure the hole is within Slovenia
        v_hole_geom := ST_Intersection(v_hole_geom, v_slo_meja);
        
        -- Process the hole if it exists
        IF v_hole_geom IS NOT NULL AND NOT ST_IsEmpty(v_hole_geom) THEN
            -- Check if this hole intersects with existing holes
            -- If so, merge them; if not, insert as new hole
            WITH overlapping_holes AS (
                SELECT id, geom
                FROM topoloske_vrzeli
                WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
                  AND ST_Intersects(geom, v_hole_geom)
            )
            -- Delete overlapping holes and create union with new hole
            DELETE FROM topoloske_vrzeli
            WHERE id IN (SELECT id FROM overlapping_holes)
            RETURNING ST_Union(geom) INTO v_hole_geom;
            
            -- If we had overlapping holes, v_hole_geom now contains their union
            -- Otherwise, v_hole_geom is unchanged
            IF v_hole_geom IS NOT NULL THEN
                -- Re-union with the original hole geometry
                WITH overlapping_geoms AS (
                    SELECT geom FROM topoloske_vrzeli
                    WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
                      AND ST_Intersects(geom, OLD.geom)
                )
                SELECT ST_Union(ST_Union(geom), OLD.geom)
                INTO v_hole_geom
                FROM overlapping_geoms;
                
                -- Remove all existing shapes from the hole
                SELECT ST_Difference(
                    COALESCE(v_hole_geom, OLD.geom),
                    COALESCE(ST_Union(geom), ST_GeomFromText('GEOMETRYCOLLECTION EMPTY'))
                )
                INTO v_hole_geom
                FROM md_geo_obm
                WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
                  AND id != OLD.id
                  AND geom IS NOT NULL;
            END IF;
            
            -- Insert the hole(s) if any remain
            IF v_hole_geom IS NOT NULL AND NOT ST_IsEmpty(v_hole_geom) THEN
                INSERT INTO topoloske_vrzeli (id_rel_geo_verzija, geom)
                SELECT v_id_rel_geo_verzija, (ST_Dump(v_hole_geom)).geom;
            END IF;
        END IF;
        
        -- --------------------------------------------------------------------
        -- Update INTERSECTION flags for previously intersecting geometries
        -- --------------------------------------------------------------------
        IF OLD.intersecting THEN
            -- Find geometries that were intersecting with the deleted one
            SELECT ARRAY_AGG(id) INTO v_intersecting_ids
            FROM md_geo_obm
            WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
              AND id != OLD.id
              AND (ST_Overlaps(geom, OLD.geom) OR ST_Contains(geom, OLD.geom) OR ST_Contains(OLD.geom, geom));
            
            -- For each previously intersecting geometry, check if it still intersects anything
            IF v_intersecting_ids IS NOT NULL THEN
                UPDATE md_geo_obm m
                SET intersecting = EXISTS (
                    SELECT 1
                    FROM md_geo_obm m2
                    WHERE m2.id_rel_geo_verzija = v_id_rel_geo_verzija
                      AND m2.id != m.id
                      AND ST_Overlaps(m.geom, m2.geom)
                )
                WHERE m.id = ANY(v_intersecting_ids);
            END IF;
        END IF;
        
        RETURN OLD;
    END IF;
    
    -- ========================================================================
    -- HANDLE INSERT OPERATION
    -- ========================================================================
    IF (TG_OP = 'INSERT') THEN
        v_id_rel_geo_verzija := NEW.id_rel_geo_verzija;
        
        -- Initialize flags
        NEW.intersecting := FALSE;
        NEW.overflowing := FALSE;
        
        -- --------------------------------------------------------------------
        -- Check for OVERFLOW (geometry extends beyond Slovenia)
        -- --------------------------------------------------------------------
        v_overflow_geom := ST_Difference(NEW.geom, v_slo_meja);
        IF v_overflow_geom IS NOT NULL AND NOT ST_IsEmpty(v_overflow_geom) THEN
            NEW.overflowing := TRUE;
        END IF;
        
        -- --------------------------------------------------------------------
        -- Check for INTERSECTIONS with existing geometries
        -- --------------------------------------------------------------------
        SELECT ARRAY_AGG(id) INTO v_intersecting_ids
        FROM md_geo_obm
        WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
          AND id != NEW.id
          AND (ST_Overlaps(geom, NEW.geom) OR ST_Contains(geom, NEW.geom) OR ST_Contains(NEW.geom, geom));
        
        IF v_intersecting_ids IS NOT NULL AND array_length(v_intersecting_ids, 1) > 0 THEN
            NEW.intersecting := TRUE;
            
            -- Mark the intersecting geometries as well
            UPDATE md_geo_obm
            SET intersecting = TRUE
            WHERE id = ANY(v_intersecting_ids);
        END IF;
        
        -- --------------------------------------------------------------------
        -- Update HOLES (new geometry might fill or reduce existing holes)
        -- --------------------------------------------------------------------
        -- Find holes that intersect with the new geometry
        WITH affected_holes AS (
            SELECT id, geom
            FROM topoloske_vrzeli
            WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
              AND ST_Intersects(geom, NEW.geom)
        ),
        updated_holes AS (
            SELECT 
                id,
                ST_Difference(geom, NEW.geom) as new_geom
            FROM affected_holes
        )
        -- Delete old holes and insert updated ones
        DELETE FROM topoloske_vrzeli
        WHERE id IN (SELECT id FROM affected_holes);
        
        -- Insert updated holes (only if they still exist after difference)
        INSERT INTO topoloske_vrzeli (id_rel_geo_verzija, geom)
        SELECT 
            v_id_rel_geo_verzija,
            (ST_Dump(new_geom)).geom
        FROM updated_holes
        WHERE new_geom IS NOT NULL AND NOT ST_IsEmpty(new_geom);
        
        RETURN NEW;
    END IF;
    
    -- ========================================================================
    -- HANDLE UPDATE OPERATION
    -- ========================================================================
    IF (TG_OP = 'UPDATE') THEN
        -- For UPDATE, we treat it as DELETE old + INSERT new
        -- This is simpler and equally efficient since we need to check everything anyway
        
        v_id_rel_geo_verzija := NEW.id_rel_geo_verzija;
        
        -- --------------------------------------------------------------------
        -- PHASE 1: Process deletion of OLD geometry
        -- --------------------------------------------------------------------
        
        -- Check if deletion of old geometry creates a hole
        v_hole_geom := OLD.geom;
        
        -- Remove all remaining geometries (except the one being updated)
        SELECT ST_Difference(v_hole_geom, COALESCE(ST_Union(geom), ST_GeomFromText('GEOMETRYCOLLECTION EMPTY')))
        INTO v_hole_geom
        FROM md_geo_obm
        WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
          AND id != OLD.id
          AND geom IS NOT NULL;
        
        v_hole_geom := ST_Intersection(v_hole_geom, v_slo_meja);
        
        IF v_hole_geom IS NOT NULL AND NOT ST_IsEmpty(v_hole_geom) THEN
            -- Merge with existing overlapping holes
            WITH overlapping_geoms AS (
                SELECT geom FROM topoloske_vrzeli
                WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
                  AND ST_Intersects(geom, OLD.geom)
            )
            SELECT ST_Union(ST_Union(geom), OLD.geom)
            INTO v_hole_geom
            FROM overlapping_geoms;
            
            -- Delete overlapping holes
            DELETE FROM topoloske_vrzeli
            WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
              AND ST_Intersects(geom, OLD.geom);
            
            -- Recalculate hole after removing existing geometries
            SELECT ST_Difference(
                COALESCE(v_hole_geom, OLD.geom),
                COALESCE(ST_Union(geom), ST_GeomFromText('GEOMETRYCOLLECTION EMPTY'))
            )
            INTO v_hole_geom
            FROM md_geo_obm
            WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
              AND id != OLD.id
              AND geom IS NOT NULL;
            
            IF v_hole_geom IS NOT NULL AND NOT ST_IsEmpty(v_hole_geom) THEN
                INSERT INTO topoloske_vrzeli (id_rel_geo_verzija, geom)
                SELECT v_id_rel_geo_verzija, (ST_Dump(v_hole_geom)).geom;
            END IF;
        END IF;
        
        -- Update intersection flags for geometries that were intersecting with OLD
        IF OLD.intersecting THEN
            SELECT ARRAY_AGG(id) INTO v_intersecting_ids
            FROM md_geo_obm
            WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
              AND id != OLD.id
              AND (ST_Overlaps(geom, OLD.geom) OR ST_Contains(geom, OLD.geom) OR ST_Contains(OLD.geom, geom));
            
            IF v_intersecting_ids IS NOT NULL THEN
                UPDATE md_geo_obm m
                SET intersecting = EXISTS (
                    SELECT 1
                    FROM md_geo_obm m2
                    WHERE m2.id_rel_geo_verzija = v_id_rel_geo_verzija
                      AND m2.id != m.id
                      AND m2.id != NEW.id  -- Don't check against the geometry being updated
                      AND ST_Overlaps(m.geom, m2.geom)
                )
                WHERE m.id = ANY(v_intersecting_ids);
            END IF;
        END IF;
        
        -- --------------------------------------------------------------------
        -- PHASE 2: Process insertion of NEW geometry
        -- --------------------------------------------------------------------
        
        NEW.intersecting := FALSE;
        NEW.overflowing := FALSE;
        
        -- Check for overflow
        v_overflow_geom := ST_Difference(NEW.geom, v_slo_meja);
        IF v_overflow_geom IS NOT NULL AND NOT ST_IsEmpty(v_overflow_geom) THEN
            NEW.overflowing := TRUE;
        END IF;
        
        -- Check for intersections
        SELECT ARRAY_AGG(id) INTO v_intersecting_ids
        FROM md_geo_obm
        WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
          AND id != NEW.id
          AND (ST_Overlaps(geom, NEW.geom) OR ST_Contains(geom, NEW.geom) OR ST_Contains(NEW.geom, geom));
        
        IF v_intersecting_ids IS NOT NULL AND array_length(v_intersecting_ids, 1) > 0 THEN
            NEW.intersecting := TRUE;
            
            UPDATE md_geo_obm
            SET intersecting = TRUE
            WHERE id = ANY(v_intersecting_ids);
        END IF;
        
        -- Update holes affected by new geometry
        WITH affected_holes AS (
            SELECT id, geom
            FROM topoloske_vrzeli
            WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
              AND ST_Intersects(geom, NEW.geom)
        )
        DELETE FROM topoloske_vrzeli
        WHERE id IN (SELECT id FROM affected_holes);
        
        INSERT INTO topoloske_vrzeli (id_rel_geo_verzija, geom)
        SELECT 
            v_id_rel_geo_verzija,
            (ST_Dump(ST_Difference(geom, NEW.geom))).geom
        FROM topoloske_vrzeli
        WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
          AND ST_Intersects(geom, NEW.geom)
          AND NOT ST_IsEmpty(ST_Difference(geom, NEW.geom));
        
        RETURN NEW;
    END IF;
    
    RETURN NEW;
END;
$$;

-- ============================================================================
-- Create the trigger
-- ============================================================================

-- DROP TRIGGER IF EXISTS trg_validate_topology ON md_geo_obm;

CREATE TRIGGER trg_validate_topology_incremental
    BEFORE INSERT OR UPDATE OR DELETE ON md_geo_obm
    FOR EACH ROW
    EXECUTE FUNCTION validate_topology_incremental();

-- ============================================================================
-- Usage notes and testing
-- ============================================================================

-- The trigger is now active and will automatically validate topology on:
-- 1. INSERT: Checks for intersections, overflows, and reduces holes
-- 2. UPDATE: Treats as delete+insert, updating all relevant validations
-- 3. DELETE: Checks for new holes and updates intersection flags

-- Testing examples:

-- Test 1: Insert a new geometry
-- INSERT INTO md_geo_obm (geom, id_rel_geo_verzija)
-- VALUES (ST_GeomFromText('POLYGON((...))', 3794), 1);

-- Test 2: Check if flags were set correctly
-- SELECT id, intersecting, overflowing FROM md_geo_obm WHERE id = <new_id>;

-- Test 3: Check if holes were updated
-- SELECT * FROM topoloske_vrzeli WHERE id_rel_geo_verzija = 1;

-- Test 4: Update a geometry
-- UPDATE md_geo_obm SET geom = ST_GeomFromText('POLYGON((...))', 3794) WHERE id = <id>;

-- Test 5: Delete a geometry and check for new holes
-- DELETE FROM md_geo_obm WHERE id = <id>;
-- SELECT * FROM topoloske_vrzeli WHERE id_rel_geo_verzija = 1;


select * from md_geo_obm where id = '7fde5c3d-9b0d-43b0-871d-9a17e27341e0';
0106000020D20E0000010000000103000000010000003E0000002FDD2486EADE20411283C0CA2D3C03410000000020DF2041DD240681CC3903414E62101873DF2041759318041A3603418716D9CEC0DF2041FA7E6ABC9C3203411283C08A15E020418716D9CECE2E034191ED7CFF49E020415EBA490C792C0341B07268D14CE02041CFF753E3582C03410C022BC7A5E0204146B6F3FDC2280341EC51B8DEE7E020418716D9CEA9250341C1CAA1451FE12041E17A14AEA42303412FDD244687E12041295C8FC28E1F034152B81E05C5E12041EC51B81E801C03411F85EB51D4E120418D976E12ED190341068195C3BDE120411904560EF2170341F6285C8F32E12041F853E3A50F130341378941201EDD2041A01A2FDD9618034146B6F33DE6D42041A4703D0A8C230341B6F3FD545ED420410C022B87B7230341000000C08FD32041CDCCCCCC4A2303413F355E7A5DD220410C022B8745220341250681154ED120416891ED7C5A2703411283C08AFED1204108AC1C5ADF2A0341DF4F8D1759D220411F85EB511C2A034179E926310ED32041B4C876BEDB3003412B8716595AD3204104560E2D3F340341643BDFCF5AD32041DF4F8D978837034191ED7CFF1DD22041DF4F8D97A3370341E17A14AE40D12041986E1283F8380341D34D62103CD120411904560EB63B0341295C8F824AD22041560E2DB2CE3C03418B6CE73B09D3204183C0CAA1ED3E03411904564EF5D42041A245B6F3E9450341F0A7C6CB99D620418B6CE7FB884A0341FA7E6ABCC8D72041894160E55A480341D122DB792FD920410AD7A370374303413108AC1C99D920411D5A643B8E440341FCA9F152F9D92041986E128301460341E17A14EE04DB2041C1CAA145D5420341CFF753E352DB204177BE9F1ADB4103417D3F355E65DB204125068195A7410341E3A59B449ADB20414C378941334103414C3789812BDC204166666666CD3F0341E5D0229B7ADC204139B4C876213F03418195438BABDC20415839B4C87F3E03416DE7FBA9D5DC20414C378941223E03418195438BF8DC2041C74B3789F13D03418195438B0DDD2041B0726891DE3D03411B2FDDA40EDD2041E3A59BC4DD3D0341D34D629037DD20412B8716D9BF3D0341448B6C6752DD2041CDCCCCCCAC3D0341FCA9F1526BDD2041333333339B3D034139B4C8F66CDD204148E17A14703D0341B4C8763E80DD2041508D976E5D3D03416DE7FB2986DD20416F1283C0573D03410681954390DD2041508D976E733D0341BE9F1AAF9EDD2041CBA145B66E3D0341E7FBA9F1ABDD20413BDF4F8D6A3D0341F2D24D62AFDD2041FED478E9913D034177BE9F9AC1DD2041C976BE9F883D0341621058393FDE2041C520B0721E3D0341FCA9F1D294DE204114AE47E1AF3C03412FDD2486EADE20411283C0CA2D3C0341
select st_astext(geom) from md_geo_obm where id = '7fde5c3d-9b0d-43b0-871d-9a17e27341e0';
MULTIPOLYGON(((552821.262 157573.724,552848 157497.563,552889.547 157379.252,552928.404 157267.592,552970.771 157145.851,552996.999 157071.131,552998.409 157067.111,553042.889 156952.374,553075.935 156853.226,553103.636 156788.585,553155.637 156657.845,553186.51 156560.015,553194.16 156477.634,553182.882 156414.257,553113.28 156257.956,552591.063 156434.858,551539.121 156785.505,551471.166 156790.941,551367.875 156777.35,551214.739 156744.691,551079.042 156907.311,551167.271 157019.919,551212.546 156995.54,551303.096 157211.468,551341.174 157319.897,551341.406 157425.074,551182.999 157428.449,551072.34 157471.064,551070.032 157558.757,551205.255 157593.837,551300.617 157661.704,551546.653 157885.244,551756.898 158033.123,551908.368 157963.362,552087.738 157798.93,552140.556 157841.779,552188.662 157888.189,552322.465 157786.659,552361.444 157755.388,552370.684 157748.948,552397.134 157734.407,552469.753 157689.675,552509.303 157668.183,552533.772 157647.973,552554.832 157636.282,552572.272 157630.192,552582.772 157627.821,552583.322 157627.721,552603.782 157623.981,552617.202 157621.6,552629.662 157619.4,552630.482 157614.01,552640.122 157611.679,552643.082 157610.969,552648.132 157614.429,552655.342 157613.839,552661.972 157613.319,552663.692 157618.239,552672.802 157617.078,552735.612 157603.806,552778.412 157589.985,552821.262 157573.724)))
