-- Geometry ownership: OBM -> CONA -> LAO -> TAO.

DROP TRIGGER IF EXISTS trg_ensure_snap_to_grid ON md_geo_cona;
DROP TRIGGER IF EXISTS trg_ensure_snap_to_grid ON md_geo_lao;
DROP TRIGGER IF EXISTS trg_ensure_snap_to_grid ON md_geo_tao;
DROP TRIGGER IF EXISTS trg_refresh_hierarchy_from_obm ON md_geo_obm;
DROP TRIGGER IF EXISTS trg_refresh_hierarchy_from_obmxcona ON md_geo_obmxcona;
DROP TRIGGER IF EXISTS trg_refresh_hierarchy_from_cona ON md_geo_cona;
DROP TRIGGER IF EXISTS trg_refresh_hierarchy_from_lao ON md_geo_lao;
DROP FUNCTION IF EXISTS hierarchy_cascade();
DROP FUNCTION IF EXISTS trg_ensure_snap_to_grid();
DROP FUNCTION IF EXISTS hierarchy_refresh_cona(uuid);
DROP FUNCTION IF EXISTS hierarchy_refresh_lao(uuid);
DROP FUNCTION IF EXISTS hierarchy_refresh_tao(uuid);
DROP FUNCTION IF EXISTS hierarchy_cona_geom(uuid);
DROP FUNCTION IF EXISTS hierarchy_lao_geom(uuid);
DROP FUNCTION IF EXISTS hierarchy_tao_geom(uuid);

CREATE FUNCTION hierarchy_cona_geom(p_id uuid)
RETURNS geometry LANGUAGE sql STABLE AS $$
    SELECT ensure_snap_to_grid(ST_Union(o.geom, 0.01))
    FROM md_geo_obmxcona x JOIN md_geo_obm o ON o.id = x.id_rel_geo_obm
    WHERE x.id_rel_geo_cona = p_id AND o.geom IS NOT NULL
$$;

CREATE FUNCTION hierarchy_lao_geom(p_id uuid)
RETURNS geometry LANGUAGE sql STABLE AS $$
    SELECT ensure_snap_to_grid(ST_Union(c.geom, 0.01))
    FROM md_geo_cona c
    WHERE (c.id_rel_geo_lao = p_id OR c.id_rel_geo_lao_rd1 = p_id)
      AND c.geom IS NOT NULL
$$;

CREATE FUNCTION hierarchy_tao_geom(p_id uuid)
RETURNS geometry LANGUAGE sql STABLE AS $$
    SELECT ensure_snap_to_grid(ST_Union(l.geom, 0.01))
    FROM md_geo_lao l WHERE l.id_rel_geo_tao = p_id AND l.geom IS NOT NULL
$$;

