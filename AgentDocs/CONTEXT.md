# GeomIntegrity Project Context

## Overview

This project implements SQL functions and triggers for **topology validation** of geographic areas (obmocja) in a PostgreSQL/PostGIS database. The system validates geometric integrity across a hierarchy of geographic entities.

## Entity Hierarchy (for a given model version)

```
md_geo_tao (Top-level administrative area)
    └── md_geo_lao (Local administrative area)
        └── md_geo_cona (Zone)
            └── md_geo_obm (Area/Obmocje - base unit with geometry)
```

### Relationships
- Each model is identified by `id_rel_geo_verzija` UUID
- `md_geo_obm` - Base geographic unit with actual polygon geometry
- `md_geo_obmxcona` - Cross table linking obm to cona
- `md_geo_cona` - Zone, defined by which obms belong to it via obmxcona, has FK `id_rel_geo_lao` to lao
- `md_geo_lao` - Local admin area, has FK `id_rel_geo_tao` to tao
- `md_geo_tao` - Top admin area

## Database Schema Summary

### md_geo_obm (Base areas with geometry)
- `id` UUID (PK)
- `id_rel_geo_verzija` UUID - model version
- `kopiran_id` UUID
- `ime_obmocja` TEXT
- `split_group_id` UUID
- `geom` GEOMETRY

### md_geo_obmxcona (OBM to Cona mapping)
- `id_rel_geo_obm` UUID (FK to md_geo_obm)
- `id_rel_geo_cona` UUID (FK to md_geo_cona)

### md_geo_cona (Zones)
- `id` UUID (PK)
- `id_rel_geo_verzija` UUID - model version
- `id_rel_geo_lao` UUID (FK to md_geo_lao)
- `ime_cone` TEXT
- ... many other attributes

### md_geo_lao (Local admin areas)
- `id` UUID (PK)
- `id_rel_geo_tao` UUID (FK to md_geo_tao)
- `id_rel_verzije_modeli` UUID
- `id_lao` SEQUENCE
- `ime_lao` TEXT
- `drugi_lao` BOOLEAN

### md_geo_tao (Top admin areas)
- `id` UUID (PK)
- `id_rel_verzije_modeli` UUID
- `id_tao` INTEGER
- `drugi_tao` BOOLEAN

## Validation Tables

### md_topoloske_kontrole_obm (OBM Topology - Geometric)
Stores **geometric** topology problems for obmocja:
- `id` UUID (PK)
- `id_rel_geo_verzija` UUID
- `topology_problem_type` TEXT - 'intersection', 'hole', 'overflow'
- `id1`, `id2` UUID - reference to obm ids (for intersections)
- `geom` GEOMETRY - the problem geometry
- `area`, `perimeter`, `compactness` - metrics

### md_topoloske_kontrole_hierarhija (Hierarchy Validation - ID-based)
Stores **ID-based** hierarchy problems for cona/lao/tao:
- `id` UUID (PK)
- `created_at` TIMESTAMP
- `created_by` UUID
- `id_rel_geo_verzija` UUID
- `entity_type` TEXT - 'cona', 'lao', 'tao'
- `problem_type` TEXT - see problem types below
- `entity_id` UUID - the entity with the problem
- `reference_id` UUID - the missing/invalid reference
- `details` TEXT - human readable description

#### Problem Types for Hierarchy Validation:
**Cona problems:**
- `obm. v nobeni coni` - OBM exists but not assigned to any cona
- `napačno obm.` - obmxcona references non-existent OBM
- `cona ne obstaja` - obmxcona references non-existent cona
- `cona brez obm.` - Cona has no OBMs

**LAO problems:**
- `cona v nobenem LAO` - Cona not assigned to any LAO (id_rel_geo_lao IS NULL)
- `LAO ne obstaja` - Cona references non-existent LAO
- `LAO brez cone` - LAO has no conas

**TAO problems:**
- `LAO v nobenem TAO` - LAO not assigned to any TAO (id_rel_geo_tao IS NULL)
- `TAO ne obstaja` - LAO references non-existent TAO
- `TAO brez LAO` - TAO has no LAOs

## Implementation - File Organization

