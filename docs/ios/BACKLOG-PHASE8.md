# Backlog des phases 7 et 8

État au 2026-10-28, branche `ios/phase8-plan`, depuis `ios/main` au commit `41c233a9`. Ce document
remplace les lignes d'une phrase des phases 7 et 8 de `PORTAGE_IOS.md` par des lots avec un
périmètre, des fichiers nommés, une preuve et un risque. Il ne remplace ni `docs/ios/BACKLOG.md` ni
`docs/ios/FEATURES-IOS.md`.

Le périmètre couvert est : `M-1`, `M-2`, `G-1`, `G-2`, `T-2`, `A-1` à `A-4`, `G-3`, `W-1`, les
deux lots de lien `AO-1` et `AO-2` et le lot transversal `TIME-1`. Un lot de socle, `WLD-1`, est ajouté avant les calques du monde : sans
lui, six lots devraient modifier `MapController.swift` et `LayersView.swift` chacun leur tour, et
la phase 8 ne serait plus parallèle.

## 1. Ce que la vérification du code et des API change

Ces points ont été vérifiés dans l'arbre et dans les documents publics des sources. Ils corrigent
les promesses des phases 7 et 8 et doivent être lus avant de lancer un lot.

1. **Transitous n'a pas d'endpoint `/api/v1/isochrones`.** La spécification MOTIS 2.10.2 exposée par
   Transitous contient `/api/v6/one-to-all` : une liste d'arrêts atteignables avec une durée et un
   nombre de correspondances. Il n'y a pas de polygone d'isochrone. `T-2` dessine donc les arrêts
   atteignables et leur enveloppe, pas une zone officielle.
2. **Transitous n'expose pas la position des véhicules.** `/api/v6/map/trips` renvoie des tronçons
   de course avec leur tracé, leurs heures prévues, leurs heures réelles et un drapeau `realTime`.
   Aucun champ ne donne la latitude et la longitude du véhicule. `T-2` affiche les courses en
   service et leurs horaires temps réel, jamais un point de véhicule inventé.
3. **`/api/experimental/map/routes` ne couvre que le rail.** Il ne renvoie que les modes métro et
   train, avec au plus quatre couleurs et six libellés. Les couleurs de toutes les lignes viennent
   de `/api/v6/map/trips` (`routeColor`), pas de cet endpoint.
4. **`plan` n'accepte `via` que sous forme d'identifiants d'arrêt.** Aucune coordonnée n'est
   acceptée. Une alternative « par Nation » demande donc de résoudre l'arrêt par son nom et sa
   position avant de replanifier.