CREATE FUNCTION hierarchy_refresh_cona(p_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_geom geometry;
BEGIN
    SELECT hierarchy_cona_geom(p_id) INTO v_geom;
    UPDATE md_geo_cona SET geom = v_geom
    WHERE id = p_id AND (
        (geom IS NULL) IS DISTINCT FROM (v_geom IS NULL)
        OR (geom IS NOT NULL AND v_geom IS NOT NULL AND NOT ST_Equals(geom, v_geom))
    );
END;
$$;

CREATE FUNCTION hierarchy_refresh_lao(p_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_geom geometry;
BEGIN
    SELECT hierarchy_lao_geom(p_id) INTO v_geom;
    UPDATE md_geo_lao SET geom = v_geom
    WHERE id = p_id AND (
        (geom IS NULL) IS DISTINCT FROM (v_geom IS NULL)
        OR (geom IS NOT NULL AND v_geom IS NOT NULL AND NOT ST_Equals(geom, v_geom))
    );
END;
$$;

CREATE FUNCTION hierarchy_refresh_tao(p_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_geom geometry;
BEGIN
    SELECT hierarchy_tao_geom(p_id) INTO v_geom;
    UPDATE md_geo_tao SET geom = v_geom
    WHERE id = p_id AND (
        (geom IS NULL) IS DISTINCT FROM (v_geom IS NULL)
        OR (geom IS NOT NULL AND v_geom IS NOT NULL AND NOT ST_Equals(geom, v_geom))
    );
END;
$$;

-- Child rows win whenever children exist, even if their derived union is NULL.
CREATE FUNCTION trg_ensure_snap_to_grid()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_geom geometry;
BEGIN
    IF TG_TABLE_NAME = 'md_geo_cona' THEN
        IF EXISTS (
            SELECT 1 FROM md_geo_obmxcona x
            JOIN md_geo_obm o ON o.id = x.id_rel_geo_obm
            WHERE x.id_rel_geo_cona = NEW.id
        ) THEN SELECT hierarchy_cona_geom(NEW.id) INTO v_geom;
        ELSE NEW.geom := ensure_snap_to_grid(NEW.geom); RETURN NEW;
        END IF;
    ELSIF TG_TABLE_NAME = 'md_geo_lao' THEN
        IF EXISTS (SELECT 1 FROM md_geo_cona WHERE id_rel_geo_lao = NEW.id OR id_rel_geo_lao_rd1 = NEW.id)
        THEN SELECT hierarchy_lao_geom(NEW.id) INTO v_geom;
        ELSE NEW.geom := ensure_snap_to_grid(NEW.geom); RETURN NEW;
        END IF;
    ELSE
        IF EXISTS (SELECT 1 FROM md_geo_lao WHERE id_rel_geo_tao = NEW.id)
        THEN SELECT hierarchy_tao_geom(NEW.id) INTO v_geom;
        ELSE NEW.geom := ensure_snap_to_grid(NEW.geom); RETURN NEW;
        END IF;
    END IF;
    NEW.geom := v_geom;
    RETURN NEW;
END;
$$;

CREATE FUNCTION hierarchy_cascade()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'md_geo_obm' THEN
        FOR v_id IN
            SELECT DISTINCT id_rel_geo_cona FROM md_geo_obmxcona
            WHERE id_rel_geo_obm = CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END
        LOOP PERFORM hierarchy_refresh_cona(v_id); END LOOP;
    ELSIF TG_TABLE_NAME = 'md_geo_obmxcona' THEN
        IF TG_OP <> 'INSERT' THEN PERFORM hierarchy_refresh_cona(OLD.id_rel_geo_cona); END IF;
        IF TG_OP <> 'DELETE' THEN PERFORM hierarchy_refresh_cona(NEW.id_rel_geo_cona); END IF;
    ELSIF TG_TABLE_NAME = 'md_geo_cona' THEN
        IF TG_OP <> 'INSERT' THEN
            PERFORM hierarchy_refresh_lao(OLD.id_rel_geo_lao);
            PERFORM hierarchy_refresh_lao(OLD.id_rel_geo_lao_rd1);
        END IF;
        IF TG_OP <> 'DELETE' THEN
            PERFORM hierarchy_refresh_lao(NEW.id_rel_geo_lao);
            PERFORM hierarchy_refresh_lao(NEW.id_rel_geo_lao_rd1);
        END IF;
    ELSE
        IF TG_OP <> 'INSERT' THEN PERFORM hierarchy_refresh_tao(OLD.id_rel_geo_tao); END IF;
        IF TG_OP <> 'DELETE' THEN PERFORM hierarchy_refresh_tao(NEW.id_rel_geo_tao); END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ensure_snap_to_grid BEFORE INSERT OR UPDATE ON md_geo_cona
    FOR EACH ROW EXECUTE FUNCTION trg_ensure_snap_to_grid();
CREATE TRIGGER trg_ensure_snap_to_grid BEFORE INSERT OR UPDATE ON md_geo_lao
    FOR EACH ROW EXECUTE FUNCTION trg_ensure_snap_to_grid();
CREATE TRIGGER trg_ensure_snap_to_grid BEFORE INSERT OR UPDATE ON md_geo_tao
    FOR EACH ROW EXECUTE FUNCTION trg_ensure_snap_to_grid();

CREATE TRIGGER trg_refresh_hierarchy_from_obm
    AFTER INSERT OR UPDATE OF geom OR DELETE ON md_geo_obm
    FOR EACH ROW EXECUTE FUNCTION hierarchy_cascade();
CREATE TRIGGER trg_refresh_hierarchy_from_obmxcona
    AFTER INSERT OR UPDATE OR DELETE ON md_geo_obmxcona
    FOR EACH ROW EXECUTE FUNCTION hierarchy_cascade();
CREATE TRIGGER trg_refresh_hierarchy_from_cona
    AFTER INSERT OR UPDATE OF geom, id_rel_geo_lao, id_rel_geo_lao_rd1 OR DELETE ON md_geo_cona
    FOR EACH ROW EXECUTE FUNCTION hierarchy_cascade();
CREATE TRIGGER trg_refresh_hierarchy_from_lao
    AFTER INSERT OR UPDATE OF geom, id_rel_geo_tao OR DELETE ON md_geo_lao
    FOR EACH ROW EXECUTE FUNCTION hierarchy_cascade();
