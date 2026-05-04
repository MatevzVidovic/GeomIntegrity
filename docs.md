# Hierarchy Triggers

This is the shortest useful map of how the hierarchy validation chain works and where the deadlock came from.

## 1) Normal incremental path

```mermaid
flowchart TD
    A["md_geo_obmxcona row change"] --> B["trg_validate_obmxcona_incremental"]
    B --> C["validate_obmxcona_incremental"]
    C --> D["find affected model version(s)"]
    D --> E["validate_all_hierarchy"]
    E --> F["validate_cona_hierarchy"]
    E --> G["validate_lao_hierarchy"]
    E --> H["validate_tao_hierarchy"]
    F --> I["md_topoloske_kontrole_hierarhija"]
    G --> I
    H --> I
```

- `trg_validate_obmxcona_incremental` is the row trigger on `md_geo_obmxcona`.
- `validate_obmxcona_incremental()` is the trigger function.
- It decides which model version is affected, then calls `validate_all_hierarchy(uuid)`.
- The validation functions write problem rows into `md_topoloske_kontrole_hierarhija`.

## 2) What used to happen

```mermaid
flowchart TD
    A["md_geo_obmxcona row change"] --> B["trg_validate_obmxcona_incremental"]
    B --> C["validate_obmxcona_incremental"]
    C --> D["validate_all_hierarchy"]
    D --> E["DROP TRIGGER on md_geo_obmxcona"]
    D --> F["run validation queries"]
    D --> G["CREATE TRIGGER on md_geo_obmxcona"]
```

- The problem was not the row trigger itself.
- The problem was `validate_all_hierarchy(uuid)` doing `DROP TRIGGER` and `CREATE TRIGGER` inside a trigger-driven update.
- That is DDL inside normal DML, which is where the lock conflict came from.

## 3) Bulk path

```mermaid
flowchart TD
    A["validate_all_hierarchies"] --> B["drop incremental triggers once"]
    B --> C["loop all model versions"]
    C --> D["validate_all_hierarchy"]
    D --> E["validation only"]
    C --> F["recreate incremental triggers once"]
```

- `validate_all_hierarchies()` is the explicit bulk wrapper.
- This is the only place where trigger suppression makes sense.
- `validate_all_hierarchy(uuid)` now stays pure and does not manage triggers.

## 4) Why it deadlocked

```mermaid
sequenceDiagram
    participant U1 as Session A
    participant U2 as Session B
    participant DB as PostgreSQL

    U1->>DB: UPDATE md_geo_obmxcona
    DB->>DB: fire trg_validate_obmxcona_incremental
    DB->>DB: call validate_obmxcona_incremental
    DB->>DB: call validate_all_hierarchy
    DB->>DB: try DROP TRIGGER

    U2->>DB: UPDATE md_geo_obmxcona
    DB->>DB: fire trg_validate_obmxcona_incremental
    DB->>DB: call validate_obmxcona_incremental
    DB->>DB: call validate_all_hierarchy
    DB->>DB: try DROP TRIGGER
```

- Each session was holding row-update locks and then asking for stronger trigger DDL locks.
- Two sessions doing that in different order can deadlock.
- The fix was to remove trigger DDL from `validate_all_hierarchy(uuid)`.

## 5) Mental model

- Incremental trigger: keep hierarchy status current after one row change.
- Bulk wrapper: temporarily disable triggers while validating everything.
- Validation function: compute problems only, no trigger DDL.
