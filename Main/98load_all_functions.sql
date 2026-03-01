-- ============================================================================
-- 98load_all_functions.sql - Load All Functions and Triggers
-- ============================================================================
-- Convenience wrapper: loads functions (97load_fns.sql) then triggers (98trigger_setups.sql).
--
-- IMPORTANT: Run this from the Main directory:
--   \cd /path/to/GeomIntegrity/Main
--   \i 98load_all_functions.sql
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

\i 97load_fns.sql
\i 98trigger_setups.sql

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
