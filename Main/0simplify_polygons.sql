




select * from simplify_polygons();

DROP FUNCTION simplify_polygons();

select * from simplify_polygons();

CREATE OR REPLACE FUNCTION simplify_polygons( )
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    last_max_simplification_version integer;
BEGIN

    last_max_simplification_version := (
    SELECT MAX(md_geo_obm.simplification_version)
    FROM md_geo_obm
    WHERE simplification_version IS NOT NULL
        );

    IF last_max_simplification_version is NULL
    THEN
        last_max_simplification_version = 1;
    end if;

    INSERT INTO md_geo_obm (
    id,
    created_at,
    created_by,
    geom,
    id_rel_geo_verzija,
    ime_obmocja,
    gv_id,
    split_group_id,
    kopiran_id,
    intersecting,
    overflowing,
    problem_topologija,
    simplification_version
)
SELECT
    uuid_generate_v4(),
                    now()::timestamp,
        '848956e8-d73e-11f0-9ff0-02420a000f64',
--     ST_MakeValid(
--     ST_SimplifyVW(geom, 100.0)
--         ),                           -- geom
        simplify_obm_geom(geom),

    id_rel_geo_verzija,                -- id_rel_geo_verzija literally
    ime_obmocja,                        -- ime_obmocja literally
    gv_id,                              -- gv_id literally
    split_group_id,                     -- split_group_id literally
    kopiran_id,                         -- kopiran_id literally
    intersecting,                       -- intersecting literally
    overflowing,                        -- overflowing literally
    problem_topologija,                 -- problem_topologija literally
    (last_max_simplification_version + 1)                                 -- simplification_version
    FROM md_geo_obm
    WHERE simplification_version is NULL;





END $$;






select * from get_num_points_statistics(NULL);
696.3981693363844394,5,36,62,102,141,197,286,447,794.2000000000003,1729.400000000002,36537,3059

select * from get_num_points_statistics(2);
10.0
563.2618502778685845,5,35,60,96,133,186,269.79999999999995,416,700.2000000000003,1514.4000000000005,16649,3059

select * from get_num_points_statistics(3);
100.0
435.0385746976135992,5,31,53,85,118,162,233.5999999999999,353,564.8000000000002,1228.2000000000003,9572,3059



select * from get_num_points_statistics(6);
321.7701863354037267,5,36,62,91,113,131,150,226.19999999999982,470.4000000000001,835.2000000000003,5896,3059





select * from get_num_points_statistics(4);
447.5720823798627002,5,36,60,96,130,174,246.79999999999995,378.7999999999997,604,1228.2000000000003,9572,3059


CREATE OR REPLACE FUNCTION public.simplify_obm_geom(g geometry)
RETURNS geometry
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
    n integer;
    out_g geometry;
BEGIN
    IF g IS NULL THEN
        RETURN NULL;
    END IF;

    n := ST_NPoints(g);

    -- Choose per-range logic
    IF n < 50 THEN
        out_g := g;  -- keep as-is (or still MakeValid if you want)
    ELSIF n < 150 THEN
        out_g := ST_SimplifyVW(g, 10.0);
    ELSIF n < 1000 THEN
        out_g := ST_SimplifyVW(g, 50.0);
    ELSE
        out_g := ST_SimplifyVW(g, 100.0);
    END IF;

    -- Clean up: validity + keep only polygonal + normalize to MultiPolygon
    out_g := ST_MakeValid(out_g);
    out_g := ST_CollectionExtract(out_g, 3);  -- polygons only
    out_g := ST_Multi(out_g);

    -- Preserve SRID (MakeValid usually preserves it, but this is safe)
    out_g := ST_SetSRID(out_g, ST_SRID(g));

    RETURN out_g;
END;
$$;



select * from get_num_points_statistics(5);
332.3291925465838509,5,35,48,68,93,149,216.79999999999995,314.5999999999999,470.4000000000001,835.2000000000003,5896,3059



CREATE OR REPLACE FUNCTION public.simplify_obm_geom(g geometry)
RETURNS geometry
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  n int;
  a double precision;
  tol double precision;
  out_g geometry;
