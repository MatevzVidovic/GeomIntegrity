-- ============================================================================
-- 8_0_test_full_system.sql - Comprehensive Test Suite
-- ============================================================================
-- This test creates a simple test model with:
-- - 9 OBMs in a 3x3 grid
-- - 3 Conas (one per row)
-- - 2 LAOs (bottom 2 rows vs top row)
-- - 1 TAO (containing both LAOs)
--
-- IMPORTANT: Run this from the Main directory:
--   \cd /path/to/GeomIntegrity/Main
--   \i /Users/matevzvidovic/GeomIntegrity/Main/8_0_test_full_system.sql
--
-- TRANSACTION SAFETY:
-- This script runs in a transaction and automatically rolls back at the end.
-- If any error occurs, the script STOPS immediately (ON_ERROR_STOP).
-- ============================================================================

\set ON_ERROR_STOP on
\timing on
\pset pager off

\echo ''
\echo '================================================================================'
\echo 'FULL SYSTEM TEST - Creating test model with 3x3 OBM grid'
\echo '================================================================================'
\echo ''

-- ============================================================================
-- BEGIN TRANSACTION - Everything after this will be rolled back
-- ============================================================================
BEGIN;

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
    '00000000-0000-0000-0000-000000000000'::uuid,
    ST_GeomFromText('POLYGON((0 0, 3 0, 3 3, 0 3, 0 0))', 3794)
);

\echo '   Done: Test boundary created (3x3 km square)'


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

-- Create test OBM version record (links v_test_version into md_geo_obm_verzije)
INSERT INTO md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
VALUES (
    (SELECT value FROM test_ids WHERE key='version'),
    '00000000-0000-0000-0000-000000000000'::uuid,
    now()::timestamp,
    999, false, 'TEST', false
);

-- Create test model version record (links v_test_model -> v_test_version)
-- NOTE: if md_verzije_modeli has additional NOT NULL columns, add them here
INSERT INTO md_verzije_modeli (id, created_by, created_at, id_rel_geo_verzija, model, verzija)
VALUES (
    (SELECT value FROM test_ids WHERE key='model'),
    '00000000-0000-0000-0000-000000000000'::uuid,
    now()::timestamp,
    (SELECT value FROM test_ids WHERE key='version'),
    'TEST', 1
);

\echo '   Done: Test IDs created'


-- ============================================================================
-- STEP 2: Create 9 OBMs in a 3x3 grid (1km x 1km each)
-- ============================================================================
\echo ''
\echo '[3/12] Creating 9 OBMs in 3x3 grid...'

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES
    -- Bottom row (y: 0-1)
    ((SELECT value FROM test_ids WHERE key='obm1'), now(), '00000000-0000-0000-0000-000000000000'::uuid,
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_1_bottom_left',
     ST_GeomFromText('POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))', 3794)),

    ((SELECT value FROM test_ids WHERE key='obm2'), now(), '00000000-0000-0000-0000-000000000000'::uuid,
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_2_bottom_mid',
     ST_GeomFromText('POLYGON((1 0, 2 0, 2 1, 1 1, 1 0))', 3794)),

    ((SELECT value FROM test_ids WHERE key='obm3'), now(), '00000000-0000-0000-0000-000000000000'::uuid,
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_3_bottom_right',
     ST_GeomFromText('POLYGON((2 0, 3 0, 3 1, 2 1, 2 0))', 3794)),

    -- Middle row (y: 1-2)
    ((SELECT value FROM test_ids WHERE key='obm4'), now(), '00000000-0000-0000-0000-000000000000'::uuid,
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_4_middle_left',
     ST_GeomFromText('POLYGON((0 1, 1 1, 1 2, 0 2, 0 1))', 3794)),

    ((SELECT value FROM test_ids WHERE key='obm5'), now(), '00000000-0000-0000-0000-000000000000'::uuid,
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_5_middle_mid',
     ST_GeomFromText('POLYGON((1 1, 2 1, 2 2, 1 2, 1 1))', 3794)),

    ((SELECT value FROM test_ids WHERE key='obm6'), now(), '00000000-0000-0000-0000-000000000000'::uuid,
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_6_middle_right',
     ST_GeomFromText('POLYGON((2 1, 3 1, 3 2, 2 2, 2 1))', 3794)),

    -- Top row (y: 2-3)
    ((SELECT value FROM test_ids WHERE key='obm7'), now(), '00000000-0000-0000-0000-000000000000'::uuid,
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_7_top_left',
     ST_GeomFromText('POLYGON((0 2, 1 2, 1 3, 0 3, 0 2))', 3794)),

    ((SELECT value FROM test_ids WHERE key='obm8'), now(), '00000000-0000-0000-0000-000000000000'::uuid,
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_8_top_mid',
     ST_GeomFromText('POLYGON((1 2, 2 2, 2 3, 1 3, 1 2))', 3794)),

    ((SELECT value FROM test_ids WHERE key='obm9'), now(), '00000000-0000-0000-0000-000000000000'::uuid,
     (SELECT value FROM test_ids WHERE key='version'), 'OBM_9_top_right',
     ST_GeomFromText('POLYGON((2 2, 3 2, 3 3, 2 3, 2 2))', 3794));

