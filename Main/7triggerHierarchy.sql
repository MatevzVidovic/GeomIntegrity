-- ============================================================================
-- 7triggerHierarchy.sql - Incremental Hierarchy Validation Triggers
-- ============================================================================
-- This file contains triggers for incremental validation of the hierarchy
-- (cona/lao/tao relationships).
--
-- Unlike OBM validation (which is geometric), these are purely ID-based checks
-- that fire when relationships change.
--
-- Each trigger determines the affected model version (id_rel_verzije_modeli)
-- and calls validate_all_hierarchy() for a full recheck. This is correct and
-- maintainable because the hierarchy tables are small.
--
-- Cona and LAO rows carry id_rel_verzije_modeli directly, so no joins are
-- needed in those triggers. Only the obmxcona trigger needs a join to get
-- the model version from the cona.
-- ============================================================================


DROP TRIGGER IF EXISTS trg_validate_obmxcona_incremental ON md_geo_obmxcona;
DROP TRIGGER IF EXISTS trg_validate_cona_lao_incremental ON md_geo_cona;
DROP TRIGGER IF EXISTS trg_validate_lao_tao_incremental ON md_geo_lao;


-- ============================================================================
-- TRIGGER FUNCTION: validate_obmxcona_incremental
-- ============================================================================
-- Fires on INSERT/UPDATE/DELETE of md_geo_obmxcona.
-- Gets the model version from the affected cona, then reruns full validation.

DROP FUNCTION IF EXISTS validate_obmxcona_incremental();

CREATE OR REPLACE FUNCTION validate_obmxcona_incremental()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_id_rel_verzije_modeli UUID;
    v_new_id_rel_verzije_modeli UUID;
BEGIN
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
        SELECT id_rel_verzije_modeli INTO v_old_id_rel_verzije_modeli
        FROM md_geo_cona
        WHERE id = OLD.id_rel_geo_cona;
    END IF;

    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        SELECT id_rel_verzije_modeli INTO v_new_id_rel_verzije_modeli
        FROM md_geo_cona
        WHERE id = NEW.id_rel_geo_cona;
    END IF;

    IF v_old_id_rel_verzije_modeli IS NOT NULL THEN
        PERFORM validate_all_hierarchy(v_old_id_rel_verzije_modeli);
    END IF;

    IF v_new_id_rel_verzije_modeli IS NOT NULL
       AND (v_old_id_rel_verzije_modeli IS NULL OR v_new_id_rel_verzije_modeli <> v_old_id_rel_verzije_modeli) THEN
        PERFORM validate_all_hierarchy(v_new_id_rel_verzije_modeli);
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
-- Cona carries id_rel_verzije_modeli directly — no joins needed.

DROP FUNCTION IF EXISTS validate_cona_lao_incremental();

CREATE OR REPLACE FUNCTION validate_cona_lao_incremental()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_rel_verzije_modeli UUID;
BEGIN
    v_id_rel_verzije_modeli := CASE WHEN TG_OP = 'DELETE' THEN OLD.id_rel_verzije_modeli ELSE NEW.id_rel_verzije_modeli END;

    IF v_id_rel_verzije_modeli IS NOT NULL THEN
        PERFORM validate_all_hierarchy(v_id_rel_verzije_modeli);
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
-- LAO carries id_rel_verzije_modeli directly — no joins or fallbacks needed.

DROP FUNCTION IF EXISTS validate_lao_tao_incremental();

CREATE OR REPLACE FUNCTION validate_lao_tao_incremental()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_rel_verzije_modeli UUID;
BEGIN
    v_id_rel_verzije_modeli := CASE WHEN TG_OP = 'DELETE' THEN OLD.id_rel_verzije_modeli ELSE NEW.id_rel_verzije_modeli END;

    IF v_id_rel_verzije_modeli IS NOT NULL THEN
        PERFORM validate_all_hierarchy(v_id_rel_verzije_modeli);
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