BEGIN
  IF g IS NULL THEN
    RETURN NULL;
  END IF;

  n := ST_NPoints(g);
  a := ST_Area(g);

  IF n < 50 THEN
    tol := 0.0; -- no simplify
    out_g := g;
  ELSIF n < 150 THEN
    tol := a * 0.0002;  -- 0.02%
    out_g := ST_SimplifyVW(g, GREATEST(2.0, tol));
  ELSIF n < 1000 THEN
    tol := a * 0.001;   -- 0.1%
    out_g := ST_SimplifyVW(g, LEAST(200.0, GREATEST(5.0, tol)));
  ELSE
    tol := a * 0.003;   -- 0.3%
    out_g := ST_SimplifyVW(g, LEAST(500.0, GREATEST(20.0, tol)));
  END IF;

  out_g := ST_MakeValid(out_g);
  out_g := ST_CollectionExtract(out_g, 3);
  out_g := ST_Multi(out_g);
  out_g := ST_SetSRID(out_g, ST_SRID(g));
  RETURN out_g;
END;
$$;




select * from get_num_points_statistics(6);
321.7701863354037267,5,36,62,91,113,131,150,226.19999999999982,470.4000000000001,835.2000000000003,5896,3059

CREATE OR REPLACE FUNCTION public.simplify_obm_geom(g geometry)
RETURNS geometry
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  n int;
  a double precision;
  tol double precision;
  out_g geometry;
BEGIN
  IF g IS NULL THEN
    RETURN NULL;
  END IF;

  n := ST_NPoints(g);
  a := ST_Area(g);

  IF n < 150 THEN
    tol := 0.0; -- no simplify
    out_g := g;
  ELSIF n < 500 THEN
    tol := a * 0.0001;  -- 0.01%
    out_g := ST_SimplifyVW(g, GREATEST(2.0, tol));
  ELSIF n < 1000 THEN
    tol := a * 0.002;   -- 0.2%
    out_g := ST_SimplifyVW(g, LEAST(200.0, GREATEST(5.0, tol)));
  ELSE
    tol := a * 0.003;   -- 0.3%
    out_g := ST_SimplifyVW(g, LEAST(500.0, GREATEST(20.0, tol)));
  END IF;

  out_g := ST_MakeValid(out_g);
  out_g := ST_CollectionExtract(out_g, 3);
  out_g := ST_Multi(out_g);
  out_g := ST_SetSRID(out_g, ST_SRID(g));
  out_g := st_reduceprecision(out_g, 0.01);

  RETURN out_g;
END;
$$;








DROP FUNCTION get_num_points_statistics(integer);

CREATE OR REPLACE FUNCTION get_num_points_statistics(simplification integer)
RETURNS TABLE (
    avg  numeric,
    min  integer,
    p10  double precision,
    p20  double precision,
    p30  double precision,
    p40  double precision,
    p50  double precision,
    p60  double precision,
    p70  double precision,
    p80  double precision,
    p90  double precision,
    max  integer,
    nall bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
BEGIN


       SELECT
    avg(a.num)                                    AS avg,
    min(a.num)                                    AS min,
    percentile_cont(0.1) WITHIN GROUP (ORDER BY a.num) AS p10,
    percentile_cont(0.2) WITHIN GROUP (ORDER BY a.num) AS p20,
    percentile_cont(0.3) WITHIN GROUP (ORDER BY a.num) AS p30,
    percentile_cont(0.4) WITHIN GROUP (ORDER BY a.num) AS p40,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY a.num) AS p50,
    percentile_cont(0.6) WITHIN GROUP (ORDER BY a.num) AS p60,
    percentile_cont(0.7) WITHIN GROUP (ORDER BY a.num) AS p70,
    percentile_cont(0.8) WITHIN GROUP (ORDER BY a.num) AS p80,
    percentile_cont(0.9) WITHIN GROUP (ORDER BY a.num) AS p90,
    max(a.num)                                    AS max,
    count(*)                                     AS nall
INTO rec
FROM (
    SELECT st_npoints(geom) AS num
    FROM md_geo_obm m
    WHERE m.simplification_version IS NOT DISTINCT FROM simplification
) a
WHERE num IS NOT NULL;


-- --         RETURN query select rec.avg, rec.nall;
    RETURN QUERY
SELECT
    rec.avg,
    rec.min,
    rec.p10,
    rec.p20,
    rec.p30,
    rec.p40,
    rec.p50,
    rec.p60,
    rec.p70,
    rec.p80,
    rec.p90,
    rec.max,
    rec.nall;

-- RETURN QUERY
-- SELECT
--     (rec).*;

END $$;


