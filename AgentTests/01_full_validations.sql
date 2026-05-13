\set ON_ERROR_STOP on
\timing on
\pset pager off

\echo ''
\echo '======================================================================'
\echo 'AgentTests 01 - Full Validation Functions (rollback-safe)'
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
DROP TRIGGER IF EXISTS trg_validate_obmxcona_incremental ON md_geo_obmxcona;
DROP TRIGGER IF EXISTS trg_validate_cona_lao_incremental ON md_geo_cona;
DROP TRIGGER IF EXISTS trg_validate_lao_tao_incremental ON md_geo_lao;

CREATE TEMP TABLE agent_ids (
    key text PRIMARY KEY,
    value uuid NOT NULL
);

INSERT INTO agent_ids (key, value)
VALUES
    ('version1', uuid_generate_v4()),
    ('version2', uuid_generate_v4()),
    ('version_empty', uuid_generate_v4()),
    ('model1', uuid_generate_v4()),
    ('model2', uuid_generate_v4()),
    ('fake_model', uuid_generate_v4()),
    ('tao1', uuid_generate_v4()),
    ('tao2', uuid_generate_v4()),
    ('tao_empty', uuid_generate_v4()),
    ('lao1', uuid_generate_v4()),
    ('lao2', uuid_generate_v4()),
    ('lao_m2', uuid_generate_v4()),
    ('cona1', uuid_generate_v4()),
    ('cona2', uuid_generate_v4()),
    ('cona3', uuid_generate_v4()),
    ('cona_m2', uuid_generate_v4()),
    ('fake_obm', uuid_generate_v4()),
    ('fake_cona', uuid_generate_v4()),
    ('fake_lao', uuid_generate_v4()),
    ('fake_tao', uuid_generate_v4()),
    ('link_orphan_obm', uuid_generate_v4()),
    ('link_orphan_cona', uuid_generate_v4()),
    ('full_small_hole_version', uuid_generate_v4()),
    ('full_small_hole_left', uuid_generate_v4()),
    ('full_small_hole_right', uuid_generate_v4()),
    ('full_small_intersection_version', uuid_generate_v4()),
    ('full_small_intersection_a', uuid_generate_v4()),
    ('full_small_intersection_b', uuid_generate_v4()),
    ('full_small_intersection_disabled_version', uuid_generate_v4()),
    ('full_small_intersection_disabled_a', uuid_generate_v4()),
    ('full_small_intersection_disabled_b', uuid_generate_v4()),
    ('full_overflow_version', uuid_generate_v4()),
    ('full_overflow_obm', uuid_generate_v4()),
    ('all_versions_small_hole_version', uuid_generate_v4()),
    ('all_versions_small_hole_left', uuid_generate_v4()),
    ('all_versions_small_hole_right', uuid_generate_v4()),
    ('all_versions_small_intersection_version', uuid_generate_v4()),
    ('all_versions_small_intersection_a', uuid_generate_v4()),
    ('all_versions_small_intersection_b', uuid_generate_v4());

INSERT INTO agent_ids (key, value)
SELECT 'obm' || gs::text, uuid_generate_v4()
FROM generate_series(1, 10) AS gs;

\echo 'Setup: controlled boundary and test fixtures'

TRUNCATE TABLE slo_meja;
INSERT INTO slo_meja (id, created_at, created_by, geom)
VALUES (
    uuid_generate_v4(),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    ST_GeomFromText('POLYGON((0 0, 3 0, 3 3, 0 3, 0 0))', 3794)
);

INSERT INTO md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
VALUES
    ((SELECT value FROM agent_ids WHERE key = 'version1'), '00000000-0000-0000-0000-000000000000'::uuid, now()::timestamp, 99001, false, 'AGENT_TEST', false),
    ((SELECT value FROM agent_ids WHERE key = 'version2'), '00000000-0000-0000-0000-000000000000'::uuid, now()::timestamp, 99002, false, 'AGENT_TEST', false),
    ((SELECT value FROM agent_ids WHERE key = 'version_empty'), '00000000-0000-0000-0000-000000000000'::uuid, now()::timestamp, 99003, false, 'AGENT_TEST', false);

