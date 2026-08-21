-- ============================================================================
-- 1_2_trigger_setups.sql - Create All Triggers
-- ============================================================================
-- Defines trigger functions and installs all triggers.
-- Run from the Main directory:
--   \i /Users/matevzvidovic/GeomIntegrity/Main/1_2_trigger_setups.sql
--
-- Requires that the validation functions (1_2_load_fns.sql) are already loaded.
-- ============================================================================

\set ON_ERROR_STOP on

\echo '[1/3] Loading OBM incremental trigger...'
\i /Users/matevzvidovic/GeomIntegrity/Main/3_1_trg_obm_geom_trigger.sql

\echo '[2/3] Loading hierarchy precision triggers...'
\i /Users/matevzvidovic/GeomIntegrity/Main/3_2_trg_ensure_snap_to_grid_cone_lao_tao.sql

\echo '[3/3] Loading hierarchy incremental triggers...'
\i /Users/matevzvidovic/GeomIntegrity/Main/4_1_trg_hierarchy_triggers.sql

\echo '✅ All triggers active.'
