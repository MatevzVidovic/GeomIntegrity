

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
    v_joined_hole geometry;
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

    RAISE NOTICE 'step 1 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
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

        SELECT ST_Difference(
            v_hole_geom, (
                SELECT ST_Union(geom)
                FROM md_geo_obm
                WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
                    AND id != OLD.id
                    AND geom IS NOT NULL
--                     AND geom && v_hole_geom  -- Fast bbox check. Because v_hole_geom is a variable, planner might not use it otherwise.
                    AND ST_Intersects(geom, v_hole_geom)
            )
        ) INTO v_hole_geom;


        RAISE NOTICE 'step 2 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
        v_step_time := clock_timestamp();

        -- Ensure the hole is within Slovenia
        v_hole_geom := ST_Intersection(v_hole_geom, v_slo_meja);

        RAISE NOTICE 'step 3 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
        v_step_time := clock_timestamp();

        -- Process the hole if it exists
        IF v_hole_geom IS NOT NULL AND NOT ST_IsEmpty(v_hole_geom) THEN

            DROP TABLE IF EXISTS joining_holes;
            CREATE TEMP TABLE joining_holes

            -- Find and merge with overlapping existing holes
            WITH overlapping_holes AS (
                SELECT geom
                FROM topoloske_vrzeli
                WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
                  AND ST_Intersects(geom, v_hole_geom)
            )
            SELECT ST_Union(ST_Union(geom), v_hole_geom)
            INTO v_joined_hole
            FROM overlapping_holes;

            RAISE NOTICE 'step 4 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
            v_step_time := clock_timestamp();

            -- Delete overlapping holes (we'll insert the merged one)
            DELETE FROM topoloske_vrzeli
            WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
              AND ST_Intersects(geom, OLD.geom);

            RAISE NOTICE 'step 5 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
            v_step_time := clock_timestamp();

            -- Insert the merged hole(s)
            IF v_hole_geom IS NOT NULL AND NOT ST_IsEmpty(v_hole_geom) THEN
--                 INSERT INTO topoloske_vrzeli (id_rel_geo_verzija, geom)
--                 SELECT v_id_rel_geo_verzija, (ST_Dump(v_hole_geom)).geom;

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
                    -1,
                    ST_Area(hole_geom),
                    'obm',
                    '848956e8-d73e-11f0-9ff0-02420a000f64',
                    uuid_generate_v4(),
                    now()::timestamp
                FROM (SELECT (ST_Dump(v_hole_geom)).geom AS hole_geom) AS dump;


            END IF;
        END IF;

        RAISE NOTICE 'step 6 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
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

            RAISE NOTICE 'step 7 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
            v_step_time := clock_timestamp();

            -- For each previously intersecting geometry, check if it still intersects anything
--             IF v_intersecting_ids IS NOT NULL THEN
--                 UPDATE md_geo_obm m
--                 SET intersecting = EXISTS (
--                     SELECT 1
--                     FROM md_geo_obm m2
--                     WHERE m2.id_rel_geo_verzija = v_id_rel_geo_verzija
--                       AND m2.id != m.id
--                       AND ST_Intersects(m.geom, m2.geom)
--                       AND NOT ST_Touches(m.geom, m2.geom)
--                 )
--                 WHERE m.id = ANY(v_intersecting_ids);
--                 END IF;

        END IF;
    END IF;


    RAISE NOTICE 'step 8 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
    v_step_time := clock_timestamp();

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

        RAISE NOTICE 'step 9 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
        v_step_time := clock_timestamp();

        IF v_intersecting_ids IS NOT NULL AND array_length(v_intersecting_ids, 1) > 0 THEN
            NEW.intersecting := TRUE;

            -- Mark the intersecting geometries as well
            UPDATE md_geo_obm
            SET intersecting = TRUE
            WHERE id = ANY(v_intersecting_ids);

            RAISE NOTICE 'step 10 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
            v_step_time := clock_timestamp();

        END IF;





        -- Why not just find all the ones that intersect what we are adding,
        -- then calculate the difference for them and if the diff is 0 delete them,
        -- and otherwise just change their geometry
        DROP TABLE IF EXISTS holes_to_update;
        CREATE TEMP TABLE holes_to_update (
            id UUID,
            reduced_geom geometry
        ) ON COMMIT DROP;

        RAISE NOTICE 'step 11 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
        v_step_time := clock_timestamp();

        INSERT INTO holes_to_update
        SELECT
            id,
            (ST_Dump(ST_Difference(geom, NEW.geom))).geom AS reduced_geom
        FROM topoloske_vrzeli
        WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
          AND ST_Intersects(geom, NEW.geom) AND NOT st_touches(geom, NEW.geom);


        RAISE NOTICE 'step 12 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
        v_step_time := clock_timestamp();

        -- - If completely covered: delete them
        DELETE FROM topoloske_vrzeli
            WHERE id in (
                SELECT id
                FROM holes_to_update h
                WHERE ST_IsEmpty(h.reduced_geom)  --very fast op
            );

        RAISE NOTICE 'step 13 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
        v_step_time := clock_timestamp();



        -- - If partially covered: replace with reduced geometry
        -- (may get multipolygon from polygon - could potentially split into multiple with ST_Dump)


        -- Update holes that remain as single polygons
        UPDATE topoloske_vrzeli t
        SET geom = h.reduced_geom
        FROM holes_to_update h
        WHERE t.id = h.id
          AND NOT ST_IsEmpty(h.reduced_geom)
          AND ST_NumGeometries(h.reduced_geom) = 1;  -- Single polygon

        RAISE NOTICE 'step 14 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
        v_step_time := clock_timestamp();

        -- Delete holes that split into multiple
        DELETE FROM topoloske_vrzeli
        WHERE id IN (
            SELECT id
            FROM holes_to_update
            WHERE NOT ST_IsEmpty(reduced_geom)
              AND ST_NumGeometries(reduced_geom) > 1
        );

        RAISE NOTICE 'step 15 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
        v_step_time := clock_timestamp();

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
            -1, -- ST_Perimeter(hole_geom),
            ST_Area(hole_geom),
            'obm',
            '848956e8-d73e-11f0-9ff0-02420a000f64',
            uuid_generate_v4(),
            now()::timestamp
        FROM holes_to_update,
        LATERAL (SELECT (ST_Dump(reduced_geom)).geom AS hole_geom) AS dump
        WHERE NOT ST_IsEmpty(reduced_geom)
          AND ST_NumGeometries(reduced_geom) > 1;


        RAISE NOTICE 'step 16 % ms', EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_step_time));
        v_step_time := clock_timestamp();



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















CREATE INDEX idx_topoloske_kontrole ON md_topoloske_kontrole (area_type, id_rel_geo_verzija, id_rel_verzije_modela, topology_problem_type, id1, id2);

ALTER TABLE md_topoloske_kontrole
ADD CONSTRAINT check_area_type
CHECK (area_type IN ('obm', 'cona'));

ALTER TABLE md_topoloske_kontrole
ADD CONSTRAINT check_topology_problem_type
CHECK (topology_problem_type IN ('intersection', 'hole', 'overflow'));

-- Allow NULL but enforce constraint when both are present
ALTER TABLE md_topoloske_kontrole
ADD CONSTRAINT check_id1_less_than_id2
CHECK (id2 IS NULL OR (id1 IS NOT NULL AND id1 < id2));




















