# Backlog de parité iOS

État au 30 octobre 2026 au soir, branche `ios/doc-3`, depuis `ios/main` au commit `2be43567`. Ce
document ferme le reste de `docs/ios/FEATURES-IOS.md` : chaque ligne ❌ ou ⚠️ y reçoit soit un lot
mergé avec sa preuve, soit un lot déjà planifié, soit un lot nouveau, soit le statut ➖. Il ne
remplace ni la matrice ni `PORTAGE_IOS.md`.

## Défauts produits ouverts

Les sept défauts produit que VAL-3 nomme, leur état sur `ios/main` au commit `2be43567`, et la
branche qui les corrige. Aucun n'est mergé : `ios/main` les porte encore tous, et aucune branche de
correctif n'a encore de run Mac.

| # | Défaut | Preuve VAL-3 | État |
|---|---|---|---|
| 1 | Une zone hors ligne téléchargée n'apparaît pas dans les régions installées | `OfflineAreaUITests.testFrameAreaAndPreferences`, `area_pct=100` puis `offline-installed-monaco` absent | corrigé, non mergé : `ios/val3-fix-core` (`5654a662`) |
| 2 | La recherche le long de la route repart de l'origine pendant la conduite | `SearchCommandUITests.testAlongRouteSkipsTheTravelledPart`, `cmd_from=origin`, `cmd_route_m=3220` | corrigé, non mergé : `ios/val3-fix-core` |
| 3 | Le bouton des options de transport n'a aucun point de toucher | `TransitTimeUITests.testTimeEverywhere`, `Computed hit point {-1, -1}` | en cours : le scénario replie le sélecteur sur `ios/val3-fix-nav`, mais il manque une entrée Options dans l'en-tête de la feuille d'itinéraire |
| 4 | La feuille de ligne du tableau s'ouvre vide sans explication | `TransitWiredUITests.testTapTransitEverywhereAndSeeTheLine`, `line_stops=0` | corrigé, non mergé : `ios/val3-fix-nav` (`b51ac977`) |
| 5 | La vue d'ensemble de conduite reste inclinée à 55 degrés | `NavCameraUITests.testThirdOfScreenZoomAndOverview`, `camtilt=55` | corrigé, non mergé : `ios/val3-fix-nav` |
| 6 | Le bandeau de guidage prend 41 % de l'écran au plus grand texte | `NavBannerUITests.testBannerAtAccessibilityXXXL`, `nav_banner_ax_fraction=0.41` | corrigé, non mergé : `ios/val3-fix-nav` |
| 7 | L'entrée « zone hors ligne » mesure 42,25 pt, sous la cible de 44 pt | `OfflineUITests` et `SettingsUITests`, `design_offline_area_height=42` | corrigé, non mergé : `ios/val3-fix-core` |

Le défaut 3 n'est donc pas fermé : le test évite le chevauchement, l'application ne l'évite pas.
Les autres familles d'échecs de VAL-3 restent du harnais et ne sont pas des défauts produit : la
fuite de la suite `vela_world` est corrigée sur `ios/val3-fix-core`, tandis que le doublon
`intents-debug`, la casse `Off` et `off`, la saisie sans focus, le menu de session touché pendant le
défilement et la scène GO pre-démarrée restent ouverts.

## État au 30 octobre (soir)

La matrice compte 204 lignes, régénérées par `python3 scripts/ios/parity_check.py --md`. Quatre
lignes passent de ⚠️ à 🟡 dans ce lot, sur preuve VAL-3 : L47-L48 (onglets de la fiche lieu), L61-L64
(carburant et fermeture), L106-L108 (arrêt ajouté en conduite) et L110-L111 (réglage vélo).

| Statut | Lignes | Part du total |
|---|---:|---:|
| ✅ validé sur iPhone | 2 | 1,0 % |
| 🟡 testé sur simulateur | 102 | 50,0 % |
| ⚠️ partiel | 53 | 26,0 % |
| ❌ absent | 28 | 13,7 % |
| ➖ sans équivalent iOS | 19 | 9,3 % |
| **Total** | **204** | **100,0 %** |

La parité testée sur simulateur ou mieux atteint donc 51,0 % (104 lignes), et 39,7 % des lignes
restent partielles ou absentes (81 lignes). Ce lot n'ajoute aucune validation iPhone : les 102
lignes 🟡 reposent sur des runs simulateur, et VAL-3, 139 tests dont 113 verts, est la dernière
passe de référence.

### Lots mergés et ouverts

| Périmètre | Lots | Mergés | Abandonné | Partiel | Ouverts |
|---|---:|---:|---:|---:|---:|
| 38 lots de parité de ce document | 38 | 38 | 0 | 0 | 0 |
| 4 lots planifiés suivis ici | 4 | 4 | 0 | 0 | 0 |
| 17 lots produits depuis le 27 octobre | 17 | 17 | 0 | 0 | 0 |
| 13 lots de phase 8 | 13 | 11 | 1 | 1 | 0 |
| 23 lots nés ou ouverts les 29 et 30 octobre | 23 | 23 | 0 | 0 | 0 |
| 17 lots nés le 30 octobre après la synchronisation de 02 h | 17 | 17 | 0 | 0 | 0 |
| **Total** | **112** | **110** | **1** | **1** | **0** |

Les six lots qui restaient ouverts à 02 h sont mergés depuis : `REVIEWS-REG` (`d105d51b`),
`HARNESS-2` (`2d861dce`), `HARNESS-FIX` (`8ba24b03`), `A11Y-W4` (`b7422808`), `TRANSIT-POLISH`
(`469f57e5`) et `CLOSING-MIDNIGHT` (`a8db0e70`). Aucun lot n'est ouvert. Deux ne sont pas fermés
pour autant : `T-2` reste partiel, seules les alternatives `via` manquent désormais puisque
`T2-REACH` livre la zone atteignable, et `A-4` reste abandonné, l'accès OAuth2 à la FAA NMS n'étant
pas accordé. `ios/val3-fix-core` et `ios/val3-fix-nav` ne sont pas des lots planifiés de ce backlog :
ce sont deux branches de correctif nées de VAL-3, comptées dans la section « Défauts produits
ouverts » et non dans ce tableau.

### Ce qui bloque quoi

Les branches de correctif sont les seules à tenir des voies. Elles ne modifient aucun fichier
commun hors `docs/ios/VAL-3.md`, qui les fera conflit à la fusion : `VAL3-FIX-CORE` passe d'abord,
`VAL3-FIX-NAV` rebase sa ligne ensuite.

| Voie | Fichiers | Tenue par | Effet |
|---|---|---|---|
| A | `MapScreen.swift` | personne | voie libre ; `TRANSIT-OPTIONS-HOOK` en a besoin pour l'entrée Options |
| B | `RouteSheets.swift` | personne | voie libre ; `TRANSIT-OPTIONS-HOOK` y pose l'en-tête épinglé |
| C | `SettingsScreen.swift` | personne | voie libre depuis `A11Y-W4` |
| D | `MapController.swift`, `MapView.swift` | `VAL3-FIX-NAV` | `VAL3-FIX-NAV` corrige la caméra d'ensemble |
| Nav | `iosApp/Vela/Nav/NavChrome.swift` | `VAL3-FIX-NAV` | le bandeau AX XXXL y est corrigé |
| Transit | `iosApp/Vela/Transit/*.swift` | `VAL3-FIX-NAV` | feuille de ligne et cockpit transport |
| Search | `SearchModel.swift` | `VAL3-FIX-CORE` | progression du corridor le long de la route |
| Offline | `iosApp/Vela/Offline/*.swift`, `OfflineStore.kt` | `VAL3-FIX-CORE` | zone installée et cible de 44 pt |
| Place | `iosApp/Vela/Place/*.swift`, `ClosingTime` commun | personne | voie libre depuis `CLOSING-MIDNIGHT` |
| Tests | `iosApp/VelaUITests/*.swift` | `VAL3-FIX-CORE` (`Offline*`, `SearchCommand*`), `VAL3-FIX-NAV` (`Nav*`, `Transit*`) | les deux branches ne se croisent sur aucun fichier de test |

`A-4` n'est plus un verrou : son verdict est rendu, la couche reste désactivée et la ligne de la
matrice garde « FAA credentials required ».

### Trois prochains lots

1. **`VAL3-FIX-CORE`** (`M`) : la branche `ios/val3-fix-core` porte un commit (`5654a662`) qui
   corrige trois défauts produit et la fuite de `vela_world`. Elle tient les voies Search et
   Offline et ne demande aucun nouveau code : un run Mac, la lecture des lignes
   `area_installed=1`, `cmd_line=nav`, `offline_area_entry_height` et le merge. C'est le lot qui
   rend la promesse hors ligne vraie.
2. **`VAL3-FIX-NAV`** (`M`) : la branche `ios/val3-fix-nav` porte un commit (`b51ac977`) qui corrige
   la caméra d'ensemble, le bandeau AX XXXL et la feuille de ligne. Elle tient les voies D, Nav et
   Transit. Même règle : un run Mac, puis le merge, après `VAL3-FIX-CORE`.
3. **`TRANSIT-OPTIONS-HOOK`** (`S`) : le seul défaut produit qui reste sans correctif écrit. Il
   ajoute une entrée Options dans l'en-tête épinglé de `RoutePickerSheet`, ou masque la colonne
   d'actions sous le panneau déplié, pour que `transit-options-open` ait un point de toucher quand
   la feuille est ouverte. Voies A et B, libres. Il rejoue `TransitTimeUITests.testTimeEverywhere`
   sans le repli du scénario.

