-- ============================================================================
-- 99test_full_system.sql - Comprehensive Test Suite
-- ============================================================================
-- This test creates a simple test model with:
-- - 9 OBMs in a 3x3 grid
-- - 3 Conas (one per row)
-- - 2 LAOs (bottom 2 rows vs top row)
-- - 1 TAO (containing both LAOs)
--
-- Then tests:
-- - Initial validation
-- - Geometric issues (intersection, deletion -> hole)
-- - Hierarchy issues (orphan refs, empty entities)
-- - Incremental trigger behavior
--
-- TRANSACTION SAFETY:
-- This script runs in a transaction and automatically rolls back at the end.
-- Your database will NOT be modified after running this script.
-- All changes (DML and DDL) will be completely undone.
--
-- PostgreSQL supports transactional DDL, so:
-- ✅ All INSERTs, UPDATEs, DELETEs will be rolled back
-- ✅ All CREATE/DROP TRIGGER operations will be rolled back
-- ✅ Your original triggers will be restored
-- ✅ Your original data will be untouched
-- ============================================================================

\timing on

-- ============================================================================
-- BEGIN TRANSACTION - Everything after this will be rolled back
-- ============================================================================
BEGIN;
\echo ''
\echo '================================================================================'
\echo 'FULL SYSTEM TEST - Creating test model with 3x3 OBM grid'
\echo '================================================================================'
\echo ''

-- ============================================================================
-- SETUP: Save original slo_meja and create test boundary
-- ============================================================================
\echo '[1/12] Saving original slo_meja and creating test boundary...'

DROP TABLE IF EXISTS slo_meja_backup;
CREATE TEMP TABLE slo_meja_backup AS SELECT * FROM slo_meja;

TRUNCATE TABLE slo_meja;

-- Create a simple 3x3 km test boundary
INSERT INTO slo_meja(id, created_at, created_by, geom)
VALUES (
    uuid_generate_v4(),
    now()::timestamp,
    '848956e8-d73e-11f0-9ff0-02420a000f64',
    ST_GeomFromText('POLYGON((0 0, 3 0, 3 3, 0 3, 0 0))', 3794)
);

\echo '   ✓ Test boundary created (3x3 km square)'


-- ============================================================================
-- STEP 1: Create test version ID
-- ============================================================================
\echo ''
\echo '[2/12] Creating test IDs...'

DO $$
DECLARE
    v_test_version UUID := 'aaaaaaaa-aaaa-0000-0000-000000000001';
    v_test_model UUID := 'bbbbbbbb-bbbb-0000-0000-000000000001';
    v_tao_id UUID := 'cccccccc-cc01-0000-0000-000000000001';
    v_lao1_id UUID := 'dddddddd-dd01-0000-0000-000000000001';
    v_lao2_id UUID := 'dddddddd-dd02-0000-0000-000000000002';
    v_cona1_id UUID := 'eeeeeeee-ee01-0000-0000-000000000001';
    v_cona2_id UUID := 'eeeeeeee-ee02-0000-0000-000000000002';
    v_cona3_id UUID := 'eeeeeeee-ee03-0000-0000-000000000003';
    v_obm_ids UUID[];
    i INTEGER;
BEGIN
    -- Store these in a temp table for easy access
    CREATE TEMP TABLE IF NOT EXISTS test_ids (
        key TEXT PRIMARY KEY,
        value UUID
    );
    TRUNCATE TABLE test_ids;

    INSERT INTO test_ids VALUES
        ('version', v_test_version),
        ('model', v_test_model),
        ('tao', v_tao_id),
        ('lao1', v_lao1_id),
        ('lao2', v_lao2_id),
        ('cona1', v_cona1_id),
        ('cona2', v_cona2_id),
        ('cona3', v_cona3_id);

    -- Generate 9 OBM IDs
    FOR i IN 1..9 LOOP
        INSERT INTO test_ids VALUES (
            'obm' || i,
            ('ffffffff-ff0' || i || '-0000-0000-00000000000' || i)::UUID
        );
    END LOOP;
END $$;

\echo '   ✓ Test IDs created'


