# 98load_all_functions.sql - Function Loader Script

## Purpose

This script loads all validation functions and triggers WITHOUT running setup operations. Use this to define all functions in your database after the initial setup is complete.

## What It Does

The script loads functions and triggers in the correct dependency order:

1. **Precision Functions** (`1make2decimalPlaces.sql`)
   - `validate_2_decimal_places()` - Check if geometries have 2 decimal precision
   - `debug_2_decimal_places()` - Debug precision issues
   - `set_to_2_decimal_places()` - Fix all geometries to 2 decimal precision

2. **OBM Topology Validation** (`3checkAllTopologies.sql`)
   - `validate_holes(uuid)` - Find uncovered areas (luknja)
   - `validate_overflows(uuid)` - Find areas beyond boundary (preliv)
   - `validate_intersections(uuid)` - Find overlapping areas (prekrivanje)
   - `validate_all(uuid)` - Run all validations for one version
   - `validate_all_topologies()` - Run all validations for all versions

3. **OBM Incremental Trigger** (`5trigger.sql`)
   - `validate_topology_incremental()` - Trigger function
   - `trg_validate_topology_incremental` - Trigger on md_geo_obm

4. **Hierarchy Validation** (`6validateHierarchy.sql`)
   - `validate_cona_hierarchy(uuid)` - Validate OBM-Cona relationships
   - `validate_lao_hierarchy(uuid)` - Validate Cona-LAO relationships
   - `validate_tao_hierarchy(uuid)` - Validate LAO-TAO relationships
   - `validate_all_hierarchy(uuid)` - Run all hierarchy checks for one version
   - `validate_all_hierarchies()` - Run all hierarchy checks for all versions

5. **Hierarchy Incremental Triggers** (`7triggerHierarchy.sql`)
   - `validate_obmxcona_incremental()` - Trigger function
   - `trg_validate_obmxcona_incremental` - Trigger on md_geo_obmxcona
   - `validate_cona_lao_incremental()` - Trigger function
   - `trg_validate_cona_lao_incremental` - Trigger on md_geo_cona
   - `validate_lao_tao_incremental()` - Trigger function
   - `trg_validate_lao_tao_incremental` - Trigger on md_geo_lao

## When to Use

Use this script when:
- ✅ You've already run `00setup.sql` to create tables and indexes
- ✅ You want to reload function definitions after making changes
- ✅ You're setting up a new environment and need all functions defined
- ✅ You want to ensure all functions are up-to-date

Do NOT use this script:
- ❌ As your first setup step (use `00setup.sql` first)
- ❌ To create tables (they must already exist)
- ❌ To populate initial validation data (use `validate_all_topologies()` after)

## Usage

```sql
\i Main/98load_all_functions.sql
```

## Safety

This script is **safe to run multiple times**:
- All functions use `CREATE OR REPLACE` - existing functions will be updated
- Triggers use `DROP TRIGGER IF EXISTS` before creating - no duplicates
- No data modifications occur (only function/trigger definitions)
- No table structure changes

## After Running

Once loaded, you can:

### Run Initial Validations
```sql
-- Validate all OBM topology for all versions
SELECT * FROM validate_all_topologies();

-- Validate all hierarchy relationships for all versions
SELECT * FROM validate_all_hierarchies();

-- Or for a specific version
SELECT * FROM validate_all('your-uuid-here');
SELECT * FROM validate_all_hierarchy('your-uuid-here');
```

### Test the System
```sql
-- Run comprehensive tests (automatic rollback)
\i Main/99test_full_system.sql
```

### Check Precision
```sql
-- Check if all geometries have 2 decimal precision
SELECT * FROM validate_2_decimal_places();

-- Fix if needed
SELECT * FROM set_to_2_decimal_places();
```

## Files Loaded (in order)

1. `1make2decimalPlaces.sql` - Precision utilities
2. `3checkAllTopologies.sql` - OBM validation functions
3. `5trigger.sql` - OBM incremental trigger
4. `6validateHierarchy.sql` - Hierarchy validation functions
5. `7triggerHierarchy.sql` - Hierarchy incremental triggers

## Files NOT Loaded (deprecated, with `-` prefix)

- `-0simplify_polygons.sql` - Old simplification utilities
- `-2topologyFixer.sql` - Old topology fixing functions
- `-4checkAllTopologiesWithSimplified.sql` - Old validation for simplified geoms

These files are kept for reference but are not part of the active system.

## What's NOT in This Script

This script does NOT include:
- ❌ Table creation (`00setup.sql` handles this)
- ❌ Index creation (`00setup.sql` handles this)
- ❌ Constraint creation (`00setup.sql` handles this)
- ❌ Initial slo_meja population (`00setup.sql` handles this)
- ❌ Initial validation data (`validate_all_topologies()` handles this)
- ❌ Test data or test execution (`99test_full_system.sql` handles this)

## Troubleshooting

### "relation does not exist" errors
**Problem**: Tables haven't been created yet
**Solution**: Run `\i Main/00setup.sql` first

### "trigger already exists" errors
**Problem**: Should not happen (script uses DROP TRIGGER IF EXISTS)
**Solution**: Check for syntax errors in the SQL files

### Functions defined but not working
**Problem**: May need to run initial validation
**Solution**: Run `SELECT * FROM validate_all_topologies();`

## Development Workflow

When modifying validation logic:

1. Edit the SQL file (e.g., `5trigger.sql`)
2. Reload definitions: `\i Main/98load_all_functions.sql`
3. Test changes: `\i Main/99test_full_system.sql`
4. Verify: Check that triggers behave as expected

This workflow is fast because:
- No need to recreate tables
- No need to reload initial data
- Test script automatically rolls back
- Can iterate quickly
