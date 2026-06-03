

sliver-creating_problems.md

2 problems:

1st:
https://claude.ai/share/cbb6b0b2-89ed-49ad-87cc-e8d6e0b663a3
- ST_ReducePrecision forces valid geom. It can let things go to empty if all vertices of a polygon are inside one grid cell (still valid); but especially for long, thin polygons (slivers) it will try to inflate them.
I suspect ST_Difference also has small rounding errors which cause extremely tiny slivers that ST_ReducePrecision would then inflate.

ST_ReducePrecision wont let polygons become invalid.
ST_SnapToGrid still has very small float errors in GEOSS 3.9
Combine both so things actually work.


2nd:
Edge abutting and T-junction abutting:

I am actually now thinking that this is not a problem in my case:
Because when we solve the 1st problem and snap to grid works correctly,
And adding/removing small control violations to neighbour geom with largest shared border
Then these problems that would happen due to this should be autofixed and create this additional interim vertex that is missing.

Details:
T-junction abutting is a real problem - the polygon with the long side needs to gain a point on the T-junction
Also, all neighbouring edges need to share the vertexes - otherwise slivers from abutting will keep happening:
https://claude.ai/share/6eb08f15-6863-488a-8fd8-d8d88ccc2b42
- Edge abutting: 
Mismatched vertices on a shared boundary — polygon A's edge goes from vertex (0,0) to (0,10), while polygon B has the abutting edge split as (0,0)→(0,4)→(0,10).

Pragmatic workflow: run ST_CoverageInvalidEdges, look at the returned geometries to see what kind of problem you have, then pick the right tool. Slivers and T-junctions → snap. Real overlaps → business-rule difference. Total mess → node and polygonize, re-attribute after.

SELECT COUNT(*) AS bad_rows
FROM (
  SELECT ST_CoverageInvalidEdges(geom) OVER () AS invalid
  FROM md_geo_obm
) s
WHERE invalid IS NOT NULL;





## Solution to the first problem:


When does ST_ReducePrecision move the vertices and force a valid geometry when we would want the geom to collapse? When does that happen?
3:39 PM
Claude responded: Good question — this gets at the heart of when ST_ReducePrecision will "save" a geometry you might rather see collapse.
Good question — this gets at the heart of when ST_ReducePrecision will "save" a geometry you might rather see collapse. Let me describe the shapes where it happens.
The core mechanism
When ST_ReducePrecision snaps vertices to the grid and that snapping would create an invalid geometry (self-intersection, collapsed ring, edges crossing), GEOS has to choose: collapse the offending part, or move vertices further than the grid would naively suggest to keep things valid. It prefers the latter when it can — vertices may be displaced by more than gridSize/2 to preserve topology.
This means a polygon can "survive" with positive area even when a naive grid-snap would have killed it.



https://claude.ai/share/cbb6b0b2-89ed-49ad-87cc-e8d6e0b663a3




survivors AS (
  SELECT geom
  FROM polygons_only
  WHERE NOT ST_IsEmpty(geom)
    AND ST_Area(geom) > 0
)
SELECT
  ST_MakeValid(ST_ReducePrecision(ST_Union(geom), 0.01)) AS geom
FROM survivors;


### Solution with more polygons as output:

CREATE OR REPLACE FUNCTION ensure_snap_to_grid(geom geometry)
RETURNS geometry
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  cleaned geometry;
BEGIN
  -- 1. Snap to grid (does the actual collapse of slivers) + clean self-intersections
  cleaned := ST_MakeValid(ST_SnapToGrid(geom, 0.01));

  -- 2. Keep only polygonal parts, drop the line/point debris
  cleaned := ST_CollectionExtract(cleaned, 3);

  -- 3. Bail out if the whole thing collapsed
  IF cleaned IS NULL OR ST_IsEmpty(cleaned) OR ST_Area(cleaned) = 0 THEN
    RETURN NULL;
  END IF;

  -- 4. Dissolve internal parts, then snap the new union nodes back onto the grid
  RETURN ST_MakeValid(ST_ReducePrecision(ST_Union(cleaned), 0.01));