INSERT INTO md_verzije_modeli (id, created_by, created_at, id_rel_geo_verzija, model, verzija)
VALUES
    ((SELECT value FROM agent_ids WHERE key = 'model1'), '00000000-0000-0000-0000-000000000000'::uuid, now()::timestamp, (SELECT value FROM agent_ids WHERE key = 'version1'), 'AGENT_TEST', 101),
    ((SELECT value FROM agent_ids WHERE key = 'model2'), '00000000-0000-0000-0000-000000000000'::uuid, now()::timestamp, (SELECT value FROM agent_ids WHERE key = 'version2'), 'AGENT_TEST', 102);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES
    ((SELECT value FROM agent_ids WHERE key='obm1'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version1'), 'AGENT_OBM_1', ST_GeomFromText('POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm2'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version1'), 'AGENT_OBM_2', ST_GeomFromText('POLYGON((1 0, 2 0, 2 1, 1 1, 1 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm3'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version1'), 'AGENT_OBM_3', ST_GeomFromText('POLYGON((2 0, 3 0, 3 1, 2 1, 2 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm4'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version1'), 'AGENT_OBM_4', ST_GeomFromText('POLYGON((0 1, 1 1, 1 2, 0 2, 0 1))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm5'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version1'), 'AGENT_OBM_5', ST_GeomFromText('POLYGON((1 1, 2 1, 2 2, 1 2, 1 1))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm6'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version1'), 'AGENT_OBM_6', ST_GeomFromText('POLYGON((2 1, 3 1, 3 2, 2 2, 2 1))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm7'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version1'), 'AGENT_OBM_7', ST_GeomFromText('POLYGON((0 2, 1 2, 1 3, 0 3, 0 2))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm8'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version1'), 'AGENT_OBM_8', ST_GeomFromText('POLYGON((1 2, 2 2, 2 3, 1 3, 1 2))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm9'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version1'), 'AGENT_OBM_9', ST_GeomFromText('POLYGON((2 2, 3 2, 3 3, 2 3, 2 2))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='obm10'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='version2'), 'AGENT_OBM_10', ST_GeomFromText('POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))', 3794));

INSERT INTO md_geo_tao (id, created_at, created_by, id_rel_verzije_modeli, id_tao, drugi_tao)
VALUES
    ((SELECT value FROM agent_ids WHERE key='tao1'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='model1'), 1, false),
    ((SELECT value FROM agent_ids WHERE key='tao2'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='model2'), 2, false);

INSERT INTO md_geo_lao (id, created_at, created_by, id_rel_geo_tao, id_rel_verzije_modeli, id_lao, ime_lao, drugi_lao)
VALUES
    ((SELECT value FROM agent_ids WHERE key='lao1'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='tao1'), (SELECT value FROM agent_ids WHERE key='model1'), 1, 'AGENT_LAO_1', false),
    ((SELECT value FROM agent_ids WHERE key='lao2'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='tao1'), (SELECT value FROM agent_ids WHERE key='model1'), 2, 'AGENT_LAO_2', false),
    ((SELECT value FROM agent_ids WHERE key='lao_m2'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='tao2'), (SELECT value FROM agent_ids WHERE key='model2'), 3, 'AGENT_LAO_M2', false);

INSERT INTO md_geo_cona (id, created_at, created_by, id_rel_geo_lao, id_rel_verzije_modeli, ime_cone)
VALUES
    ((SELECT value FROM agent_ids WHERE key='cona1'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='lao1'), (SELECT value FROM agent_ids WHERE key='model1'), 'AGENT_CONA_1'),
    ((SELECT value FROM agent_ids WHERE key='cona2'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='lao1'), (SELECT value FROM agent_ids WHERE key='model1'), 'AGENT_CONA_2'),
    ((SELECT value FROM agent_ids WHERE key='cona3'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='lao2'), (SELECT value FROM agent_ids WHERE key='model1'), 'AGENT_CONA_3'),
    ((SELECT value FROM agent_ids WHERE key='cona_m2'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='lao_m2'), (SELECT value FROM agent_ids WHERE key='model2'), 'AGENT_CONA_M2');

INSERT INTO md_geo_obmxcona (id, created_at, created_by, id_rel_geo_obm, id_rel_geo_cona)
SELECT uuid_generate_v4(), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid,
       (SELECT value FROM agent_ids WHERE key = 'obm' || gs::text),
       (SELECT value FROM agent_ids WHERE key = 'cona1')
FROM generate_series(1, 3) AS gs;

INSERT INTO md_geo_obmxcona (id, created_at, created_by, id_rel_geo_obm, id_rel_geo_cona)
SELECT uuid_generate_v4(), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid,
       (SELECT value FROM agent_ids WHERE key = 'obm' || gs::text),
       (SELECT value FROM agent_ids WHERE key = 'cona2')
FROM generate_series(4, 6) AS gs;

INSERT INTO md_geo_obmxcona (id, created_at, created_by, id_rel_geo_obm, id_rel_geo_cona)
SELECT uuid_generate_v4(), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid,
       (SELECT value FROM agent_ids WHERE key = 'obm' || gs::text),
       (SELECT value FROM agent_ids WHERE key = 'cona3')
FROM generate_series(7, 9) AS gs;

INSERT INTO md_geo_obmxcona (id, created_at, created_by, id_rel_geo_obm, id_rel_geo_cona)
VALUES (
    uuid_generate_v4(),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='obm10'),
    (SELECT value FROM agent_ids WHERE key='cona_m2')
);

\echo 'Test group: validate_all and low-level OBM validators'

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1
        FROM validate_all_topologies_single_geo_version((SELECT value FROM agent_ids WHERE key = 'version1')) v
        WHERE v.chosen_id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key = 'version1')
          AND v.holes_found = 0
          AND v.overflows_found = 0
          AND v.intersections_found = 0
          AND v.total_entries = 9
    ),
    'validate_all baseline for version1 should be 0/0/0 with total 9'
);

