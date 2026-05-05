\pset pager off
\x off

-- ============================================================================
-- repo_trigger_status.sql
-- ============================================================================
-- Lists trigger names referenced by this repo and shows whether each one exists
-- in the connected database, and whether it is enabled or disabled.
--
-- Run:
--   psql "$DATABASE_URL" -f repo_trigger_status.sql
--
-- Important:
--   This matches by trigger name only. It does not assume a schema/table name,
--   because copied databases can place the same trigger on a different schema.
-- ============================================================================

\echo ''
\echo '================================================================================'
\echo '0) Connected database'
\echo '================================================================================'

SELECT
    current_database() AS database_name,
    current_schema() AS current_schema,
    current_user AS current_user,
    inet_server_addr() AS server_addr,
    inet_server_port() AS server_port;

\echo ''
\echo '================================================================================'
\echo '1) Repo trigger names: installed and enabled status'
\echo '================================================================================'

WITH repo_trigger_names AS (
    SELECT *
    FROM (VALUES
        ('main/current', 'obm topology',   'trg_validate_topology_incremental'),
        ('main/current', 'hierarchy',      'trg_validate_obmxcona_incremental'),
        ('main/current', 'hierarchy',      'trg_validate_cona_lao_incremental'),
        ('main/current', 'hierarchy',      'trg_validate_lao_tao_incremental'),
        ('legacy/old',   'obm topology',   'trg_validate_topology'),
        ('legacy/old',   'obm topology',   'trg_validate_areas')
    ) AS t(source_group, trigger_area, trigger_name)
),
installed AS (
    SELECT
        t.tgname AS trigger_name,
        n.nspname AS schema_name,
        c.relname AS table_name,
        c.relkind AS table_kind,
        p.proname AS trigger_function,
        t.tgenabled,
        pg_get_triggerdef(t.oid, true) AS trigger_definition
    FROM pg_trigger t
    JOIN pg_class c
        ON c.oid = t.tgrelid
    JOIN pg_namespace n
        ON n.oid = c.relnamespace
    JOIN pg_proc p
        ON p.oid = t.tgfoid
    WHERE NOT t.tgisinternal
)
SELECT
    r.source_group,
    r.trigger_area,
    r.trigger_name AS repo_trigger_name,
    CASE
        WHEN i.trigger_name IS NULL THEN 'missing'
        WHEN i.tgenabled = 'D' THEN 'disabled'
        ELSE 'active'
    END AS status,
    COALESCE(i.schema_name || '.' || i.table_name, '') AS actual_table,
    COALESCE(i.trigger_function, '') AS trigger_function,
    CASE i.tgenabled
        WHEN 'O' THEN 'enabled for origin only'
        WHEN 'D' THEN 'disabled'
        WHEN 'R' THEN 'enabled for replica'
        WHEN 'A' THEN 'always enabled'
        ELSE ''
    END AS enabled_mode,
    COALESCE(i.table_kind::text, '') AS table_kind,
    COALESCE(i.trigger_definition, '') AS trigger_definition
FROM repo_trigger_names r
LEFT JOIN installed i
    ON i.trigger_name = r.trigger_name
ORDER BY
    r.source_group,
    r.trigger_area,
    r.trigger_name,
    actual_table;

\echo ''
\echo '================================================================================'
\echo '2) Summary counts for repo trigger names'
\echo '================================================================================'

WITH repo_trigger_names AS (
    SELECT *
    FROM (VALUES
        ('main/current', 'obm topology',   'trg_validate_topology_incremental'),
        ('main/current', 'hierarchy',      'trg_validate_obmxcona_incremental'),
        ('main/current', 'hierarchy',      'trg_validate_cona_lao_incremental'),
        ('main/current', 'hierarchy',      'trg_validate_lao_tao_incremental'),
        ('legacy/old',   'obm topology',   'trg_validate_topology'),
        ('legacy/old',   'obm topology',   'trg_validate_areas')
    ) AS t(source_group, trigger_area, trigger_name)
),
matches AS (
    SELECT
        r.source_group,
        r.trigger_area,
        r.trigger_name,
        t.tgenabled
    FROM repo_trigger_names r
    LEFT JOIN pg_trigger t
        ON t.tgname = r.trigger_name
       AND NOT t.tgisinternal
)
SELECT
    source_group,
    trigger_area,
    count(*) FILTER (WHERE tgenabled IS NULL) AS missing,
    count(*) FILTER (WHERE tgenabled = 'D') AS disabled,
    count(*) FILTER (WHERE tgenabled IS NOT NULL AND tgenabled <> 'D') AS active
FROM matches
GROUP BY source_group, trigger_area
ORDER BY source_group, trigger_area;

\echo ''
\echo '================================================================================'
\echo '3) All non-internal triggers currently installed in this database'
\echo '================================================================================'

SELECT
    n.nspname AS schema_name,
    c.relname AS table_name,
    c.relkind AS table_kind,
    t.tgname AS trigger_name,
    p.proname AS trigger_function,
    CASE
        WHEN t.tgenabled = 'D' THEN 'disabled'
        ELSE 'active'
    END AS status,
    CASE t.tgenabled
        WHEN 'O' THEN 'enabled for origin only'
        WHEN 'D' THEN 'disabled'
        WHEN 'R' THEN 'enabled for replica'
        WHEN 'A' THEN 'always enabled'
        ELSE ''
    END AS enabled_mode,
    pg_get_triggerdef(t.oid, true) AS trigger_definition
FROM pg_trigger t
JOIN pg_class c
    ON c.oid = t.tgrelid
JOIN pg_namespace n
    ON n.oid = c.relnamespace
JOIN pg_proc p
    ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal
ORDER BY n.nspname, c.relname, t.tgname;