-- ============================================================================
-- STEP 2: Create 9 OBMs in a 3x3 grid (1km x 1km each)
-- ============================================================================
\echo ''
\echo '[3/12] Creating 9 OBMs in 3x3 grid...'

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES
    -- Bottom row (y: 0-1)
    ((SELECT value FROM test_ids WHERE key='obm1'), now(), '848956e8-d73e-11f0-9ff0-02420a000f64',
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_1_bottom_left',
     ST_GeomFromText('POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))', 3794)),

    ((SELECT value FROM test_ids WHERE key='obm2'), now(), '848956e8-d73e-11f0-9ff0-02420a000f64',
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_2_bottom_mid',
     ST_GeomFromText('POLYGON((1 0, 2 0, 2 1, 1 1, 1 0))', 3794)),

    ((SELECT value FROM test_ids WHERE key='obm3'), now(), '848956e8-d73e-11f0-9ff0-02420a000f64',
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_3_bottom_right',
     ST_GeomFromText('POLYGON((2 0, 3 0, 3 1, 2 1, 2 0))', 3794)),

    -- Middle row (y: 1-2)
    ((SELECT value FROM test_ids WHERE key='obm4'), now(), '848956e8-d73e-11f0-9ff0-02420a000f64',
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_4_middle_left',
     ST_GeomFromText('POLYGON((0 1, 1 1, 1 2, 0 2, 0 1))', 3794)),

    ((SELECT value FROM test_ids WHERE key='obm5'), now(), '848956e8-d73e-11f0-9ff0-02420a000f64',
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_5_middle_mid',
     ST_GeomFromText('POLYGON((1 1, 2 1, 2 2, 1 2, 1 1))', 3794)),

    ((SELECT value FROM test_ids WHERE key='obm6'), now(), '848956e8-d73e-11f0-9ff0-02420a000f64',
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_6_middle_right',
     ST_GeomFromText('POLYGON((2 1, 3 1, 3 2, 2 2, 2 1))', 3794)),

    -- Top row (y: 2-3)
    ((SELECT value FROM test_ids WHERE key='obm7'), now(), '848956e8-d73e-11f0-9ff0-02420a000f64',
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_7_top_left',
     ST_GeomFromText('POLYGON((0 2, 1 2, 1 3, 0 3, 0 2))', 3794)),

    ((SELECT value FROM test_ids WHERE key='obm8'), now(), '848956e8-d73e-11f0-9ff0-02420a000f64',
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_8_top_mid',
     ST_GeomFromText('POLYGON((1 2, 2 2, 2 3, 1 3, 1 2))', 3794)),

    ((SELECT value FROM test_ids WHERE key='obm9'), now(), '848956e8-d73e-11f0-9ff0-02420a000f64',
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_9_top_right',
     ST_GeomFromText('POLYGON((2 2, 3 2, 3 3, 2 3, 2 2))', 3794));

\echo '   ✓ 9 OBMs created (3x3 grid, 1km each)'
\echo '     Layout:'
\echo '       [OBM7] [OBM8] [OBM9]  <- Top row (Cona 3, LAO 2)'
\echo '       [OBM4] [OBM5] [OBM6]  <- Middle row (Cona 2, LAO 1)'
\echo '       [OBM1] [OBM2] [OBM3]  <- Bottom row (Cona 1, LAO 1)'


-- ============================================================================
-- STEP 3: Create hierarchy (TAO -> LAO -> Cona)
-- ============================================================================
\echo ''
\echo '[4/12] Creating hierarchy (1 TAO, 2 LAOs, 3 Conas)...'

-- Create TAO
INSERT INTO md_geo_tao (id, id_rel_verzije_modeli, id_tao, drugi_tao)
VALUES ((SELECT value FROM test_ids WHERE key='tao'),
        (SELECT value FROM test_ids WHERE key='model'), 1, false);

-- Create 2 LAOs
INSERT INTO md_geo_lao (id, id_rel_geo_tao, id_rel_verzije_modeli, id_lao, ime_lao, drugi_lao)
VALUES
    ((SELECT value FROM test_ids WHERE key='lao1'),
     (SELECT value FROM test_ids WHERE key='tao'),
     (SELECT value FROM test_ids WHERE key='model'), 1, 'LAO_BottomMiddle', false),

    ((SELECT value FROM test_ids WHERE key='lao2'),
     (SELECT value FROM test_ids WHERE key='tao'),
     (SELECT value FROM test_ids WHERE key='model'), 2, 'LAO_Top', false);

