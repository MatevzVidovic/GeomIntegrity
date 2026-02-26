# AgentTests Comprehensive Coverage (Task 2602)

## What Was Achieved

Implemented a full rollback-safe test framework under `AgentTests/` with strict SQL assertions, plus production SQL fixes discovered by those tests.

Delivered:
- `AgentTests/01_full_validations.sql`
- `AgentTests/02_topology_trigger_incremental.sql`
- `AgentTests/03_hierarchy_trigger_incremental.sql`
- `AgentTests/run_agent_tests.sh`
- `Makefile` target: `make test-agent`

All tests run in transactions and end with `ROLLBACK`.

## Why This Was Added

`Main/99test_full_system.sql` is useful but only covers a narrow scenario chain.
The new suite validates all major function/trigger branches and all hierarchy problem types with fail-fast assertions.

## How It Works

## Runner

`AgentTests/run_agent_tests.sh`:
- reads DB credentials from `db_config/config.py`
- exports `PGHOST/PGPORT/PGDATABASE/PGUSER/PGPASSWORD`
- runs each SQL suite with `psql -X -v ON_ERROR_STOP=1 -f ...`
- retries each script up to 3 times for transient network failures

`Makefile`:
- `make test-agent` -> `./AgentTests/run_agent_tests.sh`

## Test Design

Each SQL test script:
- starts with `BEGIN;`
- reloads latest SQL definitions via:
  - `\cd Main`
  - `\i 98load_all_functions.sql`
  - `\cd ..`
- defines `pg_temp.assert_true(...)` helper
- creates isolated random UUID fixtures
- performs assertions after each scenario
- ends with `ROLLBACK;`

## Coverage Matrix

## 1) Full validation functions (`01_full_validations.sql`)

OBM full validators:
- `validate_holes(uuid)` positive case
- `validate_overflows(uuid)` positive case
- `validate_intersections(uuid)` positive case
- `validate_all(uuid)`:
  - normal version
  - sparse version
  - empty version
- `validate_all_topologies()` includes created versions

Hierarchy full validators:
- `validate_cona_hierarchy(uuid)`:
  - `missing_obm_in_cona`
  - `orphan_obm_ref`
  - `orphan_cona_ref`
  - `empty_cona`
  - non-existing model returns zeros
- `validate_lao_hierarchy(uuid)`:
  - `missing_cona_in_lao`
  - `orphan_lao_ref_in_cona`
  - `empty_lao`
- `validate_tao_hierarchy(uuid)`:
  - `missing_lao_in_tao`
  - `orphan_tao_ref_in_lao`
  - `empty_tao`
- wrappers:
  - `validate_all_hierarchy(uuid)`
  - `validate_all_hierarchies()`

## 2) OBM incremental trigger (`02_topology_trigger_incremental.sql`)

`validate_topology_incremental()` coverage:
- DELETE creates hole
- INSERT splits hole into two polygons
- UPDATE fills split holes
- UPDATE creates intersection
- UPDATE removes intersection
- INSERT with overflow geometry clips `NEW.geom` to boundary

## 3) Hierarchy incremental triggers (`03_hierarchy_trigger_incremental.sql`)

`validate_obmxcona_incremental()`:
- DELETE path
- INSERT path
- UPDATE path (source model revalidation verified through `orphan_cona_ref`)

`validate_cona_lao_incremental()`:
- UPDATE `id_rel_geo_lao` to NULL
- DELETE cona
- INSERT cona restoration

`validate_lao_tao_incremental()`:
- UPDATE `id_rel_geo_tao` to NULL
- DELETE lao
- INSERT lao restoration

## Defects Found And Fixed

## Fix 1: `validate_all(uuid)` empty-version return row shape

File:
- `Main/3checkAllTopologies.sql`

Issue:
- Empty-version branch returned wrong column structure/types.

Fix:
- Return now matches declared signature:
  - `p_id_rel_geo_verzija, 0, 0, 0, 0`

## Fix 2: `validate_obmxcona_incremental()` UPDATE scope

File:
- `Main/7triggerHierarchy.sql`

Issue:
- On `UPDATE`, only one model version was revalidated.

Fix:
- Revalidate both model versions when needed:
  - old cona model version
  - new cona model version (if different)

## Safety Guarantees

- No persistent test data: all suites rollback.
- Trigger/function reloads also happen inside transaction and rollback.
- Only rollbackable SQL operations are used.

## Current Usage

From repo root:

```bash
make test-agent
```

This executes all `AgentTests` suites and fails on first assertion or SQL error.

