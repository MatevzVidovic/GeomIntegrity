-- ============================================================================
-- 7triggerHierarchy.sql - Incremental Hierarchy Validation Triggers
-- ============================================================================
-- This file contains triggers for incremental validation of the hierarchy
-- (cona/lao/tao relationships).
--
-- Unlike OBM validation (which is geometric), these are purely ID-based checks
-- that fire when relationships change.
-- ============================================================================


-- ============================================================================
-- TRIGGER FUNCTION: validate_obmxcona_incremental
-- ============================================================================
-- Fires on INSERT/UPDATE/DELETE of md_geo_obmxcona
-- Validates that:
--   - The referenced OBM exists
--   - The referenced cona exists

DROP FUNCTION IF EXISTS validate_obmxcona_incremental();

CREATE OR REPLACE FUNCTION validate_obmxcona_incremental()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_rel_geo_verzija UUID;
    v_obm_exists BOOLEAN;
    v_cona_exists BOOLEAN;
BEGIN
    -- ========================================================================
    -- PHASE 1: HANDLE REMOVAL (DELETE or UPDATE)
    -- ========================================================================
    IF (TG_OP = 'DELETE' OR TG_OP = 'UPDATE') THEN
        -- Get the geo version from the old cona
        SELECT id_rel_geo_verzija INTO v_id_rel_geo_verzija
        FROM md_geo_cona
        WHERE id = OLD.id_rel_geo_cona;

        IF v_id_rel_geo_verzija IS NOT NULL THEN
            -- Remove any existing problems related to this link
            DELETE FROM md_topoloske_kontrole_hierarhija
            WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
              AND entity_type = 'cona'
              AND (
                  (problem_type = 'orphan_obm_ref' AND reference_id = OLD.id_rel_geo_obm)
                  OR (problem_type = 'orphan_cona_ref' AND reference_id = OLD.id_rel_geo_cona)
              );

            -- Check if the OBM is now orphaned (not in any cona)
            IF NOT EXISTS (
                SELECT 1 FROM md_geo_obmxcona xc
                WHERE xc.id_rel_geo_obm = OLD.id_rel_geo_obm
                  AND xc.id_rel_geo_cona != OLD.id_rel_geo_cona
            ) THEN
                -- Check if the OBM still exists
                IF EXISTS (
                    SELECT 1 FROM md_geo_obm
                    WHERE id = OLD.id_rel_geo_obm
                      AND id_rel_geo_verzija = v_id_rel_geo_verzija
                ) THEN
                    INSERT INTO md_topoloske_kontrole_hierarhija (
                        id, created_at, created_by, id_rel_geo_verzija,
                        entity_type, problem_type, entity_id, details
                    )
                    SELECT
                        uuid_generate_v4(),
                        now()::timestamp,
                        '848956e8-d73e-11f0-9ff0-02420a000f64',
                        v_id_rel_geo_verzija,
                        'cona',
                        'missing_obm_in_cona',
                        obm.id,
                        'OBM "' || COALESCE(obm.ime_obmocja, obm.id::text) || '" is not assigned to any cona'
                    FROM md_geo_obm obm
                    WHERE obm.id = OLD.id_rel_geo_obm;
                END IF;
            END IF;

            -- Check if the cona is now empty
            IF NOT EXISTS (
                SELECT 1 FROM md_geo_obmxcona xc
                WHERE xc.id_rel_geo_cona = OLD.id_rel_geo_cona
                  AND (TG_OP = 'DELETE' OR xc.id_rel_geo_obm != OLD.id_rel_geo_obm)
            ) THEN
                INSERT INTO md_topoloske_kontrole_hierarhija (
                    id, created_at, created_by, id_rel_geo_verzija,
                    entity_type, problem_type, entity_id, details
                )
                SELECT
                    uuid_generate_v4(),
                    now()::timestamp,
                    '848956e8-d73e-11f0-9ff0-02420a000f64',
                    v_id_rel_geo_verzija,
                    'cona',
                    'empty_cona',
                    c.id,
                    'Cona "' || COALESCE(c.ime_cone, c.id::text) || '" has no OBMs assigned'
                FROM md_geo_cona c
                WHERE c.id = OLD.id_rel_geo_cona
                  AND NOT EXISTS (
                      SELECT 1 FROM md_topoloske_kontrole_hierarhija
                      WHERE entity_id = c.id
                        AND problem_type = 'empty_cona'
                  );
            END IF;
        END IF;
    END IF;

    -- ========================================================================
    -- PHASE 2: HANDLE ADDITION (INSERT or UPDATE)
    -- ========================================================================
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        -- Get the geo version from the new cona
        SELECT id_rel_geo_verzija INTO v_id_rel_geo_verzija
        FROM md_geo_cona
        WHERE id = NEW.id_rel_geo_cona;

        -- Check if OBM exists
        v_obm_exists := EXISTS (
            SELECT 1 FROM md_geo_obm
            WHERE id = NEW.id_rel_geo_obm
        );

        -- Check if cona exists
        v_cona_exists := EXISTS (
            SELECT 1 FROM md_geo_cona
            WHERE id = NEW.id_rel_geo_cona
        );

        IF NOT v_obm_exists THEN
            -- Record orphan OBM reference
            INSERT INTO md_topoloske_kontrole_hierarhija (
                id, created_at, created_by, id_rel_geo_verzija,
                entity_type, problem_type, reference_id, details
            )
            VALUES (
                uuid_generate_v4(),
                now()::timestamp,
                '848956e8-d73e-11f0-9ff0-02420a000f64',
                v_id_rel_geo_verzija,
                'cona',
                'orphan_obm_ref',
                NEW.id_rel_geo_obm,
                'obmxcona references non-existent OBM: ' || NEW.id_rel_geo_obm::text
            );
        ELSE
            -- Remove any "missing_obm_in_cona" problem for this OBM
            DELETE FROM md_topoloske_kontrole_hierarhija
            WHERE entity_type = 'cona'
              AND problem_type = 'missing_obm_in_cona'
              AND entity_id = NEW.id_rel_geo_obm;
        END IF;

        IF NOT v_cona_exists THEN
            -- Try to get version from OBM instead
            IF v_id_rel_geo_verzija IS NULL THEN
                SELECT id_rel_geo_verzija INTO v_id_rel_geo_verzija
                FROM md_geo_obm
                WHERE id = NEW.id_rel_geo_obm;
            END IF;

            -- Record orphan cona reference
            INSERT INTO md_topoloske_kontrole_hierarhija (
                id, created_at, created_by, id_rel_geo_verzija,
                entity_type, problem_type, reference_id, details
            )
            VALUES (
                uuid_generate_v4(),
                now()::timestamp,
                '848956e8-d73e-11f0-9ff0-02420a000f64',
                v_id_rel_geo_verzija,
                'cona',
                'orphan_cona_ref',
                NEW.id_rel_geo_cona,
                'obmxcona references non-existent cona: ' || NEW.id_rel_geo_cona::text
            );
        ELSE
            -- Remove any "empty_cona" problem for this cona
            DELETE FROM md_topoloske_kontrole_hierarhija
            WHERE entity_type = 'cona'
              AND problem_type = 'empty_cona'
              AND entity_id = NEW.id_rel_geo_cona;
        END IF;
    END IF;

    -- Return appropriate value
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;


