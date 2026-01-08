# Topology Validation System for md_geo_obm

## Overview

This system maintains topology validation for spatial data in the `md_geo_obm` table, ensuring that for each version (`id_rel_geo_verzija`), the geometries form a perfect tiling of Slovenia (`slo_meja`) with:
- **No holes** - Every part of Slovenia must be covered
- **No intersections** - Geometries cannot overlap
- **No overflows** - Geometries cannot extend beyond Slovenia's borders

## System Architecture

### Tables

1. **md_geo_obm** - Main geometry table
   - `id` - Primary key
   - `geom` - Geometry (polygon)
   - `id_rel_geo_verzija` - Version identifier
   - `intersecting` - Boolean flag for intersection violations
   - `overflowing` - Boolean flag for overflow violations

2. **topoloske_vrzeli** - Holes table
   - `id` - Primary key
   - `id_rel_geo_verzija` - Version identifier
   - `geom` - Hole geometry

3. **slo_meja** - Slovenia boundary (materialized view)
   - `geom` - Slovenia's boundary geometry

### Components

#### 1. Incremental Validation Trigger (`validate_topology_incremental()`)
- **File**: `topology_trigger.sql`
- **Trigger**: `trg_validate_topology`
- **Timing**: BEFORE INSERT, UPDATE, DELETE
- **Scope**: FOR EACH ROW

**Operations:**

**INSERT:**
- Checks if geometry overflows Slovenia boundary
- Detects intersections with existing geometries
- Marks both the new and intersecting geometries
- Reduces or eliminates existing holes covered by new geometry

**DELETE:**
- Calculates potential hole left by removed geometry
- Merges with existing adjacent holes if applicable
- Updates intersection flags for geometries that were intersecting with deleted one

**UPDATE:**
- Treated as DELETE (old geometry) + INSERT (new geometry)
- Ensures all validations are properly maintained

#### 2. Full Revalidation Functions
- **File**: `topology_validation.sql`

**`revalidate_topology(p_id_rel_geo_verzija INTEGER)`**
- Performs complete topology validation for a single version
- Returns statistics: holes found, overflows found, intersections found, total entries

**`revalidate_all_topologies()`**
- Validates all versions in the database
- Returns per-version statistics

**Process:**
1. Unions all geometries for the version
2. Finds holes: `ST_Difference(slo_meja, ST_Union(geom))`
3. Finds overflows: `ST_Difference(ST_Union(geom), slo_meja)`
4. Finds intersections: Pairwise comparison with `ST_Overlaps`

## Installation

### Prerequisites
- PostgreSQL with PostGIS extension
- Existing `md_geo_obm`, `topoloske_vrzeli`, and `slo_meja` tables/views

### Step 1: Install Full Revalidation Functions
```sql
\i topology_validation.sql
```

This creates:
- `revalidate_topology(INTEGER)`
- `revalidate_all_topologies()`

### Step 2: Run Initial Validation
```sql
-- Validate all existing data
SELECT * FROM revalidate_all_topologies();

-- Or for a specific version
SELECT * FROM revalidate_topology(1);
```

### Step 3: Install Incremental Trigger
```sql
\i topology_trigger.sql
```

This creates:
- `validate_topology_incremental()` function
- `trg_validate_topology` trigger

### Step 4: Verify Installation
```sql
\i topology_testing_guide.sql
```

Run the setup verification queries at the top of this file.

## Usage

### Normal Operations

Once installed, the system works automatically:

```sql
-- Insert a new geometry - validation happens automatically
INSERT INTO md_geo_obm (geom, id_rel_geo_verzija)
VALUES (ST_GeomFromText('POLYGON((...))'), 1);

-- Update a geometry - validation updates automatically  
UPDATE md_geo_obm 
SET geom = ST_GeomFromText('POLYGON((...))') 
WHERE id = 123;

-- Delete a geometry - holes and intersections update automatically
DELETE FROM md_geo_obm WHERE id = 123;
```

### Checking Validation Status

```sql
-- View all problems for a version
SELECT id, intersecting, overflowing
FROM md_geo_obm
WHERE id_rel_geo_verzija = 1
  AND (intersecting OR overflowing);

-- View all holes for a version
SELECT id, ST_Area(geom) as hole_area
FROM topoloske_vrzeli
WHERE id_rel_geo_verzija = 1;

-- Get summary statistics
SELECT * FROM v_topology_summary WHERE id_rel_geo_verzija = 1;

-- Analyze coverage
SELECT * FROM analyze_coverage(1);
```

### Maintenance

```sql
-- If data seems inconsistent, run full revalidation
SELECT * FROM revalidate_topology(1);

-- Revalidate all versions (run during low-usage periods)
SELECT * FROM revalidate_all_topologies();

-- Regular maintenance
VACUUM ANALYZE md_geo_obm;
VACUUM ANALYZE topoloske_vrzeli;
```

## Performance Considerations

