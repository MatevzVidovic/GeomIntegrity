# Column Name Fixes in 5trigger.sql

## Issues Found

When creating the 98load_all_functions.sql script, I discovered that **5trigger.sql** had several column references that weren't updated to the Slovene naming convention.

## Problems

### 1. Non-existent Column: `area_type`
**Location**: Two INSERT statements in 5trigger.sql
**Issue**: Column `area_type` doesn't exist in `md_topoloske_kontrole_obm` schema
**Used in**:
- Line 161: INSERT INTO md_topoloske_kontrole_obm (... area_type ...)
- Line 206: WHERE area_type = 'obm' (in SELECT)
- Line 224: INSERT INTO md_topoloske_kontrole_obm (... area_type ...)

**Why it was there**: Likely a leftover from an earlier schema design

### 2. Old English Column Names
**Issue**: Still using English names instead of Slovene
- `area` → should be `povrsina`
- `perimeter` → should be `obseg`

**Locations**:
- Line 165: `area` in column list
- Line 166: `perimeter` in column list
- Line 226: `area` in column list
- Line 227: `perimeter` in column list

## Fixes Applied

### Fix 1: Removed `area_type` Column
```sql
-- BEFORE (WRONG):
INSERT INTO md_topoloske_kontrole_obm (
    id,
    created_at,
    created_by,
    geom,
    area_type,              -- ❌ Doesn't exist!
    id_rel_geo_verzija,
    ...
)
SELECT
    ...
    'obm',                  -- ❌ Value for non-existent column

-- AFTER (CORRECT):
INSERT INTO md_topoloske_kontrole_obm (
    id,
    created_at,
    created_by,
    geom,
    id_rel_geo_verzija,     -- ✅ No area_type
    ...
)
SELECT
    ...                     -- ✅ No 'obm' value
```

### Fix 2: Renamed English Columns to Slovene
```sql
-- BEFORE (WRONG):
INSERT INTO md_topoloske_kontrole_obm (
    ...
    area,                   -- ❌ Should be povrsina
    perimeter,              -- ❌ Should be obseg
    ...
)

-- AFTER (CORRECT):
INSERT INTO md_topoloske_kontrole_obm (
    ...
    povrsina,               -- ✅ Correct Slovene name
    obseg,                  -- ✅ Correct Slovene name
    ...
)
```

### Fix 3: Removed `area_type` from WHERE Clause
```sql
-- BEFORE (WRONG):
WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
  AND area_type = 'obm'                 -- ❌ Column doesn't exist!
  AND tip_topoloskega_problema = 'luknja'

-- AFTER (CORRECT):
WHERE id_rel_geo_verzija = v_id_rel_geo_verzija
  AND tip_topoloskega_problema = 'luknja'  -- ✅ No area_type check needed
```

### Fix 4: Fixed Function Name Inconsistency
```sql
-- BEFORE (inconsistent):
st_perimeter(hole_geom),    -- lowercase 'st_perimeter'

-- AFTER (consistent):
ST_Perimeter(hole_geom),    -- PascalCase like other PostGIS functions
```

## Impact

These fixes ensure that:
1. ✅ 5trigger.sql uses only columns that exist in the schema
2. ✅ All column names are in Slovene (consistent with 3checkAllTopologies.sql)
3. ✅ The trigger function will work correctly when loaded
4. ✅ No runtime errors from missing columns

## Files Modified

- **Main/5trigger.sql**: Fixed all column name references

## Verification

The trigger now correctly references these columns:
- `id` - UUID
- `created_at` - TIMESTAMP
- `created_by` - UUID
- `geom` - GEOMETRY
- `id_rel_geo_verzija` - UUID
- `id1`, `id2` - UUID (for intersections)
- `povrsina` - DOUBLE PRECISION (Slovene for "area")
- `obseg` - DOUBLE PRECISION (Slovene for "perimeter")
- `kompaktnost` - DOUBLE PRECISION (Slovene for "compactness")
- `tip_topoloskega_problema` - TEXT ('prekrivanje', 'luknja', 'preliv')

All of these match the final schema in **FINAL_SCHEMA.md**.

## Why This Wasn't Caught Earlier

The issue went unnoticed because:
1. We were manually loading individual files, not running them together
2. The trigger function has complex logic, making it easy to miss column references
3. These columns were buried in the middle of long INSERT statements
4. The WHERE clause issue was in a nested query

Creating the 98load_all_functions.sql script (which loads everything in order) forced a careful review of all files, which revealed these inconsistencies.

## Related Changes

This fix completes the column renaming initiative:
- ✅ **3checkAllTopologies.sql** - Already had Slovene names
- ✅ **5trigger.sql** - NOW fixed with this change
- ✅ **6validateHierarchy.sql** - Already had correct names
- ✅ **7triggerHierarchy.sql** - Already had correct names

All SQL files now use consistent Slovene naming!
