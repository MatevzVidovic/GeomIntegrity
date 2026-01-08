-- ============================================================================
-- TOPOLOGY VALIDATION - QUICK REFERENCE CARD
-- ============================================================================

-- ============================================================================
-- INSTALLATION (Run Once)
-- ============================================================================

-- 1. Install revalidation functions
\i topology_validation.sql

-- 2. Validate existing data  
SELECT * FROM revalidate_all_topologies();

-- 3. Install trigger
\i topology_trigger.sql

-- 4. Verify installation
SELECT count(*) FROM pg_proc WHERE proname LIKE '%topology%';
SELECT count(*) FROM pg_trigger WHERE tgname = 'trg_validate_topology';

-- ============================================================================
-- COMMON QUERIES
-- ============================================================================

-- Check problems for a version
SELECT id, intersecting, overflowing, ST_Area(geom) as area
FROM md_geo_obm
WHERE id_rel_geo_verzija = 1 
  AND (intersecting OR overflowing);

-- View holes
SELECT id, ST_Area(geom) as hole_area
FROM topoloske_vrzeli  
WHERE id_rel_geo_verzija = 1;

-- Summary statistics
SELECT * FROM v_topology_summary WHERE id_rel_geo_verzija = 1;

-- Coverage analysis
SELECT * FROM analyze_coverage(1);

-- Count issues
SELECT 
    COUNT(*) FILTER (WHERE intersecting) as intersections,
    COUNT(*) FILTER (WHERE overflowing) as overflows
FROM md_geo_obm
WHERE id_rel_geo_verzija = 1;

-- ============================================================================
-- MAINTENANCE
-- ============================================================================

-- Full revalidation (single version)
SELECT * FROM revalidate_topology(1);

-- Full revalidation (all versions)
SELECT * FROM revalidate_all_topologies();

-- Vacuum and analyze
VACUUM ANALYZE md_geo_obm;
VACUUM ANALYZE topoloske_vrzeli;

-- ============================================================================
-- BULK OPERATIONS
-- ============================================================================

-- Temporarily disable trigger for bulk insert
ALTER TABLE md_geo_obm DISABLE TRIGGER trg_validate_topology;

-- ... perform bulk operations ...

-- Re-enable and revalidate
ALTER TABLE md_geo_obm ENABLE TRIGGER trg_validate_topology;
SELECT * FROM revalidate_topology(1);

-- ============================================================================
-- MONITORING
-- ============================================================================

-- Trigger statistics
SELECT * FROM pg_stat_user_triggers 
WHERE trigger_name = 'trg_validate_topology';

-- Active queries
SELECT pid, state, now() - query_start as duration, query
FROM pg_stat_activity
WHERE query LIKE '%md_geo_obm%' AND state != 'idle';

-- Index usage
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE tablename IN ('md_geo_obm', 'topoloske_vrzeli')
ORDER BY idx_scan DESC;

-- ============================================================================
-- TROUBLESHOOTING
-- ============================================================================

-- Check trigger is enabled
SELECT tgname, tgenabled FROM pg_trigger 
WHERE tgname = 'trg_validate_topology';
-- tgenabled should be 'O' (origin)

-- Compare incremental vs full validation
-- 1. Save current state
CREATE TEMP TABLE current_state AS
SELECT id, intersecting, overflowing FROM md_geo_obm WHERE id_rel_geo_verzija = 1;

-- 2. Run full validation
SELECT * FROM revalidate_topology(1);

-- 3. Compare
SELECT c.id, c.intersecting as old, m.intersecting as new
FROM current_state c
JOIN md_geo_obm m ON c.id = m.id
WHERE c.intersecting != m.intersecting OR c.overflowing != m.overflowing;

-- ============================================================================
-- INDICES (Create if missing)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_md_geo_obm_geom 
    ON md_geo_obm USING GIST(geom);
    