### Indexing
Ensure proper indices exist:
```sql
CREATE INDEX IF NOT EXISTS idx_md_geo_obm_geom 
    ON md_geo_obm USING GIST(geom);
    
CREATE INDEX IF NOT EXISTS idx_md_geo_obm_version 
    ON md_geo_obm(id_rel_geo_verzija);
    
CREATE INDEX IF NOT EXISTS idx_topoloske_vrzeli_geom 
    ON topoloske_vrzeli USING GIST(geom);
    
CREATE INDEX IF NOT EXISTS idx_topoloske_vrzeli_version 
    ON topoloske_vrzeli(id_rel_geo_verzija);
```

### Performance Characteristics

**Incremental Trigger:**
- INSERT: O(n) where n = number of existing geometries in version
- DELETE: O(n) for intersection updates, O(h) for hole merging where h = adjacent holes
- UPDATE: O(n) (treated as DELETE + INSERT)

**Full Revalidation:**
- Holes: O(n) - linear in number of geometries
- Overflows: O(n) - linear in number of geometries  
- Intersections: O(n²) - quadratic, most expensive operation

For versions with many geometries (>1000), intersection detection may take several seconds. Consider running full revalidation during off-hours.

### Optimization Tips

1. **Batch Operations**: When inserting many geometries, consider:
   - Temporarily disabling the trigger
   - Performing bulk insert
   - Running full revalidation once
   - Re-enabling trigger

```sql
ALTER TABLE md_geo_obm DISABLE TRIGGER trg_validate_topology;
-- Bulk insert operations
ALTER TABLE md_geo_obm ENABLE TRIGGER trg_validate_topology;
SELECT * FROM revalidate_topology(<version>);
```

2. **Partition by Version**: For very large datasets, consider partitioning `md_geo_obm` by `id_rel_geo_verzija`.

3. **Monitor Performance**:
```sql
SELECT * FROM pg_stat_user_triggers 
WHERE trigger_name = 'trg_validate_topology';
```

## Validation Logic Details

### Intersection Detection
Two geometries are considered intersecting if they **overlap** (ST_Overlaps returns true). This means:
- They share some but not all interior points
- Contains/within relationships are also checked

### Overflow Detection  
A geometry overflows if any part extends beyond Slovenia's boundary:
```sql
overflow = ST_Difference(geometry, slo_meja)
```

### Hole Detection
Holes are calculated as the difference between Slovenia and the union of all geometries:
```sql
holes = ST_Difference(slo_meja, ST_Union(all_geometries))
```

Multiple disconnected holes are stored as separate rows in `topoloske_vrzeli`.

## Troubleshooting

### Problem: Trigger doesn't seem to work
**Check:**
```sql
SELECT tgname, tgenabled 
FROM pg_trigger 
WHERE tgname = 'trg_validate_topology';
```
Ensure `tgenabled` is not 'D' (disabled).

### Problem: Inconsistent validation results
**Solution:**
```sql
-- Run full revalidation
SELECT * FROM revalidate_topology(<version>);

-- Compare with current state
SELECT 
    id,
    intersecting,
    overflowing
FROM md_geo_obm
WHERE id_rel_geo_verzija = <version>
  AND (intersecting OR overflowing);
```

### Problem: Performance degradation
**Diagnosis:**
```sql
-- Check number of geometries per version
SELECT 
    id_rel_geo_verzija,
    COUNT(*) as geometry_count
FROM md_geo_obm
GROUP BY id_rel_geo_verzija
ORDER BY geometry_count DESC;

-- Check for missing indices
SELECT 
    schemaname,
    tablename,
    indexname
FROM pg_indexes
WHERE tablename IN ('md_geo_obm', 'topoloske_vrzeli');
```

**Solutions:**
- Ensure GIST indices exist on geometry columns
- Run VACUUM ANALYZE regularly
- Consider batch operations for large insertions
- Partition tables if dealing with many versions

### Problem: Unexpected holes reported
**Diagnosis:**
```sql
-- Visualize the union of geometries vs Slovenia
SELECT 
    ST_AsGeoJSON(ST_Union(geom)) as covered_area,
    (SELECT ST_AsGeoJSON(geom) FROM slo_meja LIMIT 1) as slovenia
FROM md_geo_obm
WHERE id_rel_geo_verzija = <version>;

-- Check hole geometries
SELECT 
    id,
    ST_Area(geom) as hole_area,
    ST_AsText(ST_Centroid(geom)) as center
FROM topoloske_vrzeli
WHERE id_rel_geo_verzija = <version>
ORDER BY ST_Area(geom) DESC;
```

Small holes might indicate:
- Precision issues in geometry data
- Gaps in source data
- Snapping tolerance problems

## Testing

Comprehensive testing examples are provided in `topology_testing_guide.sql`:

1. **Simple Insert** - Verify basic functionality
2. **Insert with Intersection** - Test intersection detection
3. **Insert with Overflow** - Test boundary checking
4. **Delete Creating Hole** - Test hole detection
5. **Update Geometry** - Test update handling

Run these tests in a development environment before deploying to production.

## Files

- `topology_validation.sql` - Full revalidation functions
- `topology_trigger.sql` - Incremental validation trigger
- `topology_testing_guide.sql` - Comprehensive testing suite
- `README.md` - This documentation

## Version History

- **v1.0** - Initial implementation with incremental and full validation

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review PostgreSQL logs for errors
3. Run full revalidation to verify data consistency
4. Check that all indices are present and valid

## License

Internal use for spatial data validation at your organization.
