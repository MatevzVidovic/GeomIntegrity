\set ON_ERROR_STOP on
\timing on
\pset pager off

\echo ''
\echo '======================================================================'
\echo 'AgentTests 02 - Topology Incremental Trigger (rollback-safe)'
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

CREATE TEMP TABLE agent_ids (
    key text PRIMARY KEY,
    value uuid NOT NULL
);

INSERT INTO agent_ids (key, value)
VALUES
    ('version', uuid_generate_v4()),
    ('model', uuid_generate_v4()),
    ('obm_out', uuid_generate_v4()),
    ('overflow_version', uuid_generate_v4()),
    ('small_version_intersection', uuid_generate_v4()),
    ('small_model_intersection', uuid_generate_v4()),
    ('small_intersection_a', uuid_generate_v4()),
    ('small_intersection_b', uuid_generate_v4()),
    ('small_version_intersection_disabled', uuid_generate_v4()),
    ('small_model_intersection_disabled', uuid_generate_v4()),
    ('small_intersection_disabled_a', uuid_generate_v4()),
    ('small_intersection_disabled_b', uuid_generate_v4()),
    ('small_version_hole', uuid_generate_v4()),
    ('small_model_hole', uuid_generate_v4()),
    ('small_hole_left', uuid_generate_v4()),
    ('small_hole_strip', uuid_generate_v4()),
    ('small_hole_right', uuid_generate_v4()),
    ('delayed_version', uuid_generate_v4()),
    ('delayed_parent', uuid_generate_v4()),
    ('delayed_child', uuid_generate_v4()),
    ('live_wide_intersection_version', uuid_generate_v4()),
    ('live_wide_intersection_a', uuid_generate_v4()),
    ('live_wide_intersection_b', uuid_generate_v4());

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
DROP TRIGGER IF EXISTS trg_validate_obm_hierarchy_incremental ON md_geo_obm;

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

INSERT INTO md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
VALUES (
    (SELECT value FROM agent_ids WHERE key='overflow_version'),
    '00000000-0000-0000-0000-000000000000'::uuid,
    now()::timestamp,
    99109,
    false,
    'AGENT_TEST_OVERFLOW',
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

SELECT pg_temp.assert_true(
    (
        SELECT bool_and(geom_is_on_2_decimal_grid(geom))
        FROM md_geo_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='version')
    ),
    'Precision trigger should keep fixture OBM geometry on 0.01 grid'
);

SELECT * FROM validate_all_topologies_single_geo_version((SELECT value FROM agent_ids WHERE key='version'));

\i /Users/matevzvidovic/GeomIntegrity/Main/3_1_trg_obm_geom_trigger.sql

SELECT pg_temp.assert_true(
    (
        SELECT array_agg(tgname::text ORDER BY tgname::text) = ARRAY[
            'trg_000_coerce_obm_geom_2_decimal_places',
            'trg_validate_topology_incremental'
        ]
        FROM pg_trigger
        WHERE tgrelid = 'md_geo_obm'::regclass
          AND NOT tgisinternal
          AND tgname IN ('trg_000_coerce_obm_geom_2_decimal_places', 'trg_validate_topology_incremental')
    ),
    'Precision trigger should sort before topology trigger'
);

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

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*)
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='version')
          AND tip_topoloskega_problema = 'luknja'
          AND kompaktnost IS NOT NULL
    ) = 1,
    'Incremental delete-created hole should have compactness'
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
    ) = CASE WHEN obm_small_topology_autofix_enabled() THEN 0 ELSE 2 END,
    'Inserting a strip through the hole should split or autofix holes according to obm_small_topology_autofix_enabled()'
);

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*)
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='version')
          AND tip_topoloskega_problema = 'luknja'
          AND kompaktnost IS NOT NULL
    ) = CASE WHEN obm_small_topology_autofix_enabled() THEN 0 ELSE 2 END,
    'Incremental insert-split hole compactness behavior should follow obm_small_topology_autofix_enabled()'
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
    ) = CASE WHEN obm_small_topology_autofix_enabled() THEN 0 ELSE 1 END,
    'Expanding obm2 intersection behavior should follow obm_small_topology_autofix_enabled()'
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
    (SELECT value FROM agent_ids WHERE key='overflow_version'),
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

