-- ============================================================================
-- 6validateHierarchy.sql - Cona/Lao/Tao Hierarchy Validation
-- ============================================================================
-- This file contains validation functions for the hierarchy above OBM:
--   - Cona: must contain exactly the OBMs assigned to it via obmxcona
--   - Lao: must contain exactly the Conas assigned to it
--   - Tao: must contain exactly the Laos assigned to it
--
-- These are ID-based checks, not geometric operations.
--
-- Problem types:
--   - 'missing_obm_in_cona': An OBM exists but is not assigned to any cona
--   - 'orphan_obm_ref': obmxcona references an OBM that doesn't exist
--   - 'orphan_cona_ref': obmxcona references a cona that doesn't exist
--   - 'empty_cona': A cona exists but has no OBMs assigned
--   - 'missing_cona_in_lao': A cona exists but is not assigned to any lao
--   - 'orphan_lao_ref_in_cona': A cona references a lao that doesn't exist
--   - 'empty_lao': A lao exists but has no conas assigned
--   - 'missing_lao_in_tao': A lao exists but is not assigned to any tao
--   - 'orphan_tao_ref_in_lao': A lao references a tao that doesn't exist
--   - 'empty_tao': A tao exists but has no laos assigned
-- ============================================================================


-- ============================================================================
-- Table: md_topoloske_kontrole_hierarhija
-- ============================================================================
-- Stores hierarchy validation problems (ID-based, no geometry)

-- CREATE TABLE IF NOT EXISTS md_topoloske_kontrole_hierarhija (
--     id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
--     created_at TIMESTAMP DEFAULT now(),
--     created_by UUID,
--     id_rel_geo_verzija UUID NOT NULL,
--     entity_type TEXT NOT NULL,  -- 'cona', 'lao', 'tao'
--     problem_type TEXT NOT NULL,
--     entity_id UUID,             -- The entity with the problem
--     reference_id UUID,          -- The missing/orphan reference
--     details TEXT                -- Additional context
-- );

-- CREATE INDEX IF NOT EXISTS idx_topoloske_kontrole_hierarhija
-- ON md_topoloske_kontrole_hierarhija (
--     id_rel_geo_verzija,
--     entity_type,
--     problem_type
-- );


-- ============================================================================
-- FUNCTION: validate_cona_hierarchy
-- ============================================================================
-- Validates that:
-- 1. Every OBM for a version is assigned to exactly one cona
-- 2. Every cona has at least one OBM
-- 3. All references in obmxcona are valid

DROP FUNCTION IF EXISTS validate_cona_hierarchy(uuid);