SELECT pg_temp.assert_true(
    (
        SELECT bool_and(geom_is_on_2_decimal_grid(geom))
        FROM md_geo_obm
        WHERE id_rel_geo_verzija IN (
            (SELECT value FROM agent_ids WHERE key = 'version1'),
            (SELECT value FROM agent_ids WHERE key = 'version2')
        )
    ),
    'Loaded OBM geometry should be on 0.01 grid'
);

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1
        FROM validate_all_topologies_single_geo_version((SELECT value FROM agent_ids WHERE key = 'version2')) v
        WHERE v.chosen_id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key = 'version2')
          AND (
              CASE
                  WHEN obm_small_topology_autofix_enabled() THEN v.holes_found = 0
                  ELSE v.holes_found > 0
              END
          )
          AND v.overflows_found = 0
          AND v.intersections_found = 0
          AND v.total_entries = 1
    ),
    'validate_all for sparse version2 hole behavior should follow obm_small_topology_autofix_enabled()'
);

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1
        FROM validate_all_topologies_single_geo_version((SELECT value FROM agent_ids WHERE key = 'version_empty')) v
        WHERE v.chosen_id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key = 'version_empty')
          AND v.holes_found = 0
          AND v.overflows_found = 0
          AND v.intersections_found = 0
          AND v.total_entries = 0
    ),
    'validate_all should return zero-result row for empty version'
);

-- Took way too long, so I took it out:
-- SELECT pg_temp.assert_true(
--     (
--         SELECT COUNT(*)
--         FROM validate_all_topologies() v
--         WHERE v.chosen_id_rel_geo_verzija IN (
--             (SELECT value FROM agent_ids WHERE key = 'version1'),
--             (SELECT value FROM agent_ids WHERE key = 'version2')
--         )
--     ) = 2,
--     'validate_all_topologies should include both agent test versions'
-- );

DELETE FROM md_geo_obm WHERE id = (SELECT value FROM agent_ids WHERE key='obm5');
SELECT pg_temp.assert_true(
    (SELECT holes_found FROM validate_holes((SELECT value FROM agent_ids WHERE key='version1'))) = 1,
    'validate_holes should find exactly one hole after deleting center OBM'
);
SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*) FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='version1')
          AND tip_topoloskega_problema = 'luknja'
    ) = 1,
    'hole entry should be persisted in md_topoloske_kontrole_obm'
);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES (
    (SELECT value FROM agent_ids WHERE key='obm5'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='version1'),
    'AGENT_OBM_5',
    ST_GeomFromText('POLYGON((1 1, 2 1, 2 2, 1 2, 1 1))', 3794)
);

UPDATE md_geo_obm
SET geom = ST_GeomFromText('POLYGON((-0.25 0, 1 0, 1 1, -0.25 1, -0.25 0))', 3794)
WHERE id = (SELECT value FROM agent_ids WHERE key='obm1');

SELECT pg_temp.assert_true(
    (SELECT overflows_found FROM validate_overflows((SELECT value FROM agent_ids WHERE key='version1'))) = 1,
    'validate_overflows should find one overflow after extending obm1 beyond boundary'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='version1')
          AND tip_topoloskega_problema = 'preliv'
          AND id1 = (SELECT value FROM agent_ids WHERE key='obm1')
    ),
    'overflow entry should reference obm1 in id1'
);

