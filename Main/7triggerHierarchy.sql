-- ============================================================================
-- 7triggerHierarchy.sql - Incremental Hierarchy Validation Triggers
-- ============================================================================
-- This file contains triggers for incremental validation of the hierarchy
-- (cona/lao/tao relationships).
--
-- Unlike OBM validation (which is geometric), these are purely ID-based checks
-- that fire when relationships change.
--
-- Each trigger simply determines the affected geo version and calls
-- validate_all_hierarchy() for a full recheck. This is correct and
-- maintainable because the hierarchy tables are small.
-- ============================================================================


DROP TRIGGER IF EXISTS trg_validate_obmxcona_incremental ON md_geo_obmxcona;
DROP TRIGGER IF EXISTS trg_validate_cona_lao_incremental ON md_geo_cona;
DROP TRIGGER IF EXISTS trg_validate_lao_tao_incremental ON md_geo_lao;


-- ============================================================================
-- TRIGGER FUNCTION: validate_obmxcona_incremental
-- ============================================================================
-- Fires on INSERT/UPDATE/DELETE of md_geo_obmxcona.
-- Gets the geo version from the affected OBM, then reruns full validation.

DROP FUNCTION IF EXISTS validate_obmxcona_incremental();

CREATE OR REPLACE FUNCTION validate_obmxcona_incremental()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_rel_geo_verzija UUID;
    v_obm_id UUID;
BEGIN
    v_obm_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id_rel_geo_obm ELSE NEW.id_rel_geo_obm END;

    SELECT id_rel_geo_verzija INTO v_id_rel_geo_verzija
    FROM md_geo_obm
    WHERE id = v_obm_id;

    IF v_id_rel_geo_verzija IS NOT NULL THEN
        PERFORM validate_all_hierarchy(v_id_rel_geo_verzija);
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;


-- ============================================================================
-- TRIGGER: trg_validate_obmxcona_incremental
-- ============================================================================
CREATE TRIGGER trg_validate_obmxcona_incremental
    AFTER INSERT OR UPDATE OR DELETE ON md_geo_obmxcona
    FOR EACH ROW
    EXECUTE FUNCTION validate_obmxcona_incremental();


-- ============================================================================
-- TRIGGER FUNCTION: validate_cona_lao_incremental
-- ============================================================================
-- Fires on INSERT/UPDATE/DELETE of md_geo_cona (when id_rel_geo_lao changes).
-- Gets the geo version from OBMs linked to this cona, then reruns full validation.

DROP FUNCTION IF EXISTS validate_cona_lao_incremental();

CREATE OR REPLACE FUNCTION validate_cona_lao_incremental()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_rel_geo_verzija UUID;
    v_cona_id UUID;
BEGIN
    v_cona_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;

    SELECT DISTINCT obm.id_rel_geo_verzija INTO v_id_rel_geo_verzija
    FROM md_geo_obm obm
    JOIN md_geo_obmxcona xc ON xc.id_rel_geo_obm = obm.id
    WHERE xc.id_rel_geo_cona = v_cona_id
    LIMIT 1;

    IF v_id_rel_geo_verzija IS NOT NULL THEN
        PERFORM validate_all_hierarchy(v_id_rel_geo_verzija);
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;


-- ============================================================================
-- TRIGGER: trg_validate_cona_lao_incremental
-- ============================================================================
CREATE TRIGGER trg_validate_cona_lao_incremental
    AFTER INSERT OR UPDATE OF id_rel_geo_lao OR DELETE ON md_geo_cona
    FOR EACH ROW
    EXECUTE FUNCTION validate_cona_lao_incremental();


-- ============================================================================
-- TRIGGER FUNCTION: validate_lao_tao_incremental
-- ============================================================================
-- Fires on INSERT/UPDATE/DELETE of md_geo_lao (when id_rel_geo_tao changes).
-- Gets the geo version from OBMs linked through conas in this LAO.
-- Falls back to the model version ID if no OBMs are reachable
-- (e.g. all conas under this LAO are empty).

DROP FUNCTION IF EXISTS validate_lao_tao_incremental();

CREATE OR REPLACE FUNCTION validate_lao_tao_incremental()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_rel_geo_verzija UUID;
    v_lao_id UUID;
BEGIN
    v_lao_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;

    SELECT DISTINCT obm.id_rel_geo_verzija INTO v_id_rel_geo_verzija
    FROM md_geo_obm obm
    JOIN md_geo_obmxcona xc ON xc.id_rel_geo_obm = obm.id
    JOIN md_geo_cona c ON xc.id_rel_geo_cona = c.id
    WHERE c.id_rel_geo_lao = v_lao_id
    LIMIT 1;

    -- Fallback: if no OBMs reachable (conas are empty), use model version
    IF v_id_rel_geo_verzija IS NULL THEN
        v_id_rel_geo_verzija := CASE WHEN TG_OP = 'DELETE' THEN OLD.id_rel_verzije_modeli ELSE NEW.id_rel_verzije_modeli END;
    END IF;

    IF v_id_rel_geo_verzija IS NOT NULL THEN
        PERFORM validate_all_hierarchy(v_id_rel_geo_verzija);
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;


-- ============================================================================
-- TRIGGER: trg_validate_lao_tao_incremental
-- ============================================================================
CREATE TRIGGER trg_validate_lao_tao_incremental
    AFTER INSERT OR UPDATE OF id_rel_geo_tao OR DELETE ON md_geo_lao
    FOR EACH ROW
    EXECUTE FUNCTION validate_lao_tao_incremental();
