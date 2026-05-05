






























\pset pager off
\x off

-- Trigger inspection for GeomIntegrity.
--
-- This prints three sections:
--   1. Expected trigger names from this repo.
--   2. Every trigger found on the expected tables.
--   3. Every non-internal trigger whose name or function looks related.
--
-- If section 1 says missing but section 2 or 3 shows similar triggers,
-- the database has different trigger names or table names than this repo.

\echo ''
\echo '================================================================================'
\echo '1) Expected GeomIntegrity triggers by exact trigger name'
\echo '================================================================================'

WITH expected_triggers AS (
    SELECT *
    FROM (VALUES
        ('obm',       'md_geo_obm',       'trg_validate_topology_incremental',  'validate_topology_incremental'),
        ('hierarchy', 'md_geo_obmxcona',  'trg_validate_obmxcona_incremental',  'validate_obmxcona_incremental'),
        ('hierarchy', 'md_geo_cona',      'trg_validate_cona_lao_incremental',  'validate_cona_lao_incremental'),
        ('hierarchy', 'md_geo_lao',       'trg_validate_lao_tao_incremental',   'validate_lao_tao_incremental')
    ) AS t(group_name, expected_table_name, trigger_name, expected_function_name)
),
matches AS (
    SELECT
        e.group_name,
        e.expected_table_name,
        e.trigger_name,
        e.expected_function_name,
        n.nspname AS schema_name,
        c.relname AS actual_table_name,
        c.relkind,
        t.tgenabled,
        p.proname AS actual_function_name
    FROM expected_triggers e
    LEFT JOIN pg_trigger t
        ON t.tgname = e.trigger_name
       AND NOT t.tgisinternal
    LEFT JOIN pg_class c
        ON c.oid = t.tgrelid
    LEFT JOIN pg_namespace n
        ON n.oid = c.relnamespace
    LEFT JOIN pg_proc p
        ON p.oid = t.tgfoid
)
SELECT
    group_name,
    expected_table_name,
    trigger_name,
    expected_function_name,
    CASE
        WHEN actual_table_name IS NULL THEN 'missing'
        WHEN tgenabled = 'D' THEN 'disabled'
        ELSE 'active'
    END AS status,
    COALESCE(schema_name || '.' || actual_table_name, '') AS actual_table,
    COALESCE(actual_function_name, '') AS actual_function,
    CASE tgenabled
        WHEN 'O' THEN 'enabled for origin only'
        WHEN 'D' THEN 'disabled'
        WHEN 'R' THEN 'enabled for replica'
        WHEN 'A' THEN 'always enabled'
        ELSE ''
    END AS enabled_mode,
    COALESCE(relkind::text, '') AS relkind
FROM matches
ORDER BY group_name, expected_table_name, trigger_name, actual_table;

\echo ''
\echo '================================================================================'
\echo '2) All triggers currently present on the expected table names'
\echo '================================================================================'

WITH expected_tables AS (
    SELECT *
    FROM (VALUES
        ('md_geo_obm'),
        ('md_geo_obmxcona'),
        ('md_geo_cona'),
        ('md_geo_lao')
    ) AS t(table_name)
)
SELECT
    n.nspname AS schema_name,
    c.relname AS table_name,
    c.relkind,
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
    END AS enabled_mode
FROM pg_class c
JOIN pg_namespace n
    ON n.oid = c.relnamespace
JOIN expected_tables e
    ON e.table_name = c.relname
LEFT JOIN pg_trigger t
    ON t.tgrelid = c.oid
   AND NOT t.tgisinternal
LEFT JOIN pg_proc p
    ON p.oid = t.tgfoid
ORDER BY n.nspname, c.relname, t.tgname;

\echo ''
\echo '================================================================================'
\echo '3) All validation-looking triggers anywhere in this database'
\echo '================================================================================'

SELECT
    n.nspname AS schema_name,
    c.relname AS table_name,
    c.relkind,
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
    END AS enabled_mode
FROM pg_trigger t
JOIN pg_class c
    ON c.oid = t.tgrelid
JOIN pg_namespace n
    ON n.oid = c.relnamespace
JOIN pg_proc p
    ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal
  AND (
      t.tgname ILIKE '%validate%'
      OR t.tgname ILIKE '%topology%'
      OR t.tgname ILIKE '%hierarchy%'
      OR t.tgname ILIKE '%obm%'
      OR t.tgname ILIKE '%cona%'
      OR t.tgname ILIKE '%lao%'
      OR t.tgname ILIKE '%tao%'
      OR p.proname ILIKE '%validate%'
      OR p.proname ILIKE '%topology%'
      OR p.proname ILIKE '%hierarchy%'
      OR p.proname ILIKE '%obm%'
      OR p.proname ILIKE '%cona%'
      OR p.proname ILIKE '%lao%'
      OR p.proname ILIKE '%tao%'
  )
ORDER BY n.nspname, c.relname, t.tgname;

