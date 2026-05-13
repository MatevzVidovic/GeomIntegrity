-- ============================================================================
-- 1_2_load_fns.sql - Load Function Definitions Only (no triggers)
-- ============================================================================
-- Loads function definitions and installs only the lightweight OBM precision trigger.
-- Run:
--   \i /Users/matevzvidovic/GeomIntegrity/Main/
--
-- Use this when you need functions available but want to control heavy validation
-- trigger activation separately (e.g. during bulk data setup).
-- ============================================================================

\set ON_ERROR_STOP on

\echo '[1/5] Loading precision validation/fixing functions...'
\i /Users/matevzvidovic/GeomIntegrity/Main/1_1_fn_coerce_2_decimal_places.sql

\echo '[2/5] Loading shared OBM topology helpers...'
\i /Users/matevzvidovic/GeomIntegrity/Main/2_0_fn_obm_topology_shared.sql

\echo '[3/5] Loading small OBM topology autofix helpers...'
\i /Users/matevzvidovic/GeomIntegrity/Main/2_1_autofix_small_violations.sql

\echo '[4/5] Loading OBM topology validation functions...'
\i /Users/matevzvidovic/GeomIntegrity/Main/3_0_fn_obm_geom_check_all.sql

\echo '[5/5] Loading hierarchy validation functions...'
\i /Users/matevzvidovic/GeomIntegrity/Main/4_0_fn_hierarchy_check_all.sql

\echo '✅ Function definitions loaded (only OBM precision trigger is active).'