5. **MapLibre Native 6.31.0 ne rend pas la propriété `sky`.** La spécification indique que `sky`
   demande un terrain 3D, et le suivi MapLibre (issue #4414) dit que la propriété n'est pas
   implémentée sur Android et iOS. `M-1` ne peut pas livrer de ciel dans la carte native. Le ciel
   et l'atmosphère de l'écran Relief sont livrés par MapLibre GL JS dans `M-2`. L'atmosphère du
   globe de `G-2` dépend du build globe, et reste une promesse conditionnelle.
6. **`MLNMapView.maximumPitch` est plafonné à 60 degrés.** La documentation MapLibre le dit
   explicitement. Aucun lot ne doit promettre une inclinaison au-delà.
7. **Terrain3D n'est pas dans MapLibre Native.** Le relief déformé de la carte principale n'existe
   pas. `M-1` livre un relief ombré, `M-2` livre un terrain déformé dans une WKWebView.
8. **OpenSky n'est pas utilisable pour une app distribuée.** Ses conditions réservent l'API REST
   à la recherche et à l'enseignement à but non lucratif et exigent un accord écrit pour tout
   emploi opérationnel dans un produit ou un service. `A-1` passe par `adsb.lol`, sous ODbL 1.0.
9. **Electricity Maps n'a pas de palier gratuit anonyme.** Le service self-serve est un essai ou
   une offre payante, avec une exception domestique. `A-3` livre d'abord l'API Carbon Intensity
   britannique, sans clé et sous CC BY 4.0, et ne branche Electricity Maps que si l'utilisateur
   fournit une clé.
10. **AISHub n'ouvre son API qu'aux membres qui alimentent une station.** La clé est personnelle,
    l'API accepte une requête par minute et les conditions interdisent de republier les données
    brutes. `A-2` livre Digitraffic, ouvert et limité à la Finlande, puis AISHub en option avec la
    clé d'un membre.
11. **UKMTO est sous Crown copyright sans conditions de réutilisation ouvertes.** `A-2` affiche le
    titre, la date et le lien d'un avis, sans recopier le texte ni dessiner de zone, jusqu'à une
    autorisation écrite.
12. **L'accès à l'API NOTAM de la FAA n'est pas self-serve en 2026.** Le NMS demande une demande
    par courriel et des identifiants OAuth2, et les chemins ne sont fournis qu'avec les
    identifiants. `A-4` commence par une session de go/no-go. Sans accès, le lot s'arrête et aucune
    couche n'est promise.
13. **`T-3` est déjà mergé** (`f57c68d9`). Son scénario de changement d'heure est encore rouge dans
    le run `val1-transit-20261028-035840-8078` : `no shifted query label`. `TIME-1` ferme ce point
    avant `T-2`.
14. **`scripts/ios/check_notices.py` bloque le build Mac** dès qu'un littéral d'hôte apparaît dans
    `iosApp/Vela`, `ios-shared/src/commonMain` ou `core-common/src/commonMain` sans notice qui le
    couvre. L'étape Notices tourne avant la compilation dans `scripts/ios/ci-ipa.sh`. Une source
    ajoutée sans notice ne se voit donc pas à la compilation Linux, mais fait échouer le run Mac.

## 2. Conventions

- **Tailles et sessions.** `S` : moins d'une session. `M` : 1 à 3 sessions. `L` : plus de 3
  sessions. Une session couvre l'implémentation, les tests Linux et la préparation du scénario
  simulateur. Les passes iPhone restent humaines et ne sont pas comptées.
- **Propriété.** Un lot possède les fichiers listés. Il ne modifie aucun autre fichier. Une ligne
  d'ancrage dans un fichier chaud est nommée et réservée dans la vague : le lot qui tient la voie
  peut modifier le fichier, les autres n'y ajoutent qu'une ancre. `LayersView.swift`,
  `MapController.swift`, `MapScreen.swift`, `RouteSheets.swift`, `PlaceSheet.swift` et
  `SettingsScreen.swift` restent des points de conflit nommés.
- **Calques du monde.** `WLD-1` pose un hôte unique, un protocole et une section générique. Chaque
  lot de calque remplit son propre fichier et ne touche plus l'hôte. Un calque non installé est
  masqué, pas affiché vide.
- **Réglages par défaut.** Tout nouveau calque est coupé par défaut. Aucune requête ne part avant
  l'interrupteur. Chaque calque affiche sa source, son horodatage et son état : frais, en retard ou
  indisponible.
- **Clés.** Une clé fournie par l'utilisateur va dans le Keychain, jamais dans `UserDefaults`,
  jamais dans `calibration.json`, jamais dans le binaire. Une source sans clé est toujours
  préférée.
- **Fraîcheur.** Un calque n'écrit « live » que si le flux l'a marqué. Une donnée plus vieille que
  sa fenêtre passe à « en retard » et perd le mot « live ».
- **Preuves.** Chaque lot nomme au moins un test JVM, un scénario UI et une capture. Un test qui
  n'existe pas encore est nommé avec son fichier. Aucun scénario n'est déclaré vert sans le tag du
  run qui l'a produit.
- **Notices.** `Notices.json` change dans le même commit que le premier littéral d'hôte. La section
  7 donne les lignes attendues.
- **Android ne bouge pas.** Un lot iOS ne change ni `app/`, ni `core/`, ni le comportement d'une
  fonction partagée de `core-common`. Les ajouts à `Transitous.kt` sont additifs et les tests
  Android existants restent verts.

Les tableaux de lots sont doublés : un tableau de périmètre, puis un tableau de preuve et de
source. Chaque lot a exactement une ligne dans chacun.

## 3. Lots

### 3.1 Socle des calques du monde

| Lot | Taille | Résultat visible | Fichiers possédés | Ne touche pas | Dépend de |
|---|---|---|---|---|---|
| **WLD-1** | S | La feuille de couches gagne un hôte unique pour les calques du monde : interrupteur, source, horodatage, état frais, en retard ou indisponible, et champ de clé stocké dans le Keychain. Aucun calque métier n'est livré : les six entrées sont masquées tant que leur lot ne les a pas installées. | `iosApp/Vela/Map/Layers/WorldLayers.swift` (nouveau) ; `iosApp/Vela/Map/Layers/WorldLayerSection.swift` (nouveau) ; `iosApp/Vela/Platform/KeychainSecrets.swift` (nouveau) ; `iosApp/Vela/Map/Layers/AviationLayer.swift`, `MaritimeLayer.swift`, `EnergyLayer.swift`, `NotamLayer.swift`, `SatelliteLayer.swift`, `WikiLayer.swift` (squelettes) ; `iosApp/Vela/Map/Layers/LayersView.swift` (une ancre) ; `iosApp/Vela/Map/MapController.swift` (un appel) ; `ios-shared/src/commonMain/kotlin/app/vela/ios/world/WorldLayerState.kt`, `WorldLayerSettings.kt` (nouveaux) ; `ios-shared/src/commonTest/kotlin/app/vela/ios/world/WorldLayerSettingsTest.kt` | `MapScreen.swift`, `RouteSheets.swift`, `PlaceSheet.swift`, `SettingsScreen.swift`, `project.yml`, `core-common`, Android | aucune |

| Lot | Preuve d'acceptation | Source et conditions | Risque |
|---|---|---|---|
| **WLD-1** | `WorldLayerSettingsTest` sur l'ensemble des interrupteurs, la présence d'une clé sans écriture en clair et les trois états ; `WorldLayersUITests.testWorldLayersStartHidden` avec `world-layers.png`, `world_layers=0`, `world_requests=0`. | aucune | L'abstraction peut ne pas couvrir un calque ; ce lot ajoute alors un adaptateur local, jamais une modification partagée supplémentaire. |

Le protocole `WorldLayer` porte un identifiant, un titre, une ligne de détail, une clé éventuelle,
un état, une liste de lignes (`WorldLayerRow`) et deux appels : `refresh(viewport:)` et
`apply(style:offline:)`. La section générique affiche l'interrupteur, le champ de clé, l'état et la
liste. Un toucher sur une ligne qui porte une coordonnée recentre la carte par le callback déjà
présent dans `MapController`. Aucun lot suivant ne modifie `WorldLayers.swift` ni
`WorldLayerSection.swift`.

### 3.2 Phase 7 : carte 3D, relief et globe

| Lot | Taille | Résultat visible | Fichiers possédés | Ne touche pas | Dépend de |
|---|---|---|---|---|---|
| **M-1** | M | À partir de z16, incliner la carte au-delà de 20 degrés fait apparaître les bâtiments extrudés avec un fondu de 350 ms ; sous 12 degrés, ils disparaissent. Un réglage « 3D buildings » est dans la feuille de couches. L'inclinaison est plafonnée à 60 degrés. Le relief ombré s'active dans la même feuille, s'insère sous les routes, est plafonné à z16 et disparaît hors ligne. Le ciel n'est pas rendu : MapLibre Native ne prend pas en charge `sky` (issue #4414), seul le fond uni reste. | `iosApp/Vela/Map/MapView.swift` ; `iosApp/Vela/Map/MapController.swift` ; `iosApp/Vela/Map/Layers/HillshadeLayer.swift` (nouveau) ; `iosApp/Vela/Map/Layers/MapStyleBuilder.swift` ; `iosApp/Vela/Map/Layers/LayersView.swift` ; `iosApp/Vela/Map/Layers/LayersModel.swift` ; `ios-shared/src/commonMain/kotlin/app/vela/ios/map/TerrainTiles.kt` (nouveau) ; `ios-shared/src/commonMain/kotlin/app/vela/ios/map/LayersStore.kt` ; `ios-shared/src/commonTest/kotlin/app/vela/ios/map/TerrainTilesTest.kt`, `LayersStoreTest.kt` ; `docs/ios/MAP-3D.md` (nouveau) | `MapScreen.swift`, `RouteSheets.swift`, `PlaceSheet.swift`, `SettingsScreen.swift`, `OfflineStyleFactory.swift`, les six `style-*.json`, `core-common`, Android | WLD-1 |
| **M-2** | L | Un écran Relief séparé ouvre un terrain déformé en MapLibre GL JS, avec ciel et atmosphère GL JS, un centrage synchronisé avec la carte native et un retour instantané. Il est en lecture seule et ne couvre pas le hors ligne. | `iosApp/Vela/Map/Terrain/TerrainScreen.swift`, `TerrainWebView.swift`, `TerrainBridge.swift` (nouveaux) ; `iosApp/Vela/Resources/terrain/index.html`, `maplibre-gl.js`, `maplibre-gl.css` (nouveaux, embarqués) ; `iosApp/Vela/Map/MapScreen.swift` (une entrée) ; `ios-shared/src/commonMain/kotlin/app/vela/ios/map/TerrainCamera.kt` (nouveau) ; `ios-shared/src/commonTest/kotlin/app/vela/ios/map/TerrainCameraTest.kt` ; `docs/ios/TERRAIN.md` (nouveau) | `MapController.swift`, `MapStyleBuilder.swift`, `OfflineStyleFactory.swift`, `RouteSheets.swift`, `PlaceSheet.swift`, `SettingsScreen.swift`, Android | M-1 |
| **G-1** | M | Un verdict documenté sur le globe natif : xcframework reproductible construit avec `MLN_WITH_GLOBE`, application jetable, projection `globe`, zoom arrière de z3 vers la planète, mesures de taille, de fps, de gestes et de limites de caméra. Aucun changement dans l'application. | `scripts/ios/fetch-maplibre-globe.sh`, `scripts/ios/ci-globe-spike.sh` (nouveaux) ; `tools/ios-globe-spike/project.yml`, `tools/ios-globe-spike/App/*.swift` (nouveaux) ; `docs/ios/GLOBE-SPIKE.md` (nouveau) | `iosApp/`, `iosApp/project.yml`, `core-common`, `ios-shared`, Android | aucune |
| **G-2** | L | Si G-1 retient le natif : bascule Mercator et globe depuis la feuille de couches, retour Mercator sans perte de caméra, épingles, itinéraires et PMTiles hors ligne sur le globe, atmosphère seulement si le build G-1 la porte. Sinon : écran Globe GL JS séparé, en lecture seule, avec un lien depuis la carte. | Natif : `iosApp/project.yml` ; `iosApp/Vela/Map/MapView.swift`, `MapController.swift`, `MapStyleBuilder.swift` ; `iosApp/Vela/Map/GlobeProjection.swift` (nouveau) ; `iosApp/Vela/Map/Layers/LayersView.swift` ; `ios-shared/src/commonMain/kotlin/app/vela/ios/map/GlobeSettings.kt` (nouveau) ; `ios-shared/src/commonTest/kotlin/app/vela/ios/map/GlobeSettingsTest.kt`. Repli : `iosApp/Vela/Map/GlobeScreen.swift`, `GlobeWebView.swift`, `iosApp/Vela/Resources/globe/index.html`, `maplibre-gl.js`, `maplibre-gl.css`, et la même entrée dans `LayersView.swift`. | `MapScreen.swift`, `RouteSheets.swift`, `PlaceSheet.swift`, `SettingsScreen.swift`, `core-common`, Android | G-1, M-1 |

| Lot | Preuve d'acceptation | Source et conditions | Risque |
|---|---|---|---|
| **M-1** | `TerrainTilesTest` sur l'URL terrarium, le plafond z16, l'absence d'URL hors ligne et hors zone ; `LayersStoreTest` sur les deux interrupteurs, coupés par défaut et persistés. `Map3DUITests.testTiltBuildingsAndHillshade` avec `map-3d.png`, `map-3d-flat.png`, `map-hillshade.png` ; lignes `map_b3d=on`, `map_pitch=25`, `map_hillshade=ready`, `map_hillshade=off` et `map_remote=0` hors ligne. Passe iPhone : 60 s incliné à z17, fps et chauffe dans `MAP-3D.md`. | AWS Terrain Tiles (`elevation-tiles-prod`, Mapzen et joerd), données sous conditions multiples, attribution obligatoire. Hôte `s3.amazonaws.com`. | `MLNRasterDEMSource` en terrarium à confirmer sur iOS ; coût du relief et des extrusions sur les iPhone anciens ; pas de hors ligne ; plafond de 60 degrés ; pas de ciel natif. |
| **M-2** | `TerrainCameraTest` sur les bornes de zoom, l'aller-retour du milieu et l'URL de style locale ; `TerrainUITests.testTerrainScreenOpensAndReturns` avec `terrain.png`, `terrain-pitch.png`, `terrain-return.png` ; lignes `terrain_js=1`, `terrain_terrain=on`, `terrain_remote_style=0`. Passe iPhone pour les gestes et le retour. | MapLibre GL JS, BSD-3-Clause, embarqué sans CDN ; AWS Terrain Tiles, même attribution ; OpenFreeMap, notice existante. | WebGL de WKWebView plante le GPU du simulateur (W-2) ; mémoire et chauffe ; synchronisation des gestes ; hors ligne non couvert ; environ 1 Mo de plus dans l'IPA. |
| **G-1** | Aucun test JVM : le lot ne touche pas le Kotlin. Preuve = `docs/ios/GLOBE-SPIKE.md` avec la taille de l'xcframework, les fps, les limites de caméra, les gestes, et les captures `globe-z3.png`, `globe-z0.png`, `globe-tilted.png`. Deux lancements Mac au maximum. | MapLibre Native pré-release `ios-v2026.10.19-globe`, BSD-2-Clause, notice existante ; OpenFreeMap, notice existante. `tools/` n'est pas scanné par `check_notices.py`. | Pré-release, API et ABI instables ; temps de construction ; gain de 208 Kio annoncé mais non vérifié ; atmosphère absente ; revalidation à chaque montée de version. |
| **G-2** | `GlobeSettingsTest` sur la projection, la conservation de caméra et le drapeau hors ligne ; `GlobeUITests.testGlobeAndBackKeepsCamera` avec `globe.png`, `globe-mercator.png`, `globe-offline.png` ; lignes `globe_projection=globe`, `globe_remote=0` hors ligne. Passe iPhone des gestes et des fps. | MapLibre, notice existante ; OpenFreeMap, notice existante ; MapLibre GL JS, BSD-3-Clause, seulement pour le repli. | Remplacer le paquet SPM par un fork pré-release fige les correctifs ; la bascule peut perdre la caméra ; PMTiles sur globe non prouvé en amont ; atmosphère non garantie ; taille de l'IPA. |

`M-1` reprend les valeurs Android de `VelaMapView.kt` : `B3D_TILT_ON` à 20, `B3D_TILT_OFF` à 12,
`B3D_FADE_MS` à 350, `B3D_LIGHT` à 0,25, une opacité plutôt qu'une visibilité pour éviter un
nouveau calcul des tuiles. Les bâtiments sont coupés en satellite et pendant la navigation, comme
sur Android. La couche `building-3d` existe déjà dans les six variantes générées ; `M-1` abaisse son
`minzoom` à 16 au chargement, sans régénérer les fichiers. Le relief s'insère sous
`tunnel_motorway_link_casing`, la première couche de voirie des six variantes, et n'est ajouté que
si le style n'est pas hors ligne.

`M-2` ajoute seulement une entrée Relief dans `MapScreen`. L'entrée Globe appartient à `G-2` et vit
dans `LayersView`, ce qui évite de sérialiser les deux lots sur le même fichier. Le pont Swift vers
JavaScript transporte le milieu, le zoom, le cap et l'inclinaison, et renvoie les mêmes valeurs
après un geste. Aucun style n'est chargé depuis un serveur : le document est construit dans
`index.html`.

`G-2` remplace le paquet SPM `MapLibre` par `Vendor/MapLibreGlobe.xcframework` si le natif est
retenu. `check_notices.py` refuse alors le framework tant que `VENDOR_FRAMEWORKS` ne le mappe pas
vers `maplibre` dans `scripts/ios/check_notices.py`. La notice `maplibre` existe déjà, aucun
nouveau texte n'est nécessaire. Si le repli GL JS est retenu, `project.yml` ne bouge pas et la
notice `maplibre-gl-js` est ajoutée.

### 3.3 Phase 8a : transports

| Lot | Taille | Résultat visible | Fichiers possédés | Ne touche pas | Dépend de |
|---|---|---|---|---|---|
| **T-2** | L | Sur la carte, toutes les lignes en service avec leur `routeColor` ou, à défaut, la couleur du mode, les courses en service avec leur tracé et leurs horaires temps réel, et les retards par ligne (vert sous 2 min, ambre de 2 à 5, rouge au-delà, rien sans heure prévue et heure réelle). Une zone « atteignable en N minutes » est construite depuis `one-to-all`. Dans un trajet, des alternatives apparaissent par arrêt intermédiaire (`via`) ou par départ décalé. Aucune position GPS de véhicule : l'API n'en expose pas. | `core-common/src/commonMain/kotlin/app/vela/core/data/transit/Transitous.kt` (bloc additif) ; `core-common/src/commonMain/kotlin/app/vela/core/model/Transit.kt` (champs additifs) ; `core-common/src/commonTest/kotlin/app/vela/core/data/transit/TransitousOneToAllTest.kt`, `TransitousMapTripsTest.kt`, `TransitousViaTest.kt` (nouveaux) ; `ios-shared/src/commonMain/kotlin/app/vela/ios/transit/TransitReach.kt`, `TransitLiveLines.kt`, `TransitAlternatives.kt` (nouveaux) ; `TransitTrip.kt`, `TransitBoardStore.kt` ; `iosApp/Vela/Transit/TransitModel.swift`, `TransitTripScreen.swift`, `TransitBoardSheet.swift`, `TransitDetailSheet.swift` ; `iosApp/Vela/Map/TransitLinesLayer.swift`, `TransitReachOverlay.swift` (nouveaux) ; `iosApp/Vela/Map/MapController.swift` (un appel) ; `ios-shared/src/commonTest/kotlin/app/vela/ios/transit/TransitReachTest.kt`, `TransitAlternativesTest.kt`, `TransitDelayTest.kt` (nouveaux) ; `docs/ios/TRANSIT.md` | `MapScreen.swift`, `RouteSheets.swift`, `SettingsScreen.swift`, Android UI, les signatures et sorties existantes de `plan`, `board` et `stopTimes` | TIME-1, M-1 |
| **TIME-1** | M | Un seul contrôle d'heure (Maintenant, Partir à, Arriver avant, date, plus 15 minutes, Appliquer) dans la feuille d'itinéraire, les options transport, l'écran de trajet, le tableau d'arrêt, le détail d'un trajet et le choix d'un itinéraire enregistré. Chaque changement relance la requête concernée et affiche l'heure de la requête. Le scénario rouge `TransitCitymapper.testSegmentTimeChangeShowsANewOptionSet` devient vert. | `iosApp/Vela/Common/TimeChoice.swift`, `TimeChoiceModel.swift` (nouveaux) ; `iosApp/Vela/Routes/RouteOptions.swift`, `RouteSheets.swift` ; `iosApp/Vela/Transit/TransitOptionsSheet.swift`, `TransitTripScreen.swift`, `TransitDetailSheet.swift`, `TransitBoardSheet.swift` ; `iosApp/Vela/Saved/SavedRoutePickerSheet.swift` ; `ios-shared/src/commonMain/kotlin/app/vela/ios/time/TimeChoice.kt` (nouveau) ; `ios-shared/src/commonTest/kotlin/app/vela/ios/time/TimeChoiceTest.kt` ; `iosApp/VelaUITests/TransitTimeUITests.swift` | `MapScreen.swift`, `MapController.swift`, `SettingsScreen.swift`, Android, la couche réseau | aucune, avant T-2 |

| Lot | Preuve d'acceptation | Source et conditions | Risque |
|---|---|---|---|
| **T-2** | `TransitousOneToAllTest` sur les arrêts atteignables, `maxTravelTime` et l'absence d'horaire inventé ; `TransitousMapTripsTest` sur `routeColor`, `realTime` et l'écart entre heure prévue et heure réelle ; `TransitousViaTest` sur un arrêt résolu par nom ; `TransitDelayTest` sur le retard par ligne ; `TransitAlternativesTest` sur les options par `via` et par décalage. `TransitAdvancedUITests.testIsochroneAndColoredLines` avec `transit-isochrone.png` et `transit-lines.png` ; `.testLiveTripBadgeOnlyWhenRealTime` avec `transit-live.png` ; `.testLineDelayColors` avec `transit-delay.png` ; `.testViaAlternativeInsideTrip` avec `transit-via.png`. Passe iPhone sur un flux temps réel. | Transitous, conditions par flux, lien `https://transitous.org/sources/`, notice existante. Pas de nouvelle notice. | Politique de 720 requêtes par 24 h ; `one-to-all` coûteux ; aucune position de véhicule ; `routeColor` souvent vide ; `via` limité aux identifiants d'arrêt ; couverture temps réel inégale ; pas de polygone officiel, et l'enveloppe convexe peut inclure des zones non atteignables. |
| **TIME-1** | `TimeChoiceTest` sur les trois modes, la normalisation, le prochain créneau de cinq minutes et les libellés ; `TransitTimeUITests.testTimeEverywhere` avec `time-route.png`, `time-transit.png`, `time-segment.png`, `time-board.png` ; rejeu vert de `TransitCitymapperUITests.testSegmentTimeChangeShowsANewOptionSet`. Passe iPhone du sélecteur de date. | Horloge locale, aucune source. | Hauteur et défilement des feuilles, cause du rouge actuel ; fuseaux et heure d'été ; « Last available » absent ; une heure de départ en voiture reste une estimation, pas une prévision de trafic. |

`T-2` emploie `/api/v6/one-to-all` avec `one`, `maxTravelTime`, `time` et `arriveBy`. Le résultat
est une liste d'arrêts avec `duration` et `k`. La carte dessine un petit disque par arrêt et une
enveloppe convexe, avec la mention « calculé depuis les arrêts, pas une zone officielle ». Une
requête `one-to-all` est lancée seulement sur action, une à la fois, avec un cache de cinq minutes
et un plafond de durée de 60 minutes.

Les lignes et les courses viennent de `/api/v6/map/trips` avec `min`, `max`, `zoom`, `startTime`,
`endTime` et `precision`. Le lot plafonne le nombre de tronçons à 800, regroupe par
`routeShortName` et par destination `to.name`, et ne dessine que les modes bus, tram, métro, train
et ferry. Une ligne sans
`routeColor` prend la couleur de son mode et l'écrit dans la ligne de debug. Le badge « live » n'est
posé que si `realTime` est vrai. Le retard n'est calculé que si l'heure prévue et l'heure réelle
existent toutes les deux.

Les alternatives d'un trajet se calculent de deux façons : `plan` avec `via` quand un arrêt
intermédiaire est proposé, et `plan` avec une heure de départ décalée pour la même ligne. Chaque
option affiche son heure de départ et d'arrivée. Aucune option n'est construite à partir d'un
horaire absent.

`TIME-1` remplace `RouteTimeOptions` par `TimeChoice`, sans changer les trois modes déjà exposés.
Le contrôle est le même objet dans les six surfaces, avec un identifiant d'accessibilité stable.
Le test rouge actuel vient du libellé de requête rendu sous le bord visible ; `TIME-1` le remonte
au-dessus des cartes de segment et le rend atteignable sans défilement.

### 3.4 Phase 8b : calques du monde

| Lot | Taille | Résultat visible | Fichiers possédés | Ne touche pas | Dépend de |
|---|---|---|---|---|---|
| **A-1** | M | Les avions autour de la vue, avec cap, altitude et indicatif. Un toucher ouvre une fiche. Plafond de 300 avions, cache de 10 s, état de quota visible. | `iosApp/Vela/Map/Layers/AviationLayer.swift` ; `ios-shared/src/commonMain/kotlin/app/vela/ios/world/AviationStore.kt` (nouveau) ; `ios-shared/src/commonTest/kotlin/app/vela/ios/world/AviationStoreTest.kt` ; `docs/ios/WORLD-LAYERS.md` (nouveau) | `MapController.swift`, `LayersView.swift`, `MapScreen.swift`, `SettingsScreen.swift`, `WorldLayers.swift`, `WorldLayerSection.swift`, Android | WLD-1 |
| **A-2** | L | Les navires AIS autour de la vue, avec cap, vitesse, type et MMSI, depuis Digitraffic en Finlande sans clé, ou depuis AISHub avec la clé d'un membre. Une liste UKMTO horodatée avec titre, date et lien, sans zone dessinée. | `iosApp/Vela/Map/Layers/MaritimeLayer.swift` ; `ios-shared/src/commonMain/kotlin/app/vela/ios/world/MaritimeStore.kt`, `MaritimeSources.kt`, `UkmtoStore.kt` (nouveaux) ; `ios-shared/src/commonTest/kotlin/app/vela/ios/world/MaritimeStoreTest.kt`, `UkmtoStoreTest.kt` ; `docs/ios/WORLD-LAYERS.md` | `MapController.swift`, `LayersView.swift`, `MapScreen.swift`, `SettingsScreen.swift`, `WorldLayers.swift`, `WorldLayerSection.swift`, Android | WLD-1 |
| **A-3** | L | L'intensité carbone par zone en Grande-Bretagne, sans clé, avec couleur et horodatage. Les pannes et attaques Cloudflare Radar avec un jeton utilisateur. Electricity Maps seulement avec une clé utilisateur, sinon l'écran dit « clé requise ». | `iosApp/Vela/Map/Layers/EnergyLayer.swift`, `RadarLayer.swift` ; `iosApp/Vela/Resources/world/neso-regions.json` (nouveau) ; `ios-shared/src/commonMain/kotlin/app/vela/ios/world/EnergyStore.kt`, `CarbonIntensitySource.kt`, `ElectricityMapsSource.kt`, `RadarStore.kt` (nouveaux) ; `ios-shared/src/commonTest/kotlin/app/vela/ios/world/EnergyStoreTest.kt`, `RadarStoreTest.kt` ; `docs/ios/WORLD-LAYERS.md` | `MapController.swift`, `LayersView.swift`, `MapScreen.swift`, `SettingsScreen.swift`, `WorldLayers.swift`, `WorldLayerSection.swift`, Android | WLD-1 |
| **A-4** | M | Les NOTAM américains en texte et, quand le GeoJSON en porte, en zone, avec filtre par aéroport ou rayon et date d'expiration. La mention « information only, not for operational use » est visible. Si l'accès NMS n'est pas obtenu, le lot s'arrête et aucune couche n'existe. | `iosApp/Vela/Map/Layers/NotamLayer.swift` ; `ios-shared/src/commonMain/kotlin/app/vela/ios/world/NotamStore.kt`, `NotamSource.kt` (nouveaux) ; `ios-shared/src/commonTest/kotlin/app/vela/ios/world/NotamStoreTest.kt` ; `docs/ios/WORLD-LAYERS.md` | `MapController.swift`, `LayersView.swift`, `MapScreen.swift`, `SettingsScreen.swift`, `WorldLayers.swift`, `WorldLayerSection.swift`, Android | WLD-1 |
| **G-3** | M | Les satellites sur le globe de G-2, avec position, trajectoire, identification et prochain passage au-dessus de la position. Les TLE sont en cache deux heures. L'atmosphère n'apparaît que si G-2 la porte. | `core-common/src/commonMain/kotlin/app/vela/core/sat/Sgp4.kt` (nouveau) ; `core-common/src/commonTest/kotlin/app/vela/core/sat/Sgp4Test.kt` ; `ios-shared/src/commonMain/kotlin/app/vela/ios/world/SatelliteStore.kt` (nouveau) ; `ios-shared/src/commonTest/kotlin/app/vela/ios/world/SatelliteStoreTest.kt` ; `iosApp/Vela/Map/Layers/SatelliteLayer.swift`, `SatelliteOrbitLayer.swift` ; `docs/ios/GLOBE-SPIKE.md` | `MapController.swift`, `MapScreen.swift`, `RouteSheets.swift`, `PlaceSheet.swift`, `SettingsScreen.swift`, Android UI, le code de projection de G-2 | G-2 |

| Lot | Preuve d'acceptation | Source et conditions | Risque |
|---|---|---|---|
| **A-1** | `AviationStoreTest` sur une fixture, le plafond de 300, le 429, la péremption à 60 s et le refus d'un avion hors zone. `AviationLayerUITests.testAircraftAroundView` avec `aviation.png`, `aviation-detail.png` ; lignes `aviation_count>0`, `aviation_source=fixture`, `aviation_live=0` ; passe live facultative sur le Mac. | adsb.lol, ODbL 1.0, hôte `api.adsb.lol`, attribution « Data from adsb.lol, ODbL 1.0 ». Notice `adsb-lol` à ajouter. | Pas de SLA ni de quota garanti ; couverture communautaire inégale au-dessus des océans et en Afrique ; pas de flux militaire officiel ; ODbL, pas de base dérivée livrée ; information seulement. |
| **A-2** | `MaritimeStoreTest` sur Digitraffic GeoJSON, AISHub XML et JSON, la déduplication par MMSI, le plafond de 500 et le cache de 5 min ; `UkmtoStoreTest` sur le titre, la date et le lien seulement. `MaritimeUITests.testShipsAndUkmtoList` avec `maritime.png`, `maritime-detail.png`, `ukmto.png` ; lignes `maritime_count>0`, `ukmto_mode=link_only`. Digitraffic en live sur le Mac, AISHub en manuel avec une clé. | Digitraffic, CC BY 4.0, hôte `meri.digitraffic.fi`, attribution « AIS data: Fintraffic Digitraffic, CC BY 4.0 ». AISHub, conditions AISHub, hôte `data.aishub.net`, attribution « Data: AISHub contributors ». UKMTO, Crown copyright, hôte `www.ukmto.org`, lien seulement. Notices `digitraffic-ais`, `aishub`, `ukmto` à ajouter. | AISHub exige une station et une clé personnelle, une requête par minute, pas de clé globale ; Digitraffic ne couvre que la Finlande ; UKMTO sans conditions ouvertes ; AIS ne doit pas servir à la navigation ; vie privée des navires. |
| **A-3** | `EnergyStoreTest` sur les zones britanniques, la péremption à 30 min et l'absence de clé ; `RadarStoreTest` sur le jeton, les pannes et la péremption. `EnergyRadarUITests.testCarbonAndRadar` avec `energy.png`, `radar.png`, `energy-key-required.png` ; lignes `energy_source=neso`, `radar_state=fresh` ou `key_required`. NESO en live, Radar en manuel avec un jeton. | Carbon Intensity API, CC BY 4.0, hôte `api.carbonintensity.org.uk`, attribution « Carbon Intensity API, NESO, CC BY 4.0 ». Electricity Maps, conditions du service, hôte `api.electricitymaps.com`, clé utilisateur. Cloudflare Radar, CC BY-NC 4.0, hôte `api.cloudflare.com`, jeton utilisateur. Notices `carbon-intensity`, `electricity-maps`, `cloudflare-radar`. | Electricity Maps sans palier gratuit anonyme ; Grande-Bretagne seulement sans clé ; CC BY-NC interdit un usage commercial ; jeton Cloudflare ; Radar ne voit que le trafic Cloudflare, pas tout Internet ; horodatage obligatoire. |
| **A-4** | `NotamStoreTest` sur le GeoJSON avec et sans géométrie, les types N, R et C, l'expiration et le texte brut ; `NotamUITests.testNotamTextAndZone` avec `notam-map.png`, `notam-text.png`, `notam-no-geometry.png` ; lignes `notam_count>0`, `notam_geometry=1`, `notam_operational=0`. Live avec identifiants en manuel, États-Unis seulement. | FAA NMS, œuvre du gouvernement américain, accès OAuth2 sur demande, hôte fourni avec les identifiants. Notice `faa-notam`. Attribution « FAA NOTAM data, U.S. Government work, not for operational use ». | Accès non self-serve, migration NMS en cours, couverture américaine, textes volumineux, aucune promesse de sécurité opérationnelle. |
| **G-3** | `Sgp4Test` sur trois TLE à une époque fixe, écart inférieur à 1 km ; `SatelliteStoreTest` sur le cache de deux heures, l'absence de requête si le cache est frais, l'horizon et le prochain passage. `SatelliteUITests.testSatellitesOverGlobe` avec `satellites.png`, `satellite-orbit.png`, `satellite-pass.png` ; lignes `sat_count>0`, `sat_projection=globe`, `sat_next_pass_min>0`. Passe iPhone. | CelesTrak GP, données libres avec attribution et politique d'usage, hôte `celestrak.org`, attribution « CelesTrak, Dr T.S. Kelso ». Notice `celestrak`. | TLE vite périmés ; politique CelesTrak (une requête par deux heures, arrêt sur erreur non 200) ; dépendance au globe G-2 ; pas d'atmosphère garantie ; pas de nouveau TLE hors ligne, seulement la propagation des TLE en cache. |

`A-1` interroge `https://api.adsb.lol/v2/point/{lat}/{lon}/{radius}` avec un rayon maximal de
250 milles marins, un rayon utile de 100, et un plafond de 300 avions les plus proches du milieu.
Une réponse 429 met le calque en état « quota » et arrête les requêtes pendant 60 s. Un avion sans
indicatif garde son hexadécimal, jamais un nom fabriqué.

`A-2` interroge Digitraffic sur `https://meri.digitraffic.fi/api/ais/v1/locations` et AISHub sur
`https://data.aishub.net/ws.php`. Une clé AISHub absente laisse le calque sur Digitraffic et
l'écrit. UKMTO ne fournit que des lignes de liste, avec `https://www.ukmto.org` en lien. Aucun
texte d'avis n'est recopié et aucune zone n'est dessinée.

`A-3` interroge `https://api.carbonintensity.org.uk/regional` pour les 14 zones britanniques. Les
centres des zones sont dans `neso-regions.json`, marqués comme approximatifs. Cloudflare Radar
passe par `https://api.cloudflare.com/client/v4/radar/annotations/outages` et la famille
`attacks`, avec un jeton utilisateur. Electricity Maps passe par son API avec la clé de
l'utilisateur, et n'est pas activé sans elle.

`A-4` commence par une session de go/no-go : demande d'accès NMS, essai sur l'environnement de
test, vérification du GeoJSON et des types N, R et C. Si l'accès n'est pas accordé, le lot est
abandonné et `PORTAGE_IOS.md` est corrigé dans le même commit. Aucun scraping de l'interface web
n'est fait.

`G-3` télécharge les TLE par groupe (`stations`, `weather`, `gps-ops`, `science`) plutôt que la liste
active entière, avec un cache de deux heures et un arrêt sur toute réponse non 200. La propagation
SGP4 est locale et testée sur JVM. Si G-2 retient le repli GL JS, la couche satellites est écrite
dans `Resources/globe/` et non dans `SatelliteLayer.swift` ; le lot le dit dans sa PR.

### 3.5 Phase 8c : savoir ouvert

| Lot | Taille | Résultat visible | Fichiers possédés | Ne touche pas | Dépend de |
|---|---|---|---|---|---|
| **W-1** | L | La fiche lieu gagne une section « En savoir plus » avec la population, l'ouverture, le site, les identifiants Wikidata et un extrait Wikivoyage, avec lien et attribution. La carte gagne un calque d'articles Wikivoyage géolocalisés. Aucune image n'est affichée dans ce lot : la section renvoie vers la page source. | `iosApp/Vela/Place/PlaceKnowledgeSection.swift` (nouveau) ; `iosApp/Vela/Place/PlaceSheet.swift` (une ancre) ; `iosApp/Vela/Place/PlaceModel.swift` ; `iosApp/Vela/Map/Layers/WikiLayer.swift` ; `ios-shared/src/commonMain/kotlin/app/vela/ios/place/WikiStore.kt`, `WikiModels.kt` (nouveaux) ; `ios-shared/src/commonTest/kotlin/app/vela/ios/place/WikiStoreTest.kt` ; `docs/ios/PLACE.md` | `MapController.swift`, `LayersView.swift`, `MapScreen.swift`, `SettingsScreen.swift`, `WorldLayers.swift`, `WorldLayerSection.swift`, le parseur Google de la fiche lieu, Android | WLD-1 |

| Lot | Preuve d'acceptation | Source et conditions | Risque |
|---|---|---|---|
| **W-1** | `WikiStoreTest` sur les champs Wikidata, l'extrait Wikivoyage, le repli de langue, le cache de 24 h et l'absence d'image ; `PlaceKnowledgeUITests.testWikidataAndWikivoyage` avec `place-wikidata.png`, `place-wikivoyage.png`, `wiki-layer.png` ; lignes `wiki_fields>=2`, `wikivoyage_chars>0`, `wiki_image=none`. Live sur un lieu connu, puis passe iPhone. | Wikidata, CC0 1.0, hôte `www.wikidata.org`. Wikivoyage, CC BY-SA 4.0, hôte `api.wikimedia.org`, attribution « Wikivoyage contributors, CC BY-SA 4.0 ». Notices `wikidata` et `wikivoyage`. | Données Wikidata lacunaires ou fausses ; couverture Wikivoyage inégale ; attribution et partage à l'identique ; limites d'API ; aucune image, donc pas de risque de fichier non libre mais une fiche moins riche. |

`W-1` interroge Wikidata par `https://www.wikidata.org/w/api.php?action=wbgetentities`, avec les
propriétés P1082 (population), P1619 (date d'ouverture), P856 (site), P625 (coordonnées) et les
identifiants.
L'extrait Wikivoyage passe par
`https://api.wikimedia.org/core/v1/wikivoyage/{lang}/page/{title}`, puis un nettoyage HTML testé
sur JVM. La langue suit celle de l'interface, avec repli sur l'anglais. Un champ absent n'est pas
affiché. Un article sans coordonnée n'entre pas dans le calque.

### 3.6 Phase 8d : Atlas Obscura et Gastro Obscura, lien seulement

Vérification faite le 2026-10-29, avec un agent de navigateur Safari. Un client HTTP nu reçoit un
403 Cloudflare sur toutes les pages, y compris `robots.txt` : le site est derrière une gestion de
robots active, et ses conditions interdisent explicitement de contourner une mesure d'accès.

- `https://www.atlasobscura.com/terms`, conditions à jour du 2021-05-20, disent : usage
  « solely for your personal, noncommercial use » ; interdiction de « copy or distribute any part
  of the Service in any medium without Atlas Obscura's prior written authorization » ; le texte,
  les photos et la compilation appartiennent à Atlas Obscura ; interdiction de toute charge
  déraisonnable et de tout contournement des mesures d'accès.
- `https://www.atlasobscura.com/robots.txt` autorise `/places/*` et interdit `/search*`, et
  publie `https://www.atlasobscura.com/sitemaps/sitemap_index.xml.gz`.
- Les plans de site existent : `sitemaps/places.xml.gz` (32 368 URL), `sitemaps/gastro.xml.gz`
  (1 387 URL, dont 1 383 en `/foods/`), plus articles, events et destinations. Ils ne portent que
  des URL et un `lastmod`, aucune coordonnée.
- Chaque page `/places/...` embarque un JSON-LD schema.org avec `geo.latitude`, `geo.longitude` et
  une description. Les pages `/foods/...` portent `"latitude": null` et `"longitude": null` : un
  article de Gastro Obscura n'est pas géolocalisé.
- Aucune API publique : `https://www.atlasobscura.com/api` et `/api/v1` rendent 404, et
  `api.atlasobscura.com` ne résout pas. Des prestataires tiers vendent un scraper en affirmant
  l'existence d'une API JSON de recherche ; cette affirmation n'est pas vérifiée, et un tel accès
  serait du moissonnage, interdit par les conditions.
- Le site construit lui-même l'URL `https://www.atlasobscura.com/search?utf8=%E2%9C%93&q=&location=&nearby=true&lat=..&lng=..`
  depuis `/search/search_nearby`. Testée le 2026-10-29 avec les coordonnées de Paris, elle rend une
  page de lieux parisiens. C'est une navigation d'utilisateur dans un navigateur, pas une requête
  de l'application.

Verdict : ni calque, ni article stocké, ni résultat de recherche. Les conditions réservent le
service à un usage personnel et non commercial et interdisent la copie ; `robots.txt` interdit en
plus `/search*` aux robots. Ce qui reste légal et utile est une action qui ouvre une page du site
dans la feuille web, avec les coordonnées dans l'URL, sans rien lire ni garder. `AO-1` et `AO-2` ne
sont donc pas des calques et ne touchent pas `WLD-1`.

Non vérifié, et à revérifier par le lot qui écrira le code : le contenu exact des conditions à la
date du lot (elles peuvent changer sans préavis), la stabilité des paramètres `nearby`, `lat` et
`lng`, le comportement de Cloudflare envers une navigation `SFSafariViewController`, et l'état d'une
éventuelle autorisation écrite, qui n'a pas été demandée. Aucune autorisation n'est supposée : la
formule « used with permission » est fausse et ne doit jamais apparaître.

| Lot | Taille | Résultat visible | Fichiers possédés | Ne touche pas | Dépend de |
|---|---|---|---|---|---|
| **AO-1** | S | Dans la fiche lieu, une ligne « Nearby places on Atlas Obscura » ouvre le site dans une feuille web, sur sa recherche par proximité centrée sur les coordonnées du lieu. La ligne dit « link only », nomme la source et ne montre aucun titre, aucun texte et aucune photo venus d'Atlas Obscura. Aucun calque, aucun stockage, aucune requête réseau lancée par Vela. | `iosApp/Vela/Place/PlaceObscuraLinks.swift` (nouveau) ; `iosApp/Vela/Place/PlaceSheet.swift` (une ancre) ; `ios-shared/src/commonMain/kotlin/app/vela/ios/place/ObscuraLinks.kt` (nouveau) ; `ios-shared/src/commonTest/kotlin/app/vela/ios/place/ObscuraLinksTest.kt` (nouveau) ; `iosApp/Vela/Settings/Notices.json` ; `docs/ios/PLACE.md` | `MapController.swift`, `LayersView.swift`, `MapScreen.swift`, `WorldLayers.swift`, `WorldLayerSection.swift`, `SettingsScreen.swift`, le parseur Google de la fiche lieu, `PlaceKnowledgeSection.swift`, Android | aucune, hors voie F libre |
| **AO-2** | S | La même section gagne une seconde ligne « Food places on Gastro Obscura » qui ouvre `https://www.atlasobscura.com/gastro/places` dans la même feuille web. Aucune coordonnée n'est envoyée : Gastro n'offre aucun filtre par position. Aucun article `/foods/`, aucun titre et aucune photo n'est stocké. | `iosApp/Vela/Place/PlaceObscuraLinks.swift` (seconde ligne) ; `ios-shared/src/commonMain/kotlin/app/vela/ios/place/ObscuraLinks.kt` (constante Gastro) ; `ios-shared/src/commonTest/kotlin/app/vela/ios/place/ObscuraLinksTest.kt` (deux cas) | `PlaceSheet.swift`, `MapController.swift`, `LayersView.swift`, `MapScreen.swift`, `WorldLayers.swift`, `WorldLayerSection.swift`, `SettingsScreen.swift`, `Notices.json`, Android | AO-1 |

| Lot | Preuve d'acceptation | Source et conditions | Risque |
|---|---|---|---|
| **AO-1** | `ObscuraLinksTest` sur l'URL de proximité : hôte, chemin `/search`, latitude et longitude à six décimales, coordonnée bornée, aucun autre paramètre et aucun texte d'article. `PlaceObscuraUITests.testAtlasObscuraLinkOpensWebSheet` avec `place-atlas-obscura.png` ; lignes `obscura_action=atlas_nearby` et `obscura_host=www.atlasobscura.com`. Le scénario ouvre une fiche, vérifie la ligne et la mention « link only », touche la ligne, vérifie l'apparition du bouton « Done » de la feuille Safari, capture, puis ferme. Passe iPhone pour la présentation. | Atlas Obscura, tous droits réservés, aucune condition de réutilisation ouverte et aucune autorisation écrite obtenue, hôte `www.atlasobscura.com`, lien seulement. Notice `atlas-obscura` à ajouter, `kind: data`, `license: All rights reserved, link only`, `url: https://www.atlasobscura.com/terms`, note « Atlas Obscura and Gastro Obscura, link only, no content stored ». Attribution affichée : « Atlas Obscura, link only ». | Les paramètres `nearby`, `lat` et `lng` ne sont pas documentés et peuvent changer : si la page ne centre plus, la ligne ouvre `/places` sans coordonnée et le dit. Cloudflare peut refuser un client non navigateur, mais la feuille Safari est un vrai navigateur. Les conditions interdisent tout usage non personnel et toute copie : la ligne ne doit jamais devenir une liste de lieux. Aucune autorisation écrite n'a été demandée ; un lot futur peut l'obtenir et rouvrir le sujet. |
| **AO-2** | `ObscuraLinksTest` sur l'URL Gastro : hôte, chemin `/gastro/places`, absence de paramètre de coordonnée et absence de `/foods/`. `PlaceObscuraUITests.testGastroObscuraLinkOpensWebSheet` avec `place-gastro-obscura.png` ; ligne `obscura_action=gastro_places`. Passe iPhone. | Même source et même notice `atlas-obscura`, aucun nouvel élément : Gastro Obscura est le même domaine et la même société. Aucune notice ajoutée, donc `check_notices.py` reste vert sans changement. | Gastro n'a pas de recherche par proximité : la ligne ne peut pas envoyer les coordonnées, contrairement à la demande initiale, et le dit dans son libellé. Les lieux de Gastro sont des pages `/places` ordinaires, non filtrables par position ; les articles `/foods` n'ont pas de coordonnée et ne pourraient pas entrer dans une carte même avec une autorisation. |

`AO-1` construit l'URL côté Kotlin, dans `ObscuraLinks`, et la passe à Swift. Le format est celui que
le site se donne à lui-même : `q=` et `location=` vides, `nearby=true`, puis `lat` et `lng` avec six
décimales. Aucune autre valeur n'est ajoutée, et aucune réponse n'est lue. Le Swift présente un
`SFSafariViewController`, comme `WikiLayer.swift` le fait déjà pour Wikivoyage ; il ne réutilise pas
`HiddenWebView`, qui sert à lire des pages et non à les montrer.

`AO-2` n'ajoute qu'une entrée à la liste que `AO-1` affiche. Les deux lots partagent
`PlaceObscuraLinks.swift` et `ObscuraLinks.kt` : `AO-2` ne démarre pas avant `AO-1` mergé, et il ne
rouvre pas `PlaceSheet.swift`. La voie F reste occupée par `AO-1` le temps d'une ancre.

Le libellé de la ligne ne cite jamais un nom de lieu trouvé chez eux. Il dit « Nearby places on
Atlas Obscura » et « Food places on Gastro Obscura » : ces mots sont les nôtres et ne recopient rien.

## 4. Ordre des dépendances

```
WLD-1 ─┬─ M-1 ─┬─ G-2 ─ G-3
       ├─ M-2  │
       ├─ A-1  │
       ├─ A-2  │
       ├─ A-3  │
       ├─ A-4  │
       └─ W-1  │
G-1 ───────────┘
TIME-1 ─ T-2 ──┘
```

`T-2` dépend aussi de la voie `MapController.swift`, ouverte par `M-1` et reprise par `G-2` après
lui. `W-1` ne démarre pas tant qu'un lot `PLC-PAGE` ou `PLC-REVIEW` tient `PlaceSheet.swift`. `G-3` ne démarre
pas avant le verdict de `G-2`.

## 5. Plan de vagues

Les voies rappellent les fichiers chauds. Une voie vide est libre pour un lot plus tardif.

| Voie | Fichiers |
|---|---|
| A | `iosApp/Vela/Map/MapScreen.swift` |
| B | `iosApp/Vela/Routes/RouteSheets.swift` |
| C | `iosApp/Vela/Settings/SettingsScreen.swift` |
| D | `iosApp/Vela/Map/MapController.swift`, `MapView.swift` |
| E | `iosApp/Vela/Map/Layers/LayersView.swift`, `MapStyleBuilder.swift` |
| F | `iosApp/Vela/Place/PlaceSheet.swift`, `PlaceModel.swift` |
| G | `iosApp/project.yml`, paquet ou framework MapLibre |
| H | `scripts/ios/`, `tools/` |

| Vague | Lots | Voies occupées | Sessions | Sortie |
|---|---|---|---:|---|
| 0 | `WLD-1`, `G-1` | D, E pour WLD-1 ; H pour G-1 | 5 | hôte des calques, verdict globe |
| 1 | `M-1`, `TIME-1`, `A-1`, `A-3`, `W-1` | D, E pour M-1 ; B pour TIME-1 ; F pour W-1 ; aucune pour A-1 et A-3 | 17 | 3D et relief ombré, contrôle d'heure unique, avions, énergie, savoir ouvert |
| 2 | `T-2`, `G-2`, `M-2`, `A-2`, `A-4` | D pour T-2 puis G-2 ; G pour G-2 ; A pour M-2 ; aucune pour A-2 et A-4 | 23 | transports complets, globe, relief déformé, marine, NOTAM |
| 3 | `G-3` | aucune, une fois G-2 mergé | 3 | satellites sur le globe |
| 8d | `AO-1`, puis `AO-2` | F pour AO-1 (une ancre) ; aucune pour AO-2 | 2 | deux liens vers Atlas Obscura et Gastro Obscura |
| **Total** | | | **50** | |

Ce qui tourne ensemble sans partager de fichier :

- `WLD-1` et `G-1` en vague 0.
- En vague 1, `M-1`, `TIME-1`, `A-1`, `A-3` et `W-1` sont disjoints. `A-1` et `A-3` ne touchent
  que leur fichier de calque et leur magasin Kotlin.
- En vague 2, `M-2`, `A-2` et `A-4` sont disjoints. `T-2` et `G-2` se succèdent sur la voie D et
  la voie G : ce sont les deux seuls lots sérialisés de la vague.
- La moitié Kotlin de `T-2` (`core-common` et `ios-shared/transit`) peut démarrer en vague 1, mais
  ses six sessions sont comptées en vague 2 pour ne pas compter deux fois.

Ce qui est sérialisé :

- `WLD-1` avant tous les calques du monde.
- `TIME-1` avant `T-2`, à cause de `TransitTripScreen.swift` et `TransitOptionsSheet.swift`.
- `M-1` avant `G-2` et `M-2`, à cause de `MapController.swift` et `LayersView.swift`.
- `G-1` avant `G-2`, puis `G-2` avant `G-3`.
- `T-2` avant `G-2` sur la voie D.
- `W-1` avant ou après un lot `PlaceSheet`, jamais en même temps.
- `AO-1` avant `AO-2` : les deux partagent `PlaceObscuraLinks.swift` et `ObscuraLinks.kt`.

Le nominal est de **48 sessions d'agent**. La fourchette est de **40 en optimiste** si `A-4` est
abandonné tôt et si le repli GL JS de `G-2` évite le fork natif, et de **58 en réaliste** avec les
reprises de harnais, les passes iPhone et une deuxième tentative sur le globe.

`AO-1` et `AO-2` sont deux lots `S` hors vague : ils ne prennent aucune voie du chemin critique et
peuvent se glisser dès que la voie F est libre. Ils ajoutent **2 sessions**, pour un nominal de
**50**.

## 6. Effort et budget Mac

| Vague | Sessions |
|---|---:|
| 0 | 5 |
| 1 | 17 |
| 2 | 23 |
| 3 | 3 |
| 8d | 2 |
| **Total nominal** | **50** |

Le nominal demande environ 23 lancements Mac, à étaler sur deux mois ou à regrouper par classe :
`WLD-1` 1, `M-1` 2, `M-2` 2, `G-1` 2, `G-2` 3, `T-2` 3, `TIME-1` 1, `A-1` 1, `A-2` 1, `A-3` 1,
`A-4` 1, `G-3` 2, `W-1` 2, `AO-1` et `AO-2` 1. Un repo privé gratuit offre environ 200 minutes macOS réelles par mois.
La phase 8 ne démarre pas avant la parité utile, et chaque lot groupe ses vérifications dans un
seul script.

## 7. Notices, conditions et attribution

`scripts/ios/check_notices.py` lit les hôtes dans `core-common/src/commonMain`,
`ios-shared/src/commonMain` et `iosApp/Vela`, dans les fichiers `.swift`, `.kt`, `.json`, `.c` et
`.h`. Il refuse un hôte sans notice, une notice sans `id`, `title`, `kind`, `license`, `url` ou
`note`, et un hôte listé par deux notices. L'étape tourne avant la compilation dans
`scripts/ios/ci-ipa.sh`.

| Source | Conditions | Ligne d'attribution à mettre dans `note` | Hôte scruté | Blocage |
|---|---|---|---|---|
| AWS Terrain Tiles | données ouvertes sous conditions multiples, attribution obligatoire | la liste de 11 lignes de `tilezen/joerd/docs/attribution.md`, recopiée telle quelle : ArcticDEM, Australie, Autriche, Canada, Copernicus EU-DEM, NOAA ETOPO1, INEGI, LINZ, Kartverket, Environment Agency, USGS 3DEP, GMTED2010 et SRTM | `s3.amazonaws.com` | oui, dès la première URL |
| MapLibre GL JS | BSD-3-Clause | « MapLibre GL JS, BSD-3-Clause » | aucun, le fichier est embarqué | non, mais notice nécessaire pour About |
| adsb.lol | ODbL 1.0 | « Data from adsb.lol, ODbL 1.0, https://adsb.lol » | `api.adsb.lol` | oui |
| Digitraffic AIS | CC BY 4.0 | « AIS data: Fintraffic Digitraffic, CC BY 4.0, https://www.digitraffic.fi/en/marine-traffic/ » | `meri.digitraffic.fi` | oui |
| AISHub | conditions AISHub, clé personnelle, pas de republication brute | « Data: AISHub contributors, https://www.aishub.net » | `data.aishub.net` | oui |
| UKMTO | Crown copyright, aucune condition ouverte trouvée | « UKMTO advisories, Crown copyright, https://www.ukmto.org, link only » | `www.ukmto.org` | oui |
| Carbon Intensity API | CC BY 4.0 | « Carbon Intensity API, National Energy System Operator, CC BY 4.0, https://carbonintensity.org.uk » | `api.carbonintensity.org.uk` | oui |
| Electricity Maps | conditions du service, clé utilisateur, pas de palier gratuit anonyme | « Electricity Maps, https://www.electricitymaps.com » | `api.electricitymaps.com` | oui |
| Cloudflare Radar | CC BY-NC 4.0, jeton utilisateur | « Cloudflare Radar, CC BY-NC 4.0, https://radar.cloudflare.com » | `api.cloudflare.com` | oui |
| FAA NOTAM | œuvre du gouvernement américain, accès OAuth2 sur demande | « FAA NOTAM data, U.S. Government work, not for operational use, https://www.faa.gov/about/initiatives/notam » | hôte NMS fourni avec les identifiants | oui, quand l'hôte est figé |
| CelesTrak | données libres avec attribution, politique d'usage | « CelesTrak, Dr T.S. Kelso, https://celestrak.org » | `celestrak.org` | oui |
| Wikidata | CC0 1.0 | « Wikidata, CC0 1.0, https://www.wikidata.org » | `www.wikidata.org` | oui |
| Wikivoyage | CC BY-SA 4.0 | « Wikivoyage contributors, CC BY-SA 4.0, https://www.wikivoyage.org » | `api.wikimedia.org` | oui |
| Atlas Obscura et Gastro Obscura | tous droits réservés, usage personnel et non commercial seulement, aucune autorisation écrite obtenue | « Atlas Obscura, link only, https://www.atlasobscura.com » | `www.atlasobscura.com` | oui, dès le premier littéral |

Points de vigilance :

- **Terrain.** La liste complète est longue et contient des noms officiels anglophones. Elle est
  recopiée depuis `tilezen/joerd/docs/attribution.md` sans la raccourcir. Une notice `terrain-tiles`
  avec `kind: "data"` et `hosts: ["s3.amazonaws.com"]` suffit pour le contrôle, pas pour
  l'attribution à l'écran : la feuille de couches affiche un lien vers la notice complète.
- **Globe natif.** Ajouter `Vendor/MapLibreGlobe.xcframework` dans `iosApp/project.yml` fait
  échouer `check_notices.py` avec « vendor framework MapLibreGlobe: no notice mapping ». Le lot
  `G-2` ajoute la ligne `MapLibreGlobe` vers `maplibre` dans `VENDOR_FRAMEWORKS`. La notice
  `maplibre` existe déjà, aucun texte nouveau n'est nécessaire.
- **MapLibre GL JS.** Le fichier est embarqué, donc le scan d'hôtes ne le voit pas. La notice reste
  obligatoire pour la page About. Aucun CDN, aucun `unpkg`.
- **Wikivoyage.** Le lot passe par `api.wikimedia.org` pour n'avoir qu'un hôte. La notice
  `wikivoyage` est ajoutée avant le premier littéral, sinon le run Mac s'arrête à l'étape Notices.
- **AISHub.** La clé n'est pas dans le binaire. Un utilisateur sans station ne peut pas l'obtenir :
  l'écran le dit et laisse Digitraffic.
- **Cloudflare Radar.** CC BY-NC 4.0 interdit un usage commercial. Si une build payante apparaît,
  la couche est retirée, pas relicenciée.
- **OpenSky et MarineTraffic** ne sont pas employés. OpenSky réserve son API à la recherche et à
  l'enseignement, et exige un accord pour un produit en service. MarineTraffic est commercial. Ils
  n'ont donc pas de notice.
- **Atlas Obscura et Gastro Obscura.** Une seule notice `atlas-obscura` couvre les deux, parce que
  les deux vivent sur `www.atlasobscura.com`. `AO-2` n'ajoute donc aucune entrée et ne touche pas
  `Notices.json`. Aucun autre hôte du site n'entre dans le code : Vela ne charge ni image, ni style,
  ni script d'Atlas Obscura, seulement une page entière dans une feuille web.
- **Lien seulement.** Les conditions d'Atlas Obscura interdisent de copier ou distribuer une partie
  du service. Une ligne qui afficherait le titre d'un lieu, même trouvé par la recherche du site,
  sortirait du périmètre de `AO-1` et `AO-2`. Aucune capture d'écran de l'application ne doit
  contenir de contenu du site en dehors de la feuille web elle-même.

## 8. Ce qui ne sera pas fait

- **CarPlay navigation.** L'entitlement navigation d'Apple n'est pas demandé, et le sideload
  gratuit ne le permet pas.
- **CarPlay combiné d'instruments.** Même raison. Aucune vue de manœuvre sur le cluster.
- **Routeur hors ligne `.obf`.** D7 le laisse hors périmètre. Une région téléchargée fournit la
  carte, les lieux, les adresses et la recherche, pas un itinéraire calculé localement.
- **Terrain3D dans la carte native.** MapLibre Native ne le fournit pas. Le relief déformé reste
  dans l'écran GL JS de `M-2`.
- **Ciel et atmosphère dans la carte native.** `sky` n'est pas implémenté dans MapLibre Native
  (issue #4414). `M-1` ne promet qu'un fond uni. Le ciel n'existe que dans `M-2`, et l'atmosphère
  du globe que si le build de `G-2` la porte.
- **Position GPS des véhicules de transport.** Transitous ne l'expose pas. `T-2` affiche des
  courses et des horaires, jamais un point de véhicule.
- **AIS mondial sans station.** AISHub demande une station et une clé personnelle. Sans elle, la
  couche se limite à Digitraffic en Finlande.
- **NOTAM mondial.** La FAA couvre les États-Unis. Aucune couche mondiale n'est promise, et l'accès
  NMS peut ne pas être accordé.
- **Zones UKMTO.** Sans conditions de réutilisation ouvertes, la couche reste une liste de liens.
- **Calque Atlas Obscura et calque Gastro Obscura.** Les conditions du site réservent le service à
  un usage personnel et non commercial et interdisent de copier ou distribuer toute partie du
  service sans autorisation écrite, tandis que `robots.txt` interdit `/search*` aux robots. Aucun
  calque de lieux, aucun article stocké, aucune photo, aucun résultat de recherche enrichi par
  Atlas Obscura ou Gastro Obscura. `AO-1` et `AO-2` n'ouvrent qu'une page du site dans une feuille
  web, sans rien lire ni garder.
- **Electricity Maps sans clé.** Pas de palier gratuit anonyme. Sans clé, la couche se limite à la
  Grande-Bretagne avec NESO.
- **Images Wikimédia.** Aucune image n'est affichée dans `W-1`, pour éviter une vérification de
  conditions fichier par fichier. La section renvoie vers la page source.
- **Pas de couverture mondiale garantie** pour `A-1`, `A-2`, `A-4` et `G-3`. Ces sources sont
  communautaires, nationales ou expérimentales, et l'interface doit le dire.

## 9. Vérifications avant de pousser

```
python3 scripts/ios/parity_check.py --check
python3 scripts/ios/test_parity_check.py
python3 scripts/ios/check_notices.py
scripts/check-writing.sh $(git merge-base ios/main HEAD)..HEAD
```

`FEATURES-IOS.md` n'est pas modifié par ce document. `check_notices.py` reste vert tant qu'aucun
littéral d'hôte des sections 3 et 7 n'est ajouté. Chaque lot qui ajoute une source lance la
quatrième commande et joint la sortie à sa PR.

## 10. Règle de mise à jour

Quand un lot est mergé, le coordinateur :

1. met à jour la ligne du lot dans `PORTAGE_IOS.md` et dans ce document, avec le tag du run et les
   captures ;
2. met à jour `FEATURES-IOS.md` si le lot ferme une ligne de la matrice, avec le nom du test ou du
   run ;
3. ajoute la notice et l'attribution dans le même commit que le premier littéral d'hôte ;
4. retire le lot de la section 3 et de la section 5, ou le marque « mergé » avec sa preuve.

Un lot abandonné, comme `A-4` sans accès NMS, est marqué « abandonné » avec la raison, et la ligne
correspondante de `PORTAGE_IOS.md` est corrigée. Aucun lot ne reste « planifié » après son verdict.

## 6. Apres cette phase

Le renderer custom (terrain drape, atmosphere, arbres en volume, mer, meteo temps reel) est planifie
dans [ROADMAP-3D.md](ROADMAP-3D.md). Il ne fait pas partie des 50 sessions ci-dessus et ne bloque
aucun lot de parite.
