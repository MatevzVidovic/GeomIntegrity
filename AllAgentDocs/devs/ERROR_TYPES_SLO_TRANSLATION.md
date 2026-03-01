# Prevod vseh tipov napak v slovenščino

Spodaj je prevod vseh aktivnih tipov napak iz kontrolnih tabel.

## OBM topološke napake (`md_topoloske_kontrole_obm.tip_topoloskega_problema`)

| Koda v bazi | Slovensko poimenovanje | Pomen |
|---|---|---|
| `prekrivanje` | prekrivanje | Dva OBM poligona se površinsko prekrivata. |
| `luknja` | luknja | Del znotraj meje `slo_meja` ni pokrit z nobenim OBM. |
| `preliv` | preliv | Del OBM geometrije sega izven `slo_meja`. |

## Hierarhične napake (`md_topoloske_kontrole_hierarhija.tip_problema`)

| Koda v bazi | Predlagan slovenski prevod | Pomen |
|---|---|---|
| `missing_obm_in_cona` | manjkajoči OBM v coni | OBM v tej verziji ni povezan v nobeno cono. |
| `orphan_obm_ref` | osirotela referenca na OBM | Povezava `obmxcona` kaže na OBM, ki ne obstaja (ali ni v pravi verziji OBM). |
| `orphan_cona_ref` | osirotela referenca na cono | Povezava `obmxcona` kaže na cono, ki ne obstaja. |
| `empty_cona` | prazna cona | Cona nima nobenega povezanega OBM. |
| `missing_cona_in_lao` | manjkajoča cona v LAO | Cona nima nastavljenega `id_rel_geo_lao` (NULL). |
| `orphan_lao_ref_in_cona` | osirotela referenca na LAO v coni | Cona kaže na LAO, ki ne obstaja. |
| `empty_lao` | prazen LAO | LAO nima nobene cone. |
| `missing_lao_in_tao` | manjkajoči LAO v TAO | LAO nima nastavljenega `id_rel_geo_tao` (NULL). |
| `orphan_tao_ref_in_lao` | osirotela referenca na TAO v LAO | LAO kaže na TAO, ki ne obstaja. |
| `empty_tao` | prazen TAO | TAO nima nobenega LAO. |

## Opomba za razvoj

- V bazi se uporabljajo **kode** (zgornji levi stolpec), ker jih uporablja SQL logika.
- V UI in dokumentaciji lahko uporabljate slovenske nazive iz tega dokumenta.
