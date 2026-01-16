truncate md_geo_obm_verzije;
truncate md_geo_obm;
------------------------------------------------------------------------------------------------------------------------
-- HIS, STA, STZ, DRZ, SDP, KDS
------------------------------------------------------------------------------------------------------------------------
-- md_geo_obm_verzije
insert into md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
values (uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), 1, false, 'HIS, STA, STZ, DRZ, SDP, KDS', true);

-- md_geo_obm
insert into md_geo_obm (id, created_by, created_at, geom, id_rel_geo_verzija, ime_obmocja, gv_id)
select uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), geometry, vr.id, ime, cone.id
from primoz_gv_cone cone,
     ( select id from md_geo_obm_verzije where verzija_obmocja = 1 ) vr
where cone.model = 'HIS'
  and verzija = 286;
update md_verzije_modeli vm set id_rel_geo_verzija = geo.id from md_geo_obm_verzije geo where geo.verzija_obmocja = 1 and vm.model = 'HIS' and vm.verzija = 286;
update md_verzije_modeli vm set id_rel_geo_verzija = geo.id from md_geo_obm_verzije geo where geo.verzija_obmocja = 1 and vm.model = 'STA' and vm.verzija = 223;
update md_verzije_modeli vm set id_rel_geo_verzija = geo.id from md_geo_obm_verzije geo where geo.verzija_obmocja = 1 and vm.model = 'STZ' and vm.verzija = 44;
update md_verzije_modeli vm set id_rel_geo_verzija = geo.id from md_geo_obm_verzije geo where geo.verzija_obmocja = 1 and vm.model = 'DRZ' and vm.verzija = 16;
update md_verzije_modeli vm set id_rel_geo_verzija = geo.id from md_geo_obm_verzije geo where geo.verzija_obmocja = 1 and vm.model = 'SDP' and vm.verzija = 33;
update md_verzije_modeli vm set id_rel_geo_verzija = geo.id from md_geo_obm_verzije geo where geo.verzija_obmocja = 1 and vm.model = 'KDS' and vm.verzija = 46;

------------------------------------------------------------------------------------------------------------------------
-- GAR
------------------------------------------------------------------------------------------------------------------------
-- md_geo_obm_verzije
insert into md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
values (uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), 2, false, 'GAR', true);
-- md_geo_obm
insert into md_geo_obm (id, created_by, created_at, geom, id_rel_geo_verzija, ime_obmocja, gv_id)
select uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), geometry, vr.id, ime, cone.id
from primoz_gv_cone cone,
     ( select id from md_geo_obm_verzije where verzija_obmocja = 2 ) vr
where cone.model = 'GAR'
  and verzija = 90;
update md_verzije_modeli vm set id_rel_geo_verzija = geo.id from md_geo_obm_verzije geo where geo.verzija_obmocja = 2 and vm.model = 'GAR' and vm.verzija = 90;

------------------------------------------------------------------------------------------------------------------------
-- GOZ
------------------------------------------------------------------------------------------------------------------------
-- md_geo_obm_verzije
insert into md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
values (uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), 3, false, 'GOZ', true);
-- md_geo_obm
insert into md_geo_obm (id, created_by, created_at, geom, id_rel_geo_verzija, ime_obmocja, gv_id)
select uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), geometry, vr.id, ime, cone.id
from primoz_gv_cone cone,
     ( select id from md_geo_obm_verzije where verzija_obmocja = 3 ) vr
where cone.model = 'GOZ'
  and verzija = 96;
update md_verzije_modeli vm set id_rel_geo_verzija = geo.id from md_geo_obm_verzije geo where geo.verzija_obmocja = 3 and vm.model = 'GOZ' and vm.verzija = 96;

------------------------------------------------------------------------------------------------------------------------
-- IND
------------------------------------------------------------------------------------------------------------------------
-- md_geo_obm_verzije
insert into md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
values (uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), 4, false, 'IND', true);
-- md_geo_obm
insert into md_geo_obm (id, created_by, created_at, geom, id_rel_geo_verzija, ime_obmocja, gv_id)
select uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), geometry, vr.id, ime, cone.id
from primoz_gv_cone cone,
     ( select id from md_geo_obm_verzije where verzija_obmocja = 4 ) vr
where cone.model = 'IND'
  and verzija = 66;
update md_verzije_modeli vm set id_rel_geo_verzija = geo.id from md_geo_obm_verzije geo where geo.verzija_obmocja = 4 and vm.model = 'IND' and vm.verzija = 66;