-- ============================================================================
-- TRIGGER: trg_validate_obmxcona_incremental
-- ============================================================================
DROP TRIGGER IF EXISTS trg_validate_obmxcona_incremental ON md_geo_obmxcona;

CREATE TRIGGER trg_validate_obmxcona_incremental
    AFTER INSERT OR UPDATE OR DELETE ON md_geo_obmxcona
    FOR EACH ROW
    EXECUTE FUNCTION validate_obmxcona_incremental();


-- ============================================================================
-- TRIGGER FUNCTION: validate_cona_lao_incremental
-- ============================================================================
-- Fires on INSERT/UPDATE/DELETE of md_geo_cona (when id_rel_geo_lao changes)
-- Validates that the referenced LAO exists

DROP FUNCTION IF EXISTS validate_cona_lao_incremental();

CREATE OR REPLACE FUNCTION validate_cona_lao_incremental()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_lao_exists BOOLEAN;
BEGIN
    -- ========================================================================
    -- PHASE 1: HANDLE REMOVAL (DELETE or UPDATE of id_rel_geo_lao)
    -- ========================================================================
    IF (TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD.id_rel_geo_lao IS DISTINCT FROM NEW.id_rel_geo_lao)) THEN
        -- Remove old problems for this cona
        DELETE FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_geo_verzija = OLD.id_rel_geo_verzija
          AND entity_type = 'lao'
          AND entity_id = OLD.id;

        -- Check if the old LAO is now empty
        IF OLD.id_rel_geo_lao IS NOT NULL THEN
            IF NOT EXISTS (
                SELECT 1 FROM md_geo_cona c
                WHERE c.id_rel_geo_lao = OLD.id_rel_geo_lao
                  AND c.id != OLD.id
                  AND c.id_rel_geo_verzija = OLD.id_rel_geo_verzija
            ) THEN
                INSERT INTO md_topoloske_kontrole_hierarhija (
                    id, created_at, created_by, id_rel_geo_verzija,
                    entity_type, problem_type, entity_id, details
                )
                SELECT
                    uuid_generate_v4(),
                    now()::timestamp,
                    '848956e8-d73e-11f0-9ff0-02420a000f64',
                    OLD.id_rel_geo_verzija,
                    'lao',
                    'empty_lao',
                    l.id,
                    'LAO "' || COALESCE(l.ime_lao, l.id::text) || '" has no conas assigned'
                FROM md_geo_lao l
                WHERE l.id = OLD.id_rel_geo_lao
                  AND NOT EXISTS (
                      SELECT 1 FROM md_topoloske_kontrole_hierarhija
                      WHERE entity_id = l.id
                        AND problem_type = 'empty_lao'
                  );
            END IF;
        END IF;
    END IF;

    -- ========================================================================
    -- PHASE 2: HANDLE ADDITION (INSERT or UPDATE of id_rel_geo_lao)
    -- ========================================================================
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        IF NEW.id_rel_geo_lao IS NULL THEN
            -- Cona not assigned to any LAO
            INSERT INTO md_topoloske_kontrole_hierarhija (
                id, created_at, created_by, id_rel_geo_verzija,
                entity_type, problem_type, entity_id, details
            )
            VALUES (
                uuid_generate_v4(),
                now()::timestamp,
                '848956e8-d73e-11f0-9ff0-02420a000f64',
                NEW.id_rel_geo_verzija,
                'lao',
                'missing_cona_in_lao',
                NEW.id,
                'Cona "' || COALESCE(NEW.ime_cone, NEW.id::text) || '" is not assigned to any LAO'
            );
        ELSE
            -- Check if LAO exists
            v_lao_exists := EXISTS (
                SELECT 1 FROM md_geo_lao
                WHERE id = NEW.id_rel_geo_lao
            );

            IF NOT v_lao_exists THEN
                -- Record orphan LAO reference
                INSERT INTO md_topoloske_kontrole_hierarhija (
                    id, created_at, created_by, id_rel_geo_verzija,
                    entity_type, problem_type, entity_id, reference_id, details
                )
                VALUES (
                    uuid_generate_v4(),
                    now()::timestamp,
                    '848956e8-d73e-11f0-9ff0-02420a000f64',
                    NEW.id_rel_geo_verzija,
                    'lao',
                    'orphan_lao_ref_in_cona',
                    NEW.id,
                    NEW.id_rel_geo_lao,
                    'Cona "' || COALESCE(NEW.ime_cone, NEW.id::text) || '" references non-existent LAO: ' || NEW.id_rel_geo_lao::text
                );
            ELSE
                -- Remove any "empty_lao" problem for this LAO
                DELETE FROM md_topoloske_kontrole_hierarhija
                WHERE entity_type = 'lao'
                  AND problem_type = 'empty_lao'
                  AND entity_id = NEW.id_rel_geo_lao;
            END IF;
        END IF;
    END IF;

    -- Return appropriate value
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;


