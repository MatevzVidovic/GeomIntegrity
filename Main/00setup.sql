

DROP TRIGGER IF EXISTS trg_validate_topology_incremental ON md_geo_obm;

obmocja_reset pognat


select * from set_to_2_decimal_places();
select * from validate_2_decimal_places();


-- maybe could be materialized view, but if we ever accidentally allow an overflow to be made, we have a problem
-- ustvari sloj slo_meja v lift-u

INSERT INTO slo_meja(id, created_at, created_by, geom)
 SELECT uuid_generate_v4() AS id,
        now()::timestamp,
        '848956e8-d73e-11f0-9ff0-02420a000f64',
    st_reduceprecision(st_union(md_geo_obm.geom), (0.01)::double precision) AS geom
   FROM md_geo_obm;

-- CREATE MATERIALIZED VIEW slo_meja as
-- SELECT st_reduceprecision(st_union(geom), 0.01) as geom
-- FROM md_geo_obm;


select * from validate_all_topologies();

select * from fix_holes();
select * from fix_overflows();
select * from fix_intersections();

select * from validate_all_topologies();

select count(*) from md_topoloske_kontrole;

select * from fix_holes();
select * from fix_overflows();
select * from fix_intersections();