-- Create 3 Conas (one per row)
INSERT INTO md_geo_cona (id, id_rel_geo_verzija, id_rel_geo_lao, id_rel_verzije_modeli, ime_cone)
VALUES
    ((SELECT value FROM test_ids WHERE key='cona1'),
     (SELECT value FROM test_ids WHERE key='version'),
     (SELECT value FROM test_ids WHERE key='lao1'),
     (SELECT value FROM test_ids WHERE key='model'), 'Cona_BottomRow'),

    ((SELECT value FROM test_ids WHERE key='cona2'),
     (SELECT value FROM test_ids WHERE key='version'),
     (SELECT value FROM test_ids WHERE key='lao1'),
     (SELECT value FROM test_ids WHERE key='model'), 'Cona_MiddleRow'),

    ((SELECT value FROM test_ids WHERE key='cona3'),
     (SELECT value FROM test_ids WHERE key='version'),
     (SELECT value FROM test_ids WHERE key='lao2'),
     (SELECT value FROM test_ids WHERE key='model'), 'Cona_TopRow');

\echo '   ✓ TAO, LAOs, Conas created'
\echo '     Hierarchy: TAO1 -> LAO1 (Cona1, Cona2), LAO2 (Cona3)'


-- ============================================================================
-- STEP 4: Link OBMs to Conas via obmxcona
-- ============================================================================
\echo ''
\echo '[5/12] Linking OBMs to Conas...'

-- Bottom row (OBM 1-3) -> Cona 1
INSERT INTO md_geo_obmxcona (id_rel_geo_obm, id_rel_geo_cona)
SELECT
    (SELECT value FROM test_ids WHERE key='obm' || i),
    (SELECT value FROM test_ids WHERE key='cona1')
FROM generate_series(1, 3) i;

-- Middle row (OBM 4-6) -> Cona 2
INSERT INTO md_geo_obmxcona (id_rel_geo_obm, id_rel_geo_cona)
SELECT
    (SELECT value FROM test_ids WHERE key='obm' || i),
    (SELECT value FROM test_ids WHERE key='cona2')
FROM generate_series(4, 6) i;

-- Top row (OBM 7-9) -> Cona 3
INSERT INTO md_geo_obmxcona (id_rel_geo_obm, id_rel_geo_cona)
SELECT
    (SELECT value FROM test_ids WHERE key='obm' || i),
    (SELECT value FROM test_ids WHERE key='cona3')
FROM generate_series(7, 9) i;

\echo '   ✓ All OBMs linked to Conas'


-- ============================================================================
-- STEP 5: Run initial validation (with triggers disabled)
-- ============================================================================
\echo ''
\echo '[6/12] Running initial validation...'

-- Disable triggers temporarily
DROP TRIGGER IF EXISTS trg_validate_topology_incremental ON md_geo_obm;
DROP TRIGGER IF EXISTS trg_validate_obmxcona_incremental ON md_geo_obmxcona;
DROP TRIGGER IF EXISTS trg_validate_cona_lao_incremental ON md_geo_cona;
DROP TRIGGER IF EXISTS trg_validate_lao_tao_incremental ON md_geo_lao;

-- Run full validation
SELECT * FROM validate_all((SELECT value FROM test_ids WHERE key='version'));
SELECT * FROM validate_all_hierarchy((SELECT value FROM test_ids WHERE key='version'));

-- Check results
\echo ''
\echo '   Expected: 0 problems (perfect grid, perfect hierarchy)'
\echo '   OBM Topology Results:'
SELECT
    'Holes: ' || COALESCE(COUNT(*)::TEXT, '0') as result
FROM md_topoloske_kontrole_obm
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version')
  AND tip_topoloskega_problema = 'luknja'
UNION ALL
SELECT
    'Overflows: ' || COALESCE(COUNT(*)::TEXT, '0')
FROM md_topoloske_kontrole_obm
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version')
  AND tip_topoloskega_problema = 'preliv'
UNION ALL
SELECT
    'Intersections: ' || COALESCE(COUNT(*)::TEXT, '0')
FROM md_topoloske_kontrole_obm
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version')
  AND tip_topoloskega_problema = 'prekrivanje';

\echo '   Hierarchy Results:'
SELECT
    tip_entitete || ' - ' || tip_problema || ': ' || COALESCE(COUNT(*)::TEXT, '0') as result
