# Instructions for Renaming Columns to Slovene

## Recommended Approach

Since the column renames affect **every SQL file** in the project, the most efficient approach is to use find-and-replace across all files.

### Step 1: Run Column Rename Script (in database)

```bash
psql your_database < Main/00a_rename_columns_to_slovene.sql
```

This will rename the actual database columns.

### Step 2: Update SQL Files (find-replace)

Use your IDE or command line to replace across all `.sql` files in `Main/`:

#### OBM Topology Table Renames:

```
topology_problem_type  →  tip_topoloskega_problema
id1                    →  id_prvega_obm
id2                    →  id_drugega_obm
area                   →  povrsina
perimeter              →  obseg
compactness            →  kompaktnost
```

#### Hierarchy Table Renames:

```
entity_type            →  tip_entitete
problem_type           →  tip_problema
entity_id              →  id_entitete
reference_id           →  id_referenca
details                →  podrobnosti
```

### Step 3: Update Constraints

Run these SQL commands to update constraint names:

```sql
-- Update OBM constraints
ALTER TABLE md_topoloske_kontrole_obm DROP CONSTRAINT IF EXISTS check_topology_problem_type_obm;
ALTER TABLE md_topoloske_kontrole_obm ADD CONSTRAINT check_tip_topoloskega_problema_obm
    CHECK (tip_topoloskega_problema IN ('intersection', 'hole', 'overflow'));

ALTER TABLE md_topoloske_kontrole_obm DROP CONSTRAINT IF EXISTS check_id1_less_than_id2_obm;
ALTER TABLE md_topoloske_kontrole_obm ADD CONSTRAINT check_id_prvega_less_than_drugega_obm
    CHECK (id_drugega_obm IS NULL OR (id_prvega_obm IS NOT NULL AND id_prvega_obm < id_drugega_obm));

-- Update hierarchy constraints
ALTER TABLE md_topoloske_kontrole_hierarhija DROP CONSTRAINT IF EXISTS check_entity_type_hierarhija;
ALTER TABLE md_topoloske_kontrole_hierarhija ADD CONSTRAINT check_tip_entitete_hierarhija
    CHECK (tip_entitete IN ('cona', 'lao', 'tao'));

ALTER TABLE md_topoloske_kontrole_hierarhija DROP CONSTRAINT IF EXISTS check_problem_type_hierarhija;
ALTER TABLE md_topoloske_kontrole_hierarhija ADD CONSTRAINT check_tip_problema_hierarhija
    CHECK (tip_problema IN (
        'missing_obm_in_cona', 'orphan_obm_ref', 'orphan_cona_ref', 'empty_cona',
        'missing_cona_in_lao', 'orphan_lao_ref_in_cona', 'empty_lao',
        'missing_lao_in_tao', 'orphan_tao_ref_in_lao', 'empty_tao'
    ));
```

### Step 4: Update Index Names (optional but recommended)

```sql
-- OBM indexes
ALTER INDEX IF EXISTS idx_topoloske_kontrole_obm_query
    RENAME TO idx_topoloske_kontrole_obm_poizvedba;

-- Hierarchy indexes
ALTER INDEX IF EXISTS idx_topoloske_kontrole_hierarhija_query
    RENAME TO idx_topoloske_kontrole_hierarhija_poizvedba;
```

## Files That Need Updates

All files in `Main/`:
- ✅ `00a_rename_columns_to_slovene.sql` (migration script, already has Slovene names)
- ❌ `00setup.sql` (needs find-replace)
- ❌ `3checkAllTopologies.sql` (needs find-replace)
- ❌ `5trigger.sql` (needs find-replace)
- ❌ `6validateHierarchy.sql` (needs find-replace)
- ❌ `7triggerHierarchy.sql` (needs find-replace)
- ❌ `99test_full_system.sql` (needs find-replace)

## Alternative: Let Me Create Updated Files

If you prefer, I can create updated versions of each file with Slovene names. However, this would mean:
- 6 large files to regenerate
- Risk of losing any local changes you've made
- More work to review all changes

**Recommendation**: Use find-replace in your IDE - it's faster, safer, and you can review each change.

## VS Code Find-Replace Example

1. Open the `Main/` folder
2. Press `Ctrl+Shift+H` (or `Cmd+Shift+H` on Mac)
3. Click "Use Regular Expression" button (.*)
4. Find: `\btopology_problem_type\b`
5. Replace: `tip_topoloskega_problema`
6. Click "Replace All in 6 files"

Repeat for each column name mapping.

The `\b` ensures whole-word matching (won't replace partial matches).
