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
-- Scoping: all hierarchy validation is per id_rel_verzije_modeli (model version).
-- The OBM version (id_rel_geo_verzija) is derived via:
--   md_verzije_modeli.id_rel_geo_verzija
-- Multiple model versions can share the same OBM version, so model version
-- is the correct discriminator for hierarchy checks.
--
-- Results are stored in md_topoloske_kontrole_hierarhija using the
-- id_rel_verzije_modeli field as the version discriminator.
--
-- Problem types:
--   - 'obm. v nobeni coni': An OBM exists but is not assigned to any cona
--   - 'napačno obm.': obmxcona references an OBM that doesn't exist
--   - 'cone ne obstaja': obmxcona references a cona that doesn't exist
--   - 'cona brez obm.': A cona exists but has no OBMs assigned
--   - 'cona v nobenem LAO': A cona exists but is not assigned to any lao
--   - 'LAO ne obstaja': A cona references a lao that doesn't exist
--   - 'LAO brez cone': A lao exists but has no conas assigned
--   - 'LAO v nobenem TAO': A lao exists but is not assigned to any tao
--   - 'TAO ne obstaja': A lao references a tao that doesn't exist
--   - 'TAO brez LAO': A tao exists but has no laos assigned
-- ============================================================================


-- ============================================================================
-- FUNCTION: validate_cona_hierarchy
-- ============================================================================
-- Validates that:
-- 1. Every OBM for a version is assigned to exactly one cona
-- 2. Every cona has at least one OBM
-- 3. All references in obmxcona are valid

DROP FUNCTION IF EXISTS validate_cona_hierarchy(uuid);

CREATE OR REPLACE FUNCTION validate_cona_hierarchy(p_id_rel_verzije_modeli uuid)
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
    v_id_rel_geo_verzija UUID;
BEGIN
    -- Get the OBM version for this model version
    SELECT id_rel_geo_verzija INTO v_id_rel_geo_verzija
    FROM md_verzije_modeli
    WHERE id = p_id_rel_verzije_modeli;

    IF v_id_rel_geo_verzija IS NULL THEN
        RETURN QUERY SELECT 0, 0, 0, 0;
        RETURN;
    END IF;

    -- Clear existing cona problems for this model version
    DELETE FROM md_topoloske_kontrole_hierarhija
    WHERE id_rel_verzije_modeli = p_id_rel_verzije_modeli
      AND tip_entitete = 'cona';

    -- 1. Find OBMs not assigned to any cona
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_verzije_modeli,
        tip_entitete, tip_problema, problematicen_id
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '00000000-0000-0000-0000-000000000000'::uuid,
        p_id_rel_verzije_modeli,
        'cona',
        'obm. v nobeni coni',
        obm.id
    FROM md_geo_obm obm
    WHERE obm.id_rel_geo_verzija = v_id_rel_geo_verzija
      AND NOT EXISTS (
          SELECT 1 FROM md_geo_obmxcona xc
          WHERE xc.id_rel_geo_obm = obm.id
      );
    GET DIAGNOSTICS v_missing_obms = ROW_COUNT;

    -- 2. Find obmxcona entries referencing non-existent OBMs
    --    (scoped to conas belonging to this model version)
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_verzije_modeli,
        tip_entitete, tip_problema, problematicen_id
    )
    SELECT DISTINCT
        uuid_generate_v4(),
        now()::timestamp,
        '00000000-0000-0000-0000-000000000000'::uuid,
        p_id_rel_verzije_modeli,
        'cona',
        'napačno obm.',
        xc.id_rel_geo_obm
    FROM md_geo_obmxcona xc
    JOIN md_geo_cona c ON xc.id_rel_geo_cona = c.id
    WHERE c.id_rel_verzije_modeli = p_id_rel_verzije_modeli
      AND NOT EXISTS (
          SELECT 1 FROM md_geo_obm obm
          WHERE obm.id = xc.id_rel_geo_obm
            AND obm.id_rel_geo_verzija = v_id_rel_geo_verzija
      );
    GET DIAGNOSTICS v_orphan_obm_refs = ROW_COUNT;

    -- 3. Find obmxcona entries referencing non-existent conas
    --    (scoped via OBMs belonging to this version)
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_verzije_modeli,
        tip_entitete, tip_problema, problematicen_id
    )
    SELECT DISTINCT
        uuid_generate_v4(),
        now()::timestamp,
        '00000000-0000-0000-0000-000000000000'::uuid,
        p_id_rel_verzije_modeli,
        'cona',
        'cone ne obstaja',
        xc.id_rel_geo_cona
    FROM md_geo_obmxcona xc
    JOIN md_geo_obm obm ON xc.id_rel_geo_obm = obm.id
    WHERE obm.id_rel_geo_verzija = v_id_rel_geo_verzija
      AND NOT EXISTS (
          SELECT 1 FROM md_geo_cona c
          WHERE c.id = xc.id_rel_geo_cona
      );
    GET DIAGNOSTICS v_orphan_cona_refs = ROW_COUNT;

    -- 4. Find conas with no OBMs (for this model version)
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_verzije_modeli,
        tip_entitete, tip_problema, problematicen_id
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '00000000-0000-0000-0000-000000000000'::uuid,
        p_id_rel_verzije_modeli,
        'cona',
        'cona brez obm.',
        c.id
    FROM md_geo_cona c
    WHERE c.id_rel_verzije_modeli = p_id_rel_verzije_modeli
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
-- 1. Every cona for a model version is assigned to a lao (via id_rel_geo_lao)
-- 2. Every lao has at least one cona
-- 3. All lao references in conas are valid

