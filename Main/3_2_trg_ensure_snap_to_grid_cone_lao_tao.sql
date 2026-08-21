-- Snap hierarchy geometries to the configured grid before they are stored.

DROP TRIGGER IF EXISTS trg_ensure_snap_to_grid ON md_geo_cona;
DROP TRIGGER IF EXISTS trg_ensure_snap_to_grid ON md_geo_lao;
DROP TRIGGER IF EXISTS trg_ensure_snap_to_grid ON md_geo_tao;
DROP FUNCTION IF EXISTS trg_ensure_snap_to_grid();

CREATE OR REPLACE FUNCTION trg_ensure_snap_to_grid()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.geom := ensure_snap_to_grid(NEW.geom);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ensure_snap_to_grid
    BEFORE INSERT OR UPDATE ON md_geo_cona
    FOR EACH ROW
    EXECUTE FUNCTION trg_ensure_snap_to_grid();

CREATE TRIGGER trg_ensure_snap_to_grid
    BEFORE INSERT OR UPDATE ON md_geo_lao
    FOR EACH ROW
    EXECUTE FUNCTION trg_ensure_snap_to_grid();

CREATE TRIGGER trg_ensure_snap_to_grid
    BEFORE INSERT OR UPDATE ON md_geo_tao
    FOR EACH ROW
    EXECUTE FUNCTION trg_ensure_snap_to_grid();
