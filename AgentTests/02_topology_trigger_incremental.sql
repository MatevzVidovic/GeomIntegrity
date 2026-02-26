\set ON_ERROR_STOP on
\timing on

\echo ''
\echo '======================================================================'
\echo 'AgentTests 02 - Topology Incremental Trigger (rollback-safe)'
\echo '======================================================================'

BEGIN;
SET LOCAL client_min_messages TO WARNING;
\cd Main
\i 98load_all_functions.sql
\cd ..

CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_condition boolean, p_message text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT COALESCE(p_condition, false) THEN
        RAISE EXCEPTION 'ASSERTION FAILED: %', p_message;
    END IF;
END;
$$;

CREATE TEMP TABLE agent_ids (
    key text PRIMARY KEY,
    value uuid NOT NULL
);

INSERT INTO agent_ids (key, value)
VALUES
    ('version', uuid_generate_v4()),
    ('model', uuid_generate_v4()),
    ('obm_out', uuid_generate_v4());

INSERT INTO agent_ids (key, value)
SELECT 'obm' || gs::text, uuid_generate_v4()
FROM generate_series(1, 9) AS gs;

TRUNCATE TABLE slo_meja;
INSERT INTO slo_meja (id, created_at, created_by, geom)
VALUES (
    uuid_generate_v4(),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    ST_GeomFromText('POLYGON((0 0, 3 0, 3 3, 0 3, 0 0))', 3794)
);

DROP TRIGGER IF EXISTS trg_validate_topology_incremental ON md_geo_obm;

INSERT INTO md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
VALUES (
    (SELECT value FROM agent_ids WHERE key='version'),
    '00000000-0000-0000-0000-000000000000'::uuid,
    now()::timestamp,
    99101,
    false,
    'AGENT_TEST',
    false
);

INSERT INTO md_verzije_modeli (id, created_by, created_at, id_rel_geo_verzija, model, verzija)
VALUES (
    (SELECT value FROM agent_ids WHERE key='model'),
    '00000000-0000-0000-0000-000000000000'::uuid,
    now()::timestamp,
    (SELECT value FROM agent_ids WHERE key='version'),
    'AGENT_TEST',
    201
);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES
    ((SELECT value FROM agent_ids WHERE key='obm1'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version'), 'T_OBM_1', ST_GeomFromText('POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm2'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version'), 'T_OBM_2', ST_GeomFromText('POLYGON((1 0, 2 0, 2 1, 1 1, 1 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm3'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version'), 'T_OBM_3', ST_GeomFromText('POLYGON((2 0, 3 0, 3 1, 2 1, 2 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm4'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version'), 'T_OBM_4', ST_GeomFromText('POLYGON((0 1, 1 1, 1 2, 0 2, 0 1))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm5'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version'), 'T_OBM_5', ST_GeomFromText('POLYGON((1 1, 2 1, 2 2, 1 2, 1 1))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm6'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version'), 'T_OBM_6', ST_GeomFromText('POLYGON((2 1, 3 1, 3 2, 2 2, 2 1))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm7'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version'), 'T_OBM_7', ST_GeomFromText('POLYGON((0 2, 1 2, 1 3, 0 3, 0 2))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm8'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version'), 'T_OBM_8', ST_GeomFromText('POLYGON((1 2, 2 2, 2 3, 1 3, 1 2))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm9'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version'), 'T_OBM_9', ST_GeomFromText('POLYGON((2 2, 3 2, 3 3, 2 3, 2 2))', 3794));

SELECT * FROM validate_all((SELECT value FROM agent_ids WHERE key='version'));

\i Main/5trigger.sql

\echo 'Case: DELETE creates one hole'
DELETE FROM md_geo_obm WHERE id = (SELECT value FROM agent_ids WHERE key='obm5');
SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*)
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='version')
          AND tip_topoloskega_problema = 'luknja'
    ) = 1,
    'Deleting center obm should create exactly one hole'
);

\echo 'Case: INSERT splits a hole into two'
INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES (
    (SELECT value FROM agent_ids WHERE key='obm5'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='version'),
    'T_OBM_5_STRIP',
    ST_GeomFromText('POLYGON((1.45 1, 1.55 1, 1.55 2, 1.45 2, 1.45 1))', 3794)
);

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*)
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='version')
          AND tip_topoloskega_problema = 'luknja'
    ) = 2,
    'Inserting a strip through the hole should split it into two holes'
);

\echo 'Case: UPDATE fills split holes'
UPDATE md_geo_obm
SET geom = ST_GeomFromText('POLYGON((1 1, 2 1, 2 2, 1 2, 1 1))', 3794)
WHERE id = (SELECT value FROM agent_ids WHERE key='obm5');

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*)
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='version')
          AND tip_topoloskega_problema = 'luknja'
    ) = 0,
    'Updating obm5 back to full square should remove all holes'
);

\echo 'Case: UPDATE creates and removes intersection incrementally'
UPDATE md_geo_obm
SET geom = ST_GeomFromText('POLYGON((1 0, 2 0, 2 1.5, 1 1.5, 1 0))', 3794)
WHERE id = (SELECT value FROM agent_ids WHERE key='obm2');

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*)
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='version')
          AND tip_topoloskega_problema = 'prekrivanje'
    ) = 1,
    'Expanding obm2 should create one intersection record'
);

UPDATE md_geo_obm
SET geom = ST_GeomFromText('POLYGON((1 0, 2 0, 2 1, 1 1, 1 0))', 3794)
WHERE id = (SELECT value FROM agent_ids WHERE key='obm2');

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*)
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='version')
          AND tip_topoloskega_problema = 'prekrivanje'
    ) = 0,
    'Restoring obm2 should remove intersection record'
);

\echo 'Case: INSERT outside boundary clips NEW.geom'
INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES (
    (SELECT value FROM agent_ids WHERE key='obm_out'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='version'),
    'T_OBM_OUT',
    ST_GeomFromText('POLYGON((2.5 2.5, 3.5 2.5, 3.5 3.5, 2.5 3.5, 2.5 2.5))', 3794)
);

SELECT pg_temp.assert_true(
    (
        SELECT ST_CoveredBy(o.geom, s.geom)
        FROM md_geo_obm o
        CROSS JOIN slo_meja s
        WHERE o.id = (SELECT value FROM agent_ids WHERE key='obm_out')
        LIMIT 1
    ),
    'Trigger should clip inserted geometry to slo_meja boundary'
);

SELECT pg_temp.assert_true(
    (
        SELECT abs(ST_Area(geom) - 0.25) < 1e-6
        FROM md_geo_obm
        WHERE id = (SELECT value FROM agent_ids WHERE key='obm_out')
    ),
    'Clipped geometry area should be 0.25 square units'
);

\echo 'All assertions passed for AgentTests 02'
ROLLBACK;

\echo 'AgentTests 02 complete (rollback executed)'
