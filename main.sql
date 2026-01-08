-- ============================================================================
-- PART 1: Incremental Validation Trigger (REFACTORED)
-- ============================================================================
-- Simplified structure:
-- - DELETE/UPDATE: Process removal of OLD geometry
-- - INSERT/UPDATE: Process addition of NEW geometry
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_topology_incremental()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_slo_meja geometry;
    v_overflow_geom geometry;
    v_hole_geom geometry;
    v_intersecting_ids UUID[];
    v_id_rel_geo_verzija UUID;
    v_step_time timestamp;

BEGIN
    v_step_time := clock_timestamp();
    -- Get Slovenia boundary
    SELECT geom INTO v_slo_meja FROM slo_meja LIMIT 1;

    IF v_slo_meja IS NULL THEN
        RAISE EXCEPTION 'Slovenia boundary (slo_meja) not found';
    END IF;

    RAISE NOTICE 'step 1', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
    v_step_time := clock_timestamp();

    -- ========================================================================
    -- PHASE 1: HANDLE REMOVAL (DELETE or UPDATE)
    -- ========================================================================
    IF (TG_OP = 'DELETE' OR TG_OP = 'UPDATE') THEN
        v_id_rel_geo_verzija := OLD.id_rel_geo_verzija;

        -- --------------------------------------------------------------------
        -- Check if removal creates a HOLE
        -- --------------------------------------------------------------------
        -- Start with the removed geometry as potential hole
        v_hole_geom := OLD.geom;

        -- Remove all remaining geometries from this potential hole
        SELECT ST_Difference(
            v_hole_geom,
            COALESCE(ST_Union(geom), ST_GeomFromText('GEOMETRYCOLLECTION EMPTY'))
        )
        INTO v_hole_geom
        FROM md_geo_obm
        WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
          AND id != OLD.id
          AND geom IS NOT NULL;

        RAISE NOTICE 'step 2', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
        v_step_time := clock_timestamp();

        -- Ensure the hole is within Slovenia
        v_hole_geom := ST_Intersection(v_hole_geom, v_slo_meja);

        RAISE NOTICE 'step 3', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
        v_step_time := clock_timestamp();

        -- Process the hole if it exists
        IF v_hole_geom IS NOT NULL AND NOT ST_IsEmpty(v_hole_geom) THEN
            -- Find and merge with overlapping existing holes
            WITH overlapping_holes AS (
                SELECT geom
                FROM topoloske_vrzeli
                WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
                  AND ST_Intersects(geom, v_hole_geom)
            )
            SELECT ST_Union(ST_Union(geom), v_hole_geom)
            INTO v_hole_geom
            FROM overlapping_holes;

            RAISE NOTICE 'step 4', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
            v_step_time := clock_timestamp();

            -- Delete overlapping holes (we'll insert the merged one)
            DELETE FROM topoloske_vrzeli
            WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
              AND ST_Intersects(geom, OLD.geom);

            RAISE NOTICE 'step 5', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
            v_step_time := clock_timestamp();

            -- Insert the merged hole(s)
            IF v_hole_geom IS NOT NULL AND NOT ST_IsEmpty(v_hole_geom) THEN
                INSERT INTO topoloske_vrzeli (id_rel_geo_verzija, geom)
                SELECT v_id_rel_geo_verzija, (ST_Dump(v_hole_geom)).geom;
            END IF;
        END IF;

        RAISE NOTICE 'step 6', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
        v_step_time := clock_timestamp();

        -- --------------------------------------------------------------------
        -- Update INTERSECTION flags for previously intersecting geometries
        -- --------------------------------------------------------------------
        IF OLD.intersecting THEN
            -- Find geometries that were intersecting with the removed one
            SELECT ARRAY_AGG(id) INTO v_intersecting_ids
            FROM md_geo_obm
            WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
              AND id != OLD.id
              AND ST_Intersects(geom, OLD.geom)
              AND NOT ST_Touches(geom, OLD.geom);

            -- For each previously intersecting geometry, check if it still intersects anything
            IF v_intersecting_ids IS NOT NULL THEN
                UPDATE md_geo_obm m
                SET intersecting = EXISTS (
                    SELECT 1
                    FROM md_geo_obm m2
                    WHERE m2.id_rel_geo_verzija = v_id_rel_geo_verzija
                      AND m2.id != m.id
                      AND ST_Intersects(m.geom, m2.geom)
                      AND NOT ST_Touches(m.geom, m2.geom)
                )
                WHERE m.id = ANY(v_intersecting_ids);
            END IF;
        END IF;
    END IF;




    -- ========================================================================
    -- PHASE 2: HANDLE ADDITION (INSERT or UPDATE)
    -- ========================================================================
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
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
          AND ST_Intersects(geom, NEW.geom)
          AND NOT ST_Touches(geom, NEW.geom);

        IF v_intersecting_ids IS NOT NULL AND array_length(v_intersecting_ids, 1) > 0 THEN
            NEW.intersecting := TRUE;

            -- Mark the intersecting geometries as well
            UPDATE md_geo_obm
            SET intersecting = TRUE
            WHERE id = ANY(v_intersecting_ids);
        END IF;





        -- Why not just find all the ones that intersect what we are adding,
        -- then calculate the difference for them and if the diff is 0 delete them,
        -- and otherwise just change their geometry
        DROP TABLE IF EXISTS holes_to_update;
        CREATE TEMP TABLE holes_to_update (
            id UUID,
            reduced_geom geometry
        ) ON COMMIT DROP;

        INSERT INTO holes_to_update
        SELECT
            id,
            (ST_Dump(ST_Difference(geom, NEW.geom))).geom AS reduced_geom
        FROM topoloske_vrzeli
        WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
          AND ST_Intersects(geom, NEW.geom) AND NOT st_touches(geom, NEW.geom);

        -- - If completely covered: delete them
        DELETE FROM topoloske_vrzeli
            WHERE id in (
                SELECT id
                FROM holes_to_update h
                WHERE ST_IsEmpty(h.reduced_geom)  --very fast op
            );



        -- - If partially covered: replace with reduced geometry
        -- (may get multipolygon from polygon - could potentially split into multiple with ST_Dump)
        -- Update holes that remain as single polygons
        UPDATE topoloske_vrzeli t
        SET geom = h.reduced_geom
        FROM holes_to_update h
        WHERE t.id = h.id
          AND NOT ST_IsEmpty(h.reduced_geom)
          AND ST_NumGeometries(h.reduced_geom) = 1;  -- Single polygon

        -- Delete holes that split into multiple
        DELETE FROM topoloske_vrzeli
        WHERE id IN (
            SELECT id
            FROM holes_to_update
            WHERE NOT ST_IsEmpty(reduced_geom)
              AND ST_NumGeometries(reduced_geom) > 1
        );

        -- Insert the split holes
        INSERT INTO topoloske_vrzeli (
            id_rel_geo_verzija,
            geom,
            perimeter,
            area,
            area_type,
            created_by,
            id,
            created_at
        )
        SELECT
            v_id_rel_geo_verzija,
            hole_geom,
            ST_Perimeter(hole_geom),
            ST_Area(hole_geom),
            'obm',
            '848956e8-d73e-11f0-9ff0-02420a000f64',
            uuid_generate_v4(),
            now()::timestamp
        FROM holes_to_update,
        LATERAL (SELECT (ST_Dump(reduced_geom)).geom AS hole_geom) AS dump
        WHERE NOT ST_IsEmpty(reduced_geom)
          AND ST_NumGeometries(reduced_geom) > 1;



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
    BEFORE INSERT OR UPDATE OR DELETE ON md_geo_obm
    FOR EACH ROW
    EXECUTE FUNCTION validate_topology_incremental();

select * from md_geo_obm where id = 'f68b2b55-1d3f-4693-9a39-25abdc7f3f5c';








select * from md_geo_obm where id = '7fde5c3d-9b0d-43b0-871d-9a17e27341e0';
0106000020D20E0000010000000103000000010000003E0000002FDD2486EADE20411283C0CA2D3C03410000000020DF2041DD240681CC3903414E62101873DF2041759318041A3603418716D9CEC0DF2041FA7E6ABC9C3203411283C08A15E020418716D9CECE2E034191ED7CFF49E020415EBA490C792C0341B07268D14CE02041CFF753E3582C03410C022BC7A5E0204146B6F3FDC2280341EC51B8DEE7E020418716D9CEA9250341C1CAA1451FE12041E17A14AEA42303412FDD244687E12041295C8FC28E1F034152B81E05C5E12041EC51B81E801C03411F85EB51D4E120418D976E12ED190341068195C3BDE120411904560EF2170341F6285C8F32E12041F853E3A50F130341378941201EDD2041A01A2FDD9618034146B6F33DE6D42041A4703D0A8C230341B6F3FD545ED420410C022B87B7230341000000C08FD32041CDCCCCCC4A2303413F355E7A5DD220410C022B8745220341250681154ED120416891ED7C5A2703411283C08AFED1204108AC1C5ADF2A0341DF4F8D1759D220411F85EB511C2A034179E926310ED32041B4C876BEDB3003412B8716595AD3204104560E2D3F340341643BDFCF5AD32041DF4F8D978837034191ED7CFF1DD22041DF4F8D97A3370341E17A14AE40D12041986E1283F8380341D34D62103CD120411904560EB63B0341295C8F824AD22041560E2DB2CE3C03418B6CE73B09D3204183C0CAA1ED3E03411904564EF5D42041A245B6F3E9450341F0A7C6CB99D620418B6CE7FB884A0341FA7E6ABCC8D72041894160E55A480341D122DB792FD920410AD7A370374303413108AC1C99D920411D5A643B8E440341FCA9F152F9D92041986E128301460341E17A14EE04DB2041C1CAA145D5420341CFF753E352DB204177BE9F1ADB4103417D3F355E65DB204125068195A7410341E3A59B449ADB20414C378941334103414C3789812BDC204166666666CD3F0341E5D0229B7ADC204139B4C876213F03418195438BABDC20415839B4C87F3E03416DE7FBA9D5DC20414C378941223E03418195438BF8DC2041C74B3789F13D03418195438B0DDD2041B0726891DE3D03411B2FDDA40EDD2041E3A59BC4DD3D0341D34D629037DD20412B8716D9BF3D0341448B6C6752DD2041CDCCCCCCAC3D0341FCA9F1526BDD2041333333339B3D034139B4C8F66CDD204148E17A14703D0341B4C8763E80DD2041508D976E5D3D03416DE7FB2986DD20416F1283C0573D03410681954390DD2041508D976E733D0341BE9F1AAF9EDD2041CBA145B66E3D0341E7FBA9F1ABDD20413BDF4F8D6A3D0341F2D24D62AFDD2041FED478E9913D034177BE9F9AC1DD2041C976BE9F883D0341621058393FDE2041C520B0721E3D0341FCA9F1D294DE204114AE47E1AF3C03412FDD2486EADE20411283C0CA2D3C0341
select st_astext(geom) from md_geo_obm where id = '7fde5c3d-9b0d-43b0-871d-9a17e27341e0';
MULTIPOLYGON(((552821.262 157573.724,552848 157497.563,552889.547 157379.252,552928.404 157267.592,552970.771 157145.851,552996.999 157071.131,552998.409 157067.111,553042.889 156952.374,553075.935 156853.226,553103.636 156788.585,553155.637 156657.845,553186.51 156560.015,553194.16 156477.634,553182.882 156414.257,553113.28 156257.956,552591.063 156434.858,551539.121 156785.505,551471.166 156790.941,551367.875 156777.35,551214.739 156744.691,551079.042 156907.311,551167.271 157019.919,551212.546 156995.54,551303.096 157211.468,551341.174 157319.897,551341.406 157425.074,551182.999 157428.449,551072.34 157471.064,551070.032 157558.757,551205.255 157593.837,551300.617 157661.704,551546.653 157885.244,551756.898 158033.123,551908.368 157963.362,552087.738 157798.93,552140.556 157841.779,552188.662 157888.189,552322.465 157786.659,552361.444 157755.388,552370.684 157748.948,552397.134 157734.407,552469.753 157689.675,552509.303 157668.183,552533.772 157647.973,552554.832 157636.282,552572.272 157630.192,552582.772 157627.821,552583.322 157627.721,552603.782 157623.981,552617.202 157621.6,552629.662 157619.4,552630.482 157614.01,552640.122 157611.679,552643.082 157610.969,552648.132 157614.429,552655.342 157613.839,552661.972 157613.319,552663.692 157618.239,552672.802 157617.078,552735.612 157603.806,552778.412 157589.985,552821.262 157573.724)))

After change:
0106000020D20E0000010000000103000000010000003E00000052B81E85EADE2041295C8FC22D3C03410000000020DF2041AE47E17ACC3903419A99991973DF2041000000001A360341CDCCCCCCC0DF204185EB51B89C320341A4703D8A15E02041CDCCCCCCCE2E0341000000004AE02041A4703D0A792C03411F85EBD14CE0204115AE47E1582C03417B14AEC7A5E020415C8FC2F5C228034115AE47E1E7E02041713D0AD7A92503417B14AE471FE1204185EB51B8A42303417B14AE4787E12041CDCCCCCC8E1F034152B81E05C5E120418FC2F528801C03411F85EB51D4E12041A4703D0AED190341295C8FC2BDE1204148E17A14F2170341F6285C8F32E12041E17A14AE0F130341EC51B81E1EDD204115AE47E196180341D7A3703DE6D4204148E17A148C230341713D0A575ED4204152B81E85B7230341295C8FC28FD32041CDCCCCCC4A230341AE47E17A5DD2204152B81E854522034148E17A144ED12041AE47E17A5A270341A4703D8AFED12041C3F5285CDF2A03419A99991959D220411F85EB511C2A0341333333330ED32041295C8FC2DB300341713D0A575AD32041333333333F3403411F85EBD15AD32041F6285C8F88370341000000001ED220419A999999A3370341E17A14AE40D12041AE47E17AF8380341F6285C0F3CD1204148E17A14B63B034152B81E854AD2204185EB51B8CE3C0341D7A3703D09D320419A999999ED3E0341CDCCCC4CF5D42041B81E85EBE94503415C8FC275B2D6204115AE47E186430341D7A370BDC8D7204115AE47E15A480341AE47E17A2FD920410AD7A37037430341EC51B81E99D92041D7A3703D8E4403411F85EB51F9D9204152B81E85014603410AD7A3F004DB20417B14AE47D542034115AE47E152DB2041EC51B81EDB410341C3F5285C65DB20419A999999A7410341295C8F429ADB20417B14AE4733410341000000802BDC2041C3F5285CCD3F03419A9999997ADC20410AD7A370213F0341A4703D8AABDC2041295C8FC27F3E03418FC2F5A8D5DC2041D7A3703D223E0341A4703D8AF8DC204152B81E85F13D0341A4703D8A0DDD2041F6285C8FDE3D03413E0AD7A30EDD2041295C8FC2DD3D0341F6285C8F37DD2041713D0AD7BF3D03416666666652DD2041CDCCCCCCAC3D03411F85EB516BDD2041333333339B3D03415C8FC2F56CDD204148E17A14703D0341D7A3703D80DD20410AD7A3705D3D03418FC2F52886DD2041295C8FC2573D0341295C8F4290DD20410AD7A370733D0341E17A14AE9EDD204185EB51B86E3D03410AD7A3F0ABDD2041F6285C8F6A3D034115AE4761AFDD2041B81E85EB913D03419A999999C1DD20413E0AD7A3883D034185EB51383FDE2041AE47E17A1E3D03411F85EBD194DE2041713D0AD7AF3C034152B81E85EADE2041295C8FC22D3C0341

original:
UPDATE md_geo_obm
SET geom = '0106000020D20E0000010000000103000000010000003E0000002FDD2486EADE20411283C0CA2D3C03410000000020DF2041DD240681CC3903414E62101873DF2041759318041A3603418716D9CEC0DF2041FA7E6ABC9C3203411283C08A15E020418716D9CECE2E034191ED7CFF49E020415EBA490C792C0341B07268D14CE02041CFF753E3582C03410C022BC7A5E0204146B6F3FDC2280341EC51B8DEE7E020418716D9CEA9250341C1CAA1451FE12041E17A14AEA42303412FDD244687E12041295C8FC28E1F034152B81E05C5E12041EC51B81E801C03411F85EB51D4E120418D976E12ED190341068195C3BDE120411904560EF2170341F6285C8F32E12041F853E3A50F130341378941201EDD2041A01A2FDD9618034146B6F33DE6D42041A4703D0A8C230341B6F3FD545ED420410C022B87B7230341000000C08FD32041CDCCCCCC4A2303413F355E7A5DD220410C022B8745220341250681154ED120416891ED7C5A2703411283C08AFED1204108AC1C5ADF2A0341DF4F8D1759D220411F85EB511C2A034179E926310ED32041B4C876BEDB3003412B8716595AD3204104560E2D3F340341643BDFCF5AD32041DF4F8D978837034191ED7CFF1DD22041DF4F8D97A3370341E17A14AE40D12041986E1283F8380341D34D62103CD120411904560EB63B0341295C8F824AD22041560E2DB2CE3C03418B6CE73B09D3204183C0CAA1ED3E03411904564EF5D42041A245B6F3E9450341F0A7C6CB99D620418B6CE7FB884A0341FA7E6ABCC8D72041894160E55A480341D122DB792FD920410AD7A370374303413108AC1C99D920411D5A643B8E440341FCA9F152F9D92041986E128301460341E17A14EE04DB2041C1CAA145D5420341CFF753E352DB204177BE9F1ADB4103417D3F355E65DB204125068195A7410341E3A59B449ADB20414C378941334103414C3789812BDC204166666666CD3F0341E5D0229B7ADC204139B4C876213F03418195438BABDC20415839B4C87F3E03416DE7FBA9D5DC20414C378941223E03418195438BF8DC2041C74B3789F13D03418195438B0DDD2041B0726891DE3D03411B2FDDA40EDD2041E3A59BC4DD3D0341D34D629037DD20412B8716D9BF3D0341448B6C6752DD2041CDCCCCCCAC3D0341FCA9F1526BDD2041333333339B3D034139B4C8F66CDD204148E17A14703D0341B4C8763E80DD2041508D976E5D3D03416DE7FB2986DD20416F1283C0573D03410681954390DD2041508D976E733D0341BE9F1AAF9EDD2041CBA145B66E3D0341E7FBA9F1ABDD20413BDF4F8D6A3D0341F2D24D62AFDD2041FED478E9913D034177BE9F9AC1DD2041C976BE9F883D0341621058393FDE2041C520B0721E3D0341FCA9F1D294DE204114AE47E1AF3C03412FDD2486EADE20411283C0CA2D3C0341'
where id = '7fde5c3d-9b0d-43b0-871d-9a17e27341e0';


to new:
UPDATE md_geo_obm
SET geom = '0106000020D20E0000010000000103000000010000003E00000052B81E85EADE2041295C8FC22D3C03410000000020DF2041AE47E17ACC3903419A99991973DF2041000000001A360341CDCCCCCCC0DF204185EB51B89C320341A4703D8A15E02041CDCCCCCCCE2E0341000000004AE02041A4703D0A792C03411F85EBD14CE0204115AE47E1582C03417B14AEC7A5E020415C8FC2F5C228034115AE47E1E7E02041713D0AD7A92503417B14AE471FE1204185EB51B8A42303417B14AE4787E12041CDCCCCCC8E1F034152B81E05C5E120418FC2F528801C03411F85EB51D4E12041A4703D0AED190341295C8FC2BDE1204148E17A14F2170341F6285C8F32E12041E17A14AE0F130341EC51B81E1EDD204115AE47E196180341D7A3703DE6D4204148E17A148C230341713D0A575ED4204152B81E85B7230341295C8FC28FD32041CDCCCCCC4A230341AE47E17A5DD2204152B81E854522034148E17A144ED12041AE47E17A5A270341A4703D8AFED12041C3F5285CDF2A03419A99991959D220411F85EB511C2A0341333333330ED32041295C8FC2DB300341713D0A575AD32041333333333F3403411F85EBD15AD32041F6285C8F88370341000000001ED220419A999999A3370341E17A14AE40D12041AE47E17AF8380341F6285C0F3CD1204148E17A14B63B034152B81E854AD2204185EB51B8CE3C0341D7A3703D09D320419A999999ED3E0341CDCCCC4CF5D42041B81E85EBE94503415C8FC275B2D6204115AE47E186430341D7A370BDC8D7204115AE47E15A480341AE47E17A2FD920410AD7A37037430341EC51B81E99D92041D7A3703D8E4403411F85EB51F9D9204152B81E85014603410AD7A3F004DB20417B14AE47D542034115AE47E152DB2041EC51B81EDB410341C3F5285C65DB20419A999999A7410341295C8F429ADB20417B14AE4733410341000000802BDC2041C3F5285CCD3F03419A9999997ADC20410AD7A370213F0341A4703D8AABDC2041295C8FC27F3E03418FC2F5A8D5DC2041D7A3703D223E0341A4703D8AF8DC204152B81E85F13D0341A4703D8A0DDD2041F6285C8FDE3D03413E0AD7A30EDD2041295C8FC2DD3D0341F6285C8F37DD2041713D0AD7BF3D03416666666652DD2041CDCCCCCCAC3D03411F85EB516BDD2041333333339B3D03415C8FC2F56CDD204148E17A14703D0341D7A3703D80DD20410AD7A3705D3D03418FC2F52886DD2041295C8FC2573D0341295C8F4290DD20410AD7A370733D0341E17A14AE9EDD204185EB51B86E3D03410AD7A3F0ABDD2041F6285C8F6A3D034115AE4761AFDD2041B81E85EB913D03419A999999C1DD20413E0AD7A3883D034185EB51383FDE2041AE47E17A1E3D03411F85EBD194DE2041713D0AD7AF3C034152B81E85EADE2041295C8FC22D3C0341'
where id = '7fde5c3d-9b0d-43b0-871d-9a17e27341e0';



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



































-- ============================================================================
-- PART 2: Complete Revalidation Function
-- ============================================================================
-- This function performs a full topology validation for a specific version
-- of the md_geo_obm table, checking for holes, overflows, and intersections.
-- ============================================================================

CREATE OR REPLACE FUNCTION revalidate_topology(p_id_rel_geo_verzija uuid)
RETURNS TABLE(
    holes_found INTEGER,
    overflows_found INTEGER,
    intersections_found INTEGER,
    total_entries INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_slo_meja geometry;
    v_union_geom geometry;
    v_overflow_geom geometry;
    v_holes_geom geometry;
    v_holes_count INTEGER := 0;
    v_overflows_count INTEGER := 0;
    v_intersections_count INTEGER := 0;
    v_total_count INTEGER := 0;
BEGIN
    -- Get Slovenia boundary
    SELECT geom INTO v_slo_meja FROM slo_meja LIMIT 1;

    IF v_slo_meja IS NULL THEN
        RAISE EXCEPTION 'Slovenia boundary (slo_meja) not found';
    END IF;

    -- Get count of entries for this version
    SELECT COUNT(*) INTO v_total_count
    FROM md_geo_obm
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija;

    IF v_total_count = 0 THEN
        RAISE NOTICE 'No entries found for version %', p_id_rel_geo_verzija;
        RETURN QUERY SELECT 0, 0, 0, 0;
        RETURN;
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
    DELETE FROM topoloske_vrzeli
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija;

    -- Insert new holes if they exist
    IF v_holes_geom IS NOT NULL AND NOT ST_IsEmpty(v_holes_geom) THEN
        -- Handle multipolygon case - insert each polygon separately
       INSERT INTO topoloske_vrzeli (id_rel_geo_verzija, geom, perimeter, area, area_type, created_by, id, created_at)
        SELECT
            p_id_rel_geo_verzija,
            geom,
            perimeter,
            area,
--             0, -- area / (perimeter * perimeter) as compactness,    -- (circle has it 0.08 (1/4*pi) and is most compact. Everything else is less compact.)
            'obm',
            '848956e8-d73e-11f0-9ff0-02420a000f64',
            uuid_generate_v4(),
            now()::timestamp
        FROM (
            SELECT
                (dump_result).geom as geom,
--                 ST_Perimeter((dump_result).geom) as perimeter,
                -1 AS perimeter,
                ST_Area((dump_result).geom) as area
            FROM (
                SELECT ST_Dump(v_holes_geom) AS dump_result
            ) AS dumps
        ) AS calculated
        WHERE area >= 1000;

        GET DIAGNOSTICS v_holes_count = ROW_COUNT;
    END IF;

    -- ========================================================================
    -- STEP 3: Find and mark OVERFLOWS
    -- ========================================================================
    -- Overflow = areas that extend beyond Slovenia boundary
    v_overflow_geom := ST_Difference(v_union_geom, v_slo_meja);

    -- Reset all overflow flags for this version
    UPDATE md_geo_obm
    SET overflowing = FALSE
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija;

    -- Mark entries that overflow Slovenia boundary
    IF v_overflow_geom IS NOT NULL AND NOT ST_IsEmpty(v_overflow_geom) THEN
        UPDATE md_geo_obm
        SET overflowing = TRUE
        WHERE id_rel_geo_verzija = p_id_rel_geo_verzija
--           AND ST_Intersects(geom, v_overflow_geom);
            AND ST_Area(ST_Intersection(geom, v_overflow_geom)) > 1000;

        GET DIAGNOSTICS v_overflows_count = ROW_COUNT;
    END IF;

    -- ========================================================================
    -- STEP 4: Find and mark INTERSECTIONS
    -- ========================================================================
    -- Reset all intersection flags for this version
--     UPDATE md_geo_obm
--     SET intersecting = FALSE
--     WHERE id_rel_geo_verzija = p_id_rel_geo_verzija;
--
--     -- Find all pairs of intersecting geometries
--     -- Use a.id < b.id to avoid checking each pair twice
--     WITH intersecting_pairs AS (
--         SELECT DISTINCT a.id as id_a, b.id as id_b
--         FROM md_geo_obm a
--         JOIN md_geo_obm b ON a.id_rel_geo_verzija = b.id_rel_geo_verzija
--         WHERE a.id_rel_geo_verzija = p_id_rel_geo_verzija
--           AND a.id < b.id
--           AND ST_Intersects(a.geom, b.geom)
--           AND NOT ST_Touches(b.geom, b.geom);
--     ),
--     all_intersecting_ids AS (
--         SELECT id_a as id FROM intersecting_pairs
--         UNION
--         SELECT id_b as id FROM intersecting_pairs
--     )
--     UPDATE md_geo_obm
--     SET intersecting = TRUE
--     FROM all_intersecting_ids
--     WHERE md_geo_obm.id = all_intersecting_ids.id;

    GET DIAGNOSTICS v_intersections_count = ROW_COUNT;

    -- ========================================================================
    -- Return summary statistics
    -- ========================================================================
    RETURN QUERY SELECT
        v_holes_count,
        v_overflows_count,
        v_intersections_count,
        v_total_count;
END;
$$;






-- ============================================================================
-- Helper function to revalidate ALL versions
-- ============================================================================
CREATE OR REPLACE FUNCTION revalidate_all_topologies()
RETURNS TABLE(
    id_rel_geo_verzija uuid,
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
        SELECT v_version, *
        FROM revalidate_topology(v_version);
    END LOOP;
END;
$$;

-- ============================================================================
-- Usage examples and testing queries
-- ============================================================================

-- Example 1: Revalidate a specific version
SELECT * FROM revalidate_topology('20a6ad30-8457-41c9-8fbd-5423c15dae9b'::uuid);

SELECT * FROM revalidate_topology('2647f13d-faea-4f37-9309-3ab8639457f1'::uuid);


-- Example 2: Revalidate all versions
SELECT * FROM revalidate_all_topologies();




The run without areas and perimeters does sth like 40 sec.
The new one needs like 4 min.


05c23679-1f97-403e-9344-ba65b20a9d9b,2,10,10,125
08958afb-4360-438d-af25-9b0f5af57681,2,10,10,132
20a6ad30-8457-41c9-8fbd-5423c15dae9b,2,18,18,233
2647f13d-faea-4f37-9309-3ab8639457f1,2,18,18,238
6045e8e5-abc6-4ab1-a6cf-886637c2f944,2,10,10,227
68e3a6de-6685-4820-8358-95ad7b13f0fd,2,10,10,132
701d04d0-b9eb-4fa0-b54b-1069bb8b0c16,2,18,18,236
99d0e803-9ff2-40e3-822b-995289ee60d6,2,33,33,1042
9d8bf0cc-beab-43da-bded-14f9bfa80684,2,23,23,458


































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