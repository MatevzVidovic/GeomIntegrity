-- ============================================================================
-- 1_0_setup.sql - GeomIntegrity Setup Script
-- ============================================================================
-- This script sets up the topology validation system for obmocja (OBM).
-- Run this ONCE to initialize the system.
--
-- Prerequisites:
--   - PostGIS extension installed
--   - uuid-ossp extension installed
--   - md_geo_obm table exists with geometry data
--   - slo_meja table exists (for Slovenia boundary)
--   - md_topoloske_kontrole_obm table exists
--
-- After running this setup, run validate_all_topologies() to populate
-- the initial topology controls.
-- ============================================================================



-- ============================================================================
-- STEP 0: Run \i commands with psql in the terminal, or manually do cmd a, and run the scripts
        -- cd into Main first
--     ➜  Main git:(main) ✗ psql -h test.gurs.db.flycom.si -p 5432 -U gurs_readwrite -d fmp_data_gurs -W
-- ============================================================================

--     Possibly uncomment the part in this script about 2_decimal_places
--     (btw: its nice that in this script we drop the triggers beforehand, so things are quicker)

-- \i /Users/matevzvidovic/GeomIntegrity/Main/1_0_setup.sql

-- \i /Users/matevzvidovic/GeomIntegrity/Main/8_0_test_full_system.sql
--

\pset pager off


-- ============================================================================
-- STEP 0: Create OBM topology controls table (if not exists)
-- ============================================================================
-- NOTE: This table should be created in Lift first!
-- If the table already exists in your database, you can comment out this step.

-- CREATE TABLE IF NOT EXISTS md_topoloske_kontrole_obm (
--     id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
--     created_at TIMESTAMP DEFAULT now(),
--     created_by UUID,
--     updated_at TIMESTAMP,
--     updated_by UUID,
--     id_rel_geo_verzija UUID NOT NULL,
--     tip_topoloskega_problema TEXT NOT NULL,  -- 'prekrivanje', 'luknja', 'preliv'
--     id1 UUID,                -- First OBM id (for intersections)
--     id2 UUID,                -- Second OBM id (for intersections)
--     geom GEOMETRY(Geometry, 3794),
--     povrsina DOUBLE PRECISION,
--     obseg DOUBLE PRECISION,
--     kompaktnost DOUBLE PRECISION
-- );

-- Note: Geometry columns typically get automatic spatial indexes in PostGIS.
-- Check if your backend (Lift) already creates these indexes automatically.



-- ============================================================================
-- STEP 0.1: Create indexes on OBM topology controls table
-- ============================================================================
-- Note: Check if your backend already creates indexes on geometry columns!
-- PostGIS/Lift often auto-creates spatial indexes (GIST) on geometry columns.
-- You can check with: SELECT * FROM pg_indexes WHERE tablename = 'md_topoloske_kontrole_obm';

-- Query optimization index (non-geometry columns)
CREATE INDEX IF NOT EXISTS idx_topoloske_kontrole_obm_query
ON md_topoloske_kontrole_obm (
    id_rel_geo_verzija,
    tip_topoloskega_problema,
    id1,
    id2
);

-- Spatial index on geometry column (if not auto-created by backend)
-- Uncomment if needed:
-- CREATE INDEX IF NOT EXISTS idx_topoloske_kontrole_obm_geom
-- ON md_topoloske_kontrole_obm USING GIST (geom);


-- ============================================================================
-- STEP 0.2: Add constraints to OBM topology controls table
-- ============================================================================

-- Constraint: tip_topoloskega_problema must be valid for OBM
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'check_tip_topoloskega_problema_obm'
    ) THEN
        ALTER TABLE md_topoloske_kontrole_obm
        ADD CONSTRAINT check_tip_topoloskega_problema_obm
        CHECK (tip_topoloskega_problema IN ('prekrivanje', 'luknja', 'preliv'));
    END IF;
END $$;

-- Constraint: id1 < id2 when both present (prevents duplicate intersection records)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'check_id1_less_than_id2_obm'
    ) THEN
        ALTER TABLE md_topoloske_kontrole_obm
        ADD CONSTRAINT check_id1_less_than_id2_obm
        CHECK (id2 IS NULL OR (id1 IS NOT NULL AND id1 < id2));
    END IF;
END $$;



-- ============================================================================
-- STEP 1: Create hierarchy validation table
-- ============================================================================
-- This table stores ID-based validation problems for cona/lao/tao hierarchy
-- NOTE: This table should be created in Lift first!
-- If the table already exists in your database, you can comment out this step.

-- CREATE TABLE IF NOT EXISTS md_topoloske_kontrole_hierarhija (
--     id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
--     created_at TIMESTAMP DEFAULT now(),
--     created_by UUID,
--     updated_at TIMESTAMP,
--     updated_by UUID,
--     id_rel_verzije_modeli UUID NOT NULL,
--     tip_entitete TEXT NOT NULL,  -- 'cona', 'lao', 'tao'
--     tip_problema TEXT NOT NULL,  -- Describes problem and implicitly what problematicen_id refers to
--     problematicen_id UUID        -- The relevant ID (entity or reference, depending on tip_problema)
-- );

-- Required column: validation functions and indexes depend on this existing.
-- This must be created by the application/schema layer, not by this loader.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'md_topoloske_kontrole_hierarhija'
          AND column_name = 'id_rel_geo_verzija'
    ) THEN
        RAISE EXCEPTION 'Missing required column md_topoloske_kontrole_hierarhija.id_rel_geo_verzija';
    END IF;
END $$;

