# Kontrole topologije in hierarhije (kratko, v slovenščini)

Ta dokument na kratko razloži, kako delujejo kontrole, kam se zapisujejo in kaj pomenijo ID polja.

## OBM kontrole

Kaj se preverja:
- geometrijska pravilnost pokritosti znotraj `id_rel_geo_verzija`
- prekrivanja, luknje, prelivi

Izvorni podatki:
- `md_geo_obm`
- meja: `slo_meja`

Rezultati se zapisujejo v:
- `md_topoloske_kontrole_obm`

Ključna polja v rezultatih:
- `id_rel_geo_verzija`: verzija OBM, za katero velja napaka
- `tip_topoloskega_problema`: `prekrivanje`, `luknja`, `preliv`
- `id1`, `id2`:
  - `prekrivanje`: `id1` in `id2` sta ID-ja obeh konfliktnih `md_geo_obm.id` (z `id1 < id2`)
  - `preliv`: `id1` je `md_geo_obm.id`, ki preliva mejo
  - `luknja`: običajno `id1`/`id2` nista uporabljena (problem je območje luknje)
- `geom`: geometrija napake
- `povrsina`, `obseg`, `kompaktnost`: metrični opis napake

Pomen tipov napak:
- `prekrivanje`: dva OBM poligona se površinsko prekrivata
- `luknja`: del Slovenije (`slo_meja`) ni pokrit z nobenim OBM
- `preliv`: del OBM je izven `slo_meja`

## Hierarhične kontrole

Kaj se preverja:
- relacije OBM -> cona -> LAO -> TAO po `id_rel_verzije_modeli`
- manjkajoče povezave, osirotele reference, prazne entitete

Izvorni podatki:
- `md_geo_obmxcona`, `md_geo_cona`, `md_geo_lao`, `md_geo_tao`
- preslikava model -> OBM verzija prek `md_verzije_modeli.id_rel_geo_verzija`

Rezultati se zapisujejo v:
- `md_topoloske_kontrole_hierarhija`

Ključna polja v rezultatih:
- `id_rel_verzije_modeli`: modelna verzija, za katero velja napaka
- `tip_entitete`: `cona`, `lao`, `tao`
- `tip_problema`: tip hierarhične napake
- `problematicen_id`: ID problematičnega objekta ali reference (odvisno od tipa)

Kaj pomeni `problematicen_id` po tipu:
- `missing_obm_in_cona`: ID OBM, ki ni dodeljen nobeni coni
- `orphan_obm_ref`: ID OBM reference, ki ne obstaja/ni veljavna
- `orphan_cona_ref`: ID cone reference, ki ne obstaja
- `empty_cona`: ID prazne cone
- `missing_cona_in_lao`: ID cone brez LAO
- `orphan_lao_ref_in_cona`: ID LAO reference, ki ne obstaja
- `empty_lao`: ID praznega LAO
- `missing_lao_in_tao`: ID LAO brez TAO
- `orphan_tao_ref_in_lao`: ID TAO reference, ki ne obstaja
- `empty_tao`: ID praznega TAO

## Sprožanje kontrol

- Polna validacija:
  - OBM: `validate_all_topologies_single_geo_version(uuid)`, `validate_all_topologies()`
  - hierarhija: `validate_all_hierarchy(uuid)`, `validate_all_hierarchies()`
- Inkrementalno prek triggerjev:
  - `md_geo_obm` -> `validate_topology_incremental()`
  - `md_geo_obmxcona` -> `validate_obmxcona_incremental()`
  - `md_geo_cona` -> `validate_cona_lao_incremental()`
  - `md_geo_lao` -> `validate_lao_tao_incremental()`

## Kratka opomba

Kontrole ne preverjajo vsebine med različnimi verzijami med sabo, ampak vedno znotraj izbrane verzije (`id_rel_geo_verzija` ali `id_rel_verzije_modeli`).
