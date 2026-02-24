-- ============================================================================
-- 00setup.sql - GeomIntegrity Setup Script
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
-- STEP 1: Disable trigger during setup (prevents conflicts during bulk ops)
-- ============================================================================
DROP TRIGGER IF EXISTS trg_validate_topology_incremental ON md_geo_obm;


-- ============================================================================
-- STEP 2: Ensure geometries have 2 decimal place precision
-- ============================================================================
-- Run these to check and fix precision issues:
-- SELECT * FROM validate_2_decimal_places();
-- SELECT * FROM set_to_2_decimal_places();
-- SELECT * FROM validate_2_decimal_places();


-- ============================================================================
-- STEP 3: Initialize Slovenia boundary from obmocja union
-- ============================================================================
-- The slo_meja table stores the outer boundary of all obmocja combined.
-- This is used to detect holes (uncovered areas) and overflows.

TRUNCATE TABLE slo_meja;

INSERT INTO slo_meja(id, created_at, created_by, geom)
SELECT
    uuid_generate_v4() AS id,
    now()::timestamp,
    '848956e8-d73e-11f0-9ff0-02420a000f64',
    ST_MakePolygon(ST_ExteriorRing(
        ST_ReducePrecision(
            ST_Union(md_geo_obm.geom),
            0.01
        )
    )) AS geom
FROM md_geo_obm;


-- ============================================================================
-- STEP 4: Create index on OBM topology controls table
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_topoloske_kontrole_obm
ON md_topoloske_kontrole_obm (
    id_rel_geo_verzija,
    topology_problem_type,
    id1,
    id2
);


-- ============================================================================
-- STEP 5: Add constraints to OBM topology controls table
-- ============================================================================

-- Constraint: topology_problem_type must be valid for OBM
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'check_topology_problem_type_obm'
    ) THEN
        ALTER TABLE md_topoloske_kontrole_obm
        ADD CONSTRAINT check_topology_problem_type_obm
        CHECK (topology_problem_type IN ('intersection', 'hole', 'overflow'));
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
-- STEP 6: Run initial topology validation
-- ============================================================================
-- This populates md_topoloske_kontrole_obm with all topology issues.
-- Uncomment to run:

-- SELECT * FROM validate_all_topologies();


-- ============================================================================
-- STEP 7: Re-enable incremental trigger
-- ============================================================================
-- After initial validation, the trigger handles incremental updates.
-- This is done by running 5trigger.sql

-- To enable the trigger, run:
-- \i 5trigger.sql


-- ============================================================================
-- STEP 8: Create hierarchy validation table
-- ============================================================================
-- This table stores ID-based validation problems for cona/lao/tao hierarchy

CREATE TABLE IF NOT EXISTS md_topoloske_kontrole_hierarhija (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMP DEFAULT now(),
    created_by UUID,
    id_rel_geo_verzija UUID NOT NULL,
    entity_type TEXT NOT NULL,  -- 'cona', 'lao', 'tao'
    problem_type TEXT NOT NULL,
    entity_id UUID,             -- The entity with the problem
    reference_id UUID,          -- The missing/orphan reference
    details TEXT                -- Additional context
);

CREATE INDEX IF NOT EXISTS idx_topoloske_kontrole_hierarhija
ON md_topoloske_kontrole_hierarhija (
    id_rel_geo_verzija,
    entity_type,
    problem_type
);

-- Constraint: entity_type must be valid
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'check_entity_type_hierarhija'
    ) THEN
        ALTER TABLE md_topoloske_kontrole_hierarhija
        ADD CONSTRAINT check_entity_type_hierarhija
        CHECK (entity_type IN ('cona', 'lao', 'tao'));
    END IF;
END $$;

-- Constraint: problem_type must be valid
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'check_problem_type_hierarhija'
    ) THEN
        ALTER TABLE md_topoloske_kontrole_hierarhija
        ADD CONSTRAINT check_problem_type_hierarhija
        CHECK (problem_type IN (
            'missing_obm_in_cona', 'orphan_obm_ref', 'orphan_cona_ref', 'empty_cona',
            'missing_cona_in_lao', 'orphan_lao_ref_in_cona', 'empty_lao',
            'missing_lao_in_tao', 'orphan_tao_ref_in_lao', 'empty_tao'
        ));
    END IF;
END $$;


-- ============================================================================
-- STEP 9: Run initial hierarchy validation
-- ============================================================================
-- This populates md_topoloske_kontrole_hierarhija with all hierarchy issues.
-- Uncomment to run:

-- SELECT * FROM validate_all_hierarchies();


-- ============================================================================
-- STEP 10: Enable hierarchy triggers
-- ============================================================================
-- After initial validation, the triggers handle incremental updates.
-- This is done by running 7triggerHierarchy.sql

-- To enable the triggers, run:
-- \i 7triggerHierarchy.sql


-- ============================================================================
-- Manual fixing functions (use with caution):
-- ============================================================================
-- SELECT * FROM fix_holes();
-- SELECT * FROM fix_overflows();
-- SELECT * FROM fix_intersections();