DROP FUNCTION IF EXISTS validate_lao_hierarchy(uuid);

CREATE OR REPLACE FUNCTION validate_lao_hierarchy(p_id_rel_verzije_modeli uuid)
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
    -- Clear existing lao problems for this model version
    DELETE FROM md_topoloske_kontrole_hierarhija
    WHERE id_rel_verzije_modeli = p_id_rel_verzije_modeli
      AND tip_entitete = 'lao';

    -- 1. Find conas not assigned to any lao (id_rel_geo_lao IS NULL)
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_verzije_modeli,
        tip_entitete, tip_problema, problematicen_id
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '00000000-0000-0000-0000-000000000000'::uuid,
        p_id_rel_verzije_modeli,
        'lao',
        'cona v nobenem LAO',
        c.id
    FROM md_geo_cona c
    WHERE c.id_rel_verzije_modeli = p_id_rel_verzije_modeli
      AND c.id_rel_geo_lao IS NULL;
    GET DIAGNOSTICS v_missing_conas = ROW_COUNT;

    -- 2. Find conas referencing non-existent laos
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_verzije_modeli,
        tip_entitete, tip_problema, problematicen_id
    )
    SELECT DISTINCT
        uuid_generate_v4(),
        now()::timestamp,
        '00000000-0000-0000-0000-000000000000'::uuid,
        p_id_rel_verzije_modeli,
        'lao',
        'LAO ne obstaja',
        c.id_rel_geo_lao
    FROM md_geo_cona c
    WHERE c.id_rel_verzije_modeli = p_id_rel_verzije_modeli
      AND c.id_rel_geo_lao IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM md_geo_lao l
          WHERE l.id = c.id_rel_geo_lao
      );
    GET DIAGNOSTICS v_orphan_lao_refs = ROW_COUNT;

    -- 3. Find laos with no conas (for this model version)
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_verzije_modeli,
        tip_entitete, tip_problema, problematicen_id
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '00000000-0000-0000-0000-000000000000'::uuid,
        p_id_rel_verzije_modeli,
        'lao',
        'LAO brez cone',
        l.id
    FROM md_geo_lao l
    WHERE l.id_rel_verzije_modeli = p_id_rel_verzije_modeli
      AND NOT EXISTS (
          SELECT 1 FROM md_geo_cona c
          WHERE c.id_rel_geo_lao = l.id
            AND c.id_rel_verzije_modeli = p_id_rel_verzije_modeli
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

CREATE OR REPLACE FUNCTION validate_tao_hierarchy(p_id_rel_verzije_modeli uuid)
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
BEGIN
    -- Clear existing tao problems for this model version
    DELETE FROM md_topoloske_kontrole_hierarhija
    WHERE id_rel_verzije_modeli = p_id_rel_verzije_modeli
      AND tip_entitete = 'tao';

    -- 1. Find laos not assigned to any tao (id_rel_geo_tao IS NULL)
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_verzije_modeli,
        tip_entitete, tip_problema, problematicen_id
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '00000000-0000-0000-0000-000000000000'::uuid,
        p_id_rel_verzije_modeli,
        'tao',
        'LAO v nobenem TAO',
        l.id
    FROM md_geo_lao l
    WHERE l.id_rel_verzije_modeli = p_id_rel_verzije_modeli
      AND l.id_rel_geo_tao IS NULL;
    GET DIAGNOSTICS v_missing_laos = ROW_COUNT;

    -- 2. Find laos referencing non-existent taos
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_verzije_modeli,
        tip_entitete, tip_problema, problematicen_id
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '00000000-0000-0000-0000-000000000000'::uuid,
        p_id_rel_verzije_modeli,
        'tao',
        'TAO ne obstaja',
        l.id_rel_geo_tao
    FROM md_geo_lao l
    WHERE l.id_rel_verzije_modeli = p_id_rel_verzije_modeli
      AND l.id_rel_geo_tao IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM md_geo_tao t
          WHERE t.id = l.id_rel_geo_tao
      );
    GET DIAGNOSTICS v_orphan_tao_refs = ROW_COUNT;

    -- 3. Find taos with no laos (for this model version)
    INSERT INTO md_topoloske_kontrole_hierarhija (
        id, created_at, created_by, id_rel_verzije_modeli,
        tip_entitete, tip_problema, problematicen_id
    )
    SELECT
        uuid_generate_v4(),
        now()::timestamp,
        '00000000-0000-0000-0000-000000000000'::uuid,
        p_id_rel_verzije_modeli,
        'tao',
        'TAO brez LAO',
        t.id
    FROM md_geo_tao t
    WHERE t.id_rel_verzije_modeli = p_id_rel_verzije_modeli
      AND NOT EXISTS (
          SELECT 1 FROM md_geo_lao l
          WHERE l.id_rel_geo_tao = t.id
            AND l.id_rel_verzije_modeli = p_id_rel_verzije_modeli
      );
    GET DIAGNOSTICS v_empty_taos = ROW_COUNT;

    RETURN QUERY SELECT v_missing_laos, v_orphan_tao_refs, v_empty_taos;
