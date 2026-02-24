-- ============================================================================
-- PART 2: Complete Revalidation Function
-- ============================================================================
-- This function performs a full topology validation for a specific version
-- of the md_geo_obm table, checking for holes, overflows, and intersections.
-- ============================================================================

CREATE OR REPLACE FUNCTION revalidate_topology(p_id_rel_geo_verzija INTEGER)
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
        INSERT INTO topoloske_vrzeli (id_rel_geo_verzija, geom)
        SELECT 
            p_id_rel_geo_verzija,
            (ST_Dump(v_holes_geom)).geom;
        
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
          AND ST_Intersects(geom, v_overflow_geom);
        
        GET DIAGNOSTICS v_overflows_count = ROW_COUNT;
    END IF;
    
    -- ========================================================================
    -- STEP 4: Find and mark INTERSECTIONS
    -- ========================================================================
    -- Reset all intersection flags for this version
    UPDATE md_geo_obm
    SET intersecting = FALSE
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija;
    
    -- Find all pairs of intersecting geometries
    -- Use a.id < b.id to avoid checking each pair twice
    WITH intersecting_pairs AS (
        SELECT DISTINCT a.id as id_a, b.id as id_b
        FROM md_geo_obm a
        JOIN md_geo_obm b ON a.id_rel_geo_verzija = b.id_rel_geo_verzija
        WHERE a.id_rel_geo_verzija = p_id_rel_geo_verzija
          AND a.id < b.id
          AND ST_Overlaps(a.geom, b.geom)
    ),
    all_intersecting_ids AS (
        SELECT id_a as id FROM intersecting_pairs
        UNION
        SELECT id_b as id FROM intersecting_pairs
    )
    UPDATE md_geo_obm
    SET intersecting = TRUE
    FROM all_intersecting_ids
    WHERE md_geo_obm.id = all_intersecting_ids.id;
    
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
    id_rel_geo_verzija INTEGER,
    holes_found INTEGER,
    overflows_found INTEGER,
    intersections_found INTEGER,
    total_entries INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_version INTEGER;
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
-- SELECT * FROM revalidate_topology(1);

-- Example 2: Revalidate all versions
-- SELECT * FROM revalidate_all_topologies();

-- Example 3: View holes for a specific version
-- SELECT id, id_rel_geo_verzija, ST_Area(geom) as hole_area
-- FROM topoloske_vrzeli
-- WHERE id_rel_geo_verzija = 1;

-- Example 4: View entries with problems for a specific version
-- SELECT id, intersecting, overflowing, ST_Area(geom) as area
-- FROM md_geo_obm
-- WHERE id_rel_geo_verzija = 1
--   AND (intersecting = TRUE OR overflowing = TRUE)
-- ORDER BY id;

-- Example 5: Get summary statistics for a version
-- SELECT 
--     COUNT(*) as total_entries,
--     COUNT(*) FILTER (WHERE intersecting) as intersecting_count,
--     COUNT(*) FILTER (WHERE overflowing) as overflowing_count,
--     (SELECT COUNT(*) FROM topoloske_vrzeli WHERE id_rel_geo_verzija = 1) as holes_count
-- FROM md_geo_obm
-- WHERE id_rel_geo_verzija = 1;
