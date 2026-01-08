-- ============================================================================
-- TOPOLOGY VALIDATION SYSTEM - TESTING & USAGE GUIDE
-- ============================================================================

-- ============================================================================
-- SETUP VERIFICATION
-- ============================================================================

-- 1. Verify tables exist
SELECT 
    schemaname, tablename, tableowner
FROM pg_tables
WHERE tablename IN ('md_geo_obm', 'topoloske_vrzeli', 'slo_meja')
ORDER BY tablename;

-- 2. Verify table structures
\d md_geo_obm
\d topoloske_vrzeli
\d slo_meja

-- 3. Verify functions exist
SELECT 
    proname as function_name,
    pg_get_function_arguments(oid) as arguments
FROM pg_proc
WHERE proname IN ('revalidate_topology', 'revalidate_all_topologies', 'validate_topology_incremental')
ORDER BY proname;

-- 4. Verify trigger exists
SELECT 
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE trigger_name = 'trg_validate_topology';

-- ============================================================================
-- INITIAL SETUP AND FULL REVALIDATION
-- ============================================================================

-- If you have existing data, run full revalidation first to establish baseline
SELECT * FROM revalidate_all_topologies();

-- Or for a specific version:
SELECT * FROM revalidate_topology(1);

-- ============================================================================
-- TEST CASE 1: SIMPLE INSERT (NO VIOLATIONS)
-- ============================================================================

-- Create a test geometry that doesn't violate any rules
DO $$
DECLARE
    v_test_geom geometry;
BEGIN
    -- Create a small polygon within Slovenia
    v_test_geom := ST_GeomFromText('POLYGON((
        461000 103000,
        462000 103000,
        462000 104000,
        461000 104000,
        461000 103000
    ))', 3794);
    
    -- Insert it
    INSERT INTO md_geo_obm (geom, id_rel_geo_verzija, intersecting, overflowing)
    VALUES (v_test_geom, 999, FALSE, FALSE);
    
    RAISE NOTICE 'Test geometry inserted';
END $$;

-- Verify the insert
SELECT 
    id,
    intersecting,
    overflowing,
    ST_Area(geom) as area,
    id_rel_geo_verzija
FROM md_geo_obm
WHERE id_rel_geo_verzija = 999;

-- Check if any holes were created (should be none for first insert)
SELECT 
    id,
    ST_Area(geom) as hole_area,
    id_rel_geo_verzija
FROM topoloske_vrzeli
WHERE id_rel_geo_verzija = 999;

-- ============================================================================
-- TEST CASE 2: INSERT WITH INTERSECTION
-- ============================================================================

-- Insert a geometry that overlaps with the previous one
DO $$
DECLARE
    v_test_geom geometry;
BEGIN
    -- Create a polygon that overlaps with the first test geometry
    v_test_geom := ST_GeomFromText('POLYGON((
        461500 103500,
        462500 103500,
        462500 104500,
        461500 104500,
        461500 103500
    ))', 3794);
    
    INSERT INTO md_geo_obm (geom, id_rel_geo_verzija, intersecting, overflowing)
    VALUES (v_test_geom, 999, FALSE, FALSE);
    
    RAISE NOTICE 'Intersecting geometry inserted';
END $$;

-- Verify both geometries are now marked as intersecting
SELECT 
    id,
    intersecting,
    overflowing,
    ST_Area(geom) as area
FROM md_geo_obm
WHERE id_rel_geo_verzija = 999
ORDER BY id;

-- ============================================================================
-- TEST CASE 3: INSERT WITH OVERFLOW
-- ============================================================================

-- Insert a geometry that extends beyond Slovenia
-- Note: You'll need to adjust coordinates based on your actual slo_meja extent
DO $$
DECLARE
    v_test_geom geometry;
    v_slo_extent geometry;
BEGIN
    -- Get Slovenia extent
    SELECT ST_Envelope(geom) INTO v_slo_extent FROM slo_meja LIMIT 1;
    
    -- Create a polygon that definitely extends beyond (using extreme coordinates)
    v_test_geom := ST_GeomFromText('POLYGON((
        800000 200000,
        900000 200000,
        900000 300000,
        800000 300000,
        800000 200000
    ))', 3794);
    
    INSERT INTO md_geo_obm (geom, id_rel_geo_verzija, intersecting, overflowing)
    VALUES (v_test_geom, 998, FALSE, FALSE);
    
    RAISE NOTICE 'Overflowing geometry inserted';
END $$;

-- Verify overflow flag is set
SELECT 
    id,
    intersecting,
    overflowing,
    ST_Area(geom) as area