------------------------------------------------------------------------------------------------------------------------
-- INP
------------------------------------------------------------------------------------------------------------------------
-- md_geo_obm_verzije
insert into md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
values (uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), 5, false, 'INP', true);
-- md_geo_obm
insert into md_geo_obm (id, created_by, created_at, geom, id_rel_geo_verzija, ime_obmocja, gv_id)
select uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), geometry, vr.id, ime, cone.id
from primoz_gv_cone cone,
     ( select id from md_geo_obm_verzije where verzija_obmocja = 5 ) vr
where cone.model = 'INP'
  and verzija = 49;
update md_verzije_modeli vm set id_rel_geo_verzija = geo.id from md_geo_obm_verzije geo where geo.verzija_obmocja = 5 and vm.model = 'INP' and vm.verzija = 49;

------------------------------------------------------------------------------------------------------------------------
-- KME
------------------------------------------------------------------------------------------------------------------------
-- md_geo_obm_verzije
insert into md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
values (uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), 6, false, 'KME', true);
-- md_geo_obm
insert into md_geo_obm (id, created_by, created_at, geom, id_rel_geo_verzija, ime_obmocja, gv_id)
select uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), geometry, vr.id, ime, cone.id
from primoz_gv_cone cone,
     ( select id from md_geo_obm_verzije where verzija_obmocja = 6 ) vr
where cone.model = 'KME'
  and verzija = 102;
update md_verzije_modeli vm set id_rel_geo_verzija = geo.id from md_geo_obm_verzije geo where geo.verzija_obmocja = 6 and vm.model = 'KME' and vm.verzija = 100;

------------------------------------------------------------------------------------------------------------------------
-- PPL
------------------------------------------------------------------------------------------------------------------------
-- md_geo_obm_verzije
insert into md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
values (uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), 7, false, 'PPL', true);
-- md_geo_obm
insert into md_geo_obm (id, created_by, created_at, geom, id_rel_geo_verzija, ime_obmocja, gv_id)
select uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), geometry, vr.id, ime, cone.id
from primoz_gv_cone cone,
     ( select id from md_geo_obm_verzije where verzija_obmocja = 7 ) vr
where cone.model = 'PPL'
  and verzija = 192;
update md_verzije_modeli vm set id_rel_geo_verzija = geo.id from md_geo_obm_verzije geo where geo.verzija_obmocja = 7 and vm.model = 'PPL' and vm.verzija = 192;

------------------------------------------------------------------------------------------------------------------------
-- PPP
------------------------------------------------------------------------------------------------------------------------
-- md_geo_obm_verzije
insert into md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
values (uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), 8, false, 'PPP', true);
-- md_geo_obm
insert into md_geo_obm (id, created_by, created_at, geom, id_rel_geo_verzija, ime_obmocja, gv_id)
select uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), geometry, vr.id, ime, cone.id
from primoz_gv_cone cone,
     ( select id from md_geo_obm_verzije where verzija_obmocja = 8 ) vr
where cone.model = 'PPP'
  and verzija = 225;
update md_verzije_modeli vm set id_rel_geo_verzija = geo.id from md_geo_obm_verzije geo where geo.verzija_obmocja = 8 and vm.model = 'PPP' and vm.verzija = 225;

------------------------------------------------------------------------------------------------------------------------
-- TUR
------------------------------------------------------------------------------------------------------------------------
-- md_geo_obm_verzije
insert into md_geo_obm_verzije (id, created_by, created_at, verzija_obmocja, zaklenjena, modeli, delovna_geo_coniranje)
values (uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), 9, false, 'TUR', true);
-- md_geo_obm
insert into md_geo_obm (id, created_by, created_at, geom, id_rel_geo_verzija, ime_obmocja, gv_id)
select uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), geometry, vr.id, ime, cone.id
from primoz_gv_cone cone,
     ( select id from md_geo_obm_verzije where verzija_obmocja = 9 ) vr
where cone.model = 'TUR'
  and verzija = 42;
update md_verzije_modeli vm set id_rel_geo_verzija = geo.id from md_geo_obm_verzije geo where geo.verzija_obmocja = 9 and vm.model = 'TUR' and vm.verzija = 42;


-- md_geo_obmxcona; požene se samo enkrat, ko bodo vsi modeli zagnani
truncate md_geo_obmxcona;
insert into md_geo_obmxcona (id, created_by, created_at, id_rel_geo_obm, id_rel_geo_cona)
select uuid_generate_v4(), '00000000-0000-0000-0000-000000000000', now(), obm.id, cone.id
from md_geo_cona cone
         join md_geo_obm obm on cone.gv_id = obm.gv_id;

-- nastavitev primarne vrednosti za rezanje poligonov
update md_geo_obm set split_group_id = uuid_generate_v1() where split_group_id is null;
