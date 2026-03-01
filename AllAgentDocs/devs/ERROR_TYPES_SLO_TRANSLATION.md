# Prevod vseh tipov napak v slovenščino

Spodaj je prevod vseh aktivnih tipov napak iz kontrolnih tabel.

## obm. topološke napake (`md_topoloske_kontrole_obm.tip_topoloskega_problema`)

| Koda v bazi | Slovensko poimenovanje | Pomen |
|---|---|---|
| `prekrivanje` | prekrivanje | Dva poligona obm. se površinsko prekrivata. |
| `luknja` | luknja | Del znotraj meje `slo_meja` ni pokrit z nobenim obm. |
| `preliv` | preliv | Del geometrije obm. sega izven `slo_meja`. |

## Hierarhične napake (`md_topoloske_kontrole_hierarhija.tip_problema`)

| Koda v bazi | Predlagan slovenski prevod | Pomen |
|---|---|---|
| `missing_obm_in_cona` | `obm. v nobeni coni` | obm. v tej verziji modela ni povezano v nobeno cono. |
| `orphan_obm_ref` | `napačno obm.` | Vnos v `obmxcona` kaže na obm., ki ne obstaja (ali ni v verziji verziji obm., ki se navezuje na verzijo modela con) |
| `orphan_cona_ref` | `cona ne obstaja` | Vnos v `obmxcona` kaže na cono, ki ne obstaja. |
| `empty_cona` | `cona brez obm.` | Cona nima nobenega povezanega obm. |
| `missing_cona_in_lao` | `cona v nobenem LAO` | Cona nima nastavljenega `id_rel_geo_lao` (NULL), torej verzija modela za LAO ne more biti popolna. |
| `orphan_lao_ref_in_cona` | `LAO ne obstaja` | Cona kaže na LAO, ki ne obstaja. |
| `empty_lao` | `LAO brez cone` | LAO nima nobene cone. |
| `missing_lao_in_tao` | `LAO v nobenem TAO` | LAO nima nastavljenega `id_rel_geo_tao` (NULL), torej verzija modela za TAO ne more biti popolna. |
| `orphan_tao_ref_in_lao` | `TAO ne obstaja` | LAO kaže na TAO, ki ne obstaja. |
| `empty_tao` | `TAO brez LAO` | TAO nima nobenega LAO. |

## Opomba za razvoj

- V bazi se uporabljajo **kode** (zgornji levi stolpec), ker jih uporablja SQL logika.
- V UI in dokumentaciji lahko uporabljate slovenske nazive iz tega dokumenta.