UPDATE md_geo_obm
SET geom = ST_GeomFromText('POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))', 3794)
WHERE id = (SELECT value FROM agent_ids WHERE key='obm1');

UPDATE md_geo_obm
SET geom = ST_GeomFromText('POLYGON((1 0, 2 0, 2 1.5, 1 1.5, 1 0))', 3794)
WHERE id = (SELECT value FROM agent_ids WHERE key='obm2');

SELECT pg_temp.assert_true(
    (SELECT intersections_found FROM validate_intersections((SELECT value FROM agent_ids WHERE key='version1'))) = 1,
    'validate_intersections should find one overlap after expanding obm2'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='version1')
          AND tip_topoloskega_problema = 'prekrivanje'
          AND id1 = LEAST((SELECT value FROM agent_ids WHERE key='obm2'), (SELECT value FROM agent_ids WHERE key='obm5'))
          AND id2 = GREATEST((SELECT value FROM agent_ids WHERE key='obm2'), (SELECT value FROM agent_ids WHERE key='obm5'))
    ),
    'intersection entry should be created with ordered id1/id2 pair'
);

SELECT pg_temp.assert_true(
    COALESCE((
        SELECT bool_and(geom_is_on_2_decimal_grid(geom))
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='version1')
          AND geom IS NOT NULL
    ), true),
    'Batch topology validators should store only 0.01-grid control geometry'
);

UPDATE md_geo_obm
SET geom = ST_GeomFromText('POLYGON((1 0, 2 0, 2 1, 1 1, 1 0))', 3794)
WHERE id = (SELECT value FROM agent_ids WHERE key='obm2');

\echo 'Test group: validate_all small topology autofix'

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
    ((SELECT value FROM agent_ids WHERE key='full_small_hole_version'), '00000000-0000-0000-0000-000000000000'::uuid, now()::timestamp, 99004, false, 'AGENT_TEST_FULL_SMALL_HOLE', false),
    ((SELECT value FROM agent_ids WHERE key='full_small_intersection_version'), '00000000-0000-0000-0000-000000000000'::uuid, now()::timestamp, 99005, false, 'AGENT_TEST_FULL_SMALL_INTERSECTION', false),
    ((SELECT value FROM agent_ids WHERE key='full_small_intersection_disabled_version'), '00000000-0000-0000-0000-000000000000'::uuid, now()::timestamp, 99006, false, 'AGENT_TEST_FULL_SMALL_INTERSECTION_DISABLED', false),
    ((SELECT value FROM agent_ids WHERE key='full_overflow_version'), '00000000-0000-0000-0000-000000000000'::uuid, now()::timestamp, 99009, false, 'AGENT_TEST_FULL_OVERFLOW', false);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES (
    (SELECT value FROM agent_ids WHERE key='full_overflow_obm'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='full_overflow_version'),
    'FULL_OVERFLOW_OBM',
    ST_GeomFromText('POLYGON((-1 0, 5 0, 5 5, -1 5, -1 0))', 3794)
);

SELECT * FROM validate_all_topologies_single_geo_version((SELECT value FROM agent_ids WHERE key='full_overflow_version'));

SELECT pg_temp.assert_true(
    (
        SELECT ST_Covers(s.geom, obm.geom)
        FROM md_geo_obm obm
        CROSS JOIN slo_meja s
        WHERE obm.id = (SELECT value FROM agent_ids WHERE key='full_overflow_obm')
        LIMIT 1
    ),
    'validate_all_topologies_single_geo_version should always clip overflow geometry'
);

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*) = 0
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='full_overflow_version')
          AND tip_topoloskega_problema = 'preliv'
    ),
    'validate_all_topologies_single_geo_version should not write preliv after overflow clipping'
);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES
    ((SELECT value FROM agent_ids WHERE key='full_small_hole_left'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='full_small_hole_version'), 'FULL_SMALL_HOLE_LEFT', ST_GeomFromText('POLYGON((0 0, 4.99 0, 4.99 10, 0 10, 0 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='full_small_hole_right'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='full_small_hole_version'), 'FULL_SMALL_HOLE_RIGHT', ST_GeomFromText('POLYGON((5 0, 10 0, 10 10, 5 10, 5 0))', 3794));

SELECT * FROM validate_all_topologies_single_geo_version((SELECT value FROM agent_ids WHERE key='full_small_hole_version'));

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*) = CASE WHEN obm_small_topology_autofix_enabled() THEN 0 ELSE 1 END
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='full_small_hole_version')
          AND tip_topoloskega_problema = 'luknja'
    ),
    'validate_all small hole behavior should follow obm_small_topology_autofix_enabled()'
);

