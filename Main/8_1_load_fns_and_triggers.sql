-- ============================================================================
-- 8_1_load_fns_and_triggers.sql - Load All Functions and Triggers
-- ============================================================================
-- Convenience wrapper: loads functions (1_2_load_fns.sql) then triggers (1_2_trigger_setups.sql).
--
-- IMPORTANT: Run this from the Main directory:
--   \cd /path/to/GeomIntegrity/Main
--   \i /Users/matevzvidovic/GeomIntegrity/Main/8_1_load_fns_and_triggers.sql
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

\i /Users/matevzvidovic/GeomIntegrity/Main/1_2_load_fns.sql
\i /Users/matevzvidovic/GeomIntegrity/Main/1_2_trigger_setups.sql

\echo ''
\echo '================================================================================'
\echo '✅ ALL FUNCTIONS AND TRIGGERS LOADED SUCCESSFULLY!'
\echo '================================================================================'
\echo ''
\echo 'Loaded Functions:'
\echo '  • Precision: validate_2_decimal_places, set_to_2_decimal_places'
\echo '  • OBM Shared: get_obm_hole_candidates, get_obm_overflow_candidates, obm_topology_compactness'
\echo '  • OBM Validation: validate_holes, validate_overflows, validate_intersections'
\echo '  • OBM Batch: validate_all_topologies_single_geo_version, validate_all_topologies, autofix_overflows_and_maybe_autofix_small_napake'
\echo '  • Hierarchy Validation: validate_cona_hierarchy, validate_lao_hierarchy, validate_tao_hierarchy'
\echo '  • Hierarchy Batch: validate_all_hierarchy, validate_all_hierarchies'
\echo ''
\echo 'Active Triggers:'
\echo '  • md_geo_obm: trg_000_coerce_obm_geom_2_decimal_places'
\echo '  • md_geo_obm: trg_validate_topology_incremental'
\echo '  • md_geo_obm: trg_validate_obm_hierarchy_incremental'
\echo '  • md_geo_obmxcona: trg_validate_obmxcona_incremental'
\echo '  • md_geo_cona/md_geo_lao/md_geo_tao: trg_ensure_snap_to_grid'
\echo '  • md_geo_cona: trg_validate_cona_lao_incremental'
\echo '  • md_geo_lao: trg_validate_lao_tao_incremental'
\echo ''