END;
$$;







### THIS BELOW ISNT THE POINT - AFTER BEING MADE VALID THEY WOULD NEVER REDUCE.
IT IS ONLY AFTER ST_Difference CREATES A SMALL SLIVER BELOW THE ACTUAL GRIDSIZE THAT THEY MIGHT REDUCE TO Emtpy
SO IT NEEDS TO BE IN THE ACTUAL FN




WITH snapped AS (
  SELECT
    id,
    ST_MakeValid(ST_SnapToGrid(geom, 0.01)) AS geom
  FROM md_topoloske_kontrole_obm
),
polygons_only AS (
  SELECT
    id,
    ST_CollectionExtract(geom, 3) AS geom
  FROM snapped
  WHERE geom IS NOT NULL
),
survivors AS (
  SELECT id, geom
  FROM polygons_only
  WHERE NOT ST_IsEmpty(geom)
    AND ST_Area(geom) > 0
),
survivors_reduced AS (
  SELECT 
        id,
        ST_ReducePrecision(geom, 0.01) AS geom
    FROM survivors
)
SELECT
    COUNT(*)
FROM survivors_reduced;





Quick test on your data
sql
SELECT
  count(*) FILTER (WHERE ST_IsEmpty(ST_ReducePrecision(geom, 0.01))) AS vanished,
  count(*) FILTER (WHERE NOT ST_IsEmpty(ST_ReducePrecision(geom, 0.01))) AS survived
FROM md_topoloske_kontrole_obm;

That'll tell you whether ReducePrecision is collapsing the things you expect to collapse. If the numbers look right, you can skip the SnapToGrid pipeline entirely.









Shapes where this matters
1. Thin polygons with width less than the grid size
A rectangle 100 units long and 0.005 wide at grid size 0.01. Naive snapping puts both long edges on the same grid line → zero-area sliver → MakeValid turns it into a LineString.
ST_ReducePrecision instead nudges one edge to the next grid line over (displacement of ~0.005, which is half the grid size — still within tolerance). The result is a 100 × 0.01 rectangle. It survived, with positive area, even though it was thinner than the grid.
This is the most common surprise. If you have many thin features (slivers from intersections, narrow strips, gaps between near-coincident boundaries), ST_ReducePrecision will tend to preserve them at one grid cell of width rather than letting them vanish.
2. Small polygons smaller than a grid cell
A 0.003 × 0.003 square at grid size 0.01. All four corners snap to the same grid point → degenerate.
ReducePrecision can let this go to empty — small isolated polygons whose entire footprint fits inside one grid cell usually do collapse, because there's no valid non-empty result. So this case typically does vanish. Worth testing on your data though.
3. Polygons with thin protrusions or tails
A blob with a long thin spike sticking out, where the spike is thinner than the grid. Naive snap collapses the spike to a line. ReducePrecision will often thicken the spike to one grid cell width and keep it attached. The polygon ends up slightly bigger and weirder-shaped than the original blob.
If you wanted the spike gone, you're out of luck with ReducePrecision alone.
4. Polygons with narrow waists / near-pinches
A figure-8-ish polygon where the waist is narrower than the grid. Naive snap pinches it into two polygons touching at a point (invalid). ReducePrecision will either:
Widen the waist to keep it as one connected polygon, or
Split it cleanly into a MultiPolygon at the pinch.
Either way, area survives. You don't get vanishing.
5. Holes (interior rings) smaller than the grid
Interesting asymmetry: small holes generally do collapse and disappear (the polygon becomes solid where the hole was), because removing a hole doesn't threaten validity — it just makes the polygon larger. So this one behaves like you'd intuit.
6. Adjacent sub-polygons in a MultiPolygon
If a MultiPolygon has one big piece and one tiny piece, the tiny piece can be dropped if it can't be represented validly. So MultiPolygons can lose components even when the overall geometry doesn't go empty.
