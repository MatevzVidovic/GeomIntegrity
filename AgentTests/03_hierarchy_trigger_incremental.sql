\set ON_ERROR_STOP on
\timing on
\pset pager off

\echo ''
\echo '======================================================================'
\echo 'AgentTests 03 - Hierarchy Incremental Triggers (rollback-safe)'
\echo '======================================================================'

BEGIN;
SET LOCAL client_min_messages TO WARNING;
\cd Main
\i /Users/matevzvidovic/GeomIntegrity/Main/8_1_load_fns_and_triggers.sql
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

DROP TRIGGER IF EXISTS trg_validate_topology_incremental ON md_geo_obm;

CREATE TEMP TABLE agent_ids (
    key text PRIMARY KEY,
    value uuid NOT NULL
);

INSERT INTO agent_ids (key, value)
VALUES
    ('version1', uuid_generate_v4()),
    ('version2', uuid_generate_v4()),
    ('model1', uuid_generate_v4()),
    ('model2', uuid_generate_v4()),
    ('tao1', uuid_generate_v4()),
    ('tao2', uuid_generate_v4()),
    ('lao1', uuid_generate_v4()),
    ('lao2', uuid_generate_v4()),
    ('cona1', uuid_generate_v4()),
    ('cona2', uuid_generate_v4()),
    ('fake_cona', uuid_generate_v4()),
    ('obm1', uuid_generate_v4()),
    ('obm2', uuid_generate_v4()),
    ('obm3', uuid_generate_v4());

TRUNCATE TABLE slo_meja;
INSERT INTO slo_meja (id, created_at, created_by, geom)
VALUES (
    uuid_generate_v4(),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    ST_GeomFromText('POLYGON((0 0, 10 0, 10 10, 0 10, 0 0))', 3794)
);

INSERT INTO md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
VALUES
    ((SELECT value FROM agent_ids WHERE key='version1'), '00000000-0000-0000-0000-000000000000'::uuid, now()::timestamp, 99201, false, 'AGENT_TEST', false),
    ((SELECT value FROM agent_ids WHERE key='version2'), '00000000-0000-0000-0000-000000000000'::uuid, now()::timestamp, 99202, false, 'AGENT_TEST', false);

INSERT INTO md_verzije_modeli (id, created_by, created_at, id_rel_geo_verzija, model, verzija)
VALUES
    ((SELECT value FROM agent_ids WHERE key='model1'), '00000000-0000-0000-0000-000000000000'::uuid, now()::timestamp, (SELECT value FROM agent_ids WHERE key='version1'), 'AGENT_TEST', 301),
    ((SELECT value FROM agent_ids WHERE key='model2'), '00000000-0000-0000-0000-000000000000'::uuid, now()::timestamp, (SELECT value FROM agent_ids WHERE key='version2'), 'AGENT_TEST', 302);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES
    ((SELECT value FROM agent_ids WHERE key='obm1'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version1'), 'H_OBM_1', ST_GeomFromText('POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm2'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version1'), 'H_OBM_2', ST_GeomFromText('POLYGON((1 0, 2 0, 2 1, 1 1, 1 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm3'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version2'), 'H_OBM_3', ST_GeomFromText('POLYGON((5 5, 6 5, 6 6, 5 6, 5 5))', 3794));

INSERT INTO md_geo_tao (id, created_at, created_by, id_rel_verzije_modeli, id_tao, drugi_tao)
VALUES
    ((SELECT value FROM agent_ids WHERE key='tao1'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='model1'), 1, false),
    ((SELECT value FROM agent_ids WHERE key='tao2'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='model2'), 2, false);

INSERT INTO md_geo_lao (id, created_at, created_by, id_rel_geo_tao, id_rel_verzije_modeli, id_lao, ime_lao, drugi_lao)
VALUES
    ((SELECT value FROM agent_ids WHERE key='lao1'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='tao1'), (SELECT value FROM agent_ids WHERE key='model1'), 1, 'H_LAO_1', false),
    ((SELECT value FROM agent_ids WHERE key='lao2'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='tao2'), (SELECT value FROM agent_ids WHERE key='model2'), 2, 'H_LAO_2', false);

INSERT INTO md_geo_cona (id, created_at, created_by, id_rel_geo_lao, id_rel_verzije_modeli, ime_cone)
VALUES
    ((SELECT value FROM agent_ids WHERE key='cona1'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='lao1'), (SELECT value FROM agent_ids WHERE key='model1'), 'H_CONA_1'),
    ((SELECT value FROM agent_ids WHERE key='cona2'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='lao2'), (SELECT value FROM agent_ids WHERE key='model2'), 'H_CONA_2');

INSERT INTO md_geo_obmxcona (id, created_at, created_by, id_rel_geo_obm, id_rel_geo_cona)
VALUES
    (uuid_generate_v4(), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='obm1'), (SELECT value FROM agent_ids WHERE key='cona1')),
    (uuid_generate_v4(), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='obm2'), (SELECT value FROM agent_ids WHERE key='cona1')),
    (uuid_generate_v4(), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='obm3'), (SELECT value FROM agent_ids WHERE key='cona2'));

