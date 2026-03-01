-- ============================================================================
-- 97load_fns.sql - Load Function Definitions Only (no triggers)
-- ============================================================================
-- Loads all validation function definitions WITHOUT creating any triggers.
-- Run from the Main directory:
--   \i 97load_fns.sql
--
-- Use this when you need functions available but want to control trigger
-- activation separately (e.g. during bulk data setup).
-- ============================================================================

\set ON_ERROR_STOP on

\echo '[1/3] Loading precision validation/fixing functions...'
\i 1make2decimalPlaces.sql

\echo '[2/3] Loading OBM topology validation functions...'
\i 3checkAllTopologies.sql

\echo '[3/3] Loading hierarchy validation functions...'
\i 6validateHierarchy.sql

\echo '[4/3] Migrating tip_problema constraint to current valid values...'
DO $$
BEGIN
    -- Drop first so the UPDATE below is not blocked by the old constraint
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'check_tip_problema_hierarhija') THEN
        ALTER TABLE md_topoloske_kontrole_hierarhija DROP CONSTRAINT check_tip_problema_hierarhija;
    END IF;

    -- Rename any existing rows that still use the old value
    UPDATE md_topoloske_kontrole_hierarhija
    SET tip_problema = 'cona ne obstaja'
    WHERE tip_problema = 'cone ne obstaja';

    -- Recreate constraint with current valid values
    ALTER TABLE md_topoloske_kontrole_hierarhija
    ADD CONSTRAINT check_tip_problema_hierarhija
    CHECK (tip_problema IN (
        'obm. v nobeni coni', 'napačno obm.', 'cona ne obstaja', 'cona brez obm.',
        'cona v nobenem LAO', 'LAO ne obstaja', 'LAO brez cone',
        'LAO v nobenem TAO', 'TAO ne obstaja', 'TAO brez LAO'
    ));
END $$;

\echo '✅ Function definitions loaded (no triggers active).'
