





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

- make copy of md_geo_obm

CREATE TABLE md_geo_obm_safety_copy AS 
SELECT * FROM md_geo_obm;



- Make new fields on md_geo_obm: intersecting, overflowing  bool fields, with default val false
Names:    V preseku, Izven mej Slovenije



- Make slo_meja attribute table from SQL, and then make a layer from it:


The first way is the way to go, I think:



SELECT
    uuid_generate_v4() AS id,
    ST_MakePolygon(
        ST_ExteriorRing(ST_Union(kn_nep_rpe_obcine_h.geom))
    )::geometry(Polygon,3794) AS geom
FROM kn_nep_rpe_obcine_h
WHERE (kn_nep_rpe_obcine_h.postopek_id_do IS NULL);


SELECT
    ST_GeometryType(slo.geom) as geom_type,
    ST_NumGeometries(slo.geom) as num_parts,
    ST_NumInteriorRings(slo.geom) as num_holes
FROM (

SELECT
    uuid_generate_v4() AS id,
    ST_MakePolygon(
        ST_ExteriorRing(ST_Union(kn_nep_rpe_obcine_h.geom))
    )::geometry(Polygon,3794) AS geom
FROM kn_nep_rpe_obcine_h
WHERE (kn_nep_rpe_obcine_h.postopek_id_do IS NULL)

) as slo;




 SELECT uuid_generate_v4() AS id,
    (st_union(kn_nep_rpe_obcine_h.geom))::geometry(Polygon,3794) AS geom
   FROM kn_nep_rpe_obcine_h
  WHERE (kn_nep_rpe_obcine_h.postopek_id_do IS NULL);




SELECT
    uuid_generate_v4() AS id,
    ST_MakePolygon(
        ST_ExteriorRing(ST_Union(md_geo_obm.geom))
    )::geometry(Polygon,3794) AS geom
FROM md_geo_obm
WHERE id_rel_geo_verzija = '2647f13d-faea-4f37-9309-3ab8639457f1';





- Make new layer   topoloske_vrzeli
And add fields: area_type text (obm, cona, lao, tao),  id_rel_geo_verzija, area, perimeter
Names: Vrsta področja,  id_rel_geo_verzija, površina, obseg



- make full validation fn
- make trigger fn
- set trigger




































## Slo meja problem with holes



-- Check the union result
SELECT
    ST_GeometryType(ST_Union(geom)) as geom_type,
    ST_NumGeometries(ST_Union(geom)) as num_parts,
    ST_NumInteriorRings(ST_Union(geom)) as num_holes
FROM kn_nep_rpe_obcine_h
WHERE postopek_id_do IS NULL;







SELECT
    ST_GeometryType(slo.geom) as geom_type,
    ST_NumGeometries(slo.geom) as num_parts,
    ST_NumInteriorRings(lo.geom) as num_holes
FROM (SELECT 
    uuid_generate_v4() AS id,
    ST_Union(
        ST_MakePolygon(
            ST_ExteriorRing((ST_Dump(ST_Union(kn_nep_rpe_obcine_h.geom))).geom)
        )
    )::geometry(Polygon,3794) AS geom
FROM kn_nep_rpe_obcine_h
WHERE kn_nep_rpe_obcine_h.postopek_id_do IS NULL) as slo;















 SELECT uuid_generate_v4() AS id,
    (st_union(kn_nep_rpe_obcine_h.geom))::geometry(Polygon,3794) AS geom
   FROM kn_nep_rpe_obcine_h
  WHERE (kn_nep_rpe_obcine_h.postopek_id_do IS NULL);

Intersections wrong, no area checking

05c23679-1f97-403e-9344-ba65b20a9d9b,8349,49,49,125
08958afb-4360-438d-af25-9b0f5af57681,8348,44,44,132
20a6ad30-8457-41c9-8fbd-5423c15dae9b,8350,45,45,233
2647f13d-faea-4f37-9309-3ab8639457f1,8349,57,57,238
6045e8e5-abc6-4ab1-a6cf-886637c2f944,8362,61,61,227
68e3a6de-6685-4820-8358-95ad7b13f0fd,8348,44,44,132
701d04d0-b9eb-4fa0-b54b-1069bb8b0c16,8348,49,49,236
99d0e803-9ff2-40e3-822b-995289ee60d6,8532,139,139,1041
9d8bf0cc-beab-43da-bded-14f9bfa80684,8348,63,63,458




















## Solution Implementation Proposal:


### Row level triggers are the way:

If we get an update for many areas at once, we have to process them one by one.