\i /Users/matevzvidovic/GeomIntegrity/Main/4_1_trg_hierarchy_triggers.sql

SELECT * FROM validate_all_hierarchy((SELECT value FROM agent_ids WHERE key='model1'));
SELECT * FROM validate_all_hierarchy((SELECT value FROM agent_ids WHERE key='model2'));

\echo 'Case: obmxcona DELETE and INSERT trigger'
DELETE FROM md_geo_obmxcona
WHERE id_rel_geo_obm = (SELECT value FROM agent_ids WHERE key='obm2')
  AND id_rel_geo_cona = (SELECT value FROM agent_ids WHERE key='cona1');

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model1')
          AND tip_problema = 'obm. v nobeni coni'
          AND problematicen_id = (SELECT value FROM agent_ids WHERE key='obm2')
    ),
    'DELETE on obmxcona should create obm. v nobeni coni via incremental trigger'
);

INSERT INTO md_geo_obmxcona (id, created_at, created_by, id_rel_geo_obm, id_rel_geo_cona)
VALUES (
    uuid_generate_v4(),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='obm2'),
    (SELECT value FROM agent_ids WHERE key='cona1')
);

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*) FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model1')
          AND tip_problema = 'obm. v nobeni coni'
    ) = 0,
    'INSERT on obmxcona should clear obm. v nobeni coni after restoration'
);

\echo 'Case: obmxcona UPDATE to non-existent cona revalidates source model'
UPDATE md_geo_obmxcona
SET id_rel_geo_cona = (SELECT value FROM agent_ids WHERE key='fake_cona')
WHERE id_rel_geo_obm = (SELECT value FROM agent_ids WHERE key='obm1')
  AND id_rel_geo_cona = (SELECT value FROM agent_ids WHERE key='cona1');

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM md_topoloske_kontrole_hierarhija h
        JOIN md_geo_obmxcona xc ON xc.id = h.problematicen_id
        WHERE h.id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model1')
          AND h.tip_problema = 'cona ne obstaja'
          AND xc.id_rel_geo_obm = (SELECT value FROM agent_ids WHERE key='obm1')
          AND xc.id_rel_geo_cona = (SELECT value FROM agent_ids WHERE key='fake_cona')
    ),
    'UPDATE obmxcona to missing cona: problematicen_id should be the broken obmxcona row'
);

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*) FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model2')
          AND tip_problema IN ('obm. v nobeni coni', 'napačno obm.', 'cona ne obstaja')
    ) = 0,
    'UPDATE obmxcona to missing cona should not introduce destination-model problems'
);

