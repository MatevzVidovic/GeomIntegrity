





## Problem description:

We have a table called md_geo_obm. It has columns: id, geom, id_rel_geo_verzija, intersecting, overflowing.
We have a materialized view called slo_meja.
For each group of id_rel_geo_verzija, the geom column should be a tiling of slo_meja - no holes, no intersectionlps, no overflow.

On each insert, update, or delete, we have to check the violations of this condition and write them down.
Intersection and overflow violations are written as booleans in columns intersecting and overflowing.

Holes are written as geoms in a table called topoloske_vrzeli, with columns id, id_rel_geo_verzija, geom.
They are updated with every insert, update, or delete.




## Solution:

First part:

We create a trigger with FOR EACH ROW.
The trigger fn should get the old and new geoms of the row, and check if there are any problems.
It also gets the operation (insert, update, delete) and acts accordingly.

- If there is a delete, is there a hole there now? Remove all existing areas from the lost area, then see what remains.
hole = OLD.geom.   hole = ST_Difference(hole, geom). If the hole intersects with any existing hole, join them in a union.
Was the shape in intersection? If so, find with which entries. For those entries, find out if they still intersect anybody and set their intersection flag correctly. 

- If there is an insert, does this new shape intersect any existing shape (ST_Overlaps(geom, %s) OR ST_Contains(geom, %s)), 
or fall out of Slovenia? ST_Difference(NEW.geom, slovenia_geom)? Does it cover any hole and thus reduce it or even fill it?

- If there is an update, first do the algorithm for removal of the old, and then for adding of the new.
We have to check all of these problems anyway. It's the same amount of comp time. No need to complicate things.



Second part:

In case anything got messed up in the process, we want a function that completely redoes all checks.
So it should check:
- holes created by all entries ST_Difference(slo_meja, ST_Union(geom))
- overflows for all entries ST_Difference(ST_Union(geom), slo_meja). 
Then for all overflows, you see which entries intersect with them and mark them as overflows.
- intersections for all entries ST_Intersection(a.geom, b.geom) (a.id < b.id)  -  Expensive operation.



## Solution implementation:


- Make slo_meja attribute table from SQL, and then make a layer from it:


CREATE MATERIALIZED VIEW slo_meja as
SELECT uuid_generate_v4() as id, st_reduceprecision(st_union(geom), 0.01) as geom
FROM md_geo_obm;


- Make new layer   md_topoloske_kontrole
And add fields: area_type text (obm, cona, lao, tao),  id_rel_geo_verzija, area, perimeter, compactness
Names: Vrsta področja,  id_rel_geo_verzija, površina, obseg


create table md_topoloske_kontrole
(
    id                    uuid      not null
        primary key,
    created_at            timestamp not null,
    updated_at            timestamp,
    created_by            uuid      not null,
    updated_by            uuid,
    gid                   serial,
    geom                  geometry(MultiPolygon, 3794),
    area_type             text      not null
        constraint check_area_type
            check (area_type = ANY (ARRAY ['obm'::text, 'cona'::text])),
    id_rel_geo_verzija    uuid,
    id_rel_verzije_modela uuid,
    id2                   uuid,
    id1                   uuid,
    area                  numeric,
    perimeter             numeric,
    compactness           numeric,
    topology_problem_type text
        constraint check_topology_problem_type
            check (topology_problem_type = ANY (ARRAY ['intersection'::text, 'hole'::text, 'overflow'::text])),
    constraint check_id1_less_than_id2
        check ((id2 IS NULL) OR ((id1 IS NOT NULL) AND (id1 < id2)))
);



- make full validation fn (so we fill topoloske_vrzeli with existing problems)
- make trigger fn
- set trigger






CREATE INDEX idx_topoloske_kontrole ON md_topoloske_kontrole (area_type, id_rel_geo_verzija, id_rel_verzije_modela, topology_problem_type, id1, id2);

ALTER TABLE md_topoloske_kontrole
ADD CONSTRAINT check_area_type
CHECK (area_type IN ('obm', 'cona'));

ALTER TABLE md_topoloske_kontrole
ADD CONSTRAINT check_topology_problem_type
CHECK (topology_problem_type IN ('intersection', 'hole', 'overflow'));

-- Allow NULL but enforce constraint when both are present
ALTER TABLE md_topoloske_kontrole
ADD CONSTRAINT check_id1_less_than_id2
CHECK (id2 IS NULL OR (id1 IS NOT NULL AND id1 < id2));