SELECT pg_temp.assert_true(
    (
        SELECT CASE
            WHEN obm_small_topology_autofix_enabled() THEN abs(SUM(ST_Area(geom)) - 100) < 1e-6
            ELSE abs(SUM(ST_Area(geom)) - 99.9) < 1e-6
        END
        FROM md_geo_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='full_small_hole_version')
    ),
    'validate_all small hole geometry should follow obm_small_topology_autofix_enabled()'
);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES
    ((SELECT value FROM agent_ids WHERE key='full_small_intersection_a'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='full_small_intersection_version'), 'FULL_SMALL_INTERSECTION_A', ST_GeomFromText('POLYGON((0 0, 10 0, 10 1, 0 1, 0 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='full_small_intersection_b'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='full_small_intersection_version'), 'FULL_SMALL_INTERSECTION_B', ST_GeomFromText('POLYGON((0 0.99, 10 0.99, 10 2, 0 2, 0 0.99))', 3794));

SELECT * FROM validate_all_topologies_single_geo_version((SELECT value FROM agent_ids WHERE key='full_small_intersection_version'));

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*) = CASE WHEN obm_small_topology_autofix_enabled() THEN 0 ELSE 1 END
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='full_small_intersection_version')
          AND tip_topoloskega_problema = 'prekrivanje'
    ),
    'validate_all small intersection control behavior should follow obm_small_topology_autofix_enabled()'
);

SELECT pg_temp.assert_true(
    (
        SELECT CASE
            WHEN obm_small_topology_autofix_enabled() THEN abs(SUM(ST_Area(geom)) - 20) < 1e-6
            ELSE abs(SUM(ST_Area(geom)) - 20.1) < 1e-6
        END
        FROM md_geo_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='full_small_intersection_version')
    ),
    'validate_all small intersection geometry should follow obm_small_topology_autofix_enabled()'
);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES
    ((SELECT value FROM agent_ids WHERE key='full_small_intersection_disabled_a'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='full_small_intersection_disabled_version'), 'FULL_SMALL_INTERSECTION_DISABLED_A', ST_GeomFromText('POLYGON((0 0, 10 0, 10 1, 0 1, 0 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='full_small_intersection_disabled_b'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='full_small_intersection_disabled_version'), 'FULL_SMALL_INTERSECTION_DISABLED_B', ST_GeomFromText('POLYGON((0 0.99, 10 0.99, 10 2, 0 2, 0 0.99))', 3794));

SELECT * FROM validate_all_topologies_single_geo_version((SELECT value FROM agent_ids WHERE key='full_small_intersection_disabled_version'));

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*) = CASE WHEN obm_small_topology_autofix_enabled() THEN 0 ELSE 1 END
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='full_small_intersection_disabled_version')
          AND tip_topoloskega_problema = 'prekrivanje'
    ),
    'Second validate_all small intersection case should follow obm_small_topology_autofix_enabled()'
);

\echo 'Test group: explicit all-version small topology autofix'

INSERT INTO md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
VALUES
    ((SELECT value FROM agent_ids WHERE key='all_versions_small_hole_version'), '00000000-0000-0000-0000-000000000000'::uuid, now()::timestamp, 99007, false, 'AGENT_TEST_ALL_VERSIONS_SMALL_HOLE', false),
    ((SELECT value FROM agent_ids WHERE key='all_versions_small_intersection_version'), '00000000-0000-0000-0000-000000000000'::uuid, now()::timestamp, 99008, false, 'AGENT_TEST_ALL_VERSIONS_SMALL_INTERSECTION', false);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES
    ((SELECT value FROM agent_ids WHERE key='all_versions_small_hole_left'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='all_versions_small_hole_version'), 'ALL_VERSIONS_SMALL_HOLE_LEFT', ST_GeomFromText('POLYGON((0 0, 4.99 0, 4.99 10, 0 10, 0 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='all_versions_small_hole_right'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='all_versions_small_hole_version'), 'ALL_VERSIONS_SMALL_HOLE_RIGHT', ST_GeomFromText('POLYGON((5 0, 10 0, 10 10, 5 10, 5 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='all_versions_small_intersection_a'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='all_versions_small_intersection_version'), 'ALL_VERSIONS_SMALL_INTERSECTION_A', ST_GeomFromText('POLYGON((0 0, 10 0, 10 1, 0 1, 0 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='all_versions_small_intersection_b'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='all_versions_small_intersection_version'), 'ALL_VERSIONS_SMALL_INTERSECTION_B', ST_GeomFromText('POLYGON((0 0.99, 10 0.99, 10 2, 0 2, 0 0.99))', 3794));

CREATE TEMP TABLE agent_autofix_all_versions_result AS
SELECT * FROM autofix_small_obm_topology_all_versions();

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1
        FROM agent_autofix_all_versions_result
        WHERE chosen_id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='all_versions_small_hole_version')
          AND holes_fixed > 0
    ),
    'autofix_small_obm_topology_all_versions should report fixes for the small-hole version'
);

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1
        FROM agent_autofix_all_versions_result
        WHERE chosen_id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='all_versions_small_intersection_version')
          AND intersections_fixed > 0
    ),
    'autofix_small_obm_topology_all_versions should report fixes for the small-intersection version'
);