-- Query optimization index
DROP INDEX IF EXISTS idx_topoloske_kontrole_hierarhija_query;
CREATE INDEX IF NOT EXISTS idx_topoloske_kontrole_hierarhija_query
ON md_topoloske_kontrole_hierarhija (
    id_rel_verzije_modeli,
    id_rel_geo_verzija,
    tip_entitete,
    tip_problema,
    problematicen_id
);

-- Constraint: tip_entitete must be valid
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'check_tip_entitete_hierarhija'
    ) THEN
        ALTER TABLE md_topoloske_kontrole_hierarhija
        ADD CONSTRAINT check_tip_entitete_hierarhija
        CHECK (tip_entitete IN ('cona', 'lao', 'tao'));
    END IF;
END $$;

-- Constraint: tip_problema must be valid (drop and recreate to allow updates)
DO $$
BEGIN
    -- Drop first so the UPDATE below is not blocked by any old constraint value
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'check_tip_problema_hierarhija'
    ) THEN
        ALTER TABLE md_topoloske_kontrole_hierarhija
        DROP CONSTRAINT check_tip_problema_hierarhija;
    END IF;

    -- Rename rows from any previous name (idempotent)
    UPDATE md_topoloske_kontrole_hierarhija
    SET tip_problema = 'cona ne obstaja'
    WHERE tip_problema = 'cone ne obstaja';

    ALTER TABLE md_topoloske_kontrole_hierarhija
    ADD CONSTRAINT check_tip_problema_hierarhija
    CHECK (tip_problema IN (
        'obm. v nobeni coni', 'napačno obm.', 'cona ne obstaja', 'cona brez obm.',
        'cona v nobenem LAO', 'LAO ne obstaja', 'LAO brez cone',
        'LAO v nobenem TAO', 'TAO ne obstaja', 'TAO brez LAO'
    ));
END $$;





-- ============================================================================
-- STEP 2: Disable triggers during setup (prevents conflicts during bulk ops)
-- ============================================================================
-- Disable all triggers to prevent them from firing during initial data setup
DROP TRIGGER IF EXISTS trg_validate_topology_incremental ON md_geo_obm;
DROP TRIGGER IF EXISTS trg_validate_obmxcona_incremental ON md_geo_obmxcona;
DROP TRIGGER IF EXISTS trg_validate_cona_lao_incremental ON md_geo_cona;
DROP TRIGGER IF EXISTS trg_validate_lao_tao_incremental ON md_geo_lao;

-- Load function definitions immediately after disabling triggers,
-- so validation functions below can be called without stale DB definitions.
\i /Users/matevzvidovic/GeomIntegrity/Main/1_2_load_fns.sql





-- ============================================================================
-- STEP 3: Truncate kontrole tables so we get a truly fresh copy
-- ============================================================================

TRUNCATE TABLE md_topoloske_kontrole_obm
TRUNCATE TABLE md_topoloske_kontrole_hierarhija



-- ============================================================================
-- STEP 3: Ensure obm geometries have 2 decimal place precision
-- ============================================================================
-- Run these to check and fix precision issues:
SELECT * FROM validate_2_decimal_places();
SELECT * FROM set_to_2_decimal_places();
SELECT * FROM validate_2_decimal_places();


-- ============================================================================
-- STEP 4: Initialize Slovenia boundary from obmocja union
-- ============================================================================
-- The slo_meja table stores the outer boundary of all obmocja combined.
-- This is used to detect holes (uncovered areas) and overflows.

TRUNCATE TABLE slo_meja;

INSERT INTO slo_meja(id, created_at, created_by, geom)
SELECT
    uuid_generate_v4() AS id,
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000',
    ST_MakePolygon(ST_ExteriorRing(
        ST_ReducePrecision(
            ST_Union(md_geo_obm.geom),
            0.01
        )
    )) AS geom
FROM md_geo_obm;





-- ============================================================================
-- STEP 7: Run initial topology validation
-- ============================================================================
-- This populates md_topoloske_kontrole_obm with all topology issues.

-- For a single model version:
-- SELECT * FROM validate_all('your-uuid-here');

-- For all model versions:
SELECT * FROM validate_all_topologies();






-- ============================================================================
-- STEP 9: Run initial hierarchy validation
-- ============================================================================
-- This populates md_topoloske_kontrole_hierarhija with all hierarchy issues.

-- For a single model version:
-- SELECT * FROM validate_all_hierarchy('your-uuid-here');

-- For all model versions:
SELECT * FROM validate_all_hierarchies();


-- ============================================================================
-- STEP 10: Activate triggers
-- ============================================================================
-- Trigger functions and triggers are created here, after all validation has run,
-- so the initial bulk validation above is not slowed down by per-row trigger calls.
\i /Users/matevzvidovic/GeomIntegrity/Main/1_2_trigger_setups.sql


-- ============================================================================
-- Validation Functions Reference
-- ============================================================================

-- OBM Topology Validation:
-- -------------------------
-- For a single model version:
--   SELECT * FROM validate_holes('uuid-here');
--   SELECT * FROM validate_overflows('uuid-here');
--   SELECT * FROM validate_intersections('uuid-here');
--   SELECT * FROM validate_all('uuid-here');

-- For all model versions:
--   SELECT * FROM validate_all_topologies();

-- Hierarchy Validation:
-- ---------------------
-- For a single model version:
--   SELECT * FROM validate_cona_hierarchy('uuid-here');
--   SELECT * FROM validate_lao_hierarchy('uuid-here');
--   SELECT * FROM validate_tao_hierarchy('uuid-here');
--   SELECT * FROM validate_all_hierarchy('uuid-here');

-- For all model versions:
--   SELECT * FROM validate_all_hierarchies();