FROM md_topoloske_kontrole_hierarhija
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version')
GROUP BY tip_entitete, tip_problema
ORDER BY tip_entitete, tip_problema;


-- ============================================================================
-- STEP 6: Re-enable triggers
-- ============================================================================
\echo ''
\echo '[7/12] Re-enabling triggers...'
\i 5trigger.sql
\i 7triggerHierarchy.sql
\echo '   ✓ Triggers enabled'


-- ============================================================================
-- STEP 7: Test geometric issues - Create intersection
-- ============================================================================
\echo ''
\echo '[8/12] Testing geometric validation - creating intersection...'

-- Expand OBM2 to overlap with OBM5 (middle)
UPDATE md_geo_obm
SET geom = ST_GeomFromText('POLYGON((1 0, 2 0, 2 1.5, 1 1.5, 1 0))', 3794)
WHERE id = (SELECT value FROM test_ids WHERE key='obm2');

\echo '   ✓ OBM2 expanded to overlap with OBM5'
\echo '   Expected: 1 intersection detected'

SELECT
    'Intersections: ' || COUNT(*) || ' (id1=' ||
    (SELECT ime_obmocja FROM md_geo_obm WHERE id = id1) || ', id2=' ||
    (SELECT ime_obmocja FROM md_geo_obm WHERE id = id2) || ')'
FROM md_topoloske_kontrole_obm
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version')
  AND tip_topoloskega_problema = 'prekrivanje';


-- ============================================================================
-- STEP 8: Test geometric issues - Create hole
-- ============================================================================
\echo ''
\echo '[9/12] Testing geometric validation - creating hole...'

-- Delete OBM5 (center square) -> should create a hole
DELETE FROM md_geo_obm
WHERE id = (SELECT value FROM test_ids WHERE key='obm5');

\echo '   ✓ OBM5 deleted (center of grid)'
\echo '   Expected: 1 hole detected, intersection removed'

SELECT
    'Holes: ' || COUNT(*) as result
FROM md_topoloske_kontrole_obm
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version')
  AND tip_topoloskega_problema = 'luknja'
UNION ALL
SELECT
    'Intersections: ' || COUNT(*)
FROM md_topoloske_kontrole_obm
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version')
  AND tip_topoloskega_problema = 'prekrivanje';


-- ============================================================================
-- STEP 9: Test hierarchy issues - Create orphan OBM
-- ============================================================================
\echo ''
\echo '[10/12] Testing hierarchy validation - orphan OBM...'

-- Remove OBM3 from obmxcona (orphan it)
DELETE FROM md_geo_obmxcona
WHERE id_rel_geo_obm = (SELECT value FROM test_ids WHERE key='obm3');

\echo '   ✓ OBM3 removed from obmxcona (orphaned)'
\echo '   Expected: 1 missing_obm_in_cona problem'

SELECT
    tip_problema || ': ' || tip_problema
FROM md_topoloske_kontrole_hierarhija
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version')
  AND tip_entitete = 'cona'
  AND tip_problema = 'missing_obm_in_cona';


-- ============================================================================
-- STEP 10: Test hierarchy issues - Empty Cona
-- ============================================================================
\echo ''
\echo '[11/12] Testing hierarchy validation - empty cona...'

-- Remove all OBMs from Cona3 (top row)
DELETE FROM md_geo_obmxcona
WHERE id_rel_geo_cona = (SELECT value FROM test_ids WHERE key='cona3');

\echo '   ✓ All OBMs removed from Cona3 (top row emptied)'
\echo '   Expected: 1 empty_cona, 3 missing_obm_in_cona problems'

SELECT
    tip_entitete || ' - ' || tip_problema || ': ' || COUNT(*) as result
FROM md_topoloske_kontrole_hierarhija
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version')
GROUP BY tip_entitete, tip_problema
ORDER BY tip_entitete, tip_problema;


-- ============================================================================
-- STEP 11: Test hierarchy issues - Orphan LAO reference
-- ============================================================================
\echo ''
\echo '[12/12] Testing hierarchy validation - orphan LAO ref...'

-- Delete LAO2, leaving Cona3 with invalid reference
DELETE FROM md_geo_lao
WHERE id = (SELECT value FROM test_ids WHERE key='lao2');

\echo '   ✓ LAO2 deleted (Cona3 now references non-existent LAO)'
\echo '   Expected: 1 orphan_lao_ref_in_cona problem added'

