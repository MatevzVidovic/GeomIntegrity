-- ============================================================================
-- 00a_rename_columns_to_slovene.sql - Rename columns to Slovene
-- ============================================================================
-- This script renames all English column names to Slovene in the topology
-- control tables.
--
-- Run this AFTER creating the tables but BEFORE loading any validation
-- functions or triggers.
--
-- IMPORTANT: After running this, you must update all function/trigger files
-- to use the new Slovene column names.
-- ============================================================================

\echo 'Renaming columns in md_topoloske_kontrole_obm to Slovene...'

-- Rename columns in OBM topology controls table
DO $$
BEGIN
    -- topology_problem_type -> tip_topoloskega_problema
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'md_topoloske_kontrole_obm'
               AND column_name = 'topology_problem_type') THEN
        ALTER TABLE md_topoloske_kontrole_obm
        RENAME COLUMN topology_problem_type TO tip_topoloskega_problema;
        RAISE NOTICE 'Renamed topology_problem_type -> tip_topoloskega_problema';
    END IF;

    -- id1 -> id_prvega_obm
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'md_topoloske_kontrole_obm'
               AND column_name = 'id1') THEN
        ALTER TABLE md_topoloske_kontrole_obm
        RENAME COLUMN id1 TO id_prvega_obm;
        RAISE NOTICE 'Renamed id1 -> id_prvega_obm';
    END IF;

    -- id2 -> id_drugega_obm
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'md_topoloske_kontrole_obm'
               AND column_name = 'id2') THEN
        ALTER TABLE md_topoloske_kontrole_obm
        RENAME COLUMN id2 TO id_drugega_obm;
        RAISE NOTICE 'Renamed id2 -> id_drugega_obm';
    END IF;

    -- area -> povrsina
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'md_topoloske_kontrole_obm'
               AND column_name = 'area') THEN
        ALTER TABLE md_topoloske_kontrole_obm
        RENAME COLUMN area TO povrsina;
        RAISE NOTICE 'Renamed area -> povrsina';
    END IF;

    -- perimeter -> obseg
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'md_topoloske_kontrole_obm'
               AND column_name = 'perimeter') THEN
        ALTER TABLE md_topoloske_kontrole_obm
        RENAME COLUMN perimeter TO obseg;
        RAISE NOTICE 'Renamed perimeter -> obseg';
    END IF;

    -- compactness -> kompaktnost
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'md_topoloske_kontrole_obm'
               AND column_name = 'compactness') THEN
        ALTER TABLE md_topoloske_kontrole_obm
        RENAME COLUMN compactness TO kompaktnost;
        RAISE NOTICE 'Renamed compactness -> kompaktnost';
    END IF;
END $$;

\echo ''
\echo 'Renaming columns in md_topoloske_kontrole_hierarhija to Slovene...'

-- Rename columns in hierarchy controls table
DO $$
BEGIN
    -- entity_type -> tip_entitete
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'md_topoloske_kontrole_hierarhija'
               AND column_name = 'entity_type') THEN
        ALTER TABLE md_topoloske_kontrole_hierarhija
        RENAME COLUMN entity_type TO tip_entitete;
        RAISE NOTICE 'Renamed entity_type -> tip_entitete';
    END IF;

    -- problem_type -> tip_problema
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'md_topoloske_kontrole_hierarhija'
               AND column_name = 'problem_type') THEN
        ALTER TABLE md_topoloske_kontrole_hierarhija
        RENAME COLUMN problem_type TO tip_problema;
        RAISE NOTICE 'Renamed problem_type -> tip_problema';
    END IF;

    -- entity_id -> id_entitete
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'md_topoloske_kontrole_hierarhija'
               AND column_name = 'entity_id') THEN
        ALTER TABLE md_topoloske_kontrole_hierarhija
        RENAME COLUMN entity_id TO id_entitete;
        RAISE NOTICE 'Renamed entity_id -> id_entitete';
    END IF;

    -- reference_id -> id_referenca
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'md_topoloske_kontrole_hierarhija'
               AND column_name = 'reference_id') THEN
        ALTER TABLE md_topoloske_kontrole_hierarhija
        RENAME COLUMN reference_id TO id_referenca;
        RAISE NOTICE 'Renamed reference_id -> id_referenca';
    END IF;

    -- details -> podrobnosti
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'md_topoloske_kontrole_hierarhija'
               AND column_name = 'details') THEN
        ALTER TABLE md_topoloske_kontrole_hierarhija
        RENAME COLUMN details TO podrobnosti;
        RAISE NOTICE 'Renamed details -> podrobnosti';
    END IF;
END $$;

\echo ''
\echo '✓ Column renaming complete!'
\echo ''
\echo 'IMPORTANT: You must now update constraint names!'
\echo 'Run the following to update constraints:'
\echo ''
\echo '-- Update OBM constraints'
\echo 'ALTER TABLE md_topoloske_kontrole_obm DROP CONSTRAINT IF EXISTS check_topology_problem_type_obm;'
\echo 'ALTER TABLE md_topoloske_kontrole_obm ADD CONSTRAINT check_tip_topoloskega_problema_obm'
\echo '    CHECK (tip_topoloskega_problema IN (''intersection'', ''hole'', ''overflow''));'
\echo ''
\echo 'ALTER TABLE md_topoloske_kontrole_obm DROP CONSTRAINT IF EXISTS check_id1_less_than_id2_obm;'
\echo 'ALTER TABLE md_topoloske_kontrole_obm ADD CONSTRAINT check_id_prvega_less_than_drugega_obm'
\echo '    CHECK (id_drugega_obm IS NULL OR (id_prvega_obm IS NOT NULL AND id_prvega_obm < id_drugega_obm));'
\echo ''
\echo '-- Update hierarchy constraints'
\echo 'ALTER TABLE md_topoloske_kontrole_hierarhija DROP CONSTRAINT IF EXISTS check_entity_type_hierarhija;'
\echo 'ALTER TABLE md_topoloske_kontrole_hierarhija ADD CONSTRAINT check_tip_entitete_hierarhija'
\echo '    CHECK (tip_entitete IN (''cona'', ''lao'', ''tao''));'
\echo ''
\echo 'ALTER TABLE md_topoloske_kontrole_hierarhija DROP CONSTRAINT IF EXISTS check_problem_type_hierarhija;'
\echo 'ALTER TABLE md_topoloske_kontrole_hierarhija ADD CONSTRAINT check_tip_problema_hierarhija'
\echo '    CHECK (tip_problema IN ('
\echo '        ''missing_obm_in_cona'', ''orphan_obm_ref'', ''orphan_cona_ref'', ''empty_cona'','
\echo '        ''missing_cona_in_lao'', ''orphan_lao_ref_in_cona'', ''empty_lao'','
\echo '        ''missing_lao_in_tao'', ''orphan_tao_ref_in_lao'', ''empty_tao'''
\echo '    ));'
\echo ''