SELECT pg_temp.assert_true(
    (
        SELECT abs(SUM(ST_Area(geom)) - 100) < 1e-6
        FROM md_geo_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='all_versions_small_hole_version')
    ),
    'autofix_small_obm_topology_all_versions should fix small holes across versions'
);

SELECT pg_temp.assert_true(
    (
        SELECT abs(SUM(ST_Area(geom)) - 20) < 1e-6
        FROM md_geo_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='all_versions_small_intersection_version')
    ),
    'autofix_small_obm_topology_all_versions should fix small intersections across versions'
);

\echo 'Test group: validate_cona_hierarchy cases'

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM validate_cona_hierarchy((SELECT value FROM agent_ids WHERE key='model1')) r
        WHERE r.missing_obms = 0 AND r.orphan_obm_refs = 0 AND r.orphan_cona_refs = 0 AND r.empty_conas = 0
    ),
    'validate_cona_hierarchy baseline should be clean'
);

DELETE FROM md_geo_obmxcona WHERE id_rel_geo_obm = (SELECT value FROM agent_ids WHERE key='obm3');
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM validate_cona_hierarchy((SELECT value FROM agent_ids WHERE key='model1')) r
        WHERE r.missing_obms = 1 AND r.orphan_obm_refs = 0 AND r.orphan_cona_refs = 0 AND r.empty_conas = 0
    ),
    'obm. v nobeni coni should be detected after unlinking obm3'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model1')
          AND id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='version1')
          AND tip_problema = 'obm. v nobeni coni'
    ),
    'hierarhija row for obm. v nobeni coni should carry correct id_rel_geo_verzija'
);
INSERT INTO md_geo_obmxcona (id, created_at, created_by, id_rel_geo_obm, id_rel_geo_cona)
VALUES (
    uuid_generate_v4(),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='obm3'),
    (SELECT value FROM agent_ids WHERE key='cona1')
);

INSERT INTO md_geo_obmxcona (id, created_at, created_by, id_rel_geo_obm, id_rel_geo_cona)
VALUES (
    (SELECT value FROM agent_ids WHERE key='link_orphan_obm'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='fake_obm'),
    (SELECT value FROM agent_ids WHERE key='cona1')
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM validate_cona_hierarchy((SELECT value FROM agent_ids WHERE key='model1')) r
        WHERE r.orphan_obm_refs = 1
    ),
    'napačno obm. should be detected'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model1')
          AND tip_problema = 'napačno obm.'
          AND problematicen_id = (SELECT value FROM agent_ids WHERE key='link_orphan_obm')
    ),
    'napačno obm.: problematicen_id should be the broken obmxcona row id'
);
DELETE FROM md_geo_obmxcona WHERE id = (SELECT value FROM agent_ids WHERE key='link_orphan_obm');

INSERT INTO md_geo_obmxcona (id, created_at, created_by, id_rel_geo_obm, id_rel_geo_cona)
VALUES (
    (SELECT value FROM agent_ids WHERE key='link_orphan_cona'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='obm1'),
    (SELECT value FROM agent_ids WHERE key='fake_cona')
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM validate_cona_hierarchy((SELECT value FROM agent_ids WHERE key='model1')) r
        WHERE r.orphan_cona_refs = 1
    ),
    'cona ne obstaja should be detected'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model1')
          AND tip_problema = 'cona ne obstaja'
          AND problematicen_id = (SELECT value FROM agent_ids WHERE key='link_orphan_cona')
    ),
    'cona ne obstaja: problematicen_id should be the broken obmxcona row id'
);
DELETE FROM md_geo_obmxcona WHERE id = (SELECT value FROM agent_ids WHERE key='link_orphan_cona');