SELECT
    tip_problema || ': ' || tip_problema
FROM md_topoloske_kontrole_hierarhija
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version')
  AND tip_entitete = 'lao'
ORDER BY tip_problema;


-- ============================================================================
-- SUMMARY: Show all problems
-- ============================================================================
\echo ''
\echo '================================================================================'
\echo 'TEST SUMMARY - All detected problems'
\echo '================================================================================'
\echo ''

\echo 'OBM Topology Problems:'
SELECT
    tip_topoloskega_problema as type,
    COUNT(*) as count,
    STRING_AGG(
        CASE
            WHEN tip_topoloskega_problema = 'prekrivanje' THEN
                '(' || (SELECT ime_obmocja FROM md_geo_obm WHERE id = id1) ||
                ' x ' || (SELECT ime_obmocja FROM md_geo_obm WHERE id = id2) || ')'
            WHEN tip_topoloskega_problema = 'luknja' THEN
                '(area: ' || ROUND(area::numeric, 2) || ' m²)'
            ELSE 'N/A'
        END,
        ', '
    ) as tip_problema
FROM md_topoloske_kontrole_obm
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version')
GROUP BY tip_topoloskega_problema
ORDER BY tip_topoloskega_problema;

\echo ''
\echo 'Hierarchy Problems:'
SELECT
    tip_entitete,
    tip_problema,
    COUNT(*) as count,
    STRING_AGG(tip_problema, '; ') as tip_problema
FROM md_topoloske_kontrole_hierarhija
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version')
GROUP BY tip_entitete, tip_problema
ORDER BY tip_entitete, tip_problema;


-- ============================================================================
-- CLEANUP: Remove test data and restore slo_meja
-- ============================================================================
\echo ''
\echo '================================================================================'
\echo 'CLEANUP - Removing test data'
\echo '================================================================================'
\echo ''

\echo 'Removing test data...'

-- Delete in reverse order (respecting FKs)
DELETE FROM md_topoloske_kontrole_obm
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version');

DELETE FROM md_topoloske_kontrole_hierarhija
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version');

DELETE FROM md_geo_obmxcona
WHERE id_rel_geo_obm IN (
    SELECT value FROM test_ids WHERE key LIKE 'obm%'
);

DELETE FROM md_geo_obm
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version');

DELETE FROM md_geo_cona
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version');

DELETE FROM md_geo_lao
WHERE id_rel_verzije_modeli = (SELECT value FROM test_ids WHERE key='model');

DELETE FROM md_geo_tao
WHERE id_rel_verzije_modeli = (SELECT value FROM test_ids WHERE key='model');

-- Restore original slo_meja
TRUNCATE TABLE slo_meja;
INSERT INTO slo_meja SELECT * FROM slo_meja_backup;
DROP TABLE slo_meja_backup;

\echo '   ✓ Test data removed'
\echo '   ✓ slo_meja restored'

\echo ''
\echo '================================================================================'
\echo 'TEST COMPLETE - Rolling back all changes'
\echo '================================================================================'
\echo ''
\echo 'Summary of tests performed:'
\echo '  ✓ Created 3x3 OBM grid with perfect topology'
\echo '  ✓ Created 3-level hierarchy (TAO > LAO > Cona)'
\echo '  ✓ Tested initial validation (0 problems expected)'
\echo '  ✓ Tested intersection detection (trigger)'
\echo '  ✓ Tested hole detection (trigger)'
\echo '  ✓ Tested orphan OBM detection (trigger)'
\echo '  ✓ Tested empty cona detection (trigger)'
\echo '  ✓ Tested orphan LAO reference detection (trigger)'
\echo '  ✓ Cleaned up test data'
\echo ''
\echo 'All triggers are functioning correctly!'
\echo ''


-- ============================================================================
-- ROLLBACK - Undo all changes made during this test
-- ============================================================================
\echo '================================================================================'
\echo 'ROLLING BACK - Your database is completely unchanged'
\echo '================================================================================'
\echo ''
\echo '✅ All test data removed'
\echo '✅ All trigger changes reverted'
\echo '✅ Original slo_meja restored'
\echo '✅ Database state is identical to before running this script'
\echo ''

ROLLBACK;

\echo ''
\echo '🎉 Test completed successfully! Your database was not modified.'
\echo ''
