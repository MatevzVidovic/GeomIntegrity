




> make AgentDocs/ and write what we are doing here. Write all context for you so you can know what is up on
next sessions

We are making sql functions and triggers for topology controls of obm and then also of cone, lao, tao (we
havent implemented that next part)


Then go do this without stopping:


We want to change our system
  First make sure that 00setup actually looks good and is clear

  In the new version we want to have topoloske_kontrole_obm instead of topoloske kontrole, where we check the
  validity of obmocja like we do here (this also means we dont need the column filled with obm anymore)

  We then also need new code where we will check thecorrectness of cona, lao, and tao - but there we dont reallz
  need geometric operations, we just need to check that they encompass all obmocja for a given model, and only
  have those obmocja
  So we just need to check the ids

  A given model it goes obm - obmxcona cross table / cona / lao / tao
  A model is defined with id_rel_geo_verzija UUID
  So cona is basically defined solely by what obms it has
  And lao only by what conas it has
  And lao by what taos it has

  So we need this new validate all and new trigger (for incremental changes) that will check the correctness for these 3 tables (we already have it for obm) and write it to topoloske_kontrole, where we just need to know if cona, lao, or tao, and we need to know if id is missing or id is not found in the table we are relating to, and what that it is.


  The schema is sort of like this:



  md_geo_obm
id_rel_geo_verzija UUID
kopiran_id UUID
ime_obmocja TEXT
split_group_id UUID
id_rel_geo_verzija UUID
kopiran_id UUID
ime_obmocja TEXT


md_geo_obmxcona
id_rel_geo_obm UUID
id_rel_geo_cona UUID
id_rel_geo_obm UUID
id_rel_geo_cona UUID


md_geo_cona
id_rel_geo_lao UUID
id_rel_geo_lao_rd1 UUID
id_rel_verzije_modeli UUID
ime_cone TEXT
verificirano BOOLEAN
tip TEXT
svetilnik BOOLEAN
nacin_dol INTEGER
st_ravni INTEGER
mn INTEGER
st_prodaj INTEGER
st_vseh_prodaj INTEGER
razmerje_vr_najem_prodaja INTEGER
st_ravni_izr_med INTEGER
st_ravni_izr_avg INTEGER
st_ravni_predlog INTEGER
k_avg INTEGER
k_med INTEGER
k_sd INTEGER
e_avg INTEGER
e_med INTEGER
e_sd INTEGER
ravan INTEGER
m2_ravan INTEGER
prd INTEGER
cod INTEGER
cena_avg INTEGER
cena_m2_avg INTEGER
velikost_avg INTEGER
leto_izg_avg INTEGER
trzna BOOLEAN
id_rel_geo_verzija UUID
id_rel_geo_lao UUID
id_rel_geo_lao_rd1 UUID
id_rel_verzije_modeli UUID
ime_cone TEXT
verificirano BOOLEAN
tip TEXT
svetilnik BOOLEAN
nacin_dol INTEGER
st_ravni INTEGER
mn INTEGER
st_prodaj INTEGER
st_vseh_prodaj INTEGER
razmerje_vr_najem_prodaja INTEGER
st_ravni_izr_med INTEGER
st_ravni_izr_avg INTEGER
st_ravni_predlog INTEGER
k_avg INTEGER
k_med INTEGER
k_sd INTEGER
e_avg INTEGER
e_med INTEGER
e_sd INTEGER
ravan INTEGER
m2_ravan INTEGER
prd INTEGER
cod INTEGER
cena_avg INTEGER
cena_m2_avg INTEGER
velikost_avg INTEGER
leto_izg_avg INTEGER
trzna BOOLEAN


md_geo_lao
id_rel_geo_tao UUID
id_rel_verzije_modeli UUID
id_lao SEQUENCE
ime_lao TEXT
drugi_lao BOOLEAN
id_rel_geo_tao UUID
id_lao SEQUENCE
ime_lao TEXT
drugi_lao BOOLEAN


md_geo_tao
id_rel_verzije_modeli UUID
id_tao INTEGER
drugi_tao BOOLEAN
id_tao INTEGER
drugi_tao BOOLEAN


