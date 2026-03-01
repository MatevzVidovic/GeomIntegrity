


## 2nd added task

`cone ne obstaja` should actually be `cona ne obstaja`

id_rel_verzije_modeli is a field in md_topoloske_kontrole_hierarhija and should be filled



## Added task

Actually, can you fix your commit like this pls:

  Make load_all_fns different file:
  - keep only non trigger setups and name 97_load_fns
  - make another file 98_trigger_setups where you set up the triggers


  Then in 00setup, right after dropping triggers at top, do load fns

  And only at the end of 00setup, zou do the activation of triggers

  This way the validate_all fns dont suffer from managing triggers on every insert

  In fact, make it so the validate_all fns for any model version actually drop the trigger and then reinstate it, so that they can be nicely sped up
  whenever they are called - I assume this is the way to do it by best practices - if not, tell me another way so we can discuss

## Task


You have AgentDocs and AllAgentDocs to learn about the project and where tests are and such.

look at what we are doing in AgentDocs/

Read GENERAL.md in StarterPrompts


I need you to perform this renaming of all problems as is defined in this schema of translation to slovene

I need you to update tests and test all of this thoroughly with the same strategy we were using before

Go ahead and dont stop until done



| Koda v bazi | Predlagan slovenski prevod | Pomen |
|---|---|---|
| `missing_obm_in_cona` | `obm. v nobeni coni` | obm. v tej verziji ni povezano v nobeno cono. |
| `orphan_obm_ref` | `napačno obm.` | Vnos v `obmxcona` kaže na obm., ki ne obstaja (ali ni v pravi verziji obm.) |
| `orphan_cona_ref` | `cone ne obstaja` | Vnos v `obmxcona` kaže na cono, ki ne obstaja. |
| `empty_cona` | `cona brez obm.` | Cona nima nobenega povezanega obm. |
| `missing_cona_in_lao` | `cona v nobenem LAO` | Cona nima nastavljenega `id_rel_geo_lao` (NULL), torej verzija modela za LAO ne more biti popolna. |
| `orphan_lao_ref_in_cona` | `LAO ne obstaja` | Cona kaže na LAO, ki ne obstaja. |
| `empty_lao` | `LAO brez cone` | LAO nima nobene cone. |
| `missing_lao_in_tao` | `LAO v nobenem TAO` | LAO nima nastavljenega `id_rel_geo_tao` (NULL), torej verzija modela za TAO ne more biti popolna. |
| `orphan_tao_ref_in_lao` | `TAO ne obstaja` | LAO kaže na TAO, ki ne obstaja. |
| `empty_tao` | `TAO brez LAO` | TAO nima nobenega LAO. |
