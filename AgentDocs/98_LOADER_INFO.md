# 8_1_load_fns_and_triggers.sql - Function Loader Script

## Purpose

This script loads all validation functions and triggers WITHOUT running setup operations. Use this to define all functions in your database after the initial setup is complete.

## What It Does

The script loads functions and triggers in the correct dependency order:

1. **Precision Functions** (`1_1_fn_coerce_2_decimal_places.sql`)
   - `validate_2_decimal_places()` - Check if geometries have 2 decimal precision
   - `debug_2_decimal_places()` - Debug precision issues
   - `set_to_2_decimal_places()` - Fix all geometries to 2 decimal precision

2. **OBM Topology Validation** (`2_0_fn_obm_geom_check_all.sql`)
   - `validate_holes(uuid)` - Find uncovered areas (luknja)
   - `validate_overflows(uuid)` - Find areas beyond boundary (preliv)
   - `validate_intersections(uuid)` - Find overlapping areas (prekrivanje)
   - `validate_all(uuid)` - Run all validations for one version
   - `validate_all_topologies()` - Run all validations for all versions

3. **OBM Incremental Trigger** (`2_1_trg_obm_geom_trigger.sql`)
   - `validate_topology_incremental()` - Trigger function
   - `trg_validate_topology_incremental` - Trigger on md_geo_obm

4. **Hierarchy Validation** (`3_0_fn_hierarchy_check_all.sql`)
   - `validate_cona_hierarchy(uuid)` - Validate OBM-Cona relationships
   - `validate_lao_hierarchy(uuid)` - Validate Cona-LAO relationships
   - `validate_tao_hierarchy(uuid)` - Validate LAO-TAO relationships
   - `validate_all_hierarchy(uuid)` - Run all hierarchy checks for one version
   - `validate_all_hierarchies()` - Run all hierarchy checks for all versions

5. **Hierarchy Incremental Triggers** (`3_1_trg_hierarchy_triggers.sql`)
   - `validate_obmxcona_incremental()` - Trigger function
   - `trg_validate_obmxcona_incremental` - Trigger on md_geo_obmxcona
   - `validate_cona_lao_incremental()` - Trigger function
   - `trg_validate_cona_lao_incremental` - Trigger on md_geo_cona
   - `validate_lao_tao_incremental()` - Trigger function
   - `trg_validate_lao_tao_incremental` - Trigger on md_geo_lao

## When to Use

Use this script when:
- ✅ You've already run `1_0_setup.sql` to create tables and indexes
- ✅ You want to reload function definitions after making changes
- ✅ You're setting up a new environment and need all functions defined
- ✅ You want to ensure all functions are up-to-date

Do NOT use this script:
- ❌ As your first setup step (use `1_0_setup.sql` first)
- ❌ To create tables (they must already exist)
- ❌ To populate initial validation data (use `validate_all_topologies()` after)

## Usage

```sql
\i Main/8_1_load_fns_and_triggers.sql
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
\i Main/8_0_test_full_system.sql
```

### Check Precision
```sql
-- Check if all geometries have 2 decimal precision
SELECT * FROM validate_2_decimal_places();

-- Fix if needed
SELECT * FROM set_to_2_decimal_places();
```

## Files Loaded (in order)

1. `1_1_fn_coerce_2_decimal_places.sql` - Precision utilities
2. `2_0_fn_obm_geom_check_all.sql` - OBM validation functions
3. `2_1_trg_obm_geom_trigger.sql` - OBM incremental trigger
4. `3_0_fn_hierarchy_check_all.sql` - Hierarchy validation functions
5. `3_1_trg_hierarchy_triggers.sql` - Hierarchy incremental triggers

## Files NOT Loaded (deprecated, with `-` prefix)

- `-0simplify_polygons.sql` - Old simplification utilities
- `-2topologyFixer.sql` - Old topology fixing functions
- `-4checkAllTopologiesWithSimplified.sql` - Old validation for simplified geoms

These files are kept for reference but are not part of the active system.

## What's NOT in This Script

This script does NOT include:
- ❌ Table creation (`1_0_setup.sql` handles this)
- ❌ Index creation (`1_0_setup.sql` handles this)
- ❌ Constraint creation (`1_0_setup.sql` handles this)
- ❌ Initial slo_meja population (`1_0_setup.sql` handles this)
- ❌ Initial validation data (`validate_all_topologies()` handles this)
- ❌ Test data or test execution (`8_0_test_full_system.sql` handles this)

## Troubleshooting

### "relation does not exist" errors
**Problem**: Tables haven't been created yet
**Solution**: Run `\i Main/1_0_setup.sql` first

### "trigger already exists" errors
**Problem**: Should not happen (script uses DROP TRIGGER IF EXISTS)
**Solution**: Check for syntax errors in the SQL files

### Functions defined but not working
**Problem**: May need to run initial validation
**Solution**: Run `SELECT * FROM validate_all_topologies();`

## Development Workflow

When modifying validation logic:

1. Edit the SQL file (e.g., `2_1_trg_obm_geom_trigger.sql`)
2. Reload definitions: `\i Main/8_1_load_fns_and_triggers.sql`
3. Test changes: `\i Main/8_0_test_full_system.sql`
4. Verify: Check that triggers behave as expected

This workflow is fast because:
- No need to recreate tables
- No need to reload initial data
- Test script automatically rolls back
- Can iterate quickly