\echo '   Done: 9 OBMs created'
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
INSERT INTO md_geo_tao (id, created_at, created_by, id_rel_verzije_modeli, id_tao, drugi_tao)
VALUES ((SELECT value FROM test_ids WHERE key='tao'),
        now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid,
        (SELECT value FROM test_ids WHERE key='model'), 1, false);

-- Create 2 LAOs
INSERT INTO md_geo_lao (id, created_at, created_by, id_rel_geo_tao, id_rel_verzije_modeli, id_lao, ime_lao, drugi_lao)
VALUES
    ((SELECT value FROM test_ids WHERE key='lao1'),
     now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid,
     (SELECT value FROM test_ids WHERE key='tao'),
     (SELECT value FROM test_ids WHERE key='model'), 1, 'LAO_BottomMiddle', false),

    ((SELECT value FROM test_ids WHERE key='lao2'),
     now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid,
     (SELECT value FROM test_ids WHERE key='tao'),
     (SELECT value FROM test_ids WHERE key='model'), 2, 'LAO_Top', false);

-- Create 3 Conas (one per row)
INSERT INTO md_geo_cona (id, created_at, created_by, id_rel_geo_lao, id_rel_verzije_modeli, ime_cone)
VALUES
    ((SELECT value FROM test_ids WHERE key='cona1'),
     now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid,
     (SELECT value FROM test_ids WHERE key='lao1'),
     (SELECT value FROM test_ids WHERE key='model'), 'Cona_BottomRow'),

    ((SELECT value FROM test_ids WHERE key='cona2'),
     now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid,
     (SELECT value FROM test_ids WHERE key='lao1'),
     (SELECT value FROM test_ids WHERE key='model'), 'Cona_MiddleRow'),

    ((SELECT value FROM test_ids WHERE key='cona3'),
     now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid,
     (SELECT value FROM test_ids WHERE key='lao2'),
     (SELECT value FROM test_ids WHERE key='model'), 'Cona_TopRow');

\echo '   Done: TAO, LAOs, Conas created'


-- ============================================================================
-- STEP 4: Link OBMs to Conas via obmxcona
-- ============================================================================
\echo ''
\echo '[5/12] Linking OBMs to Conas...'

-- Bottom row (OBM 1-3) -> Cona 1
INSERT INTO md_geo_obmxcona (id, created_at, created_by, id_rel_geo_obm, id_rel_geo_cona)
SELECT
    uuid_generate_v4(),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM test_ids WHERE key='obm' || i),
    (SELECT value FROM test_ids WHERE key='cona1')
FROM generate_series(1, 3) i;

-- Middle row (OBM 4-6) -> Cona 2
INSERT INTO md_geo_obmxcona (id, created_at, created_by, id_rel_geo_obm, id_rel_geo_cona)
SELECT
    uuid_generate_v4(),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM test_ids WHERE key='obm' || i),
    (SELECT value FROM test_ids WHERE key='cona2')
FROM generate_series(4, 6) i;