CREATE INDEX IF NOT EXISTS idx_md_geo_obm_version 
    ON md_geo_obm(id_rel_geo_verzija);
    
CREATE INDEX IF NOT EXISTS idx_topoloske_vrzeli_geom 
    ON topoloske_vrzeli USING GIST(geom);
    
CREATE INDEX IF NOT EXISTS idx_topoloske_vrzeli_version 
    ON topoloske_vrzeli(id_rel_geo_verzija);

-- ============================================================================
-- VISUALIZATION HELPERS
-- ============================================================================

-- Export holes as GeoJSON
SELECT 
    id_rel_geo_verzija,
    jsonb_build_object(
        'type', 'Feature',
        'geometry', ST_AsGeoJSON(geom)::jsonb,
        'properties', jsonb_build_object('id', id, 'area', ST_Area(geom))
    ) as geojson
FROM topoloske_vrzeli
WHERE id_rel_geo_verzija = 1;

-- Export problem geometries
SELECT 
    jsonb_build_object(
        'type', 'Feature',
        'geometry', ST_AsGeoJSON(geom)::jsonb,
        'properties', jsonb_build_object(
            'id', id, 
            'intersecting', intersecting,
            'overflowing', overflowing
        )
    ) as geojson
FROM md_geo_obm
WHERE id_rel_geo_verzija = 1 
  AND (intersecting OR overflowing);

-- ============================================================================
-- COMMON ERROR MESSAGES & SOLUTIONS
-- ============================================================================

-- Error: "Slovenia boundary (slo_meja) not found"
-- Solution: Verify slo_meja view/table exists and has data
SELECT count(*) FROM slo_meja;

-- Error: Slow trigger performance
-- Solution: Check number of geometries and ensure indices exist
SELECT id_rel_geo_verzija, count(*) 
FROM md_geo_obm 
GROUP BY id_rel_geo_verzija 
ORDER BY count(*) DESC;

-- Error: Unexpected holes
-- Solution: Check geometry precision and snapping tolerance
SELECT ST_Precision(geom) FROM md_geo_obm LIMIT 1;

-- ============================================================================
-- BATCH UPDATE PATTERN
-- ============================================================================

-- For large batch updates, use this pattern:
DO $$
BEGIN
    -- Disable trigger
    EXECUTE 'ALTER TABLE md_geo_obm DISABLE TRIGGER trg_validate_topology';
    
    -- Perform batch operations
    -- INSERT/UPDATE/DELETE statements here
    
    -- Re-enable trigger
    EXECUTE 'ALTER TABLE md_geo_obm ENABLE TRIGGER trg_validate_topology';
    
    -- Revalidate
    PERFORM revalidate_topology(1);  -- or your version number
END $$;

-- ============================================================================
-- PERFORMANCE BENCHMARKS (Reference)
-- ============================================================================

-- Small dataset (<100 geometries): Trigger adds ~10-50ms per operation
-- Medium dataset (100-1000 geometries): Trigger adds ~50-200ms per operation  
-- Large dataset (>1000 geometries): Full revalidation recommended
--   - Holes calculation: ~1-5 seconds
--   - Overflow check: ~1-5 seconds
--   - Intersection check: ~10-60 seconds (O(n²))

-- ============================================================================
-- USEFUL VIEWS
-- ============================================================================

-- Create view for problem geometries
CREATE OR REPLACE VIEW v_problem_geometries AS
SELECT 
    m.id,
    m.id_rel_geo_verzija,
    m.geom,
    m.intersecting,
    m.overflowing,
    ST_Area(m.geom) as area,
    CASE 
        WHEN m.intersecting AND m.overflowing THEN 'both'
        WHEN m.intersecting THEN 'intersection'
        WHEN m.overflowing THEN 'overflow'
    END as issue_type
FROM md_geo_obm m
WHERE m.intersecting OR m.overflowing;

-- Use it
SELECT * FROM v_problem_geometries WHERE id_rel_geo_verzija = 1;