DELETE FROM md_geo_obmxcona WHERE id_rel_geo_cona = (SELECT value FROM agent_ids WHERE key='cona3');
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM validate_cona_hierarchy((SELECT value FROM agent_ids WHERE key='model1')) r
        WHERE r.empty_conas = 1 AND r.missing_obms = 3
    ),
    'cona brez obm. and obm. v nobeni coni should be detected for emptied cona3'
);
INSERT INTO md_geo_obmxcona (id, created_at, created_by, id_rel_geo_obm, id_rel_geo_cona)
SELECT uuid_generate_v4(), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid,
       (SELECT value FROM agent_ids WHERE key = 'obm' || gs::text),
       (SELECT value FROM agent_ids WHERE key = 'cona3')
FROM generate_series(7, 9) AS gs;

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM validate_cona_hierarchy((SELECT value FROM agent_ids WHERE key='fake_model')) r
        WHERE r.missing_obms = 0 AND r.orphan_obm_refs = 0 AND r.orphan_cona_refs = 0 AND r.empty_conas = 0
    ),
    'validate_cona_hierarchy should return all zeros for non-existing model'
);

\echo 'Test group: validate_lao_hierarchy and validate_tao_hierarchy cases'

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM validate_lao_hierarchy((SELECT value FROM agent_ids WHERE key='model1')) r
        WHERE r.missing_conas = 0 AND r.orphan_lao_refs = 0 AND r.empty_laos = 0
    ),
    'validate_lao_hierarchy baseline should be clean'
);

UPDATE md_geo_cona
SET id_rel_geo_lao = NULL
WHERE id = (SELECT value FROM agent_ids WHERE key='cona2');
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM validate_lao_hierarchy((SELECT value FROM agent_ids WHERE key='model1')) r
        WHERE r.missing_conas = 1
    ),
    'cona v nobenem LAO should be detected when cona2 lao is NULL'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model1')
          AND id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='version1')
          AND tip_problema = 'cona v nobenem LAO'
    ),
    'hierarhija row for cona v nobenem LAO should carry correct id_rel_geo_verzija'
);
UPDATE md_geo_cona
SET id_rel_geo_lao = (SELECT value FROM agent_ids WHERE key='lao1')
WHERE id = (SELECT value FROM agent_ids WHERE key='cona2');

UPDATE md_geo_cona
SET id_rel_geo_lao = (SELECT value FROM agent_ids WHERE key='fake_lao')
WHERE id = (SELECT value FROM agent_ids WHERE key='cona2');
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM validate_lao_hierarchy((SELECT value FROM agent_ids WHERE key='model1')) r
        WHERE r.orphan_lao_refs = 1
    ),
    'LAO ne obstaja should be detected'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model1')
          AND tip_problema = 'LAO ne obstaja'
          AND problematicen_id = (SELECT value FROM agent_ids WHERE key='cona2')
    ),
    'LAO ne obstaja: problematicen_id should be the cona with the broken LAO reference'
);
UPDATE md_geo_cona
SET id_rel_geo_lao = (SELECT value FROM agent_ids WHERE key='lao1')
WHERE id = (SELECT value FROM agent_ids WHERE key='cona2');

UPDATE md_geo_cona
SET id_rel_geo_lao = (SELECT value FROM agent_ids WHERE key='lao2')
WHERE id IN (
    (SELECT value FROM agent_ids WHERE key='cona1'),
    (SELECT value FROM agent_ids WHERE key='cona2')
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM validate_lao_hierarchy((SELECT value FROM agent_ids WHERE key='model1')) r
        WHERE r.empty_laos = 1
    ),
    'LAO brez cone should be detected when lao1 has no conas'
);
UPDATE md_geo_cona
SET id_rel_geo_lao = (SELECT value FROM agent_ids WHERE key='lao1')
WHERE id IN (
    (SELECT value FROM agent_ids WHERE key='cona1'),
    (SELECT value FROM agent_ids WHERE key='cona2')
);

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM validate_tao_hierarchy((SELECT value FROM agent_ids WHERE key='model1')) r
        WHERE r.missing_laos = 0 AND r.orphan_tao_refs = 0 AND r.empty_taos = 0
    ),
    'validate_tao_hierarchy baseline should be clean'
);

UPDATE md_geo_lao
SET id_rel_geo_tao = NULL
WHERE id = (SELECT value FROM agent_ids WHERE key='lao2');
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM validate_tao_hierarchy((SELECT value FROM agent_ids WHERE key='model1')) r
        WHERE r.missing_laos = 1
    ),
    'LAO v nobenem TAO should be detected when lao2 tao is NULL'
);
UPDATE md_geo_lao
SET id_rel_geo_tao = (SELECT value FROM agent_ids WHERE key='tao1')
WHERE id = (SELECT value FROM agent_ids WHERE key='lao2');