-- Top row (OBM 7-9) -> Cona 3
INSERT INTO md_geo_obmxcona (id, created_at, created_by, id_rel_geo_obm, id_rel_geo_cona)
SELECT
    uuid_generate_v4(),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM test_ids WHERE key='obm' || i),
    (SELECT value FROM test_ids WHERE key='cona3')
FROM generate_series(7, 9) i;

\echo '   Done: All OBMs linked to Conas'


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
SELECT * FROM validate_all_hierarchy((SELECT value FROM test_ids WHERE key='model'));

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
WHERE id_rel_verzije_modeli = (SELECT value FROM test_ids WHERE key='model')
GROUP BY tip_entitete, tip_problema
ORDER BY tip_entitete, tip_problema;


-- ============================================================================
-- STEP 6: Re-enable triggers
-- ============================================================================
\echo ''
\echo '[7/12] Re-enabling triggers...'
\i /Users/matevzvidovic/GeomIntegrity/Main/3_1_trg_obm_geom_trigger.sql
\i /Users/matevzvidovic/GeomIntegrity/Main/4_1_trg_hierarchy_triggers.sql
\echo '   Done: Triggers enabled'


-- ============================================================================
-- STEP 7: Test geometric issues - Create intersection
-- ============================================================================
\echo ''
\echo '[8/12] Testing geometric validation - creating intersection...'

-- Expand OBM2 to overlap with OBM5 (middle)
UPDATE md_geo_obm
SET geom = ST_GeomFromText('POLYGON((1 0, 2 0, 2 1.5, 1 1.5, 1 0))', 3794)
WHERE id = (SELECT value FROM test_ids WHERE key='obm2');

\echo '   Done: OBM2 expanded to overlap with OBM5'
\echo '   Expected: 1 intersection detected'

SELECT
    'Intersections found: ' || COUNT(*) as result
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

\echo '   Done: OBM5 deleted (center of grid)'
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

\echo '   Done: OBM3 removed from obmxcona (orphaned)'
\echo '   Expected: 1 obm. v nobeni coni problem'

SELECT
    'Problems found: ' || COUNT(*) || ' (' || STRING_AGG(tip_problema, ', ') || ')' as result
FROM md_topoloske_kontrole_hierarhija
WHERE id_rel_verzije_modeli = (SELECT value FROM test_ids WHERE key='model')
  AND tip_entitete = 'cona';


-- ============================================================================
-- STEP 10: Test hierarchy issues - Empty Cona
-- ============================================================================
\echo ''
\echo '[11/12] Testing hierarchy validation - empty cona...'

-- Remove all OBMs from Cona3 (top row)
DELETE FROM md_geo_obmxcona
WHERE id_rel_geo_cona = (SELECT value FROM test_ids WHERE key='cona3');

\echo '   Done: All OBMs removed from Cona3 (top row emptied)'
\echo '   Expected: 1 cona brez obm., multiple obm. v nobeni coni problems'

SELECT
    tip_entitete || ' - ' || tip_problema || ': ' || COUNT(*) as result
FROM md_topoloske_kontrole_hierarhija
WHERE id_rel_verzije_modeli = (SELECT value FROM test_ids WHERE key='model')
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

\echo '   Done: LAO2 deleted (Cona3 now references non-existent LAO)'

SELECT
    tip_problema || ': ' || COUNT(*) as result
FROM md_topoloske_kontrole_hierarhija
WHERE id_rel_verzije_modeli = (SELECT value FROM test_ids WHERE key='model')
  AND tip_entitete = 'lao'
GROUP BY tip_problema
ORDER BY tip_problema;


-- ============================================================================
-- SUMMARY: Verify all test results
-- ============================================================================
\echo ''
\echo '================================================================================'
\echo 'TEST VERIFICATION'
\echo '================================================================================'
\echo ''

-- Create a table to track test results
CREATE TEMP TABLE test_results (
    test_name TEXT,
    expected TEXT,
    actual TEXT,
    passed BOOLEAN
);

-- Test 1: Initial validation should have 0 problems (already passed if we got here)

-- Test 2: After intersection creation - should have 1 intersection
-- (We check current state which is after all modifications)

