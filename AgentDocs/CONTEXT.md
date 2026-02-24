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
- `missing_obm_in_cona` - OBM exists but not assigned to any cona
- `orphan_obm_ref` - obmxcona references non-existent OBM
- `orphan_cona_ref` - obmxcona references non-existent cona
- `empty_cona` - Cona has no OBMs

**LAO problems:**
- `missing_cona_in_lao` - Cona not assigned to any LAO (id_rel_geo_lao IS NULL)
- `orphan_lao_ref_in_cona` - Cona references non-existent LAO
- `empty_lao` - LAO has no conas

**TAO problems:**
- `missing_lao_in_tao` - LAO not assigned to any TAO (id_rel_geo_tao IS NULL)
- `orphan_tao_ref_in_lao` - LAO references non-existent TAO
- `empty_tao` - TAO has no LAOs

## Implementation - File Organization

```
Main/
├── 00setup.sql                     - Setup commands (use 00setup_new.sql)
├── 00setup_new.sql                 - Clean setup script
├── -0simplify_polygons.sql         - Polygon simplification utilities
├── 1make2decimalPlaces.sql         - Precision functions
├── -2topologyFixer.sql             - Fix topology problems
├── 3checkAllTopologies.sql         - OBM full validation functions
├── -4checkAllTopologiesWithSimplified.sql - Validation for simplified geoms
├── 5trigger.sql                    - OBM incremental trigger
├── 6validateHierarchy.sql          - Cona/Lao/Tao full validation functions
└── 7triggerHierarchy.sql           - Cona/Lao/Tao incremental triggers

ignore_me/                          - Old/unused files

AgentDocs/
└── CONTEXT.md                      - This file
```

## OBM Topology Validation (Geometric)

### Full Validation Functions (3checkAllTopologies.sql)
- `validate_holes(uuid)` - Find uncovered areas within Slovenia boundary
- `validate_overflows(uuid)` - Find areas extending beyond Slovenia boundary
- `validate_intersections(uuid)` - Find overlapping obmocja
- `validate_all(uuid)` - Run all validations for a version
- `validate_all_topologies()` - Run all validations for all versions

### Incremental Trigger (5trigger.sql)
- `validate_topology_incremental()` - Trigger function
- `trg_validate_topology_incremental` - Fires on INSERT/UPDATE/DELETE of md_geo_obm
- Updates holes and intersections incrementally
- Handles geometry overflow beyond Slovenia boundary

## Hierarchy Validation (ID-based)

### Full Validation Functions (6validateHierarchy.sql)
- `validate_cona_hierarchy(uuid)` - Validate OBM-Cona relationships
- `validate_lao_hierarchy(uuid)` - Validate Cona-LAO relationships
- `validate_tao_hierarchy(uuid)` - Validate LAO-TAO relationships
- `validate_all_hierarchy(uuid)` - Run all hierarchy validations for a version
- `validate_all_hierarchies()` - Run all hierarchy validations for all versions

### Incremental Triggers (7triggerHierarchy.sql)
- `validate_obmxcona_incremental()` - Fires on md_geo_obmxcona changes
- `validate_cona_lao_incremental()` - Fires on md_geo_cona.id_rel_geo_lao changes
- `validate_lao_tao_incremental()` - Fires on md_geo_lao.id_rel_geo_tao changes

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

1. **Create required tables** (if not exist):
   - `md_topoloske_kontrole_obm` - for OBM topology issues
   - `md_topoloske_kontrole_hierarhija` - for hierarchy issues (see 6validateHierarchy.sql for schema)

2. **Run setup script**: `\i Main/00setup_new.sql`

3. **Load validation functions**:
   - `\i Main/3checkAllTopologies.sql`
   - `\i Main/6validateHierarchy.sql`

4. **Run initial validation**:
   - `SELECT * FROM validate_all_topologies();` (OBM)
   - `SELECT * FROM validate_all_hierarchies();` (Cona/Lao/Tao)

5. **Enable triggers**:
   - `\i Main/5trigger.sql` (OBM trigger)
   - `\i Main/7triggerHierarchy.sql` (Hierarchy triggers)

## Manual Actions Needed

1. **Replace 00setup.sql with 00setup_new.sql**:
   ```bash
   mv Main/00setup.sql Main/00setup_old.sql
   mv Main/00setup_new.sql Main/00setup.sql
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
