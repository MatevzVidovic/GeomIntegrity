-- ============================================================================
-- 98load_all_functions.sql - Load All Function Definitions
-- ============================================================================
-- This script loads all validation functions and triggers WITHOUT running setup.
--
-- IMPORTANT: Run this from the Main directory:
--   \cd /path/to/GeomIntegrity/Main
--   \i 98load_all_functions.sql
--
-- Or use absolute paths when running from elsewhere.
--
-- This script will STOP on first error and report failure.
-- ============================================================================

\set ON_ERROR_STOP on

\echo ''
\echo '================================================================================'
\echo 'Loading All Function Definitions'
\echo '================================================================================'
\echo ''

\timing on

\echo '[1/5] Loading precision validation/fixing functions...'
\i 1make2decimalPlaces.sql

\echo '[2/5] Loading OBM topology validation functions...'
\i 3checkAllTopologies.sql

\echo '[3/5] Loading OBM incremental trigger...'
\i 5trigger.sql

\echo '[4/5] Loading hierarchy validation functions...'
\i 6validateHierarchy.sql

\echo '[5/5] Loading hierarchy incremental triggers...'
\i 7triggerHierarchy.sql

\echo ''
\echo '================================================================================'
\echo '✅ ALL FUNCTIONS AND TRIGGERS LOADED SUCCESSFULLY!'
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
