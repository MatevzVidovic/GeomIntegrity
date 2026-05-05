# Hierarchy Trigger Map

This explains what calls what in the hierarchy validation system.

The hierarchy is:

```mermaid
flowchart TD
    OBM["md_geo_obm"]
    XCO["md_geo_obmxcona"]
    CONA["md_geo_cona"]
    LAO["md_geo_lao"]
    TAO["md_geo_tao"]

    OBM --> XCO
    XCO --> CONA
    CONA --> LAO
    LAO --> TAO
```

Validation results go into `md_topoloske_kontrole_hierarhija`.

## Main Pieces

```mermaid
flowchart TD
    T1["trg_validate_obmxcona_incremental"]
    T2["trg_validate_cona_lao_incremental"]
    T3["trg_validate_lao_tao_incremental"]

    F1["validate_obmxcona_incremental"]
    F2["validate_cona_lao_incremental"]
    F3["validate_lao_tao_incremental"]

    ALL["validate_all_hierarchy"]
    CONA["validate_cona_hierarchy"]
    LAO["validate_lao_hierarchy"]
    TAO["validate_tao_hierarchy"]
    OUT["md_topoloske_kontrole_hierarhija"]

    T1 --> F1
    T2 --> F2
    T3 --> F3

    F1 --> ALL
    F2 --> ALL
    F3 --> ALL

    ALL --> CONA
    ALL --> LAO
    ALL --> TAO

    CONA --> OUT
    LAO --> OUT
    TAO --> OUT
```

Short version:

- Row triggers only decide when validation should run.
- Incremental trigger functions find the affected model version.
- `validate_all_hierarchy` runs all checks for one model version.
- The three lower validation functions delete and rewrite problem rows.

## Obm To Cona Changes

This path runs when `md_geo_obmxcona` changes.

```mermaid
flowchart TD
    A["INSERT UPDATE DELETE on md_geo_obmxcona"]
    B["trg_validate_obmxcona_incremental"]
    C["validate_obmxcona_incremental"]
    D["read old cona model version"]
    E["read new cona model version"]
    F["validate_all_hierarchy for old version"]
    G["validate_all_hierarchy for new version when different"]

    A --> B
    B --> C
    C --> D
    C --> E
    D --> F
    E --> G
```

Why it needs a lookup:

- `md_geo_obmxcona` has `id_rel_geo_cona`.
- The model version lives on `md_geo_cona.id_rel_verzije_modeli`.
- So this trigger function joins through `md_geo_cona`.

## Cona To Lao Changes

This path runs when a cona is added, deleted, or moved to another LAO.

```mermaid
flowchart TD
    A["INSERT DELETE or id_rel_geo_lao UPDATE on md_geo_cona"]
    B["trg_validate_cona_lao_incremental"]
    C["validate_cona_lao_incremental"]
    D["use md_geo_cona.id_rel_verzije_modeli"]
    E["validate_all_hierarchy"]

    A --> B
    B --> C
    C --> D
    D --> E
```

Why it is simpler:

- `md_geo_cona` already has `id_rel_verzije_modeli`.
- No join is needed to find the affected model version.

## Lao To Tao Changes

This path runs when a LAO is added, deleted, or moved to another TAO.

```mermaid
flowchart TD
    A["INSERT DELETE or id_rel_geo_tao UPDATE on md_geo_lao"]
    B["trg_validate_lao_tao_incremental"]
    C["validate_lao_tao_incremental"]
    D["use md_geo_lao.id_rel_verzije_modeli"]
    E["validate_all_hierarchy"]

    A --> B
    B --> C
    C --> D
    D --> E
```

Why it is simpler:

- `md_geo_lao` already has `id_rel_verzije_modeli`.
- No join is needed to find the affected model version.

## One Model Version Validation

`validate_all_hierarchy` validates one `id_rel_verzije_modeli`.

```mermaid
flowchart TD
    A["validate_all_hierarchy"]
    B["validate_cona_hierarchy"]
    C["validate_lao_hierarchy"]
    D["validate_tao_hierarchy"]
    OUT["md_topoloske_kontrole_hierarhija"]

    A --> B
    A --> C
    A --> D
    B --> OUT
    C --> OUT
    D --> OUT
```

What each function checks:

- `validate_cona_hierarchy`: OBMs missing conas, bad OBM references, bad cona references, empty conas.
- `validate_lao_hierarchy`: conas missing LAO, bad LAO references, empty LAOs.
- `validate_tao_hierarchy`: LAOs missing TAO, bad TAO references, empty TAOs.

Each lower function first clears its own old problem rows for that model version, then inserts the current problems.

## Full Bulk Validation

`validate_all_hierarchies` validates every model version.

```mermaid
flowchart TD
    A["validate_all_hierarchies"]
    B["remember which incremental triggers exist"]
    C["drop incremental triggers once"]
    D["loop md_verzije_modeli"]
    E["validate_all_hierarchy for each model version"]
    F["recreate triggers that existed before"]

    A --> B
    B --> C
    C --> D
    D --> E
    E --> D
    D --> F
```

This is the only hierarchy validation function that should do trigger DDL.

Reason:

- Bulk validation deliberately touches many model versions.
- Dropping triggers once avoids repeated incremental revalidation during a full rebuild.
- The single-version function must stay normal DML only, because row triggers call it.

## Current Rule

```mermaid
flowchart TD
    A["row trigger path"]
    B["validate_all_hierarchy"]
    C["validation only"]
    D["bulk path"]
    E["validate_all_hierarchies"]
    F["may drop and recreate triggers"]

    A --> B
    B --> C
    D --> E
    E --> F
```

Keep this split:

- Incremental path: trigger function calls `validate_all_hierarchy`.
- Single-version validation: no `DROP TRIGGER`, no `CREATE TRIGGER`.
- Bulk validation: `validate_all_hierarchies` may manage triggers around the full loop.

