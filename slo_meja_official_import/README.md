# Official Slovenia Boundary Import

This imports `DRZAVNA_MEJA/EDM-mejna_crta.shp` into PostGIS and builds one
`geometry(MultiPolygon, 3794)` row.

The shapefile contains official border lines, not polygons. The import loads
those lines into a raw table first, then uses `ST_BuildArea` to create the
final multipolygon. This preserves closed inner rings from the official
linework instead of dropping them.

## Run

Set normal PostgreSQL connection variables:

```bash
export PGHOST=test.gurs.db.flycom.si
export PGPORT=5432
export PGDATABASE=fmp_data_gurs
export PGUSER=gurs_readwrite
export PGPASSWORD='...'
```

Then run:

```bash
./slo_meja_official_import/import_slo_meja_uradna.sh
```

Defaults:

```bash
RAW_SCHEMA=public
RAW_TABLE=slo_meja_uradna_raw
TARGET_SCHEMA=public
TARGET_TABLE=slo_meja_uradna
```

You can override them:

```bash
TARGET_TABLE=slo_meja_uradna_test ./slo_meja_official_import/import_slo_meja_uradna.sh
```

## Optional Live Boundary Replacement

After reviewing `slo_meja_uradna`, copy it into the live topology boundary:

```bash
psql -v ON_ERROR_STOP=1 -f slo_meja_official_import/sql/02_copy_uradna_to_slo_meja.sql
```

Do this only when you want the validation system to use the official border
instead of the current `slo_meja` built from `md_geo_obm`.