UPDATE md_geo_obmxcona
SET id_rel_geo_cona = (SELECT value FROM agent_ids WHERE key='cona1')
WHERE id_rel_geo_obm = (SELECT value FROM agent_ids WHERE key='obm1')
  AND id_rel_geo_cona = (SELECT value FROM agent_ids WHERE key='fake_cona');

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*) FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli IN (
            (SELECT value FROM agent_ids WHERE key='model1'),
            (SELECT value FROM agent_ids WHERE key='model2')
        )
          AND tip_problema IN ('cona ne obstaja', 'napačno obm.', 'obm. v nobeni coni')
    ) = 0,
    'Restoring obmxcona link should clear cona issues caused by update'
);

\echo 'Case: cona trigger UPDATE/DELETE/INSERT'
UPDATE md_geo_cona
SET id_rel_geo_lao = NULL
WHERE id = (SELECT value FROM agent_ids WHERE key='cona1');

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model1')
          AND tip_problema = 'cona v nobenem LAO'
          AND problematicen_id = (SELECT value FROM agent_ids WHERE key='cona1')
    ),
    'UPDATE cona.id_rel_geo_lao to NULL should create cona v nobenem LAO'
);

UPDATE md_geo_cona
SET id_rel_geo_lao = (SELECT value FROM agent_ids WHERE key='lao1')
WHERE id = (SELECT value FROM agent_ids WHERE key='cona1');

DELETE FROM md_geo_cona
WHERE id = (SELECT value FROM agent_ids WHERE key='cona1');

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model1')
          AND tip_problema = 'LAO brez cone'
          AND problematicen_id = (SELECT value FROM agent_ids WHERE key='lao1')
    ),
    'DELETE cona should make lao1 empty'
);

INSERT INTO md_geo_cona (id, created_at, created_by, id_rel_geo_lao, id_rel_verzije_modeli, ime_cone)
VALUES (
    (SELECT value FROM agent_ids WHERE key='cona1'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='lao1'),
    (SELECT value FROM agent_ids WHERE key='model1'),
    'H_CONA_1'
);

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*) FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model1')
          AND tip_problema IN ('LAO brez cone', 'cona ne obstaja')
    ) = 0,
    'INSERT cona back should clear LAO brez cone and cona ne obstaja'
);

\echo 'Case: lao trigger UPDATE/DELETE/INSERT'
UPDATE md_geo_lao
SET id_rel_geo_tao = NULL
WHERE id = (SELECT value FROM agent_ids WHERE key='lao1');

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model1')
          AND tip_problema = 'LAO v nobenem TAO'
          AND problematicen_id = (SELECT value FROM agent_ids WHERE key='lao1')
    ),
    'UPDATE lao.id_rel_geo_tao to NULL should create LAO v nobenem TAO'
);

UPDATE md_geo_lao
SET id_rel_geo_tao = (SELECT value FROM agent_ids WHERE key='tao1')
WHERE id = (SELECT value FROM agent_ids WHERE key='lao1');

DELETE FROM md_geo_lao
WHERE id = (SELECT value FROM agent_ids WHERE key='lao1');

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model1')
          AND tip_problema = 'TAO brez LAO'
          AND problematicen_id = (SELECT value FROM agent_ids WHERE key='tao1')
    ),
    'DELETE lao should make tao1 empty'
);

INSERT INTO md_geo_lao (id, created_at, created_by, id_rel_geo_tao, id_rel_verzije_modeli, id_lao, ime_lao, drugi_lao)
VALUES (
    (SELECT value FROM agent_ids WHERE key='lao1'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='tao1'),
    (SELECT value FROM agent_ids WHERE key='model1'),
    1,
    'H_LAO_1',
    false
);

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*) FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model1')
          AND tip_problema IN ('TAO brez LAO', 'LAO ne obstaja')
    ) = 0,
    'INSERT lao back should clear TAO brez LAO and LAO ne obstaja'
);

\echo 'All assertions passed for AgentTests 03'
ROLLBACK;

\echo 'AgentTests 03 complete (rollback executed)'