CREATE TRIGGER my_trigger
AFTER UPDATE ON my_table
FOR EACH ROW  -- This is what you need!
EXECUTE FUNCTION my_function();

Fires once for each affected row
Has access to OLD and NEW records for each row
Uses pg_op to know if it is insert, update, or delete, and act accordingly.

## Materialized view is necessary

In LIFT its said the materialized view gets recreated automatically if data changes, so no trigger is needed.

### We shant be figuring out all things that might be problematic every time we add sth

We have to make sure to process only the change that just happened.

- If there is an insert, does this new shape intersect any existing shape (ST_Overlaps(geom, %s) OR ST_Contains(geom, %s)), or fall out of slovenia? (Also, problematically: Does it cover any hole and is it the neighbour to any hole?)
- If there is a delete, is there a hole there now? (Remove all existing areas from the lost area, then see what remains).
Intersection check is still a problem.
- If there is an update, does the new shape intersect any existing shape, or fall out of slovenia? The shape that is 
now void: diff(old-new) has to be checked: take that shape and do: hole = hole - currArea. For all areas. Now we have 
this hole multipolygon that overlaps with nothing.
We then see what that hole touches. (or maybe we add a small buffer and see what it intersects).


### The original sin

The problem is, that the above system only works if things were correct before the change. 
But there are problems in the current data.
So we need to make an fn that does the long operation of checking all pairs of fields.



ST_Overlaps(geom, %s) OR ST_Contains(geom, %s)


































## Problem we are facing:

The initial idea is to have:
- geom of slovenia as a view (takes 3 seconds to get from it) (make it a materialized view later - and a trigger to recreate it if anything changes)

```
SELECT ST_Union(geom)
FROM kn_nep_rpe_obcine_h
WHERE postopek_id_do is NULL;
```

- CHECK HOLES: have md_geo_obm in a union and then see the difference with geom of slovenia. This is pretty fast. We find holes, give them a small buffer, see what obmocja the hole buffer intersects, those are the neighbours. (alternatively maybe ST_Touches would work).

- 


    SELECT ST_Union(geom) INTO areas_union
    FROM md_geo_obm;

    -- Find the difference between Slovenia and the union of areas
    difference_geom := ST_Difference(slovenia_geom, areas_union);





Main approaches we have found are:
- ST_Overlaps(a1.geom, a2.geom) (intersect is true for touches also. Overlaps means there is actual overlap, not just touching.)
- ST_Area(ST_Intersection(a1.geom, a2.geom)) > 0.01   (This approach is supposed to allow for rounding errors of floating point arithmetic for the areas)

The code in our trigger would then look something like this:
```

    WITH overlapping_pairs AS (
        SELECT DISTINCT
            a1.id as id1,
            a2.id as id2
        FROM md_geo_obm a1
        JOIN md_geo_obm a2 ON a1.id < a2.id
        WHERE ST_Overlaps(a1.geom, a2.geom)  -- Much simpler!
    ),
    all_overlapping_ids AS (
        SELECT id1 as id FROM overlapping_pairs
        UNION
        SELECT id2 as id FROM overlapping_pairs
    )
    UPDATE md_geo_obm
    SET topology_problem = 'intersection'
    WHERE id IN (SELECT id FROM all_overlapping_ids);
```

Problem:


```

-- Get the ID at exactly the 2nd percentile
SELECT id
FROM md_geo_obm
ORDER BY id
LIMIT 1 OFFSET (
    SELECT FLOOR(COUNT(*) * 0.1)::INTEGER
    FROM md_geo_obm
);

19cc94f4-7cac-44ed-859c-3ec06ff43511



SELECT COUNT(*)
FROM md_geo_obm a1
JOIN md_geo_obm a2 ON a1.id < a2.id
WHERE a2.id <= '19cc94f4-7cac-44ed-859c-3ec06ff43511'
--     and ST_Area(ST_Intersection(a1.geom, a2.geom)) > 0.01; --result: 411    --4315ms     Estimated for full:   3.6min
--         and ST_Area(ST_Intersection(a1.geom, a2.geom)) > 100000000; --result: 10    --roughly the same time
  and ST_Overlaps(a1.geom, a2.geom); -- result 374     -- 1550ms  -- estimated for full: 1,3 min



SELECT COUNT(*)
FROM md_geo_obm a1
JOIN md_geo_obm a2 ON a1.id < a2.id
--     and ST_Area(ST_Intersection(a1.geom, a2.geom)) > 0.01;
--         and ST_Area(ST_Intersection(a1.geom, a2.geom)) > 100000000;
  and ST_Overlaps(a1.geom, a2.geom); -- result 38349     -- 1m 43sec

```