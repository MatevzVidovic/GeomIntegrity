-- ============================================================================
-- 2_0_autofix_small_violations.sql - Small OBM Topology Autofix Helpers
-- ============================================================================
-- Small violations are geometry slivers we fix immediately instead of writing
-- into md_topoloske_kontrole_obm.
--
-- Rule:
--   ST_Area(geom) < 100 AND compactness < 0.01
--
-- These helpers are used by the OBM incremental trigger. They are intentionally
-- not implemented as triggers on md_topoloske_kontrole_obm, because that would
-- update md_geo_obm while the md_geo_obm trigger is already running.
-- ============================================================================

DROP FUNCTION IF EXISTS apply_internal_obm_geom_fix(uuid, geometry);
DROP FUNCTION IF EXISTS find_best_obm_neighbor_for_hole(uuid, geometry, uuid);
DROP FUNCTION IF EXISTS is_small_obm_topology_problem(geometry);
DROP FUNCTION IF EXISTS obm_topology_compactness(geometry);
DROP FUNCTION IF EXISTS obm_small_topology_autofix_enabled();

CREATE OR REPLACE FUNCTION obm_small_topology_autofix_enabled()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$


    -- current_setting('geom_integrity.obm_small_topology_autofix', true)

    -- means: “read setting named geom_integrity.obm_small_topology_autofix; if it does not exist, return NULL instead of
    -- error.”

    -- Then:

    -- NULLIF(value, '')::boolean
    
    -- turns empty string into NULL, otherwise casts values like 'on', 'off', 'true', 'false' to boolean.

    -- Then:

    -- COALESCE(..., true)

    -- means default to true when unset.

    -- So behavior is:

    -- -- default
    -- SELECT obm_small_topology_autofix_enabled();
    -- -- true

    -- -- disable for current transaction
    -- SET LOCAL geom_integrity.obm_small_topology_autofix = 'off';

    -- -- enable for current transaction
    -- SET LOCAL geom_integrity.obm_small_topology_autofix = 'on';

    -- SET LOCAL lasts only until transaction end. If you want it for the whole DB session:

    -- SET geom_integrity.obm_small_topology_autofix = 'off';

    -- In our trigger, this function decides whether these blocks run:

    -- - small hole merge autofix
    -- - small intersection subtraction autofix
    -- - suppressing small control rows when autofix is enabled.

    SELECT COALESCE(
        NULLIF(current_setting('geom_integrity.obm_small_topology_autofix', true), '')::boolean,
        true
    );
$$;

CREATE OR REPLACE FUNCTION obm_topology_compactness(p_geom geometry)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_geom IS NULL OR ST_IsEmpty(p_geom) OR ST_Perimeter(p_geom) = 0 THEN NULL
        ELSE 4 * pi() * ST_Area(p_geom) / (ST_Perimeter(p_geom) * ST_Perimeter(p_geom))
    END;
$$;

CREATE OR REPLACE FUNCTION is_small_obm_topology_problem(p_geom geometry)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p_geom IS NOT NULL
       AND NOT ST_IsEmpty(p_geom)
       AND ST_Area(p_geom) < 100
       AND obm_topology_compactness(p_geom) < 0.01;
$$;

CREATE OR REPLACE FUNCTION find_best_obm_neighbor_for_hole(
    p_id_rel_geo_verzija uuid,
    p_hole_geom geometry,
    p_excluded_obm_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT obm.id
    FROM md_geo_obm obm
    WHERE obm.id_rel_geo_verzija = p_id_rel_geo_verzija
      AND obm.geom IS NOT NULL
      AND (p_excluded_obm_id IS NULL OR obm.id <> p_excluded_obm_id)
      AND ST_Intersects(ST_Buffer(p_hole_geom, 10), obm.geom)
    ORDER BY
      ST_Area(ST_Intersection(ST_Buffer(p_hole_geom, 1), obm.geom)) DESC,
      obm.id
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION apply_internal_obm_geom_fix(
    p_obm_id uuid,
    p_fixed_geom geometry
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_previous_skip text;
BEGIN
    IF p_obm_id IS NULL OR p_fixed_geom IS NULL OR ST_IsEmpty(p_fixed_geom) THEN
        RETURN;
    END IF;

    v_previous_skip := current_setting('geom_integrity.skip_obm_topology_trigger', true);
    PERFORM set_config('geom_integrity.skip_obm_topology_trigger', 'on', true);

    UPDATE md_geo_obm
    SET geom = ST_Multi(ST_ReducePrecision(p_fixed_geom, 0.01))
    WHERE id = p_obm_id;

    PERFORM set_config(
        'geom_integrity.skip_obm_topology_trigger',
        COALESCE(NULLIF(v_previous_skip, ''), 'off'),
        true
    );
END $$;