-- ============================================================================
-- TRIGGER: trg_validate_cona_lao_incremental
-- ============================================================================
DROP TRIGGER IF EXISTS trg_validate_cona_lao_incremental ON md_geo_cona;

CREATE TRIGGER trg_validate_cona_lao_incremental
    AFTER INSERT OR UPDATE OF id_rel_geo_lao OR DELETE ON md_geo_cona
    FOR EACH ROW
    EXECUTE FUNCTION validate_cona_lao_incremental();


-- ============================================================================
-- TRIGGER FUNCTION: validate_lao_tao_incremental
-- ============================================================================
-- Fires on INSERT/UPDATE/DELETE of md_geo_lao (when id_rel_geo_tao changes)
-- Validates that the referenced TAO exists

DROP FUNCTION IF EXISTS validate_lao_tao_incremental();

CREATE OR REPLACE FUNCTION validate_lao_tao_incremental()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_tao_exists BOOLEAN;
    v_id_rel_geo_verzija UUID;
BEGIN
    -- Get the geo version from related conas
    SELECT DISTINCT c.id_rel_geo_verzija INTO v_id_rel_geo_verzija
    FROM md_geo_cona c
    WHERE c.id_rel_geo_lao = COALESCE(NEW.id, OLD.id)
    LIMIT 1;

    -- ========================================================================
    -- PHASE 1: HANDLE REMOVAL (DELETE or UPDATE of id_rel_geo_tao)
    -- ========================================================================
    IF (TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD.id_rel_geo_tao IS DISTINCT FROM NEW.id_rel_geo_tao)) THEN
        -- Remove old problems for this LAO
        DELETE FROM md_topoloske_kontrole_hierarhija
        WHERE entity_type = 'tao'
          AND entity_id = OLD.id;

        -- Check if the old TAO is now empty
        IF OLD.id_rel_geo_tao IS NOT NULL THEN
            IF NOT EXISTS (
                SELECT 1 FROM md_geo_lao l
                WHERE l.id_rel_geo_tao = OLD.id_rel_geo_tao
                  AND l.id != OLD.id
                  AND l.id_rel_verzije_modeli = OLD.id_rel_verzije_modeli
            ) THEN
                INSERT INTO md_topoloske_kontrole_hierarhija (
                    id, created_at, created_by, id_rel_geo_verzija,
                    entity_type, problem_type, entity_id, details
                )
                SELECT
                    uuid_generate_v4(),
                    now()::timestamp,
                    '848956e8-d73e-11f0-9ff0-02420a000f64',
                    v_id_rel_geo_verzija,
                    'tao',
                    'empty_tao',
                    t.id,
                    'TAO id_tao=' || t.id_tao::text || ' has no LAOs assigned'
                FROM md_geo_tao t
                WHERE t.id = OLD.id_rel_geo_tao
                  AND NOT EXISTS (
                      SELECT 1 FROM md_topoloske_kontrole_hierarhija
                      WHERE entity_id = t.id
                        AND problem_type = 'empty_tao'
                  );
            END IF;
        END IF;
    END IF;

    -- ========================================================================
    -- PHASE 2: HANDLE ADDITION (INSERT or UPDATE of id_rel_geo_tao)
    -- ========================================================================
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        IF NEW.id_rel_geo_tao IS NULL THEN
            -- LAO not assigned to any TAO
            INSERT INTO md_topoloske_kontrole_hierarhija (
                id, created_at, created_by, id_rel_geo_verzija,
                entity_type, problem_type, entity_id, details
            )
            VALUES (
                uuid_generate_v4(),
                now()::timestamp,
                '848956e8-d73e-11f0-9ff0-02420a000f64',
                v_id_rel_geo_verzija,
                'tao',
                'missing_lao_in_tao',
                NEW.id,
                'LAO "' || COALESCE(NEW.ime_lao, NEW.id::text) || '" is not assigned to any TAO'
            );
        ELSE
            -- Check if TAO exists
            v_tao_exists := EXISTS (
                SELECT 1 FROM md_geo_tao
                WHERE id = NEW.id_rel_geo_tao
            );

            IF NOT v_tao_exists THEN
                -- Record orphan TAO reference
                INSERT INTO md_topoloske_kontrole_hierarhija (
                    id, created_at, created_by, id_rel_geo_verzija,
                    entity_type, problem_type, entity_id, reference_id, details
                )
                VALUES (
                    uuid_generate_v4(),
                    now()::timestamp,
                    '848956e8-d73e-11f0-9ff0-02420a000f64',
                    v_id_rel_geo_verzija,
                    'tao',
                    'orphan_tao_ref_in_lao',
                    NEW.id,
                    NEW.id_rel_geo_tao,
                    'LAO "' || COALESCE(NEW.ime_lao, NEW.id::text) || '" references non-existent TAO: ' || NEW.id_rel_geo_tao::text
                );
            ELSE
                -- Remove any "empty_tao" problem for this TAO
                DELETE FROM md_topoloske_kontrole_hierarhija
                WHERE entity_type = 'tao'
                  AND problem_type = 'empty_tao'
                  AND entity_id = NEW.id_rel_geo_tao;
            END IF;
        END IF;
    END IF;

    -- Return appropriate value
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;


-- ============================================================================
-- TRIGGER: trg_validate_lao_tao_incremental
-- ============================================================================
DROP TRIGGER IF EXISTS trg_validate_lao_tao_incremental ON md_geo_lao;

CREATE TRIGGER trg_validate_lao_tao_incremental
    AFTER INSERT OR UPDATE OF id_rel_geo_tao OR DELETE ON md_geo_lao
    FOR EACH ROW
    EXECUTE FUNCTION validate_lao_tao_incremental();
