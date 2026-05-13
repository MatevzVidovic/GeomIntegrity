\set ON_ERROR_STOP on
\pset pager off

-- Optional step.
-- Run this only when you want the live topology boundary table `slo_meja`
-- to use the imported official border from `slo_meja_uradna`.

TRUNCATE TABLE slo_meja;

INSERT INTO slo_meja (
    id,
    created_at,
    created_by,
    geom
)
SELECT
    COALESCE(id, uuid_generate_v4()),
    COALESCE(created_at, now()::timestamp),
    COALESCE(created_by, '00000000-0000-0000-0000-000000000000'::uuid),
    ST_Multi(ST_ReducePrecision(geom, 0.01))::geometry(MultiPolygon, 3794)
FROM slo_meja_uradna
WHERE geom IS NOT NULL
  AND NOT ST_IsEmpty(geom)
LIMIT 1;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM slo_meja) THEN
        RAISE EXCEPTION 'No geometry was copied from slo_meja_uradna to slo_meja';
    END IF;
END $$;

SELECT
    'copied official boundary into slo_meja' AS status,
    ST_GeometryType(geom) AS geometry_type,
    ST_SRID(geom) AS srid,
    ST_IsValid(geom) AS is_valid,
    ROUND(ST_Area(geom)::numeric, 2) AS area_m2
FROM slo_meja
LIMIT 1;
