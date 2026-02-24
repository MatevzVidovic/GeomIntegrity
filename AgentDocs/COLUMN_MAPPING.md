# Column Name Mapping - English to Slovene

## md_topoloske_kontrole_obm (OBM Topology Controls)

| English Name | Slovene Name | Type | Description |
|--------------|--------------|------|-------------|
| id | id | uuid | Primary key |
| created_at | created_at | timestamp | Creation timestamp |
| created_by | created_by | uuid | Creator ID |
| id_rel_geo_verzija | id_rel_geo_verzija | uuid | Geo version ID |
| id_rel_verzije_modela | id_rel_verzije_modela | uuid | Model version ID |
| topology_problem_type | **tip_topoloskega_problema** | text | Problem type (intersection/hole/overflow) |
| id1 | **id_prvega_obm** | uuid | First OBM ID (for intersections) |
| id2 | **id_drugega_obm** | uuid | Second OBM ID (for intersections) |
| geom | geom | geometry | Problem geometry |
| area | **povrsina** | decimal | Area |
| perimeter | **obseg** | decimal | Perimeter |
| compactness | **kompaktnost** | decimal | Compactness metric |

## md_topoloske_kontrole_hierarhija (Hierarchy Controls)

| English Name | Slovene Name | Type | Description |
|--------------|--------------|------|-------------|
| id | id | uuid | Primary key |
| created_at | created_at | timestamp | Creation timestamp |
| created_by | created_by | uuid | Creator ID |
| id_rel_geo_verzija | id_rel_geo_verzija | uuid | Geo version ID |
| entity_type | **tip_entitete** | text | Entity type (cona/lao/tao) |
| problem_type | **tip_problema** | text | Problem type |
| entity_id | **id_entitete** | uuid | Entity with the problem |
| reference_id | **id_referenca** | uuid | Missing/orphan reference |
| details | **podrobnosti** | text | Human-readable details |

## Why id_entitete and id_referenca?

These two fields work together to describe the problem:

### id_entitete (Entity ID)
The ID of the entity **that has the problem**:
- Empty cona → stores the cona's ID
- OBM not in any cona → stores the OBM's ID
- Cona referencing invalid LAO → stores the cona's ID

### id_referenca (Reference ID)
The ID of the **missing or invalid reference** (optional, not all problems need it):
- Cona references non-existent LAO → stores the invalid LAO ID
- obmxcona references non-existent OBM → stores the invalid OBM ID
- Empty cona → NULL (no reference involved)

### Examples:

**Problem: "Cona X references non-existent LAO Y"**
- `id_entitete` = Cona X's ID (the entity with the problem)
- `id_referenca` = LAO Y's ID (the invalid reference)
- `tip_problema` = 'orphan_lao_ref_in_cona'

**Problem: "Cona Z is empty (no OBMs)"**
- `id_entitete` = Cona Z's ID (the entity with the problem)
- `id_referenca` = NULL (no reference involved)
- `tip_problema` = 'empty_cona'

**Problem: "OBM A is not assigned to any cona"**
- `id_entitete` = OBM A's ID (the entity with the problem)
- `id_referenca` = NULL (no reference involved)
- `tip_problema` = 'missing_obm_in_cona'
