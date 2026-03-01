# Final Database Schema - Slovene Column Names

## Table: md_topoloske_kontrole_obm
**Purpose**: Stores geometric topology problems for obmocja (areas)

### Columns:
| Column Name | Type | Description |
|-------------|------|-------------|
| id | UUID | Primary key |
| created_at | TIMESTAMP | Creation timestamp |
| created_by | UUID | Creator ID |
| updated_at | TIMESTAMP | Last update timestamp |
| updated_by | UUID | Last updater ID |
| id_rel_geo_verzija | UUID | Geo version ID |
| **tip_topoloskega_problema** | TEXT | Type of topology problem ('prekrivanje', 'luknja', 'preliv') |
| **id1** | UUID | First OBM ID (for intersections) |
| **id2** | UUID | Second OBM ID (for intersections) |
| geom | GEOMETRY | Problem geometry |
| **povrsina** | DOUBLE PRECISION | Area (m²) |
| **obseg** | DOUBLE PRECISION | Perimeter (m) |
| **kompaktnost** | DOUBLE PRECISION | Compactness metric |

### Constraints:
- `tip_topoloskega_problema` IN ('prekrivanje', 'luknja', 'preliv')
  - `prekrivanje` = intersection (overlapping areas)
  - `luknja` = hole (uncovered area)
  - `preliv` = overflow (area beyond boundary)
- `id2` IS NULL OR (`id1` IS NOT NULL AND `id1` < `id2`)

### Indexes:
- `idx_topoloske_kontrole_obm_query` ON (id_rel_geo_verzija, tip_topoloskega_problema, id1, id2)
- GIST index on `geom` (may be auto-created by PostGIS)

---

## Table: md_topoloske_kontrole_hierarhija
**Purpose**: Stores ID-based hierarchy validation problems for cona/lao/tao

### Columns:
| Column Name | Type | Description |
|-------------|------|-------------|
| id | UUID | Primary key |
| created_at | TIMESTAMP | Creation timestamp |
| created_by | UUID | Creator ID |
| updated_at | TIMESTAMP | Last update timestamp |
| updated_by | UUID | Last updater ID |
| id_rel_verzije_modeli | UUID | Model version ID |
| **tip_entitete** | TEXT | Entity type ('cona', 'lao', 'tao') |
| **tip_problema** | TEXT | Problem type (see list below) |
| **problematicen_id** | UUID | The relevant ID (what it refers to depends on tip_problema) |

### Problem Types and What problematicen_id Refers To:

#### Cona Problems:
| tip_problema | problematicen_id refers to |
|--------------|---------------------|
| `obm. v nobeni coni` | The orphaned OBM's ID |
| `napačno obm.` | The non-existent OBM ID referenced in obmxcona |
| `cona ne obstaja` | The non-existent cona ID referenced in obmxcona |
| `cona brez obm.` | The empty cona's ID |

#### LAO Problems:
| tip_problema | problematicen_id refers to |
|--------------|---------------------|
| `cona v nobenem LAO` | The cona's ID that isn't assigned to any LAO |
| `LAO ne obstaja` | The non-existent LAO ID that cona references |
| `LAO brez cone` | The empty LAO's ID |

#### TAO Problems:
| tip_problema | problematicen_id refers to |
|--------------|---------------------|
| `LAO v nobenem TAO` | The LAO's ID that isn't assigned to any TAO |
| `TAO ne obstaja` | The non-existent TAO ID that LAO references |
| `TAO brez LAO` | The empty TAO's ID |

### Constraints:
- `tip_entitete` IN ('cona', 'lao', 'tao')
- `tip_problema` IN ('obm. v nobeni coni', 'napačno obm.', 'cona ne obstaja', 'cona brez obm.', 'cona v nobenem LAO', 'LAO ne obstaja', 'LAO brez cone', 'LAO v nobenem TAO', 'TAO ne obstaja', 'TAO brez LAO')

### Indexes:
- `idx_topoloske_kontrole_hierarhija_query` ON (id_rel_verzije_modeli, tip_entitete, tip_problema, problematicen_id)

---

## Column Mapping: English → Slovene

### OBM Table:
- `topology_problem_type` → `tip_topoloskega_problema`
- `id1` → `id1` (unchanged)
- `id2` → `id2` (unchanged)
- `area` → `povrsina`
- `perimeter` → `obseg`
- `compactness` → `kompaktnost`

### Hierarchy Table:
- `entity_type` → `tip_entitete`
- `problem_type` → `tip_problema`
- **SIMPLIFIED**: `entity_id` + `reference_id` → single `problematicen_id`
- **REMOVED**: `details` field (redundant with tip_problema)

---

## Design Rationale

### Why Single problematicen_id Instead of entity_id + reference_id?

**Old Design** (complex):
- `entity_id`: Entity with the problem
- `reference_id`: Missing/orphan reference
- `details`: Human-readable explanation

**Problem**: Not all issues use both fields, and details field was redundant.

**New Design** (simple):
- `tip_problema`: Describes the problem AND implicitly tells you what `problematicen_id` refers to
- `problematicen_id`: The single relevant ID

**Benefits**:
1. **Simpler schema** - One ID column instead of two
2. **Less redundancy** - No need for details string
3. **Self-documenting** - tip_problema value tells you what problematicen_id means
4. **Easier queries** - No need to check which ID field is populated

### Examples:

```sql
-- Find all conas with invalid LAO references
SELECT * FROM md_topoloske_kontrole_hierarhija
WHERE tip_entitete = 'cona'
  AND tip_problema = 'LAO ne obstaja';
-- problematicen_id contains the invalid LAO IDs

-- Find all empty LAOs
SELECT * FROM md_topoloske_kontrole_hierarhija
WHERE tip_entitete = 'lao'
  AND tip_problema = 'LAO brez cone';
-- problematicen_id contains the empty LAO IDs
```
