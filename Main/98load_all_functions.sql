-- ============================================================================
-- 98load_all_functions.sql - Load All Function Definitions
-- ============================================================================
-- This script loads all validation functions and triggers WITHOUT running setup.
-- Use this to define all functions in your database in the correct order.
--
-- Prerequisites:
--   - Database tables must already exist (run 00setup.sql first if needed)
--   - PostGIS and uuid-ossp extensions installed
--
-- What this script loads:
--   1. Geometry precision validation/fixing functions (1make2decimalPlaces.sql)
--   2. OBM topology validation functions (3checkAllTopologies.sql)
--   3. OBM incremental trigger (5trigger.sql)
--   4. Hierarchy validation functions (6validateHierarchy.sql)
--   5. Hierarchy incremental triggers (7triggerHierarchy.sql)
--
-- NOTE: Files with '-' prefix are old/deprecated and NOT loaded:
--   -0simplify_polygons.sql, -2topologyFixer.sql, -4checkAllTopologiesWithSimplified.sql
--
-- Usage:
--   \i Main/98load_all_functions.sql
--
-- This script is safe to run multiple times (uses CREATE OR REPLACE).
-- ============================================================================

\echo ''
\echo '================================================================================'
\echo 'Loading All Function Definitions'
\echo '================================================================================'
\echo ''

\timing on

-- ============================================================================
-- STEP 1: Load geometry precision functions
-- ============================================================================
\echo '[1/4] Loading precision validation/fixing functions...'
\i 1make2decimalPlaces.sql
\echo '   ✓ Loaded: validate_2_decimal_places(), debug_2_decimal_places(), set_to_2_decimal_places()'

-- ============================================================================
-- STEP 2: Load OBM topology validation functions
-- ============================================================================
\echo ''
\echo '[2/4] Loading OBM topology validation functions...'
\i 3checkAllTopologies.sql
\echo '   ✓ Loaded: validate_holes(), validate_overflows(), validate_intersections()'
\echo '   ✓ Loaded: validate_all(), validate_all_topologies()'

-- ============================================================================
-- STEP 3: Load OBM incremental trigger
-- ============================================================================
\echo ''
\echo '[3/4] Loading OBM incremental trigger...'
\i 5trigger.sql
\echo '   ✓ Loaded: validate_topology_incremental() function'
\echo '   ✓ Created: trg_validate_topology_incremental trigger on md_geo_obm'

-- ============================================================================
-- STEP 4: Load hierarchy validation functions
-- ============================================================================
\echo ''
\echo '[4/4] Loading hierarchy validation functions...'
\i 6validateHierarchy.sql
\echo '   ✓ Loaded: validate_cona_hierarchy(), validate_lao_hierarchy(), validate_tao_hierarchy()'
\echo '   ✓ Loaded: validate_all_hierarchy(), validate_all_hierarchies()'

-- ============================================================================
-- STEP 5: Load hierarchy incremental triggers
-- ============================================================================
\echo ''
\echo '[5/5] Loading hierarchy incremental triggers...'
\i 7triggerHierarchy.sql
\echo '   ✓ Loaded: validate_obmxcona_incremental() function'
\echo '   ✓ Created: trg_validate_obmxcona_incremental trigger on md_geo_obmxcona'
\echo '   ✓ Loaded: validate_cona_lao_incremental() function'
\echo '   ✓ Created: trg_validate_cona_lao_incremental trigger on md_geo_cona'
\echo '   ✓ Loaded: validate_lao_tao_incremental() function'
\echo '   ✓ Created: trg_validate_lao_tao_incremental trigger on md_geo_lao'

-- ============================================================================
-- Summary
-- ============================================================================
\echo ''
\echo '================================================================================'
\echo 'All Functions and Triggers Loaded Successfully!'
\echo '================================================================================'
\echo ''
\echo 'Loaded Functions:'
\echo '  • Precision: validate_2_decimal_places, set_to_2_decimal_places'
\echo '  • OBM Validation: validate_holes, validate_overflows, validate_intersections'
\echo '  • OBM Batch: validate_all, validate_all_topologies'
\echo '  • Hierarchy Validation: validate_cona_hierarchy, validate_lao_hierarchy, validate_tao_hierarchy'
\echo '  • Hierarchy Batch: validate_all_hierarchy, validate_all_hierarchies'
\echo ''
\echo 'Active Triggers:'
\echo '  • md_geo_obm: trg_validate_topology_incremental'
\echo '  • md_geo_obmxcona: trg_validate_obmxcona_incremental'
\echo '  • md_geo_cona: trg_validate_cona_lao_incremental'
\echo '  • md_geo_lao: trg_validate_lao_tao_incremental'
\echo ''
\echo 'Next Steps:'
\echo '  • Run initial validation: SELECT * FROM validate_all_topologies();'
\echo '  • Run hierarchy validation: SELECT * FROM validate_all_hierarchies();'
\echo '  • Run tests: \\i Main/99test_full_system.sql'
\echo ''