CREATE OR REPLACE FUNCTION validate_cona_hierarchy(p_id_rel_geo_verzija uuid)
RETURNS TABLE(
    missing_obms INTEGER,
    orphan_obm_refs INTEGER,
    orphan_cona_refs INTEGER,
    empty_conas INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_missing_obms INTEGER := 0;
    v_orphan_obm_refs INTEGER := 0;
    v_orphan_cona_refs INTEGER := 0;
    v_empty_conas INTEGER := 0;
BEGIN
    -- Clear existing cona problems for this version
    DELETE FROM md_topoloske_kontrole_hierarhija
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija
      AND entity_type = 'cona';

    -- 1. Find OBMs not assigned to any cona
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_geo_verzija,
        entity_type, problem_type, entity_id, details
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '848956e8-d73e-11f0-9ff0-02420a000f64',
        p_id_rel_geo_verzija,
        'cona',
        'missing_obm_in_cona',
        obm.id,
        'OBM "' || COALESCE(obm.ime_obmocja, obm.id::text) || '" is not assigned to any cona'
    FROM md_geo_obm obm
    WHERE obm.id_rel_geo_verzija = p_id_rel_geo_verzija
      AND NOT EXISTS (
          SELECT 1 FROM md_geo_obmxcona xc
          WHERE xc.id_rel_geo_obm = obm.id
      );
    GET DIAGNOSTICS v_missing_obms = ROW_COUNT;

    -- 2. Find obmxcona entries referencing non-existent OBMs
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_geo_verzija,
        entity_type, problem_type, reference_id, details
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '848956e8-d73e-11f0-9ff0-02420a000f64',
        p_id_rel_geo_verzija,
        'cona',
        'orphan_obm_ref',
        xc.id_rel_geo_obm,
        'obmxcona references non-existent OBM: ' || xc.id_rel_geo_obm::text
    FROM md_geo_obmxcona xc
    JOIN md_geo_cona c ON xc.id_rel_geo_cona = c.id
    WHERE c.id_rel_geo_verzija = p_id_rel_geo_verzija
      AND NOT EXISTS (
          SELECT 1 FROM md_geo_obm obm
          WHERE obm.id = xc.id_rel_geo_obm
            AND obm.id_rel_geo_verzija = p_id_rel_geo_verzija
      );
    GET DIAGNOSTICS v_orphan_obm_refs = ROW_COUNT;

    -- 3. Find obmxcona entries referencing non-existent conas
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_geo_verzija,
        entity_type, problem_type, reference_id, details
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '848956e8-d73e-11f0-9ff0-02420a000f64',
        p_id_rel_geo_verzija,
        'cona',
        'orphan_cona_ref',
        xc.id_rel_geo_cona,
        'obmxcona references non-existent cona: ' || xc.id_rel_geo_cona::text
    FROM md_geo_obmxcona xc
    JOIN md_geo_obm obm ON xc.id_rel_geo_obm = obm.id
    WHERE obm.id_rel_geo_verzija = p_id_rel_geo_verzija
      AND NOT EXISTS (
          SELECT 1 FROM md_geo_cona c
          WHERE c.id = xc.id_rel_geo_cona
            AND c.id_rel_geo_verzija = p_id_rel_geo_verzija
      );
    GET DIAGNOSTICS v_orphan_cona_refs = ROW_COUNT;

    -- 4. Find conas with no OBMs
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_geo_verzija,
        entity_type, problem_type, entity_id, details
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '848956e8-d73e-11f0-9ff0-02420a000f64',
        p_id_rel_geo_verzija,
        'cona',
        'empty_cona',
        c.id,
        'Cona "' || COALESCE(c.ime_cone, c.id::text) || '" has no OBMs assigned'
    FROM md_geo_cona c
    WHERE c.id_rel_geo_verzija = p_id_rel_geo_verzija
      AND NOT EXISTS (
          SELECT 1 FROM md_geo_obmxcona xc
          WHERE xc.id_rel_geo_cona = c.id
      );
    GET DIAGNOSTICS v_empty_conas = ROW_COUNT;

    RETURN QUERY SELECT v_missing_obms, v_orphan_obm_refs, v_orphan_cona_refs, v_empty_conas;
END;
$$;


-- ============================================================================
-- FUNCTION: validate_lao_hierarchy
-- ============================================================================
-- Validates that:
-- 1. Every cona for a version is assigned to a lao (via id_rel_geo_lao)
-- 2. Every lao has at least one cona
-- 3. All lao references in conas are valid

DROP FUNCTION IF EXISTS validate_lao_hierarchy(uuid);

CREATE OR REPLACE FUNCTION validate_lao_hierarchy(p_id_rel_geo_verzija uuid)
RETURNS TABLE(
    missing_conas INTEGER,
    orphan_lao_refs INTEGER,
    empty_laos INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_missing_conas INTEGER := 0;
    v_orphan_lao_refs INTEGER := 0;
    v_empty_laos INTEGER := 0;
BEGIN
    -- Clear existing lao problems for this version
    DELETE FROM md_topoloske_kontrole_hierarhija
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija
      AND entity_type = 'lao';

    -- 1. Find conas not assigned to any lao (id_rel_geo_lao IS NULL)
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_geo_verzija,
        entity_type, problem_type, entity_id, details
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '848956e8-d73e-11f0-9ff0-02420a000f64',
        p_id_rel_geo_verzija,
        'lao',
        'missing_cona_in_lao',
        c.id,
        'Cona "' || COALESCE(c.ime_cone, c.id::text) || '" is not assigned to any LAO'
    FROM md_geo_cona c
    WHERE c.id_rel_geo_verzija = p_id_rel_geo_verzija
      AND c.id_rel_geo_lao IS NULL;
    GET DIAGNOSTICS v_missing_conas = ROW_COUNT;

    -- 2. Find conas referencing non-existent laos
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_geo_verzija,
        entity_type, problem_type, entity_id, reference_id, details
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '848956e8-d73e-11f0-9ff0-02420a000f64',
        p_id_rel_geo_verzija,
        'lao',
        'orphan_lao_ref_in_cona',
        c.id,
        c.id_rel_geo_lao,
        'Cona "' || COALESCE(c.ime_cone, c.id::text) || '" references non-existent LAO: ' || c.id_rel_geo_lao::text
    FROM md_geo_cona c
    WHERE c.id_rel_geo_verzija = p_id_rel_geo_verzija
      AND c.id_rel_geo_lao IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM md_geo_lao l
          WHERE l.id = c.id_rel_geo_lao
      );
    GET DIAGNOSTICS v_orphan_lao_refs = ROW_COUNT;

    -- 3. Find laos with no conas
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_geo_verzija,
        entity_type, problem_type, entity_id, details
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '848956e8-d73e-11f0-9ff0-02420a000f64',
        p_id_rel_geo_verzija,
        'lao',
        'empty_lao',
        l.id,
        'LAO "' || COALESCE(l.ime_lao, l.id::text) || '" has no conas assigned'
    FROM md_geo_lao l
    WHERE l.id_rel_verzije_modeli = (
        SELECT DISTINCT c.id_rel_verzije_modeli
        FROM md_geo_cona c
        WHERE c.id_rel_geo_verzija = p_id_rel_geo_verzija
        LIMIT 1
    )
      AND NOT EXISTS (
          SELECT 1 FROM md_geo_cona c
          WHERE c.id_rel_geo_lao = l.id
            AND c.id_rel_geo_verzija = p_id_rel_geo_verzija
      );
    GET DIAGNOSTICS v_empty_laos = ROW_COUNT;

    RETURN QUERY SELECT v_missing_conas, v_orphan_lao_refs, v_empty_laos;
END;
$$;


-- ============================================================================
-- FUNCTION: validate_tao_hierarchy
-- ============================================================================
-- Validates that:
-- 1. Every lao is assigned to a tao (via id_rel_geo_tao)
-- 2. Every tao has at least one lao
-- 3. All tao references in laos are valid

DROP FUNCTION IF EXISTS validate_tao_hierarchy(uuid);

CREATE OR REPLACE FUNCTION validate_tao_hierarchy(p_id_rel_geo_verzija uuid)
RETURNS TABLE(
    missing_laos INTEGER,
    orphan_tao_refs INTEGER,
    empty_taos INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_missing_laos INTEGER := 0;
    v_orphan_tao_refs INTEGER := 0;
    v_empty_taos INTEGER := 0;
    v_id_rel_verzije_modeli UUID;
BEGIN
    -- Get the model version ID from conas for this geo version
    SELECT DISTINCT c.id_rel_verzije_modeli INTO v_id_rel_verzije_modeli
    FROM md_geo_cona c
    WHERE c.id_rel_geo_verzija = p_id_rel_geo_verzija
    LIMIT 1;

    IF v_id_rel_verzije_modeli IS NULL THEN
        -- No conas for this version, nothing to validate
        RETURN QUERY SELECT 0, 0, 0;
        RETURN;
    END IF;

    -- Clear existing tao problems for this version
    DELETE FROM md_topoloske_kontrole_hierarhija
    WHERE id_rel_geo_verzija = p_id_rel_geo_verzija
      AND entity_type = 'tao';

    -- 1. Find laos not assigned to any tao (id_rel_geo_tao IS NULL)
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_geo_verzija,
        entity_type, problem_type, entity_id, details
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '848956e8-d73e-11f0-9ff0-02420a000f64',
        p_id_rel_geo_verzija,
        'tao',
        'missing_lao_in_tao',
        l.id,
        'LAO "' || COALESCE(l.ime_lao, l.id::text) || '" is not assigned to any TAO'
    FROM md_geo_lao l
    WHERE l.id_rel_verzije_modeli = v_id_rel_verzije_modeli
      AND l.id_rel_geo_tao IS NULL;
    GET DIAGNOSTICS v_missing_laos = ROW_COUNT;

    -- 2. Find laos referencing non-existent taos
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_geo_verzija,
        entity_type, problem_type, entity_id, reference_id, details
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '848956e8-d73e-11f0-9ff0-02420a000f64',
        p_id_rel_geo_verzija,
        'tao',
        'orphan_tao_ref_in_lao',
        l.id,
        l.id_rel_geo_tao,
        'LAO "' || COALESCE(l.ime_lao, l.id::text) || '" references non-existent TAO: ' || l.id_rel_geo_tao::text
    FROM md_geo_lao l
    WHERE l.id_rel_verzije_modeli = v_id_rel_verzije_modeli
      AND l.id_rel_geo_tao IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM md_geo_tao t
          WHERE t.id = l.id_rel_geo_tao
      );
    GET DIAGNOSTICS v_orphan_tao_refs = ROW_COUNT;

    -- 3. Find taos with no laos
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_geo_verzija,
        entity_type, problem_type, entity_id, details
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '848956e8-d73e-11f0-9ff0-02420a000f64',
        p_id_rel_geo_verzija,
        'tao',
        'empty_tao',
        t.id,
        'TAO id_tao=' || t.id_tao::text || ' has no LAOs assigned'
    FROM md_geo_tao t
    WHERE t.id_rel_verzije_modeli = v_id_rel_verzije_modeli
      AND NOT EXISTS (
          SELECT 1 FROM md_geo_lao l
          WHERE l.id_rel_geo_tao = t.id
            AND l.id_rel_verzije_modeli = v_id_rel_verzije_modeli
      );
    GET DIAGNOSTICS v_empty_taos = ROW_COUNT;

    RETURN QUERY SELECT v_missing_laos, v_orphan_tao_refs, v_empty_taos;
END;
$$;


-- ============================================================================
-- FUNCTION: validate_all_hierarchy
-- ============================================================================
-- Runs all hierarchy validations for a given geo version

DROP FUNCTION IF EXISTS validate_all_hierarchy(uuid);

CREATE OR REPLACE FUNCTION validate_all_hierarchy(p_id_rel_geo_verzija uuid)
RETURNS TABLE(
    chosen_id_rel_geo_verzija uuid,
    cona_missing_obms INTEGER,
    cona_orphan_obm_refs INTEGER,
    cona_orphan_cona_refs INTEGER,
    cona_empty INTEGER,
    lao_missing_conas INTEGER,
    lao_orphan_refs INTEGER,
    lao_empty INTEGER,
    tao_missing_laos INTEGER,
    tao_orphan_refs INTEGER,
    tao_empty INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_cona_results RECORD;
    v_lao_results RECORD;
    v_tao_results RECORD;
BEGIN
    -- Validate cona hierarchy
    SELECT * INTO v_cona_results FROM validate_cona_hierarchy(p_id_rel_geo_verzija);

    -- Validate lao hierarchy
    SELECT * INTO v_lao_results FROM validate_lao_hierarchy(p_id_rel_geo_verzija);

    -- Validate tao hierarchy
    SELECT * INTO v_tao_results FROM validate_tao_hierarchy(p_id_rel_geo_verzija);

    RETURN QUERY SELECT
        p_id_rel_geo_verzija,
        v_cona_results.missing_obms,
        v_cona_results.orphan_obm_refs,
        v_cona_results.orphan_cona_refs,
        v_cona_results.empty_conas,
        v_lao_results.missing_conas,
        v_lao_results.orphan_lao_refs,
        v_lao_results.empty_laos,
        v_tao_results.missing_laos,
        v_tao_results.orphan_tao_refs,
        v_tao_results.empty_taos;
END;
$$;


-- ============================================================================
-- FUNCTION: validate_all_hierarchies
-- ============================================================================
-- Runs all hierarchy validations for all geo versions

DROP FUNCTION IF EXISTS validate_all_hierarchies();

CREATE OR REPLACE FUNCTION validate_all_hierarchies()
RETURNS TABLE(
    chosen_id_rel_geo_verzija uuid,
    cona_missing_obms INTEGER,
    cona_orphan_obm_refs INTEGER,
    cona_orphan_cona_refs INTEGER,
    cona_empty INTEGER,
    lao_missing_conas INTEGER,
    lao_orphan_refs INTEGER,
    lao_empty INTEGER,
    tao_missing_laos INTEGER,
    tao_orphan_refs INTEGER,
    tao_empty INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_version uuid;
BEGIN
    -- Process each version
    FOR v_version IN
        SELECT DISTINCT md_geo_obm.id_rel_geo_verzija
        FROM md_geo_obm
        ORDER BY md_geo_obm.id_rel_geo_verzija
    LOOP
        RETURN QUERY
        SELECT *
        FROM validate_all_hierarchy(v_version);
    END LOOP;
END;
$$;