END;
$$;


-- ============================================================================
-- FUNCTION: validate_all_hierarchy
-- ============================================================================
-- Runs all hierarchy validations for a given model version

DROP FUNCTION IF EXISTS validate_all_hierarchy(uuid);

CREATE OR REPLACE FUNCTION validate_all_hierarchy(p_id_rel_verzije_modeli uuid)
RETURNS TABLE(
    chosen_id_rel_verzije_modeli uuid,
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
    SELECT * INTO v_cona_results FROM validate_cona_hierarchy(p_id_rel_verzije_modeli);
    SELECT * INTO v_lao_results FROM validate_lao_hierarchy(p_id_rel_verzije_modeli);
    SELECT * INTO v_tao_results FROM validate_tao_hierarchy(p_id_rel_verzije_modeli);

    RETURN QUERY SELECT
        p_id_rel_verzije_modeli,
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
-- Runs all hierarchy validations for all model versions

DROP FUNCTION IF EXISTS validate_all_hierarchies();

CREATE OR REPLACE FUNCTION validate_all_hierarchies()
RETURNS TABLE(
    chosen_id_rel_verzije_modeli uuid,
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
    v_model_version uuid;
BEGIN
    FOR v_model_version IN
        SELECT DISTINCT id
        FROM md_verzije_modeli
        ORDER BY id
    LOOP
        RETURN QUERY
        SELECT *
        FROM validate_all_hierarchy(v_model_version);
    END LOOP;
END;
$$;