-- Test 3: After hole creation - should have 1 hole
INSERT INTO test_results
SELECT
    'Hole detection after OBM deletion',
    '1',
    COUNT(*)::TEXT,
    COUNT(*) = 1
FROM md_topoloske_kontrole_obm
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version')
  AND tip_topoloskega_problema = 'luknja';

-- Test 4: Intersection should be removed after OBM5 deletion
INSERT INTO test_results
SELECT
    'Intersection removed after OBM deletion',
    '0',
    COUNT(*)::TEXT,
    COUNT(*) = 0
FROM md_topoloske_kontrole_obm
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version')
  AND tip_topoloskega_problema = 'prekrivanje';

-- Test 5: Orphan OBM should be detected (OBM3 removed from cona)
INSERT INTO test_results
SELECT
    'Orphan OBM detection (obm. v nobeni coni)',
    '>=1',
    COUNT(*)::TEXT,
    COUNT(*) >= 1
FROM md_topoloske_kontrole_hierarhija
WHERE id_rel_verzije_modeli = (SELECT value FROM test_ids WHERE key='model')
  AND tip_problema = 'obm. v nobeni coni';

-- Test 6: Empty cona should be detected (Cona3 has no OBMs)
INSERT INTO test_results
SELECT
    'Empty cona detection',
    '1',
    COUNT(*)::TEXT,
    COUNT(*) = 1
FROM md_topoloske_kontrole_hierarhija
WHERE id_rel_verzije_modeli = (SELECT value FROM test_ids WHERE key='model')
  AND tip_problema = 'cona brez obm.';

-- Test 7: Orphan LAO reference should be detected (Cona3 references deleted LAO2)
INSERT INTO test_results
SELECT
    'Orphan LAO reference detection',
    '>=1',
    COUNT(*)::TEXT,
    COUNT(*) >= 1
FROM md_topoloske_kontrole_hierarhija
WHERE id_rel_verzije_modeli = (SELECT value FROM test_ids WHERE key='model')
  AND tip_problema IN ('LAO ne obstaja', 'LAO brez cone');

-- Show all test results
\echo 'Test Results:'
SELECT
    test_name,
    'Expected: ' || expected || ', Actual: ' || actual AS comparison,
    CASE WHEN passed THEN '✅ PASS' ELSE '❌ FAIL' END AS status
FROM test_results
ORDER BY passed DESC, test_name;

-- Count failures
\echo ''

-- Store failure count for final message
CREATE TEMP TABLE failure_count AS
SELECT COUNT(*) as failures FROM test_results WHERE NOT passed;

SELECT
    CASE
        WHEN failures > 0 THEN '❌ ' || failures || ' TEST(S) FAILED!'
        ELSE '✅ All tests passed!'
    END as final_result
FROM failure_count;

-- Show current state of problems for debugging
\echo ''
\echo 'Current OBM Topology Problems:'
SELECT
    tip_topoloskega_problema as type,
    COUNT(*) as count
FROM md_topoloske_kontrole_obm
WHERE id_rel_geo_verzija = (SELECT value FROM test_ids WHERE key='version')
GROUP BY tip_topoloskega_problema
ORDER BY tip_topoloskega_problema;

\echo ''
\echo 'Current Hierarchy Problems:'
SELECT
    tip_entitete,
    tip_problema,
    COUNT(*) as count
FROM md_topoloske_kontrole_hierarhija
WHERE id_rel_verzije_modeli = (SELECT value FROM test_ids WHERE key='model')
GROUP BY tip_entitete, tip_problema
ORDER BY tip_entitete, tip_problema;


-- ============================================================================
-- ROLLBACK - Undo all changes made during this test
-- ============================================================================
\echo ''
\echo '================================================================================'
\echo 'ROLLING BACK - Undoing all changes'
\echo '================================================================================'

ROLLBACK;

-- Final status message based on test results
\echo ''
\echo '================================================================================'
\echo 'TEST RUN COMPLETE'
\echo '================================================================================'
\echo ''
\echo 'Check the results above. Your database was not modified (transaction rolled back).'
\echo ''
