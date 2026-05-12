
# Importing shapefiles into PostGIS PostgreSQL

**Created:** 5/12/2026 15:56:38  
**Updated:** 5/12/2026 15:57:26  
**Exported:** 5/12/2026 16:08:59  
**Link:** [https://claude.ai/chat/994cda68-8c3f-46e1-824e-37e587ed20fc](https://claude.ai/chat/994cda68-8c3f-46e1-824e-37e587ed20fc)  

## Prompt:
5/12/2026, 3:56:39 PM

> File: EDM-mejna_crta.shp

how do i import this shp into our postgress with postgis



i have this table



Data Source: nas test gurs
Database: fmp_data_gurs
Schema: public
Table: slo_meja_uradna
-- auto-generated definition
create table slo_meja_uradna
(
    id         uuid,
    created_at timestamp,
    updated_at timestamp,
    created_by uuid,
    updated_by uuid,
    gid        integer,
    geom       geometry(MultiPolygon, 3794)
);
alter table slo_meja_uradna
    owner to gurs_readwrite;
grant select on slo_meja_uradna to gurs_read;
Show table preview  




And also the shp aparently has 6 linestrings and i need a nice one cicrular linestring that will be the borders of slovenia so idk how it needs to be connected togetehre then



## Response:
5/12/2026, 3:57:26 PM

I'll help you import this shapefile into PostGIS. Let me first inspect the shapefile to understand what we're working with.

````plaintext
Bash Tool: List uploaded files to see all shapefile components
````

You only uploaded the `.shp` file. A shapefile is actually a collection of files (`.shp`, `.shx`, `.dbf`, `.prj`, and ideally `.cpg`). I can still inspect the geometry from the `.shp` alone, but for a proper import you'll want all of them. Let me check what's inside:

````plaintext
Bash Tool: Install pyshp and shapely to inspect the shapefile
````

````plaintext
Bash Tool: Inspect the shapefile structure and geometries
````

Now I have a clear picture. Let me explain what's going on and walk you through it.

## What's in the shapefile

You have 6 linestrings. Coordinates are in D96/TM (EPSG:3794) — Slovenian national CRS, which matches your table. Looking at the endpoints, four of them clearly form a closed ring around Slovenia:

- **Shape 0** ends at `(401341.56, 154507.65)` → **Shape 3** starts there, ends at `(584913.21, 192773.36)` → **Shape 4** starts there, ends at `(622607.92, 149710.22)` → **Shape 5** starts there, ends back at `(373891.71, 48606.84)` where **Shape 0** started.

These are the four border segments (probably SLO–IT, SLO–AT, SLO–HU, SLO–HR). **Shapes 1 and 2** are tiny closed loops (~86 and ~37 points, both start = end, in a ~500m bbox near coordinate 523000, 61000). Those look like small enclaves/islands in the boundary, not part of the main outline — possibly the Dragonja river area near the coast, but you should verify.

## A problem with your target table

Your `slo_meja_uradna` table has `geom geometry(MultiPolygon, 3794)`, but your shapefile contains **lines**, not polygons. You have two options:

````plaintext
Tool: Generating ask_user_input_v0...
````

While you decide, here's the **general import workflow** you'll need either way.

## Step 1 — Get all the shapefile sidecar files

`.shp` alone isn't enough for a proper import. You need at minimum:

- `EDM-mejna_crta.shp` ✓
- `EDM-mejna_crta.shx` — spatial index
- `EDM-mejna_crta.dbf` — attributes
- `EDM-mejna_crta.prj` — CRS definition (so the import tool knows it's 3794)
- `EDM-mejna_crta.cpg` — encoding (helpful for Slovenian characters)

Grab them from the original source (GURS / e-Geodetski podatki) and put all of them in the same folder.

## Step 2 — Import options

**Option A: `shp2pgsql` (classic PostGIS tool)**

```bash
shp2pgsql -s 3794 -I -W UTF-8 EDM-mejna_crta.shp public.slo_meja_raw \
  | psql -h <host> -U <user> -d fmp_data_gurs
```

Flags: `-s 3794` sets the SRID, `-I` builds a GIST index, `-W UTF-8` handles Slovenian characters. This loads into a **new raw table** (`slo_meja_raw`) with `MultiLineString` geometry — don't try to push lines directly into your `MultiPolygon` column. From there you'll transform into the final shape.

**Option B: `ogr2ogr` (more flexible)**

```bash
ogr2ogr -f "PostgreSQL" \
  PG:"host=<host> dbname=fmp_data_gurs user=<user>" \
  EDM-mejna_crta.shp \
  -nln slo_meja_raw -nlt MULTILINESTRING -lco GEOMETRY_NAME=geom \
  -a_srs EPSG:3794
```

**Option C: GUI** — QGIS → "DB Manager" → import layer. Drag the .shp in, point at your Postgres connection, done. Probably the easiest if you have QGIS already.

## Step 3 — Build the clean border (preview)

Once it's in a raw table, the SQL to stitch the 4 main segments into one closed ring and turn it into a polygon would look roughly like this:

```sql
-- Merge all line segments, then close the ring and polygonize
WITH merged AS (
  SELECT ST_LineMerge(ST_Collect(geom)) AS line
  FROM slo_meja_raw
  WHERE ST_Length(geom) > 1000   -- drops the two tiny loops
)
SELECT ST_Multi(ST_MakePolygon(line)) AS geom
FROM merged;
```

`ST_LineMerge` is the key function — it takes a `MultiLineString` and joins segments that share endpoints into a single continuous `LineString`. Since your 4 main segments connect end-to-end into a closed ring, the result should be one closed `LineString` ready for `ST_MakePolygon`.

If `ST_LineMerge` returns a `MultiLineString` instead of a single `LineString`, the endpoints don't match exactly and you'll need `ST_Snap` first to glue them — but from the coordinates I checked above, the endpoints look identical, so it should just work.

Answer the two questions above and I'll give you the exact SQL — including how to handle the tiny loops and an insert into `slo_meja_uradna` with proper `id`/`created_at`/`gid` values.





---
Powered by [Claude Exporter](https://www.ai-chat-exporter.net)