Deux lots peuvent suivre sans bloqueur : `T2-VIA` pour la dernière ligne de `T-2` (l'alternative
`via` d'un trajet et sa capture `transit-via.png`), et `VAL-4` pour rejouer la suite entière sur
`ios/main` une fois les trois lots ci-dessus mergés.

## 1. Ce que ce backlog compte

La matrice contient 204 lignes. Au 30 octobre au soir, 123 lignes sont acquises (2 ✅, 102 🟡,
19 ➖) et 81 restent ❌ (28) ou ⚠️ (53). Le découpage initial du 27 octobre annonçait 157 lignes à
fermer à partir de 47 lignes acquises ; la matrice en comptait déjà 58, et les rejeux des 28, 29 et
30 octobre ont fait monter 65 lignes, dont 59 à 🟡 et 7 de ❌ à ⚠️. Le chiffre qui fait foi est
celui de la section « État au 30 octobre (soir) », régénéré par `parity_check.py`.

L'estimation du 27 octobre reste de **136 sessions d'agent** pour les 38 lots de parité, avec une
fourchette de **115 en optimiste** et **165 en réaliste** ; les 38 lots sont maintenant mergés, donc
cette enveloppe n'est plus une projection du reste. Une session couvre l'implémentation, les tests
Linux et la préparation du scénario simulateur. Les passes iPhone restent humaines et ne sont pas
comptées.

## 2. Conventions

- **Mergé, fermé** : la fonction est dans `ios/main` et un test ou un run la prouve. Le renvoi à la
  matrice peut citer un lot plus ancien que le dernier merge.
- **Mergé, à rejouer** : le code est mergé, mais le scénario simulateur, la capture ou la passe
  iPhone manque. Le lot `VAL-1` porte ces rejeux. Il ne demande presque pas de code.
- **Planifié** : une branche existe déjà (`I-1c`, `O-3`, `L-2`) ou le lot figure dans les phases 7
  et 8 de `PORTAGE_IOS.md` (`M-1`, `T-2`, `T-3`). Ce backlog ne redécoupe pas ces lots.
- **Nouveau** : proposition de ce document. Le nom du lot peut reprendre une ancienne suggestion
  de la matrice, mais le périmètre, les fichiers et la preuve sont ceux d'ici.
- **➖** : fonction propre à Android, refusée par iOS, ou dépendante d'un entitlement absent. La
  section 6 liste les 16 groupes de lignes concernés, soit 29 lignes.
- Une ligne qui demande deux lots, comme L19-L23 ou L168-L169, est comptée une seule fois, dans la
  destination qui la ferme en dernier. Les deux lots sont cités dans la colonne Lot.
- La colonne « Prochain lot » de `FEATURES-IOS.md` est mise à jour au 30 octobre pour les lignes
  prouvées par les runs cités. Les autres colonnes gardent la destination du lot, pas son état.
  La lecture de ce backlog fait foi sur l'état du code, pas cette colonne.

## 3. Fichiers qui sérialisent la ruche

Les fichiers chauds concentrent les modifications et ne peuvent pas être édités par deux branches
en parallèle :

| Voie | Fichiers | Branche qui la tient |
|---|---|---|
| A | `iosApp/Vela/Map/MapScreen.swift` | libre ; `TRANSIT-OPTIONS-HOOK` en a besoin |
| B | `iosApp/Vela/Routes/RouteSheets.swift` | libre ; `TRANSIT-OPTIONS-HOOK` y pose l'en-tête |
| C | `iosApp/Vela/Settings/SettingsScreen.swift` | libre depuis `A11Y-W4` |
| D | `iosApp/Vela/Map/MapController.swift`, `MapView.swift` | `VAL3-FIX-NAV` |
| Nav | `iosApp/Vela/Nav/NavChrome.swift` | `VAL3-FIX-NAV` |
| Transit | `iosApp/Vela/Transit/*.swift` | `VAL3-FIX-NAV` |
| Search | `SearchModel.swift` | `VAL3-FIX-CORE` |
| Offline | `iosApp/Vela/Offline/*.swift`, `OfflineStore.kt` | `VAL3-FIX-CORE` |
| Saved | `iosApp/Vela/Saved/*.swift` | libre |
| Place | `iosApp/Vela/Place/*.swift`, `ClosingTime` commun | libre depuis `CLOSING-MIDNIGHT` |
| Tests | `iosApp/VelaUITests/*.swift` | `VAL3-FIX-CORE` et `VAL3-FIX-NAV`, sans fichier commun |

Les autres lots peuvent courir en parallèle s'ils ne partagent aucun store commun. Les gros
fichiers de vue (`PlaceSheet.swift`, `SavedViews.swift`, `NavChrome.swift`) restent des points de
conflit de fait, même s'ils ne bloquent pas la ruche entière.

## 3 bis. État des lots au 30 octobre

Chaque lot est marqué une fois. Une branche sans commit signifie que la branche a été créée depuis
`ios/main` mais qu'aucun travail n'a commencé. Un run cité sans statut est un run vert ; les runs
rouges sont nommés avec leur échec.

### 3 bis.1 Les 38 lots de parité

| Lot | Taille | État | Branche ou merge | Preuve |
|---|---|---|---|---|
| **MAP-POI** | M | Mergé | `ios/map-poi`, merge `aa4575e1` | run `map-poi-20261027-232514-13417` |
| **MAP-GESTE** | M | Mergé | `ios/map-geste`, merge `db967fd3` | run `settings-fix-20261029-080522-14080`, quatre scénarios verts |
| **MAP-STYLE** | L | Mergé | `ios/map-style`, merge `6427d847` | run `map-style-merge-20261027-220119-24997` |
| **MAP-CAM** | S | Mergé | `ios/map-cam`, merge `9b217a85` | run `map-cam-20261028-081732-9944` |
| **SRCH-CARDS** | M | Mergé | `ios/srch-cards`, merge `f17dbf42` | tests cités, aucun tag de run UI |
| **SRCH-FILTER** | M | Mergé | `ios/srch-filter`, merge `4b578d54` | run `srch-filter-20261027-202426-27986` |
| **SRCH-AREA** | S | Mergé | `ios/srch-area`, merge `ff6db81d` | run `srch-area-20261027-234526-21366` |
| **SRCH-BRANCH** | M | Mergé | `ios/srch-branch`, merge `353c9294` | tests cités, aucun tag de run UI |
| **SRCH-CMD** | M | Mergé | `ios/srch-cmd`, merge `b7735084` | run `srch-cmd-check7-20261029-180923-11072`, six commandes et contacts |
| **PLC-PAGE** | L | Mergé | `ios/plc-page`, merge `fc1e76a9` | tests cités, aucun tag de run UI |
| **PLC-REVIEW** | M | Mergé | `ios/plc-review`, merge `56e1da19` | run `val1-plcrev-20261028-025339-8681`, 3 tests verts, catégories absentes |
| **PLC-FUEL** | M | Mergé | `ios/plc-fuel`, merge `eb9cb5a7` | tests cités, aucun tag de run UI |
| **SHR-PLACE** | M | Mergé | `ios/shr-place`, merge `e93c9f34` | run `shr-place-20261028-010341-61`, échec final hors lot |
| **SV-HIST** | M | Mergé | `ios/sv-hist`, merge `b0166454` | tests cités, aucun tag de run UI |
| **RTE-PICKER** | M | Mergé | `ios/rte-picker`, merge `4f6501db` | run `rte-picker-20261027-193300-31773` |
| **RTE-CAM** | M | Mergé | `ios/rte-cam`, merge `0f4e2412` | run `rte-cam-20261027-212927-24068` |
| **RTE-STEP** | S | Mergé | `ios/rte-step`, merge `48c424fb` | `DirectionsUITests.testStepTapFocusesMap` vert dans VAL-2 B3 |
| **RTE-BIKE** | S | Mergé | `ios/rte-bike`, merge `58f80fd5` | runs `rte-bike-20261028-004741-27076` et `001302`, profil non rejoué |
| **NAV-FREEDRIVE** | L | Mergé | `ios/nav-freedrive`, merge `dd0c9c0d` | `FreeDriveUITests.testSpeedLimitRoadShieldAndSimpleMap` vert dans VAL-2 B3 |
| **NAV-BANNER** | L | Mergé | `ios/nav-banner`, merge `1bff7820` | run `nav-render-20261029-033244-31859`, quatre scénarios |
| **NAV-CAMERA** | L | Mergé | `ios/nav-camera`, merge `db2f5811` | run `nav-camera-20261029-110241-9372`, 5 scénarios UI |
| **NAV-RENDER** | L | Mergé | `ios/nav-render`, merge `0b008e78` | run `nav-render-20261029-033244-31859` |
| **NAV-LIFE** | M | Mergé | `ios/nav-life`, merge `633ea8b4` | `NavLifecycleUITests` 2 verts et `NavAlertsUITests` 3 verts dans VAL-2 B3 |
| **SET-CONTENT** | L | Mergé | `ios/set-content`, merge `1ab5a5ce` | run `settings-fix-20261029-080522-14080`, `testContentAndData` vert |
| **SET-PRIVACY** | L | Mergé | `ios/set-privacy`, merge `d312348e` | `PrivacyUITests` 4 sur 5 verts dans VAL-2 B4, compteur remis à zéro |
| **SET-VOICE** | M | Mergé | `ios/set-voice`, merge `41c233a9` | run `set-voice-20261028-045550-26220` |
| **SET-APPEARANCE** | L | Mergé | `ios/set-appearance`, merge `2a3341da` | run `set-appearance-20261029-032551-4729`, arrêt sur Show speed, corrigé sans rerun |
| **SET-ABOUT** | M | Mergé | `ios/set-about`, merge `6470f231` | run `val1-setabout-20261028-032738-12449` |
| **VO-CONTROL** | L | Mergé | `ios/vo-control`, merge `90f7aa43` | run `vo-control-20261027-185957-12567` |
| **I18N-TRANS** | M | Mergé | `ios/i18n-trans`, merge `12d163bc` | 711 chaînes localisées, `LocalizationUITests` 3 sur 4 dans VAL-2 B4 |
| **SAV-EDIT** | L | Mergé | `ios/sav-edit`, merge `71e4654b` | compilation `sav-edit-merge-20261027-185347-22573`, scénario son rouge |
| **SAV-MARK** | L | Mergé | `ios/sav-mark`, merge `f1320d6a` | tests cités, aucun tag de run UI |
| **IMP-GOOGLE** | L | Mergé | `ios/imp-google`, merge `a902ece7` | `SavedImportUITests.testGoogleListAndMyMaps` vert dans VAL-2 B2 et avec IMPORT-CONSENT |
| **OFF-AREA** | L | Mergé | `ios/off-area`, merge `58c7c1a0` | runs `offline-3-replay2-20261030-012321-17620`, trois scénarios hors ligne verts |
| **OFF-CAM** | S | Mergé | `ios/off-cam`, merge `5d38dbc9` | run `road-markings-20261029-015102-26655`, pack hors ligne vert |
| **TRIP-TRACE** | M | Mergé | `ios/trip-trace`, merge `613f8856` | run `trip-trace-20261028-141500-14306` |
| **TRIP-DIAG** | M | Mergé | `ios/trip-diag`, merge `9db92eca` | run `trip-diag-20261029-104937-27869`, `STATUS ok` |
| **VAL-1** | S | Mergé | `ios/val-1`, merge `f4210dc2` | cinq classes consignées dans `VALIDATION.md` |

### 3 bis.2 Les 4 lots planifiés suivis ici

| Lot | Taille | État | Branche ou merge | Preuve |
|---|---|---|---|---|
| **I-1c** | M | Mergé | `ios/i1c-google-layers`, merge `968e9df0` | run `i1c-google-layers-20261027-132334-4563` |
| **O-3** | L | Mergé | `ios/o3-offline-advanced`, merge `58c7c1a0` avec OFF-AREA | deltas prouvés par `offline-3-replay2-20261030-012321-17620` ; Update all reste absent |
| **L-2** | L | Mergé | `ios/l2-saved-export`, merge `7de72d2f` | runs `l2-saved-export-20261027-165047-28351` et `172143-9790` |
| **T-3** | L | Mergé, scénario fermé | `ios/t3-transit`, merge `f57c68d9` | scénario `no shifted query label` vert au run `time-1-20261029-135605-1203` |

### 3 bis.3 Les 17 lots produits depuis le 27 octobre

| Lot | Taille | État | Branche ou merge | Preuve |
|---|---|---|---|---|
| **TRANSIT-MODES** | M | Mergé | `ios/transit-modes`, merge `ba6a1017` | run `transit-modes-20261028-184626-17169` |
| **TRANSIT-INTERP** | M | Mergé | `ios/transit-interp`, merge `ca2b27c7` | run `transit-interp-20261028-214039-2108` |
| **TRANSIT-LINEVIEW** | M | Mergé | `ios/transit-lineview`, merge `e516fc4d` | trois runs, dernier `transit-lineview-20261028-161722-29244` vert à la compilation |
| **TRANSIT-GO** | L | Mergé | `ios/transit-go`, merge `6fc30a4a` | run `transit-go-20261028-230148-11678` |
| **TRANSIT-WIRE** | M | Mergé, confirmation perdue | `ios/transit-wire`, merge `76fe6437` | run `transit-wire-20261028-234454-7929` ; `transit-wire-20261029-002131-24451` sans `STATUS` |
| **UX-GOOGLE** | M | Mergé | `ios/ux-google`, merge `17db0b25` | `DESIGN.md` et `DESIGN-AUDIT.md`, jetons seuls, aucun écran |
| **SPIKE-3D** | M | Mergé | `ios/spike-3d`, merge `173840e6` | `TERRAIN-SPIKE.md`, runs `spike-3d-20261028-170222-26786` et `171055-20256` |
| **OFFLINE-FIX** | M | Mergé | `ios/offline-fix`, merge `5de188d5` | `VALIDATION.md`, Monaco vert aux runs `offline-verify`, 2 et 3 |
| **SETTINGS-FIX** | S | Mergé | `ios/settings-fix`, merge `669633b8` | run `settings-fix-20261029-080522-14080`, `STATUS ok` |
| **MAP-TAP** | L | Mergé, run UI non cité | `ios/map-tap`, merge `8e5e8391` | `MapTapRegistryTests` et `MapTapUITests` cités sans tag |
| **UNIFIED-SEARCH** | L | Mergé, run partiel | `ios/unified-search`, merge `661f34a2` | run `unified-search-20261028-172057-20579`, `line` rouge puis corrigé sans rerun |
| **TREES-LAYER** | M | Mergé | `ios/trees-layer`, merge `6a1dfc1c` | run `trees-layer-20261029-003202-16603` |
| **ROAD-MARKINGS** | L | Mergé | `ios/road-markings`, merge `9991ae4f` | run `road-markings-20261029-015102-26655` |
| **START-LOCATION** | S | Mergé | `ios/start-location`, merge `6fa5819e` | run `start-location-20261028-182329-30819` |
| **IMPORT-SHORTLINK** | S | Mergé | `ios/import-shortlink`, merge `d563aa33` | run `import-shortlink-20261028-140858-1916` |
| **POI-RESOLVE** | S | Mergé | `ios/poi-resolve`, merge `1df4da4f` | run `chrome-replay` et `MapPoiResolveUITests`, deux scénarios verts |
| **X-4-WIDGETS** | M | Mergé | `ios/x4-widgets2`, merge `a5e6c942` | run `x4-widgets2-20261029-190659-18916`, `STATUS ok`, cible `VelaWidgets` compilée |

### 3 bis.4 Les 13 lots de phase 8

Le détail de ces lots est dans [BACKLOG-PHASE8.md](BACKLOG-PHASE8.md). Ils sont comptés ici pour que
l'état de la ruche tienne en un seul tableau.

| Lot | Taille | État | Branche ou merge | Preuve |
|---|---|---|---|---|
| **WLD-1** | S | Mergé | `ios/wld-1`, merge `66e3ca7e` | run `wld-1-20261028-110902-546` |
| **M-1** | M | Mergé | `ios/m1-3d`, merge `c3292ec2` | run `m1-3d-green-20261029-142113-3419`, `Map3DUITests` vert |
| **M-2** | L | Mergé | `ios/m2-terrain`, merge `77bba6cb` | run `m2-terrain-20261029-215904-20492`, `terrain_web=1` et `terrain_dem=1` |
| **G-1** | M | Mergé | `ios/g1-globe`, merge `ae82a2d9` | `GLOBE-SPIKE.md`, runs `g1-globe-20261028-132357-18120` et `134040-28343` |
| **G-2** | L | Mergé | `ios/g2-globe`, merge `9702956a` | run `g2-globe-20261029-192003-25030`, `globe_projection=globe` et `globe_offline_remote=0` |
| **T-2** | L | Partiel, lignes et courses mergées | `ios/t2-transit`, merge `709c17b1` ; `T2-WIRE`, merge `4f9124df` | runs `t2-transit-20261028-115354-27621` et `t2-wire-replay7-20261030-000105-13051` ; zone atteignable et `via` restent à finir |
| **TIME-1** | M | Mergé | `ios/time-1`, merge `79472763` avec I18N-TRANS | run `time-1-20261029-135605-1203`, `testTimeEverywhere` vert |
| **A-1** | M | Mergé | `ios/a1-adsb`, merge `5d28aa19` | run `a1-adsb-20261028-122341-29296` |
| **A-2** | L | Mergé | `ios/a2-marine`, merge `bc310874` | run `a2-marine-20261028-124040-18722` |
| **A-3** | L | Mergé | `ios/a3-energy`, merge `d6e4c4ed` | run `a3-energy-20261028-134410-18809` |
| **A-4** | M | Abandonné | merge `ede6b42e` | run `a4-notam-20261030-012657-24873`, couche « not installed », aucune requête |
| **G-3** | M | Mergé | `ios/g3-satellites`, merge `7c5c4cff` | run `g3-satellites-20261029-224144-1973`, SGP4 à moins de 0,1 km |
| **W-1** | L | Mergé | `ios/w1-wiki`, merge `f23ed326` | runs `w1-wiki-20261028-121356-27419` et `123655-16128` |

### 3 bis.5 Les 23 lots nés ou ouverts les 29 et 30 octobre

Ces lots ne figuraient pas dans la synchronisation du 29 octobre. `REVIEWS-REG` est proposé par
VAL-2; les autres sont des branches ou des merges réels. Une preuve sans tag de run est signalée
comme telle.

| Lot | Taille | État | Branche ou merge | Preuve |
|---|---|---|---|---|
| **DESIGN-W1** | L | Mergé | `ios/design-w1`, merge `67c4129b` | `SettingsUITests.testDesignTokensApplied`, captures `design-settings.png`, `design-about.png`, `design-offline.png` ; run non tagué |
| **DESIGN-W2** | L | Mergé | `ios/design-w2`, merge `644c4855` | `MapChromeUITests.testDesignDetentsMatchMapInset`, `map_inset_matches_sheet=1`, captures `design-chrome.png`, `design-detents.png` |
| **DESIGN-W3** | M | Mergé | `ios/design-w3`, merge `bacc3c24` | run `design-w3-20261030-003546-17109`, trois suites, `design-place-header.png` ; trois points de statut restent à rejouer |
| **I18N-3** | M | Mergé | `ios/i18n-3`, merge `80f108d1` | 49 clés, `LocalizationUITests` 3 sur 4 dans VAL-2 B4, captures `terrain-fr` et `satellite-pass-fr` |
| **OFFLINE-3** | M | Mergé | `ios/offline-3`, merge `fc486f9d` | run `offline-3-replay2-20261030-012321-17620`, trois scénarios verts |
| **PERF-1** | M | Mergé | `ios/perf-1`, merge `0af70499` | run `perf-1-20261029-194720-12536`, première image à 2 273 ms contre 2 703 ms, 430 ms de moins |
| **SRCH-ALONG** | M | Mergé | `ios/srch-along`, merge `04ed9e18` | run `srch-along-check5-20261029-225405-21474`, `cmd_from=progress`, 39 lieux |
| **T2-WIRE** | M | Mergé | `ios/t2-wire`, merge `4f9124df` | run `t2-wire-replay7-20261030-000105-13051`, lignes et courses sur la carte |
| **AO-PLAN** | S | Mergé | `ios/ao-plan`, merge `2b0d85f4` | verdict lien seulement dans `BACKLOG-PHASE8.md` section 3.6 |
| **AO-1** | S | Mergé | `ios/ao-obscura`, merge `f0b42b73` | run `ao-check2`, `obscura_action=atlas_nearby`, feuille Safari fermée |
| **AO-2** | S | Mergé | `ios/ao-obscura`, merge `f0b42b73` | run `ao-check2`, `obscura_action=gastro_places`, aucun contenu lu |
| **BUGFIX-CHROME** | M | Mergé | `ios/bugfix-chrome`, merge `78f3a560` | run `bugfix-chrome-20261029-151217-7647`, `chrome_overflow=0`, `tap_seen=1` |
| **BUGFIX-A11Y** | M | Mergé | `ios/bugfix-a11y`, merge `2a39c186` | run `bugfix-a11y-20261029-154830-28435`, Close trouvé et touché |
| **BUGFIX-REVIEWS** | M | Mergé, régression rouverte | `ios/bugfix-reviews`, merge `8e42d477` | run `bugfix-reviews-20261029-145914-15506` vert, puis VAL-2 B3 reproduit le blocage |
| **IMPORT-CONSENT** | M | Mergé | `ios/import-consent`, merge `e63eed6f` | runs `import-consent-20261029-134527-18741` et `142639-24281`, quatre liens courts |
| **VAL-2** | M | Mergé | `ios/val-2`, merge `eb5ef221` | `VAL-2.md`, 123 tests, 99 verts, 24 triés |
| **BUG-HUNT** | S | Mergé | `ios/bug-hunt`, merge `5d743874` | `BUG-HUNT.md`, 50 échecs triés avec leur preuve |
| **REVIEWS-REG** | M | Mergé | `ios/reviews-reg`, merge `d105d51b` | run `reviews-reg-20261030-031615-22545`, le glissement ne bloque plus la boucle ; `PlaceReviewsUITests` 4 sur 4 dans VAL-3 B4 |
| **HARNESS-FIX** | M | Mergé | `ios/harness-fix`, merge `8ba24b03` | runs `harness-fix-20261029-160741-26596` et `171027-15750` sur la branche, puis `harness-2` sur `ios/main` |
| **HARNESS-2** | S | Mergé | `ios/harness-2`, merge `2d861dce` | runs `harness-2-20261030-021429-28682` et `harness-2c-20261030-033716-10838`, sept échecs de harnais fermés ; VAL-3 en compte encore quatorze, d'une autre famille |
| **A11Y-W4** | M | Mergé | `ios/a11y-w4`, merge `b7422808` | balayage AX3, AX5, RTL et sombre ; les runs de mesure sont ceux d'`A11Y-SPLIT`, qui le reprend après le merge |
| **TRANSIT-POLISH** | M | Mergé | `ios/transit-polish`, merge `469f57e5` | `TransitPolishUITests` vert dans VAL-3 B4, avec `TransitAdvancedUITests` 4 sur 4 |
| **CLOSING-MIDNIGHT** | S | Mergé | `ios/closing-midnight`, merge `a8db0e70` | `PlaceFuelUITests` 3 sur 3 dans VAL-3 B4, dont `testClosingCountdownAcrossMidnight` |

### 3 bis.6 Les 17 lots nés le 30 octobre après la synchronisation de 02 h

Ces lots sont arrivés entre la fusion de `DOC-2` (`e6521a33`, 02 h 27) et celle de `VAL-3`
(`2be43567`, 17 h 59). SDP4 et CELESTRAK-GPS prolongent G-3, T2-REACH ferme la zone atteignable de
T-2, et les autres sont des correctifs nés des runs de la journée.

| Lot | Taille | État | Branche ou merge | Preuve |
|---|---|---|---|---|
| **SDP4** | M | Mergé | `ios/sdp4`, merge `a4c09d31` | run `sdp4-20261030-061629-9706`, `STATUS ok`, GPS, Molniya et géostationnaires propagés par période, fixtures à 1e-8 km |
| **CELESTRAK-GPS** | M | Mergé | `ios/celestrak-gps`, merge `4b0454ad` | run `celestrak-gps-20261030-122838-9961`, `STATUS ok`, constellation `gnss` avec plafond mixte, `SatelliteUITests` vert |
| **T2-REACH** | L | Mergé | `ios/t2-reach`, merge `0c5316a7` | run `t2-reach-20261030-065045-13675`, `reach_stops=14`, `reach_hull=1`, captures `transit-reach.png` et `transit-reach-hull.png` |
| **LAYER-INFO** | M | Mergé | `ios/layer-info`, merge `2b243047` puis correctif `ac350fa8` | `LayerInfoParityTests`, `LayerInfoUITests.testLegendAndInfoParity` ; le correctif remet les interrupteurs raster au-dessus de la légende |
| **TERRAIN-ROBUST** | M | Mergé | `ios/terrain-robust`, merge `13006df4` | run `terrain-robust-20261030-121842-7441`, `TerrainUITests` vert en 44,1 s, un démarrage lent n'est plus « indisponible » |
| **A11Y-SPLIT** | M | Mergé | `ios/a11y-split`, merge `b27ddd12` | run `a11y-split-c-20261030-164422-26120`, quatre méthodes sous huit minutes, seize cas mesurés, six défauts de cible localisés |
| **PLACE-HARNESS** | M | Mergé | `ios/place-harness`, merge `51fd5631` | run `place-harness-20261030-073112-2886`, six tests verts sur fixture enregistrée |
| **PERF-GUARD** | M | Mergé | `ios/perf-guard`, merge `2060b84f` | run `perf-guard-20261030-060102-30546`, budgets relatifs : `reviews_swipe` 0,21 et `cold_start` 0,90 du budget |
| **DRIVE-SEARCH** | L | Mergé | `ios/drive-search`, merge `a739cd2c`, puis correctifs `ab39fad6` | `DriveSearchUITests.testSearchAndAddStopDuringDrive` vert dans VAL-3 B4 |
| **QUALITY-REG** | M | Mergé | `ios/quality-reg`, merge `596ec9ed` | runs `quality-reg-20261030-023147-27266` et `030119-30444`, deux scénarios verts sur dix mesurés |
| **SCROLL-FIX** | M | Mergé | `ios/scroll-fix`, merge `6c26f7cb` | runs `scroll-fix-20261030-045326-7955` et `054220-14800`, `place_photos_ax5=1`, sept scénarios Directions verts |
| **SCROLL-AX3** | S | Mergé | `ios/scroll-ax3`, merge `231a60e2` | run `scroll-ax3-20261030-082419-19490`, huit scénarios Directions verts, `route_scroll_frame=354x321` |
| **GO-ANCHOR** | S | Mergé | `ios/go-anchor`, merge `94283717` | run `go-anchor-20261030-094425-10342`, `go_anchor=board` puis `go_anchor=now` avec notice |
| **I18N-4** | M | Mergé | `ios/i18n-4`, merge `a5ed484e` | cinq libellés et deux voisins catalogués, pluriels couverts ; `LocalizationUITests` 5 sur 7 dans VAL-3, la ligne GO en préparation échoue par la couture de test et non par la clé |
| **UX-JOURNEY** | L | Mergé, verdict non rejoué | `ios/ux-journey`, merge `7a28306e` | run `ux-journey-20261030-123801-7005`, `PlaceUITests` et `SearchUITests` verts, quatre `journey_n=fail` par le harnais ; corrections non rejouées faute de budget |
| **VAL-3** | L | Mergé | `ios/val-3`, merge `2be43567` | `VAL-3.md`, 139 tests, 113 verts, 26 rouges triés, sept défauts produit localisés |
Les deux branches de correctif `ios/val3-fix-core` (`5654a662`) et `ios/val3-fix-nav` (`b51ac977`)
ne figurent pas dans ce tableau : elles ne sont ni planifiées ni mergées, et elles attendent leur
run Mac. Leur contenu est détaillé dans la section « Défauts produits ouverts ».

## 4. Lots nouveaux

### 4.1 Carte

| Lot | Taille | Couvre | Fichiers | Dépend de | Preuve d'acceptation | Risque principal |
|---|---|---|---|---|---|---|
| **MAP-POI** | M | L10-L11, L12-L13, L291-L292 | `LayersView.swift`, `MapLayers.swift`, `LayersStore.kt`, `MapPoiModel.swift`, ressources POI | I-1b | `LayersStoreTest` sur les trois sources et la taille d'icône ; `MapLayersUITests.testPoiSourceAndIconSize` avec `poi=vela` et `tiles=0` après déplacement | aucun paquet de POI Vela n'est livré aujourd'hui ; sans lui, la source Vela ne peut pas dessiner autre chose que les tuiles |
| **MAP-GESTE** | M | L16-L18, L38-L40, L264 | `MapView.swift`, `MapController.swift`, `MapScreen.swift`, `SettingsScreen.swift`, `SettingsModel.swift` | I-1b | `MapGestureUITests.testRotationReturnsNorth`, `testKeepNorthUp`, `testStartPosition` ; captures échelle, boutons de zoom et boutons carrés | gestes MapLibre et appui long ; sérialise MapScreen, SettingsScreen et MapController |
| **MAP-STYLE** | L | L8-L9, L19-L23 (styles), L27-L28, L35-L37, L306-L309 | style Liberty, `MapDefaults.swift`, `LayersView.swift`, `MapController.swift`, `OfflineStyleFactory.swift` | I-1b | captures des cinq styles, numéros à z15, bâtiments manquants, noms en trois modes ; `OfflineTests` à zéro URL distante | le style Liberty n'a pas de couche de numéros ni de sorties ; il faut une source ou un style dérivé |
| **MAP-CAM** | S | L200 | `MapLayers.swift`, `LayersStore.kt`, `LayersView.swift` | I-1b | `MapLayersTests` sur l'orientation, capture des caméras avec leur cap | le tag `direction` est inégalement renseigné dans OSM |

### 4.2 Recherche

| Lot | Taille | Couvre | Fichiers | Dépend de | Preuve d'acceptation | Risque principal |
|---|---|---|---|---|---|---|
| **SRCH-CARDS** | M | L77-L78 | `SearchModel.swift`, `SearchViews.swift`, `SearchPanels.swift`, `SearchStore.kt` | I-2b | `SearchUITests.testSuggestionPriorityAndArrow`, `testResultCardFields` ; capture d'une carte avec photo et statut | champs Google et requêtes photo supplémentaires |
| **SRCH-FILTER** | M | L79-L81 | `SearchModel.swift`, `SearchPanels.swift`, `SearchStore.kt`, `SearchParser.kt` | I-2b | tests JVM des paramètres Open now, note, prix et accès ; `SearchUITests.testFiltersAndSort` | Photon ne porte pas tous les filtres ; il faut masquer ou dégrader avec NoGoogle |
| **SRCH-AREA** | S | L82 | `SearchModel.swift`, `SearchPanels.swift`, `MapSession.kt` | I-2b | `SearchUITests.testSearchThisAreaAndMoreResults`, doublons à zéro | sérialise MapScreen si le viewport vient de la carte |
| **SRCH-BRANCH** | M | L83-L87 | `PlaceSheet.swift`, `PlaceModel.swift`, `SearchPanels.swift`, `SettingsScreen.swift` | I-2b | tests des succursales et de l'éditeur de raccourcis ; capture de la puce More | requête Google supplémentaire ; SettingsScreen sérialisé |
| **SRCH-CMD** | M | L88, L92, L93 | `MapScreen.swift`, `SearchModel.swift`, `VoicePlanner.swift`, contacts, `RouteStore.kt` | VO-2, R-1 | `QueryIntentTest` sur le texte tapé, scénario contacts, recherche le long de la route | permission Contacts et vie privée ; MapScreen sérialisé |

### 4.3 Fiche lieu et partage

| Lot | Taille | Couvre | Fichiers | Dépend de | Preuve d'acceptation | Risque principal |
|---|---|---|---|---|---|---|
| **PLC-PAGE** | L | L44-L48, L52, L58-L60 | `PlaceModel.swift`, `PlaceSheet.swift`, `PlaceCard`, fetchers Web | N-1, P-1 | `PlaceUITests.testDetailsHoursTabsActionsAndRelated` ; captures des onglets et des lieux liés | Menu et Updates peuvent manquer chez Google ; ne rien inventer |
| **PLC-REVIEW** | M | L49-L51 | `ReviewsPanel.swift`, `GalleryViews.swift`, `PopularTimesView.swift`, `PlaceModel.swift` | P-1 | `PlaceUITests.testReviewsHistogramGalleryAndViewer` ; captures catégories, avis et affluence | harnais P-1 et Q-1 encore rouge ; données de catégories |
| **PLC-FUEL** | M | L61-L64, L116 | `PlaceCard`, `FuelGb.kt`, `ClosingTime.kt`, `RouteStore.kt`, `NavStore.kt` | C-3b, N-4 | `FuelGbTest`, `ClosingTimeTest`, `PlaceUITests.testFuelAndClosure` ; capture | couverture Fuel Finder au Royaume-Uni et en Irlande du Nord ; prix US absent sans Google |
| **SHR-PLACE** | M | L53, L115 | `PlaceSheet.swift`, `SavedModel.swift`, `ActivityView.swift`, `RouteSheets.swift` | L-1 | `ShareUITests.testPlaceShareContentsAndRouteText` | pas d'API de lien court sortant ; RouteSheets sérialisé |
| **SV-HIST** | M | L65-L66 | `StreetViewModel.swift`, `StreetViewView.swift`, `StreetViewCache.kt` | SV-1 | `StreetViewTests` sur l'historique et le cône, run iPhone `sv-hist` | métadonnées historiques Google et orientation des tuiles |

### 4.4 Itinéraires

| Lot | Taille | Couvre | Fichiers | Dépend de | Preuve d'acceptation | Risque principal |
|---|---|---|---|---|---|---|
| **RTE-PICKER** | M | L104-L105, L117, L297 | `RouteSheets.swift`, `RouteModel.swift`, `RouteStore.kt` | R-1, R-2 | `DirectionsUITests.testRoutePickerStyleAndTrafficOnDemand` ; capture des deux présentations | RouteSheets sérialisé ; trafic seulement avec Google |
| **RTE-CAM** | M | L109, L201-L203 | `RouteStore.kt`, `CameraDetour.kt`, `RouteSheets.swift`, `RouteOptions.swift` | R-2 | `CameraDetourTest` sur le comptage et les variantes, `DirectionsUITests.testAvoidCameras` | qualité et temps des détours ; `CameraDetour` commun à étendre |
| **RTE-STEP** | S | L112 | `RouteSheets.swift`, `MapController.swift` | M-4 | `DirectionsUITests.testStepTapFocusesMap` | RouteSheets et MapController sérialisés |
| **RTE-BIKE** | S | L110-L111 | `SettingsScreen.swift`, `RouteStore.kt`, `RoutingPrefs` | R-2 | `RouteStoreTest` sur la persistance, scénario vélo | SettingsScreen sérialisé |

### 4.5 Navigation

| Lot | Taille | Couvre | Fichiers | Dépend de | Preuve d'acceptation | Risque principal |
|---|---|---|---|---|---|---|
| **NAV-FREEDRIVE** | L | L30-L34, L106-L108, L178-L180 | `MapScreen.swift`, `NavModel.swift`, `NavChrome.swift`, `RouteSheets.swift`, `MapLayers.swift` | N-4, R-1 | `FreeDriveUITests`, `NavStopsUITests` ; captures vitesse, limite, arrêt ajouté et carte simplifiée | plus gros changement du backlog ; trois fichiers sérialisés, session et recalcul |
| **NAV-BANNER** | L | L121-L123, L138-L140, L154-L157 | `NavChrome.swift`, `NavModel.swift`, `NavStore.kt`, `NavStrings` | M-5, N-2 | `NavBannerUITests` sur écussons, voies, balayage, ETA par arrêt ; captures | le modèle commun n'a ni écussons ni voies ; mise en page en grands textes |
| **NAV-CAMERA** | L | L124-L125, L126-L129, L162 | `MapController.swift`, `NavModel.swift`, `NavChrome.swift`, `SettingsScreen.swift` | M-5 | `NavCameraUITests` sur le tiers d'écran, le zoom vers la manœuvre et Overview | MapController sérialisé ; calcul de caméra |
| **NAV-RENDER** | L | L144, L150-L151, L152-L153, L158-L159 | `MapController.swift`, `RouteLayers.swift`, `NavModel.swift`, `RouteBar.kt` | M-4, N-2 | `NavRenderUITests` sur la ligne congestion, le gris, Road ahead, les flèches et l'écusson ; captures | nombreuses couches et mises à jour par image, performance |
| **NAV-LIFE** | M | L168-L169, L171, L208-L209, L210-L211 | `NavModel.swift`, `NavStore.kt`, `NavChrome.swift`, `NavHaptics.swift`, notifications | N-3, N-4 | `NavLifecycleTests` sur la reprise, `NavAlertsUITests` sur Alerts only et le pont ; captures | permission de notification ; pas de push ; la mini-carte reste ➖ |

### 4.6 Réglages, confidentialité et voix

| Lot | Taille | Couvre | Fichiers | Dépend de | Preuve d'acceptation | Risque principal |
|---|---|---|---|---|---|---|
| **SET-CONTENT** | L | L67-L72, L233, L377 | `SettingsScreen.swift`, `PlaceModel.swift`, fetchers, `RemoteImage.swift`, `TripScrub.kt` | P-1, DG-1 | `SettingsUITests.testContentAndData` ; tests de politique photo et de purge | SettingsScreen et MapScreen sérialisés ; cohérence entre natif et WebView |
| **SET-PRIVACY** | L | L284-L287, L290, L293, L296, L298 | `SettingsScreen.swift`, `PrivacyScreen.swift`, `PrivacySettings.swift`, `MapScreen.swift`, `MapPoiModel.swift`, `GoogleRequestCounter` | PR-1 | `PrivacyUITests.testConsentAndFullPrivacyPage`, `testRequestCounterAndClearHistory` | consentement au premier lancement ; deux fichiers sérialisés |
| **SET-VOICE** | M | L130, L136-L137, L239, L249-L251 | `SettingsScreen.swift`, `SettingsModel.swift`, `NavModel.swift`, `VelaNavVoice.swift`, `NavChrome.swift`, `RouteModel.swift` | VO-1, I-8 | `SettingsUITests.testVoiceAndLanguage`, `NavFormatTest` sur l'horloge | SettingsScreen sérialisé ; voix disponible par langue |
| **SET-APPEARANCE** | L | L141, L147, L163-L167, L181-L182, L304-L305, L312-L313 | `SettingsScreen.swift`, `NavModel.swift`, `NavHaptics.swift`, `MapController.swift`, thème | Q-2, I-8 | `SettingsUITests.testThemesSpeedAndVehicle` ; captures thèmes, icône et police | SettingsScreen et MapController sérialisés ; droits de police et Dynamic Type |
| **SET-ABOUT** | M | L315, L363-L365 | `SettingsScreen.swift`, `SettingsModel.swift`, `Notice`, bundle | I-8 | `SettingsUITests.testHubSearchAboutNoticesSupport` | nom de l'installeur difficile à obtenir sur iOS ; politique de don |
| **VO-CONTROL** | L | L240-L245 | `Voice/*.swift`, `VoiceSettingsSection`, `SpeechText.kt` | VO-1, VO-2 | `VoiceTests` sur volume, vitesse, nivellement et lexique ; écoute iPhone | sessions audio et taille du lexique |
| **I18N-TRANS** | M | L246-L247 | `*.xcstrings`, `VelaL10n.swift`, mise en page | I-8, Q-2 | `LocalizationUITests` CJK et RTL ; audit des nouvelles vues | 24 locales, dérive du catalogue et harnais Q-2 |

### 4.7 Lieux enregistrés, hors ligne et trajets

| Lot | Taille | Couvre | Fichiers | Dépend de | Preuve d'acceptation | Risque principal |
|---|---|---|---|---|---|---|
| **SAV-EDIT** | L | L256-L260, L269-L272 | `SavedViews.swift`, `SavedStore.kt`, `SavedModel.swift`, `NavStore.kt` | I-6, L-1 | `SavedUITests.testListEditingSelectionAndSound` ; captures éditeur et mode sélection | refonte de SavedViews ; abonnement NavStore et audio |
| **SAV-MARK** | L | L261-L263, L275 | `MapController.swift`, `SavedStore.kt`, `SavedViews.swift` | I-6 | `SavedMapUITests` sur couleurs, zoom, noms, dessin et zone | MapController sérialisé ; édition de formes |
| **IMP-GOOGLE** | L | L273-L274 | `SavedStore.kt`, `SavedModel.swift`, `HiddenWebView.swift`, `MyMapKml.kt` | DL-1, DL-2 | `SavedImportUITests.testGoogleListAndMyMaps` ; fixtures KML | page de liste Google fragile ; taille KML et NoGoogle |
| **OFF-AREA** | L | L229-L231, plus le cadrage seul de L216 | `MapScreen.swift`, `OfflineSheet.swift`, `OfflineModel.swift`, `OfflineStore.kt`, `SearchViews.swift`, `PlaceCache.kt` | I-7, O-2, O-3 | `OfflineUITests.testFrameAreaAndPreferences` ; globe barré et reprise | MapScreen sérialisé ; estimation de taille et espace libre |
| **OFF-CAM** | S | L212 | ressources, `MapLayers.swift`, Overpass, `OfflineStore.kt` | I-1b, O-3 | `OfflineTests` sur les caméras hors réseau ; capture | droits et fraîcheur des données ; taille du paquet |
| **TRIP-TRACE** | M | L375-L376, L379-L380 | `TripModel.swift`, `SavedDocument.swift`, `LaunchOptions.swift`, `MapScreen.swift` | DG-1 | `TripsUITests.testFullTraceAndDemoMode` ; capture | MapScreen sérialisé ; sélecteur de dossier et vie privée |
| **TRIP-DIAG** | M | L378, L381 | `AppDelegate.swift`, `DiagnosticsView.swift`, `MapController.swift`, `MapScreen.swift` | DG-1, Q-3 | `DiagnosticsUITests.testCrashExportAndPerfOverlay` ; mesures | capture de crash et symbolication ; MapScreen et MapController sérialisés |

### 4.8 Validation

| Lot | Taille | Couvre | Fichiers | Dépend de | Preuve d'acceptation | Risque principal |
|---|---|---|---|---|---|---|
| **VAL-1** | S | L14, L29, L100-L102, L142-L143, L190, L204-L207, L232, L279, L299 | aucun code, scripts et scénarios de rejeu | merge de chaque lot concerné | un run vert par scénario et une passe iPhone datée ; captures existantes reprises | dépend d'un humain et d'un iPhone ; ne pas mélanger rejeu et nouvelle implémentation |

## 5. Lots déjà planifiés

État au 30 octobre au soir : I-1c, O-3 et L-2 sont mergés. Le scénario de changement d'heure de
T-3 est vert depuis `TIME-1`. En phase 8, M-1, M-2, G-1, G-2, G-3, SDP4, CELESTRAK-GPS, T2-REACH et
TIME-1 sont mergés ; T-2 garde sur `ios/main` ses lignes, couleurs, retards, courses et sa zone
atteignable, et seules les alternatives `via` restent à finir.

| Lot | État | Couvre | Preuve |
|---|---|---|---|
| **I-1c** | Mergé, `ios/i1c-google-layers`, merge `968e9df0` | L19-L23 (trafic et satellite) | run `i1c-google-layers-20261027-132334-4563` |
| **O-3** | Mergé, `ios/o3-offline-advanced`, merge `58c7c1a0` avec OFF-AREA | L224-L226, L228 | deltas verts au run `offline-3-replay2-20261030-012321-17620` ; Update all absent |
| **L-2** | Mergé, `ios/l2-saved-export`, merge `7de72d2f` | L265-L268, L276-L278 | runs `l2-saved-export-20261027-165047-28351` et `172143-9790` |
| **T-3** | Mergé, `ios/t3-transit`, merge `f57c68d9` | L186-L189 | scénario `no shifted query label` vert au run `time-1-20261029-135605-1203` |

Le découpage de ces lots est dans [BACKLOG-PHASE8.md](BACKLOG-PHASE8.md). Les lots `M-1`, `M-2`,
`G-1`, `G-2`, `T-2`, `A-1` à `A-4`, `G-3`, `SDP4`, `CELESTRAK-GPS` et `W-1` ajoutent des fonctions qui n'ont pas de ligne
dans `FEATURES.md`, sauf `T-2` qui ferme L24-L25. Ces lots ne font pas partie du total de 136
sessions. Le lot `TIME-1` ferme le changement d'heure de `T-3` et les lignes L186-L189 ; il est
compté dans les 48 sessions de la phase 8.

## 6. Lignes à marquer ➖

Ces 16 groupes, soit 29 lignes, ne peuvent pas atteindre ✅ sur iOS dans le périmètre actuel. La
matrice doit les passer en ➖ plutôt que de les laisser en ❌ ou ⚠️. Ce changement reste réservé au
coordinateur : la matrice ne les a pas encore passées en ➖.

| Lignes | Fonction | Raison |
|---|---|---|
| L216 | téléchargement d'une zone cadrée avec routage | le cadrage, la carte, les lieux et les adresses restent livrables par `OFF-AREA`, mais la clause routage dépend du routeur `.obf` exclu par D7. La ligne complète ne peut pas atteindre ✅. |
| L222-L223 | itinéraires hors ligne avec voix, limites et évitements | D7 exclut le routeur `.obf`; aucun autre moteur local n'est prévu. La carte, les lieux et les adresses hors ligne restent livrés. |
| L314 | désactivation des transitions et renommage du lanceur | iOS ne permet pas de renommer l'entrée du lanceur. Les transitions suivent Réduire les animations du système. |
| L316-L317 | chargement vocal au démarrage et rendu de compatibilité | le rendu de compatibilité des téléphones Android n'a pas d'équivalent MapLibre iOS. Le préchargement vocal est inutile, les modèles étant lus sur disque à la demande. |
| L321-L322 | présence dans le lanceur de la voiture | pas d'entitlement CarPlay navigation. |
| L323-L324 | accueil voiture avec raccourcis et proximité | pas d'entitlement CarPlay navigation. |
| L325-L327 | recherche voiture, aperçu et assistant | pas d'entitlement CarPlay navigation. |
| L328-L330 | écran de conduite voiture et caméra | pas d'entitlement CarPlay navigation. |
| L331-L332 | conduite libre sur l'écran voiture | pas d'entitlement CarPlay navigation. La conduite libre iPhone est couverte par `NAV-FREEDRIVE`. |
| L333-L334 | habillages et trafic de la carte voiture | pas d'entitlement CarPlay navigation. |
| L335-L337 | commandes vocales, fin, Recentrer, Overview et Pause en voiture | pas d'entitlement CarPlay navigation. |
| L338 | feux et stop sur la carte voiture | pas d'entitlement CarPlay navigation. |
| L339 | alertes caméra, vitesse et fermeture dans la voiture | pas d'entitlement CarPlay navigation. |
| L340-L341 | réglages de la voiture | pas d'entitlement CarPlay navigation. |
| L342 | trajet partagé entre téléphone et voiture | pas d'entitlement CarPlay navigation. |
| L343 | affichage des virages au combiné d'instruments | pas d'entitlement CarPlay navigation. |

Le backend de push absent ne crée pas de ➖ à lui seul : la Live Activity et la notification locale
couvrent la surface visible tant que l'app vit. Les lignes qui promettaient une mise à jour minute
par minute après une fermeture forcée restent ⚠️ avec cette limite, déjà écrite dans `PARITY.md`.

Le trafic et le satellite Google ne sont plus une raison de ➖ : `I-1c` les livre par raster, avec
les modèles d'URL communs et un repli sur le style Liberty. La limite qui les déclarait absents
n'est plus vraie.

Les lignes déjà ➖ restent ➖ et ne doivent pas être rouvertes : L170 (mini-carte Android),
L227 (carte SD), L300 (gestionnaire d'intents Android), L344 (Android Automotive), L348-L350,
L351, L352 et L353 (D-pad), L358-L362 (updater APK), L387-L391 (hors Vela).

Deux points restent à trancher, mais ne sont pas des ➖ certaines :

- L188-L189 : « Last available » n'existe pas dans l'endpoint public Transitous. `T-3` peut le
  calculer en interrogeant la fin de service, au prix de requêtes supplémentaires. Si le coût est
  refusé, la ligne reste ⚠️ avec cette limite explicite.
- L47-L48, L52 et L273 : Menu, Updates, Order, Reserve et les listes Google dépendent de données
  que Google peut ne pas servir. Le lot doit afficher la section seulement quand la donnée existe ;
  une absence de donnée ne doit pas devenir une invention.

## 7. Ordre de priorité

Cet ordre date du 27 octobre et garde sa valeur pour les lignes encore ouvertes. L'ordre de
lancement du 30 octobre au soir est celui de la section « État au 30 octobre (soir) » :
`VAL3-FIX-CORE`, `VAL3-FIX-NAV`, `TRANSIT-OPTIONS-HOOK`. Les sept défauts produit de VAL-3 passent
avant toute nouvelle ligne de matrice.

1. **Bloquants de la V1 quotidienne** : `VAL-1`, `SET-CONTENT`, `SET-PRIVACY`, `MAP-POI`,
   `MAP-GESTE`, `MAP-STYLE`, `SRCH-CARDS`, `SRCH-FILTER`, `PLC-PAGE`, `PLC-REVIEW`, `PLC-FUEL`,
   `NAV-FREEDRIVE`, `NAV-RENDER`, `NAV-CAMERA`, `SET-VOICE`, `RTE-PICKER`, `RTE-CAM`, `OFF-AREA`.
2. **Forte valeur d'usage** : `SRCH-AREA`, `SRCH-CMD`, `SHR-PLACE`, `SAV-EDIT`, `SAV-MARK`,
   `NAV-BANNER`, `NAV-LIFE`, `RTE-STEP`, `RTE-BIKE`, `SET-APPEARANCE`, `OFF-CAM`, `SV-HIST`.
3. **Longue traîne** : `SRCH-BRANCH`, `IMP-GOOGLE`, `VO-CONTROL`, `I18N-TRANS`, `SET-ABOUT`,
   `TRIP-TRACE`, `TRIP-DIAG`, `MAP-CAM`.
4. **Couches exotiques** : `M-1`, `M-2`, `G-1`, `G-2`, `T-2`, `T-3`, puis les lots additifs de la
   phase 8. Ils viennent après la parité utile et ne doivent pas fragiliser la carte actuelle.

## 8. Plan de vagues

Ce plan date du 27 octobre. Les dix vagues sont mergées et la section 3 bis.5 n'a plus aucun lot
ouvert ; les trois lots de la relance du soir sont placés dans la section « État au 30 octobre
(soir) » et ne dépendent plus des voies A à D, sauf `TRANSIT-OPTIONS-HOOK`, qui prend justement A et
B.

Une vague est un ensemble de lots qui peuvent tourner ensemble. Les colonnes A, B, C et D
rappellent les fichiers sérialisés occupés : A pour `MapScreen.swift`, B pour `RouteSheets.swift`,
C pour `SettingsScreen.swift`, D pour `MapController.swift`. Une case vide signifie que la voie est
libre pour un lot plus tardif.

| Vague | Lots | Voies occupées | Sortie |
|---|---|---|---|
| 1 | `SET-CONTENT`, `MAP-STYLE`, `MAP-POI`, `SRCH-CARDS`, `PLC-PAGE`, `VAL-1` | A, C, D | réglages de contenu, styles, POI, cartes de résultats, fiche lieu, premier rejeu |
| 2 | `MAP-GESTE`, `RTE-PICKER`, `SRCH-FILTER`, `PLC-REVIEW`, `SAV-EDIT`, `VO-CONTROL` | A, B, C, D | gestes et nord, choix d'itinéraire, filtres, avis, listes, voix |
| 3 | `NAV-FREEDRIVE`, `NAV-RENDER`, `SET-VOICE`, `PLC-FUEL`, `I18N-TRANS`, `OFF-CAM` | A, B, C, D | conduite libre, rendu de route, réglages voix, carburant, traductions, caméras hors ligne |
| 4 | `SET-PRIVACY`, `NAV-CAMERA`, `RTE-CAM`, `SV-HIST`, `IMP-GOOGLE` | A, B, C, D | confidentialité, caméra de navigation, évitement, Street View, imports Google |
| 5 | `NAV-LIFE`, `RTE-STEP`, `RTE-BIKE` | A, B, C, D | reprise et alertes, focus d'étape, réglage vélo |
| 6 | `SAV-MARK`, `SHR-PLACE`, `SRCH-AREA`, `NAV-BANNER` | A, B, D | marqueurs et dessin, partage, zone de recherche, bandeau |
| 7 | `SET-APPEARANCE`, `SRCH-CMD` | A, C, D | thèmes et conduite, commandes et contacts |
| 8 | `OFF-AREA`, `SRCH-BRANCH` | A, C, D | zone cadrée, succursales et raccourcis |
| 9 | `SET-ABOUT`, `TRIP-DIAG` | A, C, D | à propos, crash et perf |
| 10 | `TRIP-TRACE`, `MAP-CAM` | A, D | trace complète et démo, orientation des caméras |

Les voies se libèrent plus vite que le travail réel : les vagues 5 à 10 sont légères parce que les
gros lots sont déjà passés, pas parce que le reste est optionnel. `VAL-1` se rejoue après chaque
vague qui ferme une ligne, sans attendre la fin.

## 9. Effort

Cette enveloppe date du 27 octobre et couvre les 38 lots de parité, dont 33 sont mergés. Elle n'est
pas réévaluée ici.

| Vague | Sessions |
|---|---:|
| 1 | 19 |
| 2 | 24 |
| 3 | 24 |
| 4 | 21 |
| 5 | 6 |
| 6 | 15 |
| 7 | 8 |
| 8 | 8 |
| 9 | 6 |
| 10 | 5 |
| **Total nominal** | **136** |

Fourchette : **115 sessions en optimiste** si les sources ouvertes et les données Google répondent
comme prévu, **165 en réaliste** avec les reprises de harnais et les passes iPhone. Un dépassement
vers 195 reste possible si les listes Google, My Maps ou Menu exigent un scrape supplémentaire.

## 10. Mapping complet des lignes ❌ et ⚠️

Ce mapping date du 27 octobre et décrit la destination prévue de chaque ligne, pas son état au
30 octobre. La colonne Statut est le statut du 27 octobre ; elle est supersédée par
`FEATURES-IOS.md`, régénéré au 30 octobre. Les mentions « branche ouverte » décrivent aussi l'état
du 27 octobre et non le code du 30 octobre. La section 3 bis donne l'état des lots et la section 6
liste les lignes qui doivent passer en ➖.

Chaque ligne de la matrice est reprise une fois. La colonne « Destination » suit les conventions de
la section 2.

### Carte

| Lignes | Statut | Destination | Lot | Preuve ou raison |
|---|---|---|---|---|
| [L8-L9](../../FEATURES.md#L8-L9) | 🟡 | Mergé | MAP-STYLE | numéros de maisons et couche de sorties ajoutés aux six styles ; une capture de sortie courte reste à faire |
| [L10-L11](../../FEATURES.md#L10-L11) | ⚠️ | Nouveau | MAP-POI | source Vela, Google ou les deux |
| [L12-L13](../../FEATURES.md#L12-L13) | ⚠️ | Nouveau | MAP-POI | taille des icônes livrée par MAP-STYLE ; source de POI et validation des filtres restantes |
| [L14](../../FEATURES.md#L14) | ⚠️ | Mergé, à rejouer | VAL-1 | N-1 et Q-2 couvrent le POI et le rotor ; numéros, bâtiments et appui long à rejouer |
| [L15](../../FEATURES.md#L15) | ⚠️ | Planifié | M-1 | M-1 phase 7, bâtiments 3D et relief |
| [L16](../../FEATURES.md#L16) | ⚠️ | Nouveau | MAP-GESTE | rotation et retour au nord |
| [L17-L18](../../FEATURES.md#L17-L18) | ⚠️ | Nouveau | MAP-GESTE | keep north up global |
| [L19-L23](../../FEATURES.md#L19-L23) | ⚠️ | Mergé | I-1c + MAP-STYLE | les deux lots sont mergés, run `map-style-merge-20261027-220119-24997` vert ; terrain et source de POI restants |
| [L24-L25](../../FEATURES.md#L24-L25) | ⚠️ | Planifié | T-2 | T-2 phase 8, lignes colorées et cache |
| [L27-L28](../../FEATURES.md#L27-L28) | 🟡 | Mergé | MAP-STYLE | zoom des numéros livré ; complétion des bâtiments absents |
| [L29](../../FEATURES.md#L29) | ⚠️ | Mergé, à rejouer | VAL-1 | M1 couvre le bouton ; cône de cap et cercle de précision à rejouer sur iPhone |
| [L30](../../FEATURES.md#L30) | ❌ | Nouveau | NAV-FREEDRIVE | conduite sans itinéraire |
| [L31-L34](../../FEATURES.md#L31-L34) | ❌ | Nouveau | NAV-FREEDRIVE | mode conduite et alertes |
| [L35-L37](../../FEATURES.md#L35-L37) | 🟡 | Mergé | MAP-STYLE | quatre modes de noms, captures à Chinatown |
| [L38](../../FEATURES.md#L38) | ⚠️ | Nouveau | MAP-GESTE | échelle, zoom et préférence |
| [L39-L40](../../FEATURES.md#L39-L40) | ⚠️ | Nouveau | MAP-GESTE | position de départ |

### Fiche lieu

| Lignes | Statut | Destination | Lot | Preuve ou raison |
|---|---|---|---|---|
| [L44-L45](../../FEATURES.md#L44-L45) | ⚠️ | Nouveau | PLC-PAGE | distance, téléphone et site à prouver |
| [L46](../../FEATURES.md#L46) | ⚠️ | Nouveau | PLC-PAGE | horaires spéciaux et départements |
| [L47-L48](../../FEATURES.md#L47-L48) | ⚠️ | Nouveau | PLC-PAGE | onglets Menu, Updates et About |
| [L49-L50](../../FEATURES.md#L49-L50) | ⚠️ | Nouveau | PLC-REVIEW | histogramme et page Google complète |
| [L51](../../FEATURES.md#L51) | ⚠️ | Nouveau | PLC-REVIEW | catégories, visionneuse et affluence |
| [L52](../../FEATURES.md#L52) | ⚠️ | Nouveau | PLC-PAGE | Order et Reserve |
| [L53](../../FEATURES.md#L53) | ⚠️ | Nouveau | SHR-PLACE | autres contenus de partage |
| [L54-L57](../../FEATURES.md#L54-L57) | ⚠️ | Mergé | DL-2 | DL-2 mergé, `MapLinkDirectionsTest` et `IncomingLinksUITests.testIncomingDirectionsLinkWithTwoStopsKeepsTheirOrder` ; run Mac à produire |
| [L58-L59](../../FEATURES.md#L58-L59) | ⚠️ | Nouveau | PLC-PAGE | lieux liés |
| [L60](../../FEATURES.md#L60) | ⚠️ | Nouveau | PLC-PAGE | source ouverte nommée |
| [L61-L64](../../FEATURES.md#L61-L64) | ⚠️ | Nouveau | PLC-FUEL | prix carburant et fraîcheur |
| [L65-L66](../../FEATURES.md#L65-L66) | ⚠️ | Nouveau | SV-HIST | historique Street View |
| [L67-L68](../../FEATURES.md#L67-L68) | ❌ | Nouveau | SET-CONTENT | réglages avis et photos |
| [L69-L70](../../FEATURES.md#L69-L70) | ❌ | Nouveau | SET-CONTENT | attente affluence et chargement complet |
| [L71-L72](../../FEATURES.md#L71-L72) | ❌ | Nouveau | SET-CONTENT | catégories adultes et liens externes |

### Recherche

| Lignes | Statut | Destination | Lot | Preuve ou raison |
|---|---|---|---|---|
| [L77](../../FEATURES.md#L77) | ⚠️ | Nouveau | SRCH-CARDS | priorité des enregistrés et flèche |
| [L78](../../FEATURES.md#L78) | ⚠️ | Nouveau | SRCH-CARDS | cartes de résultats complètes |
| [L79](../../FEATURES.md#L79) | ❌ | Nouveau | SRCH-FILTER | requête Open now |
| [L80-L81](../../FEATURES.md#L80-L81) | ❌ | Nouveau | SRCH-FILTER | filtres et tri |
| [L82](../../FEATURES.md#L82) | ⚠️ | Nouveau | SRCH-AREA | Search this area et More results |
| [L83-L84](../../FEATURES.md#L83-L84) | ❌ | Nouveau | SRCH-BRANCH | succursales et interrupteur |
| [L85](../../FEATURES.md#L85) | ⚠️ | Nouveau | SRCH-BRANCH | catégories en bouton ou masquées |
| [L86-L87](../../FEATURES.md#L86-L87) | ❌ | Nouveau | SRCH-BRANCH | ordre, puce More et variantes |
| [L88](../../FEATURES.md#L88) | ❌ | Nouveau | SRCH-CMD | commandes tapées |
| [L89-L91](../../FEATURES.md#L89-L91) | ❌ | Mergé | VO-2 | VO-2 mergé, `VoiceDictationTest`, `VoiceSearchTests`, run `vo2-dictation-20261027-040248-1507` ; micro iPhone à valider |
| [L92](../../FEATURES.md#L92) | ❌ | Nouveau | SRCH-CMD | contacts |
| [L93](../../FEATURES.md#L93) | ❌ | Nouveau | SRCH-CMD | recherche le long de la route |

### Itinéraires

| Lignes | Statut | Destination | Lot | Preuve ou raison |
|---|---|---|---|---|
| [L100](../../FEATURES.md#L100) | ⚠️ | Mergé, à rejouer | VAL-1 | R-2 mergé, `BikeNoGoogleRoutingTest` et `DirectionsUITests.testBikeRouteUsesTheSafetyProfile` ; passe iPhone à faire |
| [L101-L102](../../FEATURES.md#L101-L102) | ⚠️ | Mergé, à rejouer | VAL-1 | R-2 mergé, `DirectionsUITests.testNoGoogleDriveNeverAsksGoogle` ; passe iPhone à faire |
| [L104-L105](../../FEATURES.md#L104-L105) | ❌ | Nouveau | RTE-PICKER | présentation du choix |
| [L106-L108](../../FEATURES.md#L106-L108) | ⚠️ | Nouveau | NAV-FREEDRIVE | arrêts pendant le guidage |
| [L109](../../FEATURES.md#L109) | ⚠️ | Nouveau | RTE-CAM | évitement des caméras |
| [L110-L111](../../FEATURES.md#L110-L111) | ⚠️ | Nouveau | RTE-BIKE | ligne de réglage vélo |
| [L112](../../FEATURES.md#L112) | ⚠️ | Nouveau | RTE-STEP | focus d'une étape |
| [L115](../../FEATURES.md#L115) | ❌ | Nouveau | SHR-PLACE | partage texte du trajet |
| [L116](../../FEATURES.md#L116) | ❌ | Nouveau | PLC-FUEL | alerte de fermeture à l'arrivée |
| [L117](../../FEATURES.md#L117) | ❌ | Nouveau | RTE-PICKER | trafic à la demande |

### Navigation

| Lignes | Statut | Destination | Lot | Preuve ou raison |
|---|---|---|---|---|
| [L121-L123](../../FEATURES.md#L121-L123) | ⚠️ | Nouveau | NAV-BANNER | écussons, voies et balayage |
| [L124-L125](../../FEATURES.md#L124-L125) | ⚠️ | Nouveau | NAV-CAMERA | tiers d'écran et cadrage |
| [L126-L129](../../FEATURES.md#L126-L129) | ❌ | Nouveau | NAV-CAMERA | zoom vers la prochaine manœuvre |
| [L130](../../FEATURES.md#L130) | ⚠️ | Nouveau | SET-VOICE | Say street names |
| [L136-L137](../../FEATURES.md#L136-L137) | ⚠️ | Nouveau | SET-VOICE | trois niveaux de voix |
| [L138-L140](../../FEATURES.md#L138-L140) | ⚠️ | Nouveau | NAV-BANNER | ETA par arrêt et balayage des étapes |
| [L141](../../FEATURES.md#L141) | ⚠️ | Nouveau | SET-APPEARANCE | carillon, vibration et bandeau |
| [L142-L143](../../FEATURES.md#L142-L143) | ⚠️ | Mergé, à rejouer | VAL-1 | N-2 mergé, `NavStoreTest.trafficOfferIsMirroredAndAcceptanceAdoptsTheCandidate` ; capture UI à rejouer |
| [L144](../../FEATURES.md#L144) | ⚠️ | Nouveau | NAV-RENDER | congestion et route parcourue |
| [L147](../../FEATURES.md#L147) | ⚠️ | Nouveau | SET-APPEARANCE | Show speed et rejeu |
| [L150-L151](../../FEATURES.md#L150-L151) | ❌ | Nouveau | NAV-RENDER | Road ahead bar |
| [L152-L153](../../FEATURES.md#L152-L153) | ❌ | Nouveau | NAV-RENDER | flèches de manœuvre |
| [L154-L155](../../FEATURES.md#L154-L155) | ❌ | Nouveau | NAV-BANNER | nom de rue actuel |
| [L156-L157](../../FEATURES.md#L156-L157) | ⚠️ | Nouveau | NAV-BANNER | Road numbers first |
| [L158](../../FEATURES.md#L158) | ❌ | Nouveau | NAV-RENDER | cartouches de rues croisées |
| [L159](../../FEATURES.md#L159) | ❌ | Nouveau | NAV-RENDER | écusson de route |
| [L162](../../FEATURES.md#L162) | ⚠️ | Nouveau | NAV-CAMERA | Overview et Recentrer |
| [L163-L164](../../FEATURES.md#L163-L164) | ⚠️ | Nouveau | SET-APPEARANCE | start north-up et keep north up |
| [L165-L166](../../FEATURES.md#L165-L166) | ❌ | Nouveau | SET-APPEARANCE | icône, taille et couleurs |
| [L167](../../FEATURES.md#L167) | ⚠️ | Nouveau | SET-APPEARANCE | vibration, écran actif et fin |
| [L168-L169](../../FEATURES.md#L168-L169) | ⚠️ | Nouveau | NAV-LIFE | notification de conduite, mini-carte ➖ |
| [L171](../../FEATURES.md#L171) | ❌ | Nouveau | NAV-LIFE | reprise après fermeture |
| [L178](../../FEATURES.md#L178) | ❌ | Nouveau | NAV-FREEDRIVE | lieu touché en conduite |
| [L179-L180](../../FEATURES.md#L179-L180) | ❌ | Nouveau | NAV-FREEDRIVE | simplification en conduite |
| [L181-L182](../../FEATURES.md#L181-L182) | ⚠️ | Nouveau | SET-APPEARANCE | guidage par les feux |

### Transports

| Lignes | Statut | Destination | Lot | Preuve ou raison |
|---|---|---|---|---|
| [L186-L187](../../FEATURES.md#L186-L187) | ⚠️ | Planifié | T-3 | T-3 phase 8, compte à rebours dans le choix |
| [L188-L189](../../FEATURES.md#L188-L189) | ⚠️ | Planifié | T-3 | T-3 phase 8, heure partout ; Last available reste à trancher |
| [L190](../../FEATURES.md#L190) | ⚠️ | Mergé, à rejouer | VAL-1 | T-1 mergé, `TransitDetailSheet` ; scénario UI dédié à écrire puis rejouer |
| [L191](../../FEATURES.md#L191) | ❌ | Mergé | T-1b | T-1b mergé, guidage des marches, run `t1b-transit-walk-20261027-022635-31273` |
| [L195](../../FEATURES.md#L195) | ❌ | Mergé | T-1b | T-1b mergé, tableaux hors ligne 6 h, même run |

### Caméras et alertes routières

| Lignes | Statut | Destination | Lot | Preuve ou raison |
|---|---|---|---|---|
| [L200](../../FEATURES.md#L200) | ⚠️ | Nouveau | MAP-CAM | orientation des caméras |
| [L201-L202](../../FEATURES.md#L201-L202) | ❌ | Nouveau | RTE-CAM | comptage et évitement |
| [L203](../../FEATURES.md#L203) | ❌ | Nouveau | RTE-CAM | rues latérales |
| [L204](../../FEATURES.md#L204) | ⚠️ | Mergé, à rejouer | VAL-1 | N-2 mergé, `NavAlertsTest` ; `NavAlertsUITests` à rejouer |
| [L205-L206](../../FEATURES.md#L205-L206) | ⚠️ | Mergé, à rejouer | VAL-1 | N-2 et I-1b mergés, `NavAlertsTest` ; UI à rejouer |
| [L207](../../FEATURES.md#L207) | ⚠️ | Mergé, à rejouer | VAL-1 | N-2 mergé, `NavAlertsTest` ; scénario vocal à rejouer |
| [L208-L209](../../FEATURES.md#L208-L209) | ❌ | Nouveau | NAV-LIFE | mode Alerts only |
| [L210-L211](../../FEATURES.md#L210-L211) | ⚠️ | Nouveau | NAV-LIFE | alerte de pont sur l'itinéraire |
| [L212](../../FEATURES.md#L212) | ❌ | Nouveau | OFF-CAM | caméras hors ligne |

### Hors ligne

| Lignes | Statut | Destination | Lot | Preuve ou raison |
|---|---|---|---|---|
| [L216](../../FEATURES.md#L216) | ⚠️ | ➖ | Aucun | cadrage possible, clause routage .obf exclue ; cadrage seul dans OFF-AREA |
| [L222-L223](../../FEATURES.md#L222-L223) | ❌ | ➖ | Aucun | routage .obf exclu par D7 |
| [L224-L226](../../FEATURES.md#L224-L226) | ❌ | Planifié | O-3 | O-3, branche ouverte, deltas et Update all |
| [L228](../../FEATURES.md#L228) | ⚠️ | Planifié | O-3 | O-3, branche ouverte, stockage par catégorie |
| [L229-L230](../../FEATURES.md#L229-L230) | ⚠️ | Nouveau | OFF-AREA | Include places et Keep viewed places |
| [L231](../../FEATURES.md#L231) | ❌ | Nouveau | OFF-AREA | globe barré et nouvelle vérification |
| [L232](../../FEATURES.md#L232) | ⚠️ | Mergé, à rejouer | VAL-1 | O-2 mergé, reprise par données `URLSession` ; `OfflineUITests` à rejouer |
| [L233](../../FEATURES.md#L233) | ❌ | Nouveau | SET-CONTENT | données réduites |

### Voix et langues

| Lignes | Statut | Destination | Lot | Preuve ou raison |
|---|---|---|---|---|
| [L239](../../FEATURES.md#L239) | ⚠️ | Nouveau | SET-VOICE | interrupteur Spoken directions |
| [L240-L241](../../FEATURES.md#L240-L241) | ⚠️ | Nouveau | VO-CONTROL | volume, vitesse et nivellement |
| [L242-L243](../../FEATURES.md#L242-L243) | ⚠️ | Nouveau | VO-CONTROL | langue des directions et voix absentes |
| [L244-L245](../../FEATURES.md#L244-L245) | ⚠️ | Nouveau | VO-CONTROL | lexique de 3 500 noms |
| [L246-L247](../../FEATURES.md#L246-L247) | ⚠️ | Nouveau | I18N-TRANS | CJK, RTL et traductions partielles |
| [L249-L250](../../FEATURES.md#L249-L250) | ⚠️ | Nouveau | SET-VOICE | Directions language |
| [L251](../../FEATURES.md#L251) | ⚠️ | Nouveau | SET-VOICE | horloge et unités appliquées |

### Lieux enregistrés, listes et partage

| Lignes | Statut | Destination | Lot | Preuve ou raison |
|---|---|---|---|---|
| [L256-L258](../../FEATURES.md#L256-L258) | ⚠️ | Nouveau | SAV-EDIT | gestes, poignée et retour haptique |
| [L259-L260](../../FEATURES.md#L259-L260) | ⚠️ | Nouveau | SAV-EDIT | couleur, icône, emoji et note |
| [L261-L263](../../FEATURES.md#L261-L263) | ⚠️ | Nouveau | SAV-MARK | marqueurs, noms et zoom |
| [L264](../../FEATURES.md#L264) | ⚠️ | Nouveau | MAP-GESTE | forme des boutons de carte |
| [L265-L268](../../FEATURES.md#L265-L268) | ⚠️ | Planifié | L-2 | L-2, branche ouverte, exports et import |
| [L269-L270](../../FEATURES.md#L269-L270) | ⚠️ | Nouveau | SAV-EDIT | sélection multiple |
| [L271-L272](../../FEATURES.md#L271-L272) | ❌ | Nouveau | SAV-EDIT | son de liste et alerte au passage |
| [L273](../../FEATURES.md#L273) | ❌ | Nouveau | IMP-GOOGLE | liste Google partagée |
| [L274](../../FEATURES.md#L274) | ❌ | Nouveau | IMP-GOOGLE | My Maps |
| [L275](../../FEATURES.md#L275) | ❌ | Nouveau | SAV-MARK | lignes et zones |
| [L276-L278](../../FEATURES.md#L276-L278) | ⚠️ | Planifié | L-2 | L-2, branche ouverte, Find my car |
| [L279](../../FEATURES.md#L279) | ⚠️ | Mergé, à rejouer | VAL-1 | S-0 mergé, écriture synchrone ; `SavedUITests` de suite à rejouer |

### Confidentialité

| Lignes | Statut | Destination | Lot | Preuve ou raison |
|---|---|---|---|---|
| [L284-L286](../../FEATURES.md#L284-L286) | ❌ | Nouveau | SET-PRIVACY | consentement initial |
| [L287](../../FEATURES.md#L287) | ⚠️ | Nouveau | SET-PRIVACY | page Privacy complète |
| [L288-L289](../../FEATURES.md#L288-L289) | ⚠️ | Mergé | PR-1 | PR-1 mergé, `PrivacyUITests.testNoGoogleSearchSendsNothingToGoogle` et `.testNoGoogleDirectionsAndTransitSendNothingToGoogle` |
| [L290](../../FEATURES.md#L290) | ⚠️ | Nouveau | SET-PRIVACY | réglage des liens courts |
| [L291-L292](../../FEATURES.md#L291-L292) | ❌ | Nouveau | MAP-POI | POI Vela sans Google |
| [L293](../../FEATURES.md#L293) | ❌ | Nouveau | SET-PRIVACY | Look up tapped places |
| [L294](../../FEATURES.md#L294) | ⚠️ | Mergé | PR-1 | PR-1 mergé, `PrivacyPolicyTest` et scénario UI de rotation |
| [L295](../../FEATURES.md#L295) | ⚠️ | Mergé | PR-1 | PR-1 mergé, `HiddenWebView` et test unitaire des trois filtres |
| [L296](../../FEATURES.md#L296) | ❌ | Nouveau | SET-PRIVACY | compteur de requêtes visible |
| [L297](../../FEATURES.md#L297) | ⚠️ | Nouveau | RTE-PICKER | trafic vivant et revérifications |
| [L298](../../FEATURES.md#L298) | ⚠️ | Nouveau | SET-PRIVACY | Clear history global |
| [L299](../../FEATURES.md#L299) | ⚠️ | Mergé, à rejouer | VAL-1 | implémentation I-0 existante, aucun parcours dédié ; passe iPhone à faire |

### Apparence et réglages

| Lignes | Statut | Destination | Lot | Preuve ou raison |
|---|---|---|---|---|
| [L304-L305](../../FEATURES.md#L304-L305) | ⚠️ | Nouveau | SET-APPEARANCE | thèmes et jour/nuit |
| [L306-L309](../../FEATURES.md#L306-L309) | ⚠️ | Nouveau | MAP-STYLE | styles et palettes |
| [L312-L313](../../FEATURES.md#L312-L313) | ⚠️ | Nouveau | SET-APPEARANCE | police et taille d'interface |
| [L314](../../FEATURES.md#L314) | ❌ | ➖ | Aucun | renommage du lanceur impossible sur iOS |
| [L315](../../FEATURES.md#L315) | ⚠️ | Nouveau | SET-ABOUT | hub de réglages avec recherche |
| [L316-L317](../../FEATURES.md#L316-L317) | ❌ | ➖ | Aucun | rendu de compatibilité sans équivalent MapLibre iOS |

### Android Auto

| Lignes | Statut | Destination | Lot | Preuve ou raison |
|---|---|---|---|---|
| [L321-L322](../../FEATURES.md#L321-L322) | ❌ | ➖ | Aucun | pas d'entitlement CarPlay |
| [L323-L324](../../FEATURES.md#L323-L324) | ❌ | ➖ | Aucun | pas d'entitlement CarPlay |
| [L325-L327](../../FEATURES.md#L325-L327) | ❌ | ➖ | Aucun | pas d'entitlement CarPlay |
| [L328-L330](../../FEATURES.md#L328-L330) | ❌ | ➖ | Aucun | pas d'entitlement CarPlay |
| [L331-L332](../../FEATURES.md#L331-L332) | ❌ | ➖ | Aucun | pas d'entitlement CarPlay |
| [L333-L334](../../FEATURES.md#L333-L334) | ❌ | ➖ | Aucun | pas d'entitlement CarPlay |
| [L335-L337](../../FEATURES.md#L335-L337) | ❌ | ➖ | Aucun | pas d'entitlement CarPlay |
| [L338](../../FEATURES.md#L338) | ❌ | ➖ | Aucun | pas d'entitlement CarPlay |
| [L339](../../FEATURES.md#L339) | ❌ | ➖ | Aucun | pas d'entitlement CarPlay |
| [L340-L341](../../FEATURES.md#L340-L341) | ❌ | ➖ | Aucun | pas d'entitlement CarPlay |
| [L342](../../FEATURES.md#L342) | ❌ | ➖ | Aucun | pas d'entitlement CarPlay |
| [L343](../../FEATURES.md#L343) | ❌ | ➖ | Aucun | pas d'entitlement CarPlay |

### Mises à jour et installation

| Lignes | Statut | Destination | Lot | Preuve ou raison |
|---|---|---|---|---|
| [L363](../../FEATURES.md#L363) | ⚠️ | Nouveau | SET-ABOUT | About avec version |
| [L364](../../FEATURES.md#L364) | ⚠️ | Nouveau | SET-ABOUT | notices du projet |
| [L365](../../FEATURES.md#L365) | ❌ | Nouveau | SET-ABOUT | soutien et don |

### Trajets enregistrés et diagnostics

| Lignes | Statut | Destination | Lot | Preuve ou raison |
|---|---|---|---|---|
| [L375-L376](../../FEATURES.md#L375-L376) | ❌ | Nouveau | TRIP-TRACE | trace complète dans un dossier |
| [L377](../../FEATURES.md#L377) | ⚠️ | Nouveau | SET-CONTENT | Redact places in exports |
| [L378](../../FEATURES.md#L378) | ❌ | Nouveau | TRIP-DIAG | rapport de plantage |
| [L379-L380](../../FEATURES.md#L379-L380) | ⚠️ | Nouveau | TRIP-TRACE | simulation de conduite et de position |
| [L381](../../FEATURES.md#L381) | ❌ | Nouveau | TRIP-DIAG | trace de fluidité et debug des bâtiments |

## 11. Vérifications

Avant de pousser ce document :

```
python3 scripts/ios/parity_check.py --check
python3 scripts/ios/test_parity_check.py
scripts/check-writing.sh $(git merge-base ios/main HEAD)..HEAD
```

Ce lot modifie `FEATURES-IOS.md` : quatre lignes passent de ⚠️ à 🟡 sur preuve VAL-3, puis la
synthèse est régénérée par `parity_check.py --md`. Le compte passe de 2 ✅, 98 🟡, 57 ⚠️, 28 ❌ et
19 ➖ à 2 ✅, 102 🟡, 53 ⚠️, 28 ❌ et 19 ➖, soit 204 lignes dans les deux cas. Le contrôle `--check`
reste vert après la régénération. Les statuts ➖ de la section 6 ne sont toujours pas appliqués à la
matrice ; ce changement reste réservé au coordinateur.

## 12. Règle de mise à jour

Quand un lot ferme une ligne, il met à jour `FEATURES-IOS.md` dans le même commit, avec le nom du
test ou du run. Ce backlog ne devient pas une seconde matrice : il ne conserve que les lots
ouverts, les dépendances et les lignes ➖. Une ligne fermée sort de la section 4 et de la section 10.