```
Main/
├── 1_0_setup.sql                     - Initial setup (tables, indexes, constraints)
├── 1_1_fn_coerce_2_decimal_places.sql         - Precision functions
├── 2_0_fn_obm_geom_check_all.sql         - OBM full validation functions
├── 2_1_trg_obm_geom_trigger.sql                    - OBM incremental trigger
├── 3_0_fn_hierarchy_check_all.sql          - Cona/Lao/Tao full validation functions
├── 3_1_trg_hierarchy_triggers.sql           - Cona/Lao/Tao incremental triggers
├── 8_1_load_fns_and_triggers.sql        - Load all functions (1,3,5,6,7) in correct order
├── 8_0_test_full_system.sql          - Comprehensive test suite (auto-rollback)
├── -0simplify_polygons.sql         - OLD: Polygon simplification (deprecated)
├── -2topologyFixer.sql             - OLD: Fix topology problems (deprecated)
└── -4checkAllTopologiesWithSimplified.sql - OLD: Validation (deprecated)

ignore_me/                          - Old/unused files
AgentTests/                         - Comprehensive rollback-safe test suites
Makefile                            - Includes `make test-agent` command

Note: Files with '-' prefix are deprecated and not loaded by 8_1_load_fns_and_triggers.sql

AgentDocs/
├── CONTEXT.md                      - This file
├── AGENT_TESTS_COMPREHENSIVE.md    - Detailed AgentTests coverage + fixes
├── FINAL_SCHEMA.md                 - Final table schemas (Slovene names)
├── CHANGES_FINAL.md                - Summary of changes made
├── 98_LOADER_INFO.md               - Documentation for 8_1_load_fns_and_triggers.sql
├── ROLLBACK_INTEGRATION.md         - Rollback safety documentation
└── POSTGRESQL_ROLLBACK.md          - PostgreSQL transaction capabilities
```

## OBM Topology Validation (Geometric)

### Full Validation Functions (2_0_fn_obm_geom_check_all.sql)
- `validate_holes(uuid)` - Find uncovered areas within Slovenia boundary
- `validate_overflows(uuid)` - Find areas extending beyond Slovenia boundary
- `validate_intersections(uuid)` - Find overlapping obmocja
- `validate_all(uuid)` - Run all validations for a version
- `validate_all_topologies()` - Run all validations for all versions
- `validate_all(uuid)` returns a valid zero-count row for empty versions.

### Incremental Trigger (2_1_trg_obm_geom_trigger.sql)
- `validate_topology_incremental()` - Trigger function
- `trg_validate_topology_incremental` - Fires on INSERT/UPDATE/DELETE of md_geo_obm
- Updates holes and intersections incrementally
- Handles geometry overflow beyond Slovenia boundary

## Hierarchy Validation (ID-based)

### Full Validation Functions (3_0_fn_hierarchy_check_all.sql)
- `validate_cona_hierarchy(uuid)` - Validate OBM-Cona relationships
- `validate_lao_hierarchy(uuid)` - Validate Cona-LAO relationships
- `validate_tao_hierarchy(uuid)` - Validate LAO-TAO relationships
- `validate_all_hierarchy(uuid)` - Run all hierarchy validations for a version
- `validate_all_hierarchies()` - Run all hierarchy validations for all versions

### Incremental Triggers (3_1_trg_hierarchy_triggers.sql)
- `validate_obmxcona_incremental()` - Fires on md_geo_obmxcona changes
- `validate_cona_lao_incremental()` - Fires on md_geo_cona.id_rel_geo_lao changes
- `validate_lao_tao_incremental()` - Fires on md_geo_lao.id_rel_geo_tao changes
- `validate_obmxcona_incremental()` revalidates both old and new model versions on UPDATE when they differ.

## Key Concepts

### Slovenia Boundary (slo_meja)
- Table `slo_meja` contains the Slovenia boundary polygon
- Computed as the exterior ring of union of all obmocja
- Used to detect:
  - **Holes**: Areas inside Slovenia not covered by any obm
  - **Overflows**: Parts of obm extending outside Slovenia

### Geometry Precision
- All geometries use `ST_ReducePrecision(geom, 0.01)` for 2 decimal places
- Prevents floating point comparison issues

### Compactness Metric
- Formula: `4 * pi() * area / (perimeter^2)`
- Circle = ~0.08 (most compact)
- Used to identify sliver polygons vs real problems

## Setup Instructions

### First Time Setup

1. **Run setup script**: `\i Main/1_0_setup.sql`
   - Creates tables (if not exists)
   - Creates indexes
   - Adds constraints
   - Initializes slo_meja boundary