\echo 'Case: UPDATE coerces NEW.geom to 2 decimals'
UPDATE md_geo_obm
SET geom = ST_GeomFromText('POLYGON((2.11111 2.11111, 2.44444 2.11111, 2.44444 2.44444, 2.11111 2.44444, 2.11111 2.11111))', 3794)
WHERE id = (SELECT value FROM agent_ids WHERE key='obm_out');

SELECT pg_temp.assert_true(
    (
        SELECT geom_is_on_2_decimal_grid(geom)
        FROM md_geo_obm
        WHERE id = (SELECT value FROM agent_ids WHERE key='obm_out')
    ),
    'Precision trigger should coerce updated OBM geometry to 0.01 grid'
);

SELECT pg_temp.assert_true(
    COALESCE((
        SELECT bool_and(geom_is_on_2_decimal_grid(geom))
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='version')
          AND geom IS NOT NULL
    ), true),
    'Incremental topology trigger should store only 0.01-grid control geometry'
);

\echo 'Case: small elongated intersection is fixed directly and not written as control'
TRUNCATE TABLE slo_meja;
INSERT INTO slo_meja (id, created_at, created_by, geom)
VALUES (
    uuid_generate_v4(),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    ST_GeomFromText('POLYGON((0 0, 10 0, 10 10, 0 10, 0 0))', 3794)
);

INSERT INTO md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
VALUES (
    (SELECT value FROM agent_ids WHERE key='small_version_intersection'),
    '00000000-0000-0000-0000-000000000000'::uuid,
    now()::timestamp,
    99102,
    false,
    'AGENT_TEST_SMALL_INTERSECTION',
    false
);

INSERT INTO md_verzije_modeli (id, created_by, created_at, id_rel_geo_verzija, model, verzija)
VALUES (
    (SELECT value FROM agent_ids WHERE key='small_model_intersection'),
    '00000000-0000-0000-0000-000000000000'::uuid,
    now()::timestamp,
    (SELECT value FROM agent_ids WHERE key='small_version_intersection'),
    'AGENT_TEST_SMALL_INTERSECTION',
    202
);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES (
    (SELECT value FROM agent_ids WHERE key='small_intersection_a'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='small_version_intersection'),
    'T_SMALL_INTERSECTION_A',
    ST_GeomFromText('POLYGON((0 0, 10 0, 10 1, 0 1, 0 0))', 3794)
);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES (
    (SELECT value FROM agent_ids WHERE key='small_intersection_b'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='small_version_intersection'),
    'T_SMALL_INTERSECTION_B',
    ST_GeomFromText('POLYGON((0 0.99, 10 0.99, 10 2, 0 2, 0 0.99))', 3794)
);

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*) = CASE WHEN obm_small_topology_autofix_enabled() THEN 0 ELSE 1 END
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='small_version_intersection')
          AND tip_topoloskega_problema = 'prekrivanje'
    ),
    'Small elongated intersection control behavior should follow obm_small_topology_autofix_enabled()'
);

SELECT pg_temp.assert_true(
    (
        SELECT CASE
            WHEN obm_small_topology_autofix_enabled() THEN abs(ST_Area(geom) - 10) < 1e-6
            ELSE abs(ST_Area(geom) - 10.1) < 1e-6
        END
        FROM md_geo_obm
        WHERE id = (SELECT value FROM agent_ids WHERE key='small_intersection_b')
    ),
    'Small elongated intersection geometry should follow obm_small_topology_autofix_enabled()'
);

\echo 'Case: second small elongated intersection follows autofix function'

INSERT INTO md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
VALUES (
    (SELECT value FROM agent_ids WHERE key='small_version_intersection_disabled'),
    '00000000-0000-0000-0000-000000000000'::uuid,
    now()::timestamp,
    99104,
    false,
    'AGENT_TEST_SMALL_INTERSECTION_DISABLED',
    false
);

