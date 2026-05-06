-- ============================================================================
-- 97load_fns.sql - Load Function Definitions Only (no triggers)
-- ============================================================================
-- Loads all validation function definitions WITHOUT creating any triggers.
-- Run:
--   \i /Users/matevzvidovic/GeomIntegrity/Main/
--
-- Use this when you need functions available but want to control trigger
-- activation separately (e.g. during bulk data setup).
-- ============================================================================

\set ON_ERROR_STOP on

\echo '[1/3] Loading precision validation/fixing functions...'
\i /Users/matevzvidovic/GeomIntegrity/Main/1make2decimalPlaces.sql

\echo '[2/3] Loading OBM topology validation functions...'
\i /Users/matevzvidovic/GeomIntegrity/Main/3checkAllTopologies.sql

\echo '[3/3] Loading hierarchy validation functions...'
\i /Users/matevzvidovic/GeomIntegrity/Main/6validateHierarchy.sql

\echo '✅ Function definitions loaded (no triggers active).'