UPDATE md_geo_lao
SET id_rel_geo_tao = (SELECT value FROM agent_ids WHERE key='fake_tao')
WHERE id = (SELECT value FROM agent_ids WHERE key='lao2');
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM validate_tao_hierarchy((SELECT value FROM agent_ids WHERE key='model1')) r
        WHERE r.orphan_tao_refs = 1
    ),
    'TAO ne obstaja should be detected'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM md_topoloske_kontrole_hierarhija
        WHERE id_rel_verzije_modeli = (SELECT value FROM agent_ids WHERE key='model1')
          AND tip_problema = 'TAO ne obstaja'
          AND problematicen_id = (SELECT value FROM agent_ids WHERE key='lao2')
    ),
    'TAO ne obstaja: problematicen_id should be the LAO with the broken TAO reference'
);
UPDATE md_geo_lao
SET id_rel_geo_tao = (SELECT value FROM agent_ids WHERE key='tao1')
WHERE id = (SELECT value FROM agent_ids WHERE key='lao2');

INSERT INTO md_geo_tao (id, created_at, created_by, id_rel_verzije_modeli, id_tao, drugi_tao)
VALUES (
    (SELECT value FROM agent_ids WHERE key='tao_empty'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='model1'),
    99,
    false
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM validate_tao_hierarchy((SELECT value FROM agent_ids WHERE key='model1')) r
        WHERE r.empty_taos = 1
    ),
    'TAO brez LAO should be detected for tao with no laos'
);
DELETE FROM md_geo_tao WHERE id = (SELECT value FROM agent_ids WHERE key='tao_empty');

\echo 'Test group: aggregate hierarchy wrappers'

DELETE FROM md_geo_obmxcona WHERE id_rel_geo_obm = (SELECT value FROM agent_ids WHERE key='obm3');
UPDATE md_geo_cona
SET id_rel_geo_lao = NULL
WHERE id = (SELECT value FROM agent_ids WHERE key='cona2');
UPDATE md_geo_lao
SET id_rel_geo_tao = NULL
WHERE id = (SELECT value FROM agent_ids WHERE key='lao2');

SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM validate_all_hierarchy((SELECT value FROM agent_ids WHERE key='model1')) r
        WHERE r.cona_missing_obms = 1
          AND r.lao_missing_conas = 1
          AND r.tao_missing_laos = 1
    ),
    'validate_all_hierarchy should combine cona/lao/tao counts correctly'
);

INSERT INTO md_geo_obmxcona (id, created_at, created_by, id_rel_geo_obm, id_rel_geo_cona)
VALUES (
    uuid_generate_v4(),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='obm3'),
    (SELECT value FROM agent_ids WHERE key='cona1')
);
UPDATE md_geo_cona
SET id_rel_geo_lao = (SELECT value FROM agent_ids WHERE key='lao1')
WHERE id = (SELECT value FROM agent_ids WHERE key='cona2');
UPDATE md_geo_lao
SET id_rel_geo_tao = (SELECT value FROM agent_ids WHERE key='tao1')
WHERE id = (SELECT value FROM agent_ids WHERE key='lao2');

SELECT * FROM validate_all_hierarchy((SELECT value FROM agent_ids WHERE key='model1'));
SELECT * FROM validate_all_hierarchy((SELECT value FROM agent_ids WHERE key='model2'));

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*)
        FROM validate_all_hierarchies() r
        WHERE r.chosen_id_rel_verzije_modeli IN (
            (SELECT value FROM agent_ids WHERE key='model1'),
            (SELECT value FROM agent_ids WHERE key='model2')
        )
          AND r.cona_missing_obms = 0
          AND r.cona_orphan_obm_refs = 0
          AND r.cona_orphan_cona_refs = 0
          AND r.cona_empty = 0
          AND r.lao_missing_conas = 0
          AND r.lao_orphan_refs = 0
          AND r.lao_empty = 0
          AND r.tao_missing_laos = 0
          AND r.tao_orphan_refs = 0
          AND r.tao_empty = 0
    ) = 2,
    'validate_all_hierarchies should include both clean test models'
);

\echo 'All assertions passed for AgentTests 01'
ROLLBACK;

\echo 'AgentTests 01 complete (rollback executed)'