INSERT INTO md_verzije_modeli (id, created_by, created_at, id_rel_geo_verzija, model, verzija)
VALUES (
    (SELECT value FROM agent_ids WHERE key='small_model_intersection_disabled'),
    '00000000-0000-0000-0000-000000000000'::uuid,
    now()::timestamp,
    (SELECT value FROM agent_ids WHERE key='small_version_intersection_disabled'),
    'AGENT_TEST_SMALL_INTERSECTION_DISABLED',
    204
);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES (
    (SELECT value FROM agent_ids WHERE key='small_intersection_disabled_a'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='small_version_intersection_disabled'),
    'T_SMALL_INTERSECTION_DISABLED_A',
    ST_GeomFromText('POLYGON((0 0, 10 0, 10 1, 0 1, 0 0))', 3794)
);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES (
    (SELECT value FROM agent_ids WHERE key='small_intersection_disabled_b'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='small_version_intersection_disabled'),
    'T_SMALL_INTERSECTION_DISABLED_B',
    ST_GeomFromText('POLYGON((0 0.99, 10 0.99, 10 2, 0 2, 0 0.99))', 3794)
);

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*) = CASE WHEN obm_small_topology_autofix_enabled() THEN 0 ELSE 1 END
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='small_version_intersection_disabled')
          AND tip_topoloskega_problema = 'prekrivanje'
    ),
    'Second small intersection control behavior should follow obm_small_topology_autofix_enabled()'
);

\echo 'Case: small elongated delete-created hole is written as control'
INSERT INTO md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
VALUES (
    (SELECT value FROM agent_ids WHERE key='small_version_hole'),
    '00000000-0000-0000-0000-000000000000'::uuid,
    now()::timestamp,
    99103,
    false,
    'AGENT_TEST_SMALL_HOLE',
    false
);

INSERT INTO md_verzije_modeli (id, created_by, created_at, id_rel_geo_verzija, model, verzija)
VALUES (
    (SELECT value FROM agent_ids WHERE key='small_model_hole'),
    '00000000-0000-0000-0000-000000000000'::uuid,
    now()::timestamp,
    (SELECT value FROM agent_ids WHERE key='small_version_hole'),
    'AGENT_TEST_SMALL_HOLE',
    203
);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES
    ((SELECT value FROM agent_ids WHERE key='small_hole_left'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='small_version_hole'), 'T_SMALL_HOLE_LEFT', ST_GeomFromText('POLYGON((0 0, 4.99 0, 4.99 10, 0 10, 0 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='small_hole_strip'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='small_version_hole'), 'T_SMALL_HOLE_STRIP', ST_GeomFromText('POLYGON((4.99 0, 5 0, 5 10, 4.99 10, 4.99 0))', 3794)),
    ((SELECT value FROM agent_ids WHERE key='small_hole_right'), now()::timestamp, '00000000-0000-0000-0000-000000000000'::uuid, (SELECT value FROM agent_ids WHERE key='small_version_hole'), 'T_SMALL_HOLE_RIGHT', ST_GeomFromText('POLYGON((5 0, 10 0, 10 10, 5 10, 5 0))', 3794));

DELETE FROM md_geo_obm
WHERE id = (SELECT value FROM agent_ids WHERE key='small_hole_strip');

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*)
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='small_version_hole')
          AND tip_topoloskega_problema = 'luknja'
    ) = 1,
    'Delete-created small hole should be written as luknja control'
);

SELECT pg_temp.assert_true(
    (
        SELECT abs(SUM(ST_Area(geom)) - 99.9) < 1e-6
        FROM md_geo_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='small_version_hole')
    ),
    'Delete-created small hole should not mutate another OBM from the row trigger'
);

