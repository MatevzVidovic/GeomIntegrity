-- ============================================================================
-- 98trigger_setups.sql - Create All Triggers
-- ============================================================================
-- Defines trigger functions and installs all triggers.
-- Run from the Main directory:
--   \i /Users/matevzvidovic/GeomIntegrity/Main/98trigger_setups.sql
--
-- Requires that the validation functions (97load_fns.sql) are already loaded.
-- ============================================================================

\set ON_ERROR_STOP on

\echo '[1/2] Loading OBM incremental trigger...'
\i /Users/matevzvidovic/GeomIntegrity/Main/5trigger.sql

\echo '[2/2] Loading hierarchy incremental triggers...'
\i /Users/matevzvidovic/GeomIntegrity/Main/7triggerHierarchy.sql

\echo '✅ All triggers active.'