FROM md_geo_obm
WHERE id_rel_geo_verzija = 998;

-- ============================================================================
-- TEST CASE 4: DELETE CREATING A HOLE
-- ============================================================================

-- First, let's create a scenario with three adjacent geometries
DO $$
DECLARE
    v_geom1 geometry;
    v_geom2 geometry;
    v_geom3 geometry;
BEGIN
    -- Three adjacent squares
    v_geom1 := ST_GeomFromText('POLYGON((
        500000 100000,
        501000 100000,
        501000 101000,
        500000 101000,
        500000 100000
    ))', 3794);
    
    v_geom2 := ST_GeomFromText('POLYGON((
        501000 100000,
        502000 100000,
        502000 101000,
        501000 101000,
        501000 100000
    ))', 3794);
    
    v_geom3 := ST_GeomFromText('POLYGON((
        502000 100000,
        503000 100000,
        503000 101000,
        502000 101000,
        502000 100000
    ))', 3794);
    
    INSERT INTO md_geo_obm (geom, id_rel_geo_verzija)
    VALUES (v_geom1, 997), (v_geom2, 997), (v_geom3, 997);
    
    RAISE NOTICE 'Three adjacent geometries inserted';
END $$;

-- Check no holes exist yet
SELECT COUNT(*) as hole_count
FROM topoloske_vrzeli
WHERE id_rel_geo_verzija = 997;

-- Delete the middle geometry
DELETE FROM md_geo_obm
WHERE id_rel_geo_verzija = 997
  AND ST_Intersects(geom, ST_GeomFromText('POINT(501500 100500)', 3794));

-- Check if a hole was created
SELECT 
    id,
    ST_Area(geom) as hole_area,
    ST_AsText(ST_Centroid(geom)) as centroid
FROM topoloske_vrzeli
WHERE id_rel_geo_verzija = 997;

-- ============================================================================
-- TEST CASE 5: UPDATE GEOMETRY
-- ============================================================================

-- Update a geometry to a new location
WITH geom_to_update AS (
    SELECT id FROM md_geo_obm WHERE id_rel_geo_verzija = 997 LIMIT 1
)
UPDATE md_geo_obm
SET geom = ST_GeomFromText('POLYGON((
    500000 102000,
    501000 102000,
    501000 103000,
    500000 103000,
    500000 102000
))', 3794)
WHERE id = (SELECT id FROM geom_to_update);

-- Verify the update and check topology
SELECT 
    id,
    intersecting,
    overflowing,
    ST_Area(geom) as area
FROM md_geo_obm
WHERE id_rel_geo_verzija = 997
ORDER BY id;

-- ============================================================================
-- COMPREHENSIVE VALIDATION QUERIES
-- ============================================================================

-- 1. Summary statistics for a version
CREATE OR REPLACE VIEW v_topology_summary AS
SELECT 
    v.id_rel_geo_verzija,
    COUNT(*) as total_geometries,
    COUNT(*) FILTER (WHERE v.intersecting) as intersecting_count,
    COUNT(*) FILTER (WHERE v.overflowing) as overflowing_count,
    SUM(ST_Area(v.geom)) as total_area,
    (SELECT COUNT(*) FROM topoloske_vrzeli h 
     WHERE h.id_rel_geo_verzija = v.id_rel_geo_verzija) as holes_count,
    (SELECT COALESCE(SUM(ST_Area(geom)), 0) FROM topoloske_vrzeli h 
     WHERE h.id_rel_geo_verzija = v.id_rel_geo_verzija) as total_hole_area
FROM md_geo_obm v
GROUP BY v.id_rel_geo_verzija
ORDER BY v.id_rel_geo_verzija;

-- View the summary
SELECT * FROM v_topology_summary;

-- 2. Find all problematic geometries
SELECT 
    id,
    id_rel_geo_verzija,
    CASE 
        WHEN intersecting AND overflowing THEN 'Both Issues'
        WHEN intersecting THEN 'Intersection'
        WHEN overflowing THEN 'Overflow'
    END as issue_type,
    ST_Area(geom) as area
FROM md_geo_obm
WHERE intersecting OR overflowing
ORDER BY id_rel_geo_verzija, issue_type;

-- 3. Coverage analysis for a version
CREATE OR REPLACE FUNCTION analyze_coverage(p_id_rel_geo_verzija INTEGER)
RETURNS TABLE(
    total_slovenia_area NUMERIC,
    covered_area NUMERIC,
    hole_area NUMERIC,
    overflow_area NUMERIC,
    coverage_percentage NUMERIC
) AS $$
DECLARE
    v_slo_meja geometry;
    v_union_geom geometry;