2. **Load all functions and triggers**: `\i Main/8_1_load_fns_and_triggers.sql`
   - Loads all validation functions (scripts 1-7)
   - Creates all triggers
   - Done in correct dependency order

3. **Run initial validation**:
   ```sql
   SELECT * FROM validate_all_topologies();    -- OBM topology
   SELECT * FROM validate_all_hierarchies();   -- Hierarchy relationships
   ```

4. **Test the system**: `\i Main/8_0_test_full_system.sql`
   - Comprehensive test suite
   - Automatically rolls back (safe to run)

5. **Run comprehensive AgentTests suite**:
   ```bash
   make test-agent
   ```
   - Runs strict assertion-based SQL suites
   - Rollback-safe (no persistent DB test data)

### Updating Functions After Changes

When you modify any SQL file (1-7):
```sql
\i Main/8_1_load_fns_and_triggers.sql
```

This reloads all function definitions without affecting data or tables.

## Testing

### 8_0_test_full_system.sql
**Purpose**: Comprehensive test suite that validates all system functionality

**SAFETY**: This script automatically wraps everything in a transaction and rolls back at the end. Your database will **NOT** be modified. PostgreSQL supports transactional DDL, so even trigger changes are rolled back.

**Test Model**:
- Creates 9 OBMs in 3x3 grid (1km each)
- Creates 3 Conas (one per row)
- Creates 2 LAOs
- Creates 1 TAO

**Tests Performed**:
1. Initial validation (perfect topology + hierarchy)
2. Intersection detection (expand OBM2 to overlap OBM5)
3. Hole detection (delete OBM5)
4. Orphan OBM detection (remove OBM3 from obmxcona)
5. Empty Cona detection (remove all OBMs from Cona3)
6. Orphan LAO reference (delete LAO2)

**Usage**: Just run it - rollback is automatic:
```sql
\i Main/8_0_test_full_system.sql
```

**What gets rolled back**:
- ✅ All test data (INSERTs, UPDATEs, DELETEs)
- ✅ All trigger changes (CREATE/DROP TRIGGER)
- ✅ Temporary tables
- ✅ slo_meja modifications

**PostgreSQL Transaction Safety**:
PostgreSQL supports **transactional DDL**, which means:
- ✅ DML operations (INSERT, UPDATE, DELETE) - fully rollback-able
- ✅ DDL operations (CREATE TABLE, ALTER TABLE, DROP TABLE, CREATE/DROP TRIGGER) - also rollback-able!
- ✅ TRUNCATE - rollback-able in PostgreSQL
- ❌ Only non-transactional: DROP/CREATE DATABASE operations

### AgentTests (comprehensive coverage)
**Purpose**: broad, strict, assertion-based validation of full functions and incremental triggers.

**Suites**:
- `AgentTests/01_full_validations.sql` - full OBM + hierarchy functions and wrappers
- `AgentTests/02_topology_trigger_incremental.sql` - OBM incremental trigger paths
- `AgentTests/03_hierarchy_trigger_incremental.sql` - hierarchy incremental trigger paths

**Runner**:
- `AgentTests/run_agent_tests.sh` reads DB settings from `db_config/config.py`
- `make test-agent` executes all suites in order
- transient connection retries are built in

**Details**:
- See `AgentDocs/AGENT_TESTS_COMPREHENSIVE.md`.

## Manual Actions Needed

1. **Replace 1_0_setup.sql with 1_0_setup_new.sql**:
   ```bash
   mv Main/1_0_setup.sql Main/1_0_setup_old.sql
   mv Main/1_0_setup_new.sql Main/1_0_setup.sql
   ```

2. **Rename table in database** (if needed):
   ```sql
   ALTER TABLE md_topoloske_kontrole RENAME TO md_topoloske_kontrole_obm;
   ```

3. **Create hierarchy table**:
   ```sql
   CREATE TABLE IF NOT EXISTS md_topoloske_kontrole_hierarhija (
       id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
       created_at TIMESTAMP DEFAULT now(),
       created_by UUID,
       id_rel_geo_verzija UUID NOT NULL,
       entity_type TEXT NOT NULL,
       problem_type TEXT NOT NULL,
       entity_id UUID,
       reference_id UUID,
       details TEXT
   );

   CREATE INDEX IF NOT EXISTS idx_topoloske_kontrole_hierarhija
   ON md_topoloske_kontrole_hierarhija (
       id_rel_geo_verzija,
       entity_type,
       problem_type
   );
   ```
