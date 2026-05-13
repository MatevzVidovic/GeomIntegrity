\set ON_ERROR_STOP on
\pset pager off

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS :"target_schema".:"target_table" (
    id uuid,
    created_at timestamp,
    updated_at timestamp,
    created_by uuid,
    updated_by uuid,
    gid integer,
    geom geometry(MultiPolygon, 3794)
);

DROP TABLE IF EXISTS pg_temp.slo_meja_uradna_candidate;

CREATE TEMP TABLE slo_meja_uradna_candidate AS
WITH source_lines AS (
    SELECT
        gid,
        ST_Force2D(ST_SetSRID(geom, 3794)) AS geom
    FROM :"raw_schema".:"raw_table"
    WHERE geom IS NOT NULL
      AND NOT ST_IsEmpty(geom)
),
linework AS (
    SELECT
        COUNT(*) AS raw_line_count,
        ST_UnaryUnion(ST_Collect(geom)) AS geom
    FROM source_lines
),
built_area AS (
    SELECT
        raw_line_count,
        ST_CollectionExtract(ST_MakeValid(ST_BuildArea(geom)), 3) AS geom
    FROM linework
),
final_geom AS (
    SELECT
        raw_line_count,
        ST_Multi(ST_ReducePrecision(geom, 0.01))::geometry(MultiPolygon, 3794) AS geom
    FROM built_area
)
SELECT
    raw_line_count,
    geom,
    ST_IsValid(geom) AS is_valid,
    ST_Area(geom) AS area_m2,
    ST_NumGeometries(geom) AS polygon_count
FROM final_geom;

DO $$
DECLARE
    v_raw_line_count integer;
    v_is_valid boolean;
    v_is_empty boolean;
    v_geom_type text;
BEGIN
    SELECT
        raw_line_count,
        is_valid,
        ST_IsEmpty(geom),
        ST_GeometryType(geom)
    INTO
        v_raw_line_count,
        v_is_valid,
        v_is_empty,
        v_geom_type
    FROM pg_temp.slo_meja_uradna_candidate;

    IF COALESCE(v_raw_line_count, 0) = 0 THEN
        RAISE EXCEPTION 'No raw line geometries found in the configured raw import table';
    END IF;

    IF v_geom_type IS NULL OR COALESCE(v_is_empty, true) THEN
        RAISE EXCEPTION 'Official border polygon build produced an empty geometry';
    END IF;

    IF NOT COALESCE(v_is_valid, false) THEN
        RAISE EXCEPTION 'Official border polygon build produced invalid geometry';
    END IF;

    IF v_geom_type IS DISTINCT FROM 'ST_MultiPolygon' THEN
        RAISE EXCEPTION 'Expected ST_MultiPolygon, got %', v_geom_type;
    END IF;
END $$;

TRUNCATE TABLE :"target_schema".:"target_table";

INSERT INTO :"target_schema".:"target_table" (
    id,
    created_at,
    updated_at,
    created_by,
    updated_by,
    gid,
    geom
)
SELECT
    uuid_generate_v4(),
    now()::timestamp,
    NULL::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    NULL::uuid,
    1,
    geom
FROM pg_temp.slo_meja_uradna_candidate;

CREATE INDEX IF NOT EXISTS idx_slo_meja_uradna_geom
ON :"target_schema".:"target_table" USING GIST (geom);

ANALYZE :"target_schema".:"target_table";

SELECT
    'imported official Slovenia boundary' AS status,
    raw_line_count,
    polygon_count,
    ROUND(area_m2::numeric, 2) AS area_m2,
    ST_IsValid(geom) AS is_valid,
    ST_GeometryType(geom) AS geometry_type,
    ST_SRID(geom) AS srid
FROM pg_temp.slo_meja_uradna_candidate;