\echo 'Case: assigning a delayed version processes existing geometry as an addition'
INSERT INTO md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
VALUES (
    (SELECT value FROM agent_ids WHERE key='delayed_version'),
    '00000000-0000-0000-0000-000000000000'::uuid,
    now()::timestamp,
    99111,
    false,
    'AGENT_TEST_DELAYED_VERSION',
    false
);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES (
    (SELECT value FROM agent_ids WHERE key='delayed_parent'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='delayed_version'),
    'T_DELAYED_PARENT',
    ST_GeomFromText('POLYGON((0 0, 10 0, 10 10, 0 10, 0 0))', 3794)
);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES (
    (SELECT value FROM agent_ids WHERE key='delayed_child'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    NULL,
    'T_DELAYED_CHILD',
    ST_GeomFromText('POLYGON((5 0, 10 0, 10 10, 5 10, 5 0))', 3794)
);

UPDATE md_geo_obm
SET geom = ST_GeomFromText('POLYGON((0 0, 5 0, 5 10, 0 10, 0 0))', 3794)
WHERE id = (SELECT value FROM agent_ids WHERE key='delayed_parent');

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*)
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='delayed_version')
          AND tip_topoloskega_problema = 'luknja'
    ) = 1,
    'Updating the original before assigning the child version should temporarily create one hole'
);

UPDATE md_geo_obm
SET id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='delayed_version')
WHERE id = (SELECT value FROM agent_ids WHERE key='delayed_child');

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*)
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='delayed_version')
    ) = 0,
    'Assigning the child version should reconcile the temporary hole without creating controls for the old NULL version'
);

SELECT pg_temp.assert_true(
    (
        SELECT abs(ST_Area(ST_Union(geom)) - 100) < 1e-6
        FROM md_geo_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='delayed_version')
    ),
    'Delayed version assignment should preserve complete parent and child coverage'
);

\echo 'Case: live trigger keeps stricter small-topology threshold than preprocessing'
TRUNCATE TABLE slo_meja;
INSERT INTO slo_meja (id, created_at, created_by, geom)
VALUES (
    uuid_generate_v4(),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    ST_GeomFromText('POLYGON((0 0, 1000 0, 1000 10, 0 10, 0 0))', 3794)
);

INSERT INTO md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
VALUES (
    (SELECT value FROM agent_ids WHERE key='live_wide_intersection_version'),
    '00000000-0000-0000-0000-000000000000'::uuid,
    now()::timestamp,
    99110,
    false,
    'AGENT_TEST_LIVE_WIDE_INTERSECTION',
    false
);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES (
    (SELECT value FROM agent_ids WHERE key='live_wide_intersection_a'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='live_wide_intersection_version'),
    'T_LIVE_WIDE_INTERSECTION_A',
    ST_GeomFromText('POLYGON((0 0, 500 0, 500 1, 0 1, 0 0))', 3794)
);

INSERT INTO md_geo_obm (id, created_at, created_by, id_rel_geo_verzija, ime_obmocja, geom)
VALUES (
    (SELECT value FROM agent_ids WHERE key='live_wide_intersection_b'),
    now()::timestamp,
    '00000000-0000-0000-0000-000000000000'::uuid,
    (SELECT value FROM agent_ids WHERE key='live_wide_intersection_version'),
    'T_LIVE_WIDE_INTERSECTION_B',
    ST_GeomFromText('POLYGON((0 0.6, 500 0.6, 500 2, 0 2, 0 0.6))', 3794)
);

SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*) = 1
        FROM md_topoloske_kontrole_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='live_wide_intersection_version')
          AND tip_topoloskega_problema = 'prekrivanje'
    ),
    'Live trigger should report the 200m2 skinny overlap because only preprocessing uses the wider threshold'
);

SELECT pg_temp.assert_true(
    (
        SELECT abs(SUM(ST_Area(geom)) - 1200) < 1e-6
        FROM md_geo_obm
        WHERE id_rel_geo_verzija = (SELECT value FROM agent_ids WHERE key='live_wide_intersection_version')
    ),
    'Live trigger should not autofix the 200m2 skinny overlap'
);

\echo 'All assertions passed for AgentTests 02'
ROLLBACK;

\echo 'AgentTests 02 complete (rollback executed)'