BEGIN
    SELECT geom INTO v_slo_meja FROM slo_meja LIMIT 1;
    
    SELECT ST_Union(geom) INTO v_union_geom
    FROM md_geo_obm
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija;
    
    RETURN QUERY
    SELECT 
        ST_Area(v_slo_meja)::NUMERIC as total_slovenia_area,
        ST_Area(ST_Intersection(v_union_geom, v_slo_meja))::NUMERIC as covered_area,
        COALESCE((SELECT SUM(ST_Area(geom)) FROM topoloske_vrzeli 
                  WHERE id_rel_geo_verzija = p_id_rel_geo_verzija), 0)::NUMERIC as hole_area,
        ST_Area(ST_Difference(v_union_geom, v_slo_meja))::NUMERIC as overflow_area,
        (ST_Area(ST_Intersection(v_union_geom, v_slo_meja)) / ST_Area(v_slo_meja) * 100)::NUMERIC as coverage_percentage;
END;
$$ LANGUAGE plpgsql;

-- Use the coverage analysis
SELECT * FROM analyze_coverage(1);

-- ============================================================================
-- PERFORMANCE MONITORING
-- ============================================================================

-- Check trigger execution time (PostgreSQL 14+)
SELECT 
    schemaname,
    tablename,
    trigger_name,
    trigger_time,
    trigger_calls
FROM pg_stat_user_triggers
WHERE trigger_name = 'trg_validate_topology';

-- Monitor long-running queries
SELECT 
    pid,
    now() - query_start as duration,
    state,
    query
FROM pg_stat_activity
WHERE query LIKE '%md_geo_obm%'
  AND state != 'idle'
ORDER BY duration DESC;

-- ============================================================================
-- CLEANUP TEST DATA
-- ============================================================================

-- Remove test versions
DELETE FROM md_geo_obm WHERE id_rel_geo_verzija IN (997, 998, 999);
DELETE FROM topoloske_vrzeli WHERE id_rel_geo_verzija IN (997, 998, 999);

-- ============================================================================
-- TROUBLESHOOTING
-- ============================================================================

-- 1. If trigger seems not to work, check it's enabled:
SELECT 
    tgname as trigger_name,
    tgenabled as enabled,
    tgtype
FROM pg_trigger
WHERE tgname = 'trg_validate_topology';

-- 2. Check for any errors in logs:
-- Look at PostgreSQL logs for any errors

-- 3. Manually revalidate if incremental updates seem inconsistent:
SELECT * FROM revalidate_topology(<version_id>);

-- 4. Compare incremental vs full validation results:
CREATE TEMP TABLE validation_comparison AS
SELECT 
    m.id,
    m.intersecting as incremental_intersecting,
    m.overflowing as incremental_overflowing
FROM md_geo_obm m
WHERE m.id_rel_geo_verzija = 1;

-- Run full validation
SELECT * FROM revalidate_topology(1);

-- Compare results
SELECT 
    c.id,
    c.incremental_intersecting,
    m.intersecting as full_validation_intersecting,
    c.incremental_overflowing,
    m.overflowing as full_validation_overflowing,
    CASE 
        WHEN c.incremental_intersecting != m.intersecting 
             OR c.incremental_overflowing != m.overflowing 
        THEN 'MISMATCH'
        ELSE 'OK'
    END as status
FROM validation_comparison c
JOIN md_geo_obm m ON c.id = m.id
WHERE c.incremental_intersecting != m.intersecting 
   OR c.incremental_overflowing != m.overflowing;

-- ============================================================================
-- MAINTENANCE RECOMMENDATIONS
-- ============================================================================

-- 1. Regular revalidation (weekly/monthly depending on data volume)
--    Run this during low-usage periods:
-- SELECT * FROM revalidate_all_topologies();

-- 2. Create indices for better performance (if not already present):
-- CREATE INDEX IF NOT EXISTS idx_md_geo_obm_geom ON md_geo_obm USING GIST(geom);
-- CREATE INDEX IF NOT EXISTS idx_md_geo_obm_version ON md_geo_obm(id_rel_geo_verzija);
-- CREATE INDEX IF NOT EXISTS idx_topoloske_vrzeli_geom ON topoloske_vrzeli USING GIST(geom);
-- CREATE INDEX IF NOT EXISTS idx_topoloske_vrzeli_version ON topoloske_vrzeli(id_rel_geo_verzija);

-- 3. Vacuum and analyze regularly:
-- VACUUM ANALYZE md_geo_obm;
-- VACUUM ANALYZE topoloske_vrzeli;
