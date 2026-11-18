# Carte de la logique de présentation (lot P-0)

Ce document dit ce que contiennent `MapViewModel`, `NavController` et les holders de `ui/`, ce
que chaque fonction iOS de V1 en tire, et où chaque morceau doit aller : `:core` (déjà prévu par
`CORE-MIGRATION.md`), `:core-common` (helper pur sorti de `:app`), un store de `:ios-shared`, ou
le Swift seul. Il sert de base aux lots I-1 à I-8 et à V-2.

Mesures prises sur `ios/main` au commit `cfd98ca9`, dont `MapViewModel.kt` est identique à
`origin/main` `090d1e18` (2026-10-19). Outil : `scripts/ios/vm_map.py` (Python 3, bibliothèque
standard, réutilise le lexeur de `core_deps.py`, environ 9 s).

```
python3 scripts/ios/vm_map.py                         # résumé par fonction de MapViewModel
python3 scripts/ios/vm_map.py --members [--feature search] [--tier PURE]
python3 scripts/ios/vm_map.py --state                 # champs de MapUiState et qui les écrit
python3 scripts/ios/vm_map.py --file ui/map/NavController.kt
python3 scripts/ios/vm_map.py --holders               # objets et classes à état de ui/
python3 scripts/ios/vm_map.py --churn <rev>           # lignes changées depuis <rev>, par fonction
python3 scripts/ios/vm_map.py --check docs/ios/PRESENTATION-MAP.md   # dérive des fonctions portées
python3 scripts/ios/vm_map.py --md docs/ios/PRESENTATION-MAP.md      # régénère le bloc « surveillance »
```

## 0. En bref

- `MapViewModel` : 10 759 lignes, une classe (463-10754), **669 membres** de premier niveau,
  **311 fonctions publiques** (290 appelées par leur nom hors du fichier, 109 depuis
  `MapScreen.kt`), **39 collaborateurs** injectés, un seul état `MapUiState` de **211 champs**
  (115-456), **982** écritures de champ par `.copy(...)`.
- « 3 imports Android » est vrai mais trompeur : le corps contient **219 noms Android
  qualifiés** (`android.util.Log` ×61, `SystemClock` ×25, `Intent` et ses constantes ×49, `ConnectivityManager` et `NetworkCapabilities` ×28),
  **154 références `R.*`** (129 clés distinctes avec `NavController`), 16 `getSharedPreferences`
  et 16 `filesDir`.
- Ce qui se porte : environ **4,7 k lignes** de Kotlin dans `:ios-shared` (stores), plus
  **0,7 k** de helpers purs vers `:core-common`, plus les tests. Le reste est soit déjà dans
  `:core` (le routage, la nav, les parseurs), soit du Swift (UI, réseau système, partage, voix).
- Le point dur n'est pas Android, c'est le **couplage** : 44 des 211 champs sont écrits par trois
  fonctions ou plus (`selected` par 7, `results` par 7, `center` par 9). Des stores indépendants
  se désynchroniseraient. Recommandation : **un seul état, des facettes** (§3.0).
- Le fichier bouge vite : **40 %** de ses lignes ont changé en 30 jours (4 357 lignes depuis
  `9125956c`, 2026-09-19). Toute copie dans `:ios-shared` est surveillée par empreinte (§6).

## 1. MapViewModel

### 1.1 Méthode

1. Lexique : commentaires et texte des chaînes effacés (lexeur de `core_deps.py`).
2. Membres : chaque `fun`, `val`, `var`, `init`, type imbriqué au premier niveau du corps de la
   classe, avec sa plage de lignes (déclaration jusqu'au membre suivant, lignes vides de fin
   retirées ; le KDoc juste au-dessus est compté à part dans « avec commentaires »).
3. Par membre : champs de `MapUiState` écrits (arguments nommés des `.copy(`), collaborateurs du
   constructeur nommés, classes `app.vela.*` nommées (qualifiées ou importées), noms Android
   qualifiés, `appContext`, `R.*`, règles de bloqueurs de `core_deps.py`, appels vers les autres
   membres.
4. Fonction (au sens produit) : règles sur le nom, puis 147 corrections lues dans les corps
   (`OVERRIDES` du script), puis le voisinage d'appels pour 40 membres restants. C'est une mesure,
   pas un découpage parfait : un membre sur dix environ est discutable, les totaux par fonction
   sont fiables à ±10 %.
5. Niveau de dépendance (`tier`) : PURE (ni `_state`, ni collaborateur, ni Android) < STATE
   (`_state`, scope) < CORE (collaborateur `:core`) < APP (classes `:app` : `web/`, `offline/`,
   `voice/`, `replay/`, OkHttp) < ANDROID (API Android, `Context`, `R.*`). Propre au membre, puis
   propagé à ses appelants.

### 1.2 État (`MapUiState`, 211 champs)

Champs par fonction (attribués à la main d'après leurs écrivains, `--state` donne la liste
exacte) :

| Fonction | Champs | Exemples |
|---|---|---|
| Recherche | 19 | `query`, `queryEdits`, `suggestions`, `querySuggestions`, `localSuggestions`, `results`, `resultsMoreQuery`, `resultsLoadingMore`, `resultsBranches`, `resultsBranchesLoaded`, `resultsCollapsed`, `searching`, `showSearchThisArea`, `recents`, `recentPlaces`, `alongRouteDest`, `pendingImport`, `pendingHiddenLayers`, `openListId` |
| Fiche lieu | 21 | `selected`, `tapResolvingFor`, `sheetAlias`, `tapUnlinkedFor`, `placesHere`, `reviews*` (8), `photo*` (5), `loadingDetails`, `hiddenOpenPlaceIds` |
| Itinéraires | 24 | `routes`, `activeRoute`, `directionsOpen`, `directionsReversed`, `directionsOrigin`, `directionsWaypoints`, `picking*` (4), `pickOnMap`, `editingStops`, `travelMode`, `directionsTime*` (2), `modeEtas`, `avoid*` (3), `showSteps`, `previewStepIndex`, `routeTrafficRequested`, `openSavedRouteId`, `flockOnRoute` |
| Transport | 14 | `transit`, `transitLoading`, `transitPrefer`, `transitRoutePref`, `transitNav`, `transitPreview`, `stopDepartures*` (4), `routeDetail*` (3), `transitLines` |
| Navigation | 24 | `navigating`, `navPaused`, `nav` (`NavState`), `maneuverText`, `fasterRoute`, `fasterSavingSeconds`, `arrived*` (4), `navDestAddress`, `navCameraDetached`, `inNavOverview`, `navNorthUp`, `resumeNavLabel`, `navStarved`, `navTap*` (3), `routeBar`, `routeBarEnabled`, `roadNameLatin`, `drivenRouteOffer` |
| Position | 14 | `myLocation`, `myBearing`, `mySpeed`, `myFixRaw`, `mySpeedRaw`, `myAccuracyM`, `myLocationStale`, `compassHeading`, `speedLimitKmh`, `speedLimitOverlayKmh`, `maxspeedOverlays`, `showPsdsTip`, `tipNetworkLocation`, `recenterTick` |
| Caméra, couches | 21 | `center`, `centerZoom`, `startHold`, `startZoom`, `styleUri`, `styleName`, `ambientPois`, `ambientCoversView`, `ambientClosed`, `placesOverlays`, `placesPending`, `placesOneSet`, `buildingOverlays`, `addressOverlays`, `trafficControls`, `flockCameras`, `speedCameras`, `transitStops`, `imageryYear`, `satDeep`, `drawing` |
| Enregistrés | 12 | `saved`, `savedRoutes`, `lists`, `home`, `work`, `assigningShortcut`, `parkingSpot`, `parkedAtMillis`, `parkingHistory` ... |
| Hors ligne | 29 | `routing*` (6), `region*` (9), `poiPack*` (6), `cells*` (2), `basemapArchive`, `areaPick*` (2), `areaDownloadPct`, `updateStage`, `storageMovePct` |
| Voix | 17 | `voiceMuted`, `voiceAlertsOnly`, `voiceSpeed`, `selectedEngine`, `voice*` (6), `asr*` (6), `installingEngine` |
| Divers | 16 | `status*` (5), `notices`, `offline`, `lowData`, `update*` (3), `diagnosticsEnabled`, `tripRecordingEnabled`, `replay*` (6) |

Champs les plus partagés (fonctions distinctes qui les écrivent / écritures), mesurés par
`--state` sur `MapViewModel` et `NavController` :

| Champ | Fonctions | Écritures |
|---|---|---|
| `center` | 9 | 20 |
| `selected` | 7 | 38 |
| `results` | 7 | 31 |
| `activeRoute`, `routes`, `directionsOpen` | 7 | 19, 18, 18 |
| `query` | 6 | 24 |
| `localSuggestions`, `suggestions`, `status`, `showSteps` | 6 | 17, 15, 12, 13 |

`selectPlace` (3346-3407) remet à zéro 20 champs de quatre fonctions ; `clearSelection`
(4606-4637) 15 ; `runSearch` touche aussi `selected` et `offline`. C'est une machine d'état
« bare map / résultats / fiche / itinéraire / nav » qui n'est écrite nulle part en tant que telle.

### 1.3 Fonctions publiques et moteurs privés, par fonction

« Lignes » = lignes de déclaration ; « code » sans lignes vides ni commentaires seuls ;
« And. » = membres qui touchent Android, `Context` ou `R.*`.

| Fonction | Membres | Publiques | Lignes | Code | And. | Plages principales | Gros privés |
|---|---|---|---|---|---|---|---|
| construction | 9 | 0 | 303 | 227 | 1 | 574-849 (`init`), 5915-5950, 7361 | |
| recherche | 42 | 18 | 830 | 626 | 4 | 2540-2907, 1299-1501, 1582-1630, 2046-2273 | `runSearch` 2540-2907 (368), `handleQueryIntent` 2063-2101, `localMatches` 1446-1483 |
| fiche lieu | 66 | 16 | 1 461 | 1 050 | 19 | 3346-3491, 4017-4637, 4729-5538 | `onPoiTap` 4838-5245 (408), `fetchPhotos` 4221-4371 (151), `fetchReviews` 4476-4596 (121), `fetchPlaceDetails` 4034-4092, `mergeDetails` 4117-4152 |
| itinéraires | 72 | 46 | 595 | 519 | 16 | 4672-4715, 5550-5625, 6110-6633, 7112-7158 | `route` 6560-6633, `routeBetween` 2106-2145 |
| navigation | 59 | 30 | 492 | 437 | 11 | 526-559, 6237-6412, 6837-6991, 7262-7311, 9577-10043 | `refreshFlockOnRoute` 6837-6940, `refreshFlock` 9933-10030, `tryCameraDetour` 6949-6991, `priceNavTapDetour` 6361-6395 |
| transport | 51 | 11 | 560 | 485 | 13 | 3496-3785, 7008-7253, 9754-9929 | `refreshTransitLines` 9761-9836, `fetchStopDepartures` 3586-3630, `refreshTransitStops` 9841-9885 |
| enregistrés | 82 | 63 | 738 | 667 | 19 | 1836-2041, 5634-6103, 6646-6823, 7570-7710 | `importTakeoutRows` 7630-7696, `offerSavedRoutes` 6648-6698 |
| hors ligne | 75 | 28 | 1 074 | 957 | 26 | 1698-1796, 7372-7437, 8708-9348, 10047-10586 | `pickBasemapArchive` 9285-9348, `maybeAutoPatch` 7387-7437, `updateRegionNow` 10385-10423 |
| couches, caméra | 52 | 8 | 707 | 523 | 11 | 1248-1291, 4652-4668, 8278-8705, 9217-9745 | `maybeLoadAmbientPois` 8470-8639 (170), `refreshTrafficControls` 9478-9560 |
| Street View | 11 | 5 | 169 | 135 | 5 | 3787-3988 | `loadStreetView` 3831-3899 |
| voix, dictée | 43 | 35 | 261 | 244 | 16 | 7314-7334, 7869-8195 | |
| position | 23 | 6 | 384 | 259 | 4 | 856-1220, 8241-8257, 9394-9425 | `startLocation` 882-1124 (243), `sanePosition` 856-880 |
| liens entrants | 20 | 3 | 270 | 245 | 5 | 3004-3344 | `openTripLink` 3260-3344, `openDirectionsLink` 3140-3174 |
| connectivité | 12 | 1 | 149 | 119 | 5 | 2333-2534 | `observeConnectivity` 2342-2441 |
| statut, notices | 7 | 4 | 38 | 33 | 1 | 1642-1658, 8197-8277 | |
| trajets, diag | 35 | 30 | 214 | 212 | 9 | 7347-7854 | |
| mise à jour APK | 9 | 7 | 65 | 63 | 3 | 1666-1824 | |
| `companion` | 1 | | 166 | 85 | 0 | 10588-10753 | constantes de réglage, `ambientCap` |

Ce dont chaque fonction dépend (classes `:core` nommées, avec leur classe et leur lot dans
`CORE-MIGRATION.md`, et ce qui vient de `:app`) :

| Fonction | `:core` | `:app` et holders |
|---|---|---|
| recherche | `MapDataSource` (PURE, V-1), `GoogleMapsDataSource` (C-2), `MapLinkParser` (C-2), `PhotonGeocoder`, `ShortLinks` (C-3), `RecentSearchStore`, `RecentPlaceStore`, `SavedPlaceStore`, `PlaceListStore`, `OfflinePoiStore`, `OfflineAddressStore` (C-6), `OfflineRank` (C-8), `AddressQuery`, `PlaceNames` (V-1 util), **`QueryIntent`, `AreaNarrow`, `DiagLog` (hors lot)** | `ContactAddresses`, `PlacesArchiveSearch`, `PmtilesReader`, `PlacesTileStore` ; holders `GoogleFree`, `AppLocale`, `ContactsSearch`, `QuickCategories` |
| fiche lieu | `GoogleMapsDataSource` (`placeDetails`, `placePhotoPage`, `reviewFeed`, `searchOnce`, `reverseGeocode`, `nearbyPlaces`), `PhotosParser`, `ReviewFeedParser` (V-1), `PlaceCache`, `StreetViewCache` (C-6), `Transitous` (C-3), `PlaceJson` (C-4) | `WebPhotoFetcher`, `WebReviewsFetcher`, `WebPopularTimesFetcher`, `GoogleStanding`, `UkFuelPrices` ; holders `FullPlaceLoad`, `LoadPhotos`, `PhotosOnTap`, `ShowReviews`, `ReviewsOnTap`, `MapPoiPrefs`, `AppTune`, `MemoryPressure`, `PoiIcons.groupFor` |
| itinéraires | `GoogleMapsDataSource.directions` (dont `directionsPlain`, 779 lignes, C-2), `nameRoute`, `RoutingPrefs`, `RouteCorridor`, `SavedRoutes`, `RouteProjection` (C-5), `SavedRouteStore` (C-6) | `LinkTrip`, `TripPoint`, `TripShortcut`, `RouteTrafficOnTap`, `formatDuration` |
| navigation | `NavSession` (C-5, non déplaçable sans couper l'arête vers `Haptics`), `NavEngine`, `PassAlerts`, `CameraDetour`, `CameraAlerts`, `RouteBar` (C-5), `OverpassAlprCameras`, `OverpassSpeedCameras`, `OverpassTrafficSignals` (C-3), `VoiceGuide` (C-7) | `RoadFeatures`, `FlockCameras`, `NavigationService`, `CarBridge` ; holders `DrivingMode`, `SpeedCams`, `Flock*`, `BridgeAlert` |
| transport | `Transitous`, `TransitOrder`, `RouteGeometry` (C-3), `StopDeparturesParser` (C-2), `TransitLineCache` (C-6) | `WebDirectionsFetcher` (page Google), `WebStopDeparturesFetcher`, `TransitStopCache`, `TransitBoardCache`, `TransitShapes`, `DemoClock` |
| enregistrés | 5 stores `SharedPreferences` (C-6), `TakeoutCsv`, `ImportResult` (C-6), `SavedRoutes` (C-5), `PolylineCodec` (C-2) | export par `Intent`, `FileProvider` |
| hors ligne | `OfflinePacks`, `OfflinePoiStore`, `OfflineAddressStore` (C-6), `ObfRouteEngine` (RESTE), `VelaLinks` | `RegionCatalog`, `PoiPackStore`, `ObfStore`, `OverlayTileStore`, `MaxspeedOverlayStore`, `PlacesTileStore` (607 l.), `BasemapTileStore`, `CellStore`, `RegionPacks`, `OfflineMaps`, `StorageLocation`, `GlyphPackStore`, `DownloadService` |
| position | `FixRules`, `Stillness` (C-5), `LocationProvider`, `HeadingProvider` (RESTE) | `SimLocation`, `AppVisibility`, `AppTheme.rememberLocation`, `Units` |

### 1.4 Exposition Android réelle

| Niveau (propre au membre) | Membres | Lignes |
|---|---|---|
| PURE | 216 | 669 |
| STATE | 147 | 912 |
| CORE | 82 | 907 |
| APP | 56 | 733 |
| ANDROID | 168 | 5 255 |

Les 168 membres ANDROID se répartissent ainsi (mesure dans le corps) : 81 membres (3 729 lignes)
appellent une vraie API Android, 71 (1 335 lignes) ne touchent que `R.string` via
`appContext.getString`, 16 (191 lignes) n'utilisent `appContext` que pour des préférences ou des
fichiers. Les 81 « vraies » : `android.util.Log` (61 appels, couture `Log`), `SystemClock` (25,
couture `Clock`), partage par `Intent`/`FileProvider` (export, trajets : Swift), réseau
`ConnectivityManager` (`observeConnectivity` : Swift `NWPathMonitor`), `Bitmap` (Street View, hors
V1), `Toast` (1), capteurs/télécom/batterie dans `init` (diagnostic). Autrement dit, hors chaînes
et journaux, l'Android du VM se concentre dans cinq zones qui sont toutes du Swift ou hors V1.

Fichiers de préférences lus en direct : `vela_settings` (16 accès dans le VM, 1 dans
`NavController`), `vela_notices`, `vela_nav_resume`. Clés : `avoid_tolls`, `avoid_highways`,
`avoid_ferries`, `travel_mode`, `demo_drive`, `nav_live_rechecks`, `nav_traffic_lights`,
`route_bar`, `spoken_directions`, `spoken_alerts_only`, `voice_engine`, `voice_speed`,
`voice_volume`, `trip_recording_on`, `trip_name_on_save`, `self_update_check`,
`last_update_check_ms`, `update_dismissed_code`, `open_links_build`, et `lat`/`lng`/`label`/
`mode`/`at` pour la reprise de nav.

### 1.5 Constructeur (39 collaborateurs)

`appContext` ; `:core` : `dataSource`, `locationProvider`, `headingProvider`, `voice`,
`navSession`, `recentStore`, `recentPlaceStore`, `savedStore`, `parkingStore`, `listStore`,
`savedRouteStore`, `shortcutStore`, `calibration`, `offlinePoiStore`, `addressStore`, `diag`,
`routeEngine` ; `:app` : 5 fetchers `web/`, `voiceInstaller`, `kokoroInstaller`, `piperSynth`,
`asrRecognizer`, `diagExporter`, `tripStore`, 9 stores `offline/`, `selfUpdater` ; `http`
(OkHttp). Appels à `dataSource` : 17 méthodes distinctes (`search` 18 fois, `searchOnce` 8,
`reverseGeocode` 7, `directions` 7, `placePhotoPage` 5...).

## 2. NavController et les holders de `ui/`

### 2.1 NavController (`ui/map/NavController.kt`, 1 568 lignes)

Classe 39-1533, 105 membres, 10 collaborateurs (`appContext`, `scope`, `_state` du VM,
`navSession`, `locationProvider`, `dataSource`, `tripStore`, `voice`, `diag`, `http`) et une
interface `Host` (53-77, 20 membres) par laquelle il rappelle le VM (`startLocation`,
`flashStatus`, `updateSpeedLimit`, `nameIfNeeded`, `sanePosition`, `gateMeasuredSpeed`...).

| Fonction | Membres | Lignes | Code | Contenu |
|---|---|---|---|---|
| navigation | 73 | 823 | 677 | `bind` 109-278 (observateur `navSession.state` → `MapUiState`, plus 3 `snapshotFlow` sur `SpeedCamWarn`, `SpeedCams`, `FlockNavAlert`, `BridgeAlert`), `startNav` 282-307, `launchNav` 563-591, `stopNav` 593-627, reprise 877-942, `tunnelDeadReckonLoop` 951-1003, barre de route 1042-1110, radars 1126-1174, Flock 1179-1243, mode conduite 1248-1343, alertes 1348-1380, routes de contrôles 1461-1531 |
| trajets, démo | 9 | 261 | 196 | `startDemoDrive` 393-493, `replayTrip` 721-861 (hors V1) |
| itinéraire | 11 | 56 | 56 | ponts NDW 1385-1431, `warnClosingForAddedStop` |
| position, statut | 6 | 67 | 66 | `drivingModeFix`, `closingMessage` 357-372, `formatMinuteOfDay` |

Android : `NavigationService.start/stop` (service de premier plan), `CarBridge.clear`,
`getSharedPreferences` ×2, 10 `R.string` (14 clés distinctes), `String.format`. Il écrit aussi
des holders process : `AppTheme.navigating`, `NavTurnTarget.update`, `TurnArrows.update`,
`NavLegFigures.leg`. Niveau propre : 21 membres ANDROID (868 lignes), 56 PURE (124 lignes,
surtout des champs). 31 % des lignes nav ont changé en 30 jours.

### 2.2 Holders de `ui/` (`--holders`)

115 objets ou classes avec état (`MutableStateFlow`, `mutableStateOf`, `var`) dans 86 fichiers
de `ui/`, `ui/place`, `ui/search`, `ui/nav`, `ui/settings`, `ui/map` (hors VM et
`NavController`). 70 portent une clé de préférence (`const val KEY...`), presque tous dans
`vela_settings` (`Units` : `vela_units` ; `StartView` : aussi `vela_location`). **51 suivent le
même gabarit de 15 lignes** : `val on = mutableStateOf(défaut)`, `init(context)`,
`set(context, v)`. `VelaApp.onCreate` appelle 85 `init(this)` ; 75 holders sont démarrés là.

Holders qui recopient leur valeur dans un drapeau de `:core` (à refaire à l'identique au
démarrage iOS) : `GoogleFree` → `NoGoogle.enabled`, `HideAdult` → `CategoryFilter.enabled`,
`OtherLocationsAuto` → `OtherLocations.auto`, `RoadNumbers` → `nav.RoadNumbers.preferred`,
`SpokenDetail` → `nav.SpokenDetail.mode`, `SpokenRoadNames` → `nav.SpokenRoadNames.enabled`,
`AppLocale` → `BrowserHeaders.acceptLanguage`. `VelaApp` pousse en plus `VelaLinks.compiled`,
`LowRamMode.enabled`, `BrowserViewport.set`, `RoutingPrefs.avoid*` et `googleTraffic`,
`Transitous.durationFormatter`, `DelayText.formatter`, `GoogleTransport.interceptor`.

Holders qui portent de la logique au-delà d'un interrupteur :

| Holder | Fichier | Logique | iOS |
|---|---|---|---|
| `MapPoiPrefs` | `ui/MapPoiPrefs.kt` 23-145 | 9 états, source des lieux, `setRemoteDefault` | réglage + règle dans store couches |
| `StartView`, `startFor`, `shownStartMode` | `ui/StartView.kt` 57-159 | où la carte s'ouvre, pur | (b) |
| `QuickCategories`, `QuickChipOrder`, `CategoryQuery` | `ui/QuickCategories.kt`, `ui/QuickChipsPref.kt` 53, `ui/CategoryQuery.kt` | requêtes anglaises stables des puces, ordre | (b) pour requêtes et ordre, libellés en Swift |
| `Units`, `formatDistance/Area/Speed/SpeedLimit` | `ui/Format.kt` 13-107 | unités, pur sauf le holder | (b) avec `imperial` en paramètre |
| `formatDuration`, `formatClock`, `formatArrivalClock` | `ui/Format.kt` 62-150 | `android.icu`, `java.time` | (d) Swift (`DateComponentsFormatter`) |
| `AppTune` | `ui/AppTune.kt` | dial calibration + `setprop` par réflexion | common : `CalibrationStore.latest.tune`, sans `setprop` |
| `LinkTrip` | `ui/place/LinkTrip.kt` 15-79 | état d'un trajet ouvert par lien | état du RouteStore |
| `Place.isListing` | `ui/place/PlaceSheet.kt` 5018 | 2 lignes, pur | (b) |
| `PoiIcons.groupFor/groupForCategory/resultIconKey/fuelShort` | `ui/map/PoiIcons.kt` 30-47, 102-140, 399-492 | classement des lieux, pur au milieu d'un fichier MapLibre | (b) |
| `NavTurnTarget`, `TurnArrows`, `NavLegFigures`, `AppTheme.navigating` | `ui/map/NavFraming.kt` 277, `ui/TurnArrows.kt`, `ui/nav/NavLegFigures.kt` | miroirs de la nav | champs du NavStore |
| `roadSigns`, `routeKey`, `isCompoundNext`, `laneBucket`, `maneuverBucket` | `ui/nav/NavOverlays.kt` 471-700 | lecture du bandeau | (b) pour I-5 |
| `UkFuelPrices` | `ui/map/UkFuelPrices.kt` 35-100 | prix UK dans la fiche | store lieu, après V1 |
| `SearchActions`, `SavedActions`, `RouteActions`, `ParkingActions`, `ShapeActions` | `ui/PlaceContent.kt` 214-248 | pointeurs de fonctions posés par le VM (`init` 2216, 5920) | inutiles : Swift appelle le store |

Hors périmètre de ce lot mais signalé : `MapScreen.kt` (7,3 k) et `VelaMapView.kt` (11 k) ont
aussi des helpers purs de présentation (`routeBubblesFor`, `displayedPlaces`,
`routeTrafficSpans`, `navRoadLabel` ; `progressAlong`, `snapToRouteWindowed`,
`nearestStreetName`, `hideOpenTwins`). I-1 et I-5 doivent les mesurer avant d'écrire la carte.

## 3. Par fonction iOS V1

### 3.0 Forme proposée : un état, des facettes

Mesure qui décide : 44 champs écrits par trois fonctions ou plus, et `NavController` qui écrit
déjà dans le `_state` du VM par une interface `Host`. Le portage reprend cette forme au lieu de
la casser :

```kotlin
// :ios-shared, commonMain, package app.vela.ios.store (nom à aligner sur F-3b)
class MapSession(graph: IosGraph, scope: CoroutineScope) {     // un par processus, pas par vue
    val state: StateFlow<MapState>                              // l'état entier
    val search: SearchStore; val place: PlaceStore; val route: RouteStore
    val nav: NavStore; val saved: SavedStore; val offline: OfflineStore; val settings: SettingsStore
    fun start()                                                 // tout ce que fait init, explicitement
    fun close()
}
data class MapState(
    val mode: Mode = Mode.Browse,          // Browse, Results, Place, Directions, Navigating
    val camera: CameraState, val me: MyLocation?, val status: Status?,
    val search: SearchState, val place: PlaceState, val route: RouteState,
    val nav: NavUiState, val saved: SavedState, val offline: OfflineState, val net: NetState,
)
```

- Chaque store est une facette : il lit et écrit `MapState` par un `MutableStateFlow` partagé et
  expose `val state: StateFlow<XState>` dérivé (`map { it.x }.stateIn(...)`). Les remises à zéro
  croisées (`selectPlace`, `clearSelection`, `clearSearch`) deviennent des transitions de `mode`
  écrites une seule fois dans `MapSession`.
- Les intentions sont des fonctions simples (`fun submit()`), jamais `suspend` côté Swift.
  Pont : SKIE (D12) ; sinon chaque store a `fun watch(onChange: (XState) -> Unit): Closeable`.
- **Aucune chaîne formatée dans un store.** `status` est typé :
  `data class Status(val key: String, val args: List<String>, val autoMs: Long?)` avec `key` = le
  nom Android de `R.string` (`mapvm_no_results`...). Le String Catalog d'I-8a garde ces noms : 129
  clés à vérifier présentes. Durées et distances restent des nombres (`modeEtas` en secondes, pas
  en texte comme aujourd'hui).
- Les plateformes passent par les coutures F-2 plus trois interfaces de `:ios-shared` :
  `Connectivity` (en ligne, données limitées), `ShareSink` (partage de fichier), `DiagSink`
  (journal de trajet, no-op en V1).

### 3.1 Recherche (I-2, V-2)

| Morceau | Aujourd'hui | Reco |
|---|---|---|
| Requête Google, pages, branches, « plus » | `GoogleMapsDataSource.search/searchMore/searchBranches/suggest/searchOnce` (C-2) | (a) ; en V-2, une source iOS minimale (§4.2) |
| Photon, Nominatim | `PhotonGeocoder` (C-3) | (a) |
| Intentions (« take me home ») | `core/search/QueryIntents` (**hors lot**, SEAM `Normalizer`) | (a), à ranger dans C-2 ou C-1 |
| Réduction à la vue | `core/search/AreaNarrow` (**hors lot**, PURE) | (a), à ranger dans V-1 bis |
| Fusion des suggestions (numéro de maison, `coveredByGoogle`, dédoublonnage nom+lieu) | inline dans `onQueryChange` 1299-1425 | (b) `SuggestMerge` |
| `addressFirst` (10174-10185, lit le champ caché `lastAddressQuery`), `endpoint` (local de `routeBetween` 2127-2133), filtre `ambientExtra` (dans `runSearch`), ordre hors ligne de `offlineSearch` 2941-2946 | VM | (b) `SearchRank`, la requête en paramètre |
| `placeKey`, `nameLocKey`, `plausibleBias`, `rankBias` | VM 1434-1440, 2151-2154, 2278 | (b) `PlaceKeys` |
| Orchestration : anti-rebond 320 ms, course Google/Photon/adresses locales, vol unique (`searchJob`, `suggestJob`), repli hors ligne, `searchThisArea`, « ouvert maintenant », recherche le long du trajet, récents, suggestions locales | VM 1299-1630, 2046-2273, 2540-2995 | (c) `SearchStore`, ~500 lignes |
| Liens collés (`MapLinkParser`, listes partagées, My Maps) | `runSearch` 2551-2650 | (c) après V1, dans `SearchStore` |
| Barre, liste, puces | Compose | (d) |

```kotlin
data class SearchState(
    val query: String = "", val searching: Boolean = false,
    val suggestions: List<Place> = emptyList(), val querySuggestions: List<String> = emptyList(),
    val local: List<LocalSuggestion> = emptyList(), val results: List<Place> = emptyList(),
    val canLoadMore: Boolean = false, val loadingMore: Boolean = false, val branches: Boolean = false,
    val searchThisArea: Boolean = false, val recents: List<RecentQuery> = emptyList(),
)
// intents: setQuery(q), fillQuery(q), submit(), searchRecent(q), pickSuggestion(p), pickLocal(s),
// removeLocal(s), loadMore(), searchThisArea(), setOpenNow(on), quickSearch(chipQuery), clear()
```

### 3.2 Fiche lieu (I-3)

| Morceau | Aujourd'hui | Reco |
|---|---|---|
| Détails, photos, avis par RPC | `dataSource.placeDetails`, `placePhotoPage`, `reviewFeed` + parseurs (C-2, V-1) | (a) |
| Fusion des détails | `mergeDetails` 4117-4140 (partie pure) | (b) `Place.withDetails(d)` |
| Autres lieux à l'adresse | `streetKey` 5355-5363 (regex construite à chaque appel, dans une boucle), `othersAt` 5369-5381 | (b) `PlacePlaces`, regex en constantes |
| Cache court (6 h photos et avis, 15 min détails), essais et attentes | `placeCacheGet/Put`, `placeRetryWait`, `placeTries` 4376-4403 | (c) |
| Sélection, chargements différés (« au toucher »), annulations, garde `selected?.id == p.id` | `selectPlace` 3346-3407, `requestReviews` 4439-4472, `fetchPhotos` 4221-4371, `fetchReviews` 4476-4596, `fetchPlaceDetails` 4034-4092, `clearSelection` | (c) `PlaceStore`, ~600 lignes |
| Repli WebView (page de photos, avis complets, affluence) | `WebPhotoFetcher`, `WebReviewsFetcher`, `WebPopularTimesFetcher` | (d) Swift WKWebView derrière `interface PlaceWebFallback` (callbacks), branché après W-2 ; V1 tient sans |
| Toucher un lieu sur la carte (placeholder, résolution Google, même lot, écriture croisée) | `onPoiTap` 4838-5245, `onMapLongPress` 5385-5464, `onAddressLabelTap` 5472-5538 | (c), mais seulement après I-1 (dépend des couches) ; en V1, version courte : `reverseGeocode` + `searchOnce` |
| Liens Overture → Google mémorisés | `loadOpenPlaceLinks` 4741-4783 et voisins | hors V1 |

```kotlin
data class PlaceState(
    val selected: Place? = null, val resolving: Boolean = false, val placesHere: List<Place> = emptyList(),
    val loadingDetails: Boolean = false, val reviews: List<Review> = emptyList(),
    val reviewsLoading: Boolean = false, val reviewsLimited: Boolean = false,
    val reviewsNextToken: String? = null, val reviewsAwaitingTap: Boolean = false,
    val photosLoading: Boolean = false, val photosNextToken: String? = null, val photosAwaitingTap: Boolean = false,
)
// intents: select(p), close(), loadReviewsNow(), loadMoreReviews(), loadPhotosNow(), loadMorePhotos(),
// retryReviews(), tapMap(at, label?), longPress(at)
```

### 3.3 Itinéraires (I-4)

| Morceau | Aujourd'hui | Reco |
|---|---|---|
| Calcul voiture, marche, vélo, nommage, trafic | `GoogleMapsDataSource.directions/directionsPlain/nameRoute` (C-2), `ValhallaRouter`, `RouteGeometry` (C-3) | (a) ; c'est là qu'est le gros du routage (779 lignes) |
| Transport | `webDirections.transit` (page Google) puis `Transitous` (C-3) dans `transitTrips` 7067-7079 | (a) Transitous en V1 ; WKWebView après W-2, (d) |
| Clé et cache des temps par mode | `modeEtaKeyOf` 7112-7115 (`"%.5f".format` + `currentTimeMillis`), `shownDuration` 7121 | (b) `ModeEtas`, horloge en paramètre |
| Préférences collantes, miroir `RoutingPrefs` | `stickyAvoid`, `stickyTravelMode`, `syncRoutingAvoid`, `setAvoid*` 6497-6544 | (c), mêmes clés `vela_settings` |
| Chooser : origine, destination, arrêts, inversion, choix sur la carte, heure, sélection d'un itinéraire (par identité `===`), garde `stillWanted`, préchargement des autres modes, offre d'itinéraire enregistré | VM 4672-4715, 5550-5625, 6110-6633, 6648-6698, 7008-7158 | (c) `RouteStore`, ~550 lignes |
| Caméras sur l'itinéraire | `refreshFlockOnRoute` 6837-6940, `tryCameraDetour` | (c) après V1 |
| Panneau, liste d'étapes | Compose | (d) |

```kotlin
data class RouteState(
    val open: Boolean = false, val origin: Place? = null, val destination: Place? = null,
    val stops: List<Place> = emptyList(), val reversed: Boolean = false, val mode: TravelMode = TravelMode.DRIVE,
    val timeMode: Int = 0, val timeEpochSec: Long? = null, val avoid: Avoid = Avoid(),
    val routes: List<Route> = emptyList(), val active: Route? = null, val transit: List<TransitItinerary> = emptyList(),
    val loading: Boolean = false, val modeSeconds: Map<TravelMode, Double> = emptyMap(),
    val picking: Pick? = null, val previewStep: Int? = null,
)
// intents: directionsTo(p), setMode(m), setAvoid(a), setTime(mode, sec), setOrigin(p?), setDestination(p),
// addStop(p), applyStops(list), swap(), select(i), beginPick(kind), confirmPick(at), previewStep(i), close()
```

### 3.4 Navigation guidée avec voix (I-5)

| Morceau | Aujourd'hui | Reco |
|---|---|---|
| Moteur, recalcul, itinéraire plus rapide, arrêts, annonces | `NavSession`, `NavEngine`, `NavStrings`, `VoiceGuide` (C-5, C-7) | (a) ; **bloquant** : `NavSession` dépend de `Haptics` (STAYS), à couper dans C-5 (couture `Haptics` déjà listée au §3.1 du plan) |
| Filtre de position (sauts, lissage, porte de vitesse, cap) | `sanePosition` 856-880, `gateMeasuredSpeed` 1139-1150 (2 `var` d'état), `bearingBetween` 1154-1161 (doublon de `model.bearingTo`) | (b) `FixFilter` + `SpeedGate` |
| Pipeline GPS : réseau contre GPS, `FixRules`, `SpeedKalman`, repli GPS seul pour guider (précision ≤ 50 m), `navStarved`, minuteur de point périmé, limite de vitesse | `startLocation` 882-1124, `restartStaleTimer`, `updateSpeedLimit` | (c) `LocationPipeline`, ~250 lignes, nourri par `LocationSource` (Swift `CLLocationManager`) |
| Démarrage (re-planifier depuis ici si l'origine est loin, `prepareStart`, avertissement de fermeture), arrêt, pause, reprise après mort du processus, observateur `navSession.state`, estime en tunnel, barre de route, alertes radars/vitesse | VM 7262-7334, `NavController` 109-1343 | (c) `NavStore`, ~750 lignes |
| Fermeture bientôt | `stopArrivals` 329-339, partie pure de `closingMessage` 357-372 (`ClosingTime` en C-2) | (b) |
| Mode voix (muet, alertes seules, vitesse, volume) | `setVoiceMode` 7325-7334, `toggleVoice` | (c) ~100 lignes ; synthèse en Swift `AVSpeechSynthesizer` via `SpeechSynth` |
| Service de premier plan, notification, PiP, voiture | `NavigationService`, `CarBridge` | (d) arrière-plan iOS ; CarPlay hors V1 |
| Bandeau, voies, boucliers | `NavOverlays.kt` 471-700 (pur en partie) | (b) `roadSigns`, `routeKey`, buckets ; dessin (d) |
| Trajets enregistrés, démo, replay | `NavController` 393-493, 721-867 | hors V1 (la démo peut aider les tests simulateur : à rajouter en V1.1) |

```kotlin
data class NavUiState(
    val navigating: Boolean = false, val paused: Boolean = false, val nav: NavState = NavState(),
    val maneuverText: String = "", val faster: Route? = null, val fasterSavingSeconds: Double = 0.0,
    val arrived: Arrival? = null, val cameraDetached: Boolean = false, val overview: Boolean = false,
    val northUp: Boolean = false, val starved: Boolean = false, val resumeLabel: String? = null,
    val speedLimitKmh: Double? = null, val voice: VoiceMode = VoiceMode.ON,
)
// intents: start(), stop(), togglePause(), acceptFaster(), dismissFaster(), resume(), dismissResume(),
// panned(), recenter(), overview(), toggleNorthUp(), setVoiceMode(m), addStop(p)
// entrée plateforme : onFix(Fix) depuis Swift, onAppForeground(Boolean)
```

### 3.5 Lieux enregistrés (I-6)

| Morceau | Aujourd'hui | Reco |
|---|---|---|
| Stockage | `SavedPlaceStore`, `PlaceListStore`, `PlaceShortcutStore`, `ParkingStore`, `SavedRouteStore`, `RecentPlaceStore`, `RecentSearchStore` (C-6) | (a), clés inchangées |
| Import Takeout, GPX, KML | `TakeoutCsv`, `PlaceImport`, `ImportResult` (C-6), `MyMapKml` (C-2) | (a) |
| Enregistrer, Domicile/Travail, listes, notes, icônes, parking, déplacer/retirer en lot, routes enregistrées, import Takeout espacé (`TAKEOUT_LOOKUP_GAP_MS` 400 ms, sauvegarde tous les 25) | VM 1836-2041, 5634-5913, 6009-6103, 6703-6823, 7570-7710 | (c) `SavedStore`, ~450 lignes |
| Export (fichier + `Intent`) | `exportSavedIntent` 7501-7567 | (d) Swift `ShareLink`, le JSON vient du store |
| Dessin de formes | VM 5844-5913 | hors V1 |

```kotlin
data class SavedState(val saved: List<SavedPlace>, val lists: List<PlaceList>, val home: SavedPlace?, val work: SavedPlace?,
    val parking: ParkedSpot?, val parkingHistory: List<ParkedSpot>, val savedRoutes: List<SavedRoute>, val assigning: ShortcutKind?)
// intents: toggleSave(p), setShortcut(kind, p), clearShortcut(kind), createList(..), updateList(..), moveList(..),
// deleteList(id), addToList(id, p), removeFromList(id, ids), setNote(id, s), saveParking(at), clearParking(),
// importTakeout(csvs), exportJson(): String, saveActiveRoute(name), openSavedRoute(id)
```

### 3.6 Régions hors ligne, carte et recherche (I-7)

| Morceau | Aujourd'hui | Reco |
|---|---|---|
| Lecture PMTiles, catalogue, polygones, recherche dans les archives | `PmtilesReader`, `PmtilesCompact`, `PmtilesPatch`, `RegionCatalog`, `RegionPolys`, `PlacesArchiveSearch`, `OfflineRank` | (a) C-8 |
| Paquets de lieux et adresses | `OfflinePoiStore`, `OfflineAddressStore`, `OfflinePacks` (C-6) | (a) |
| Stores de tuiles et de paquets de `app/offline/` : `PoiPackStore` (257), `PlacesTileStore` (607), `CellStore` (189), `OverlayTileStore` (132), `BasemapTileStore`, `MaxspeedOverlayStore` (63), `RegionPacks` (42), `RegionPick` (34), `OfflineMaps` (148), `GlyphPackStore` (125) | `:app` | **trou dans le plan** : C-8 ne les cite pas. (b) pour la logique de manifeste et de choix d'archive, fichiers par `PlatformFiles` ; environ 1,5 k lignes à classer avant I-7 |
| Choix de l'archive de fond de carte, mises à jour, file de téléchargement, estimation d'une zone, stockage | `pickBasemapArchive` 9285-9348, `refreshRegionUpdates`, `updateRegionNow`, `areaDownloadPlan` 8946-8985, `offlineStorageBreakdown` | (c) `OfflineStore`, ~500 lignes |
| Téléchargement (fond de tâche, reprise, Wi-Fi seul) | `downloadLaunch` + `DownloadService` | (d) `URLSession` background, rapporte la progression au store |
| Routage hors ligne `.obf` | `ObfStore`, `ObfRouteEngine` | hors V1 (D7) |

```kotlin
data class OfflineState(val regions: List<RegionRow>, val installed: Set<String>, val updates: Map<String, List<String>>,
    val download: DownloadProgress?, val queue: Int, val basemapArchive: String?, val storage: OfflineStorage?)
// intents: refreshCatalog(), download(regionId), cancel(), update(regionId), updateAll(), delete(regionId),
// startAreaPick(), areaPlan(bounds), downloadArea(bounds), deleteAll()
// entrée plateforme : onDownloadProgress(id, bytes, total), onDownloadDone(id, path)
```

### 3.7 Réglages, sous-ensemble V1 (I-8)

| Morceau | Aujourd'hui | Reco |
|---|---|---|
| 51 interrupteurs au même gabarit, plus `MapPoiPrefs`, `Units`, `AppLocale`, `StartView`, `RoutePicker`, `SpokenDetail`... | holders `ui/*.kt`, démarrés dans `VelaApp` | (c) `SettingsStore` : un `PrefFlag(store, key, default, mirror)` générique (~40 lignes) et un registre des réglages V1 avec **les mêmes fichiers et clés** que le tableau du §2.2, ~150 lignes |
| Miroirs vers `:core` (`NoGoogle`, `CategoryFilter`, `RoutingPrefs`...) | `init` des holders, `VelaApp` | (c) dans `MapSession.start()`, avant toute requête |
| Écrans de réglages | Compose | (d) |

### 3.8 Helpers purs vers `:core-common` (catégorie b)

Deux cas. Dans `MapViewModel` et `NavController` (que le fork ne modifie pas), on **copie**
dans `:core-common` et on surveille l'original par empreinte (§6) ; Android garde sa version.
Ailleurs dans `:app` (fichiers peu modifiés : `PoiIcons.kt` 8 commits en 3 mois, `Format.kt` 9,
`StartView.kt` 2), on **déplace** et on laisse dans `:app` une délégation d'une ligne, pour que
les appelants ne changent pas.

| Cible `:core-common` (proposée) | Source | Lignes | Mode |
|---|---|---|---|
| `presentation/FixFilter.kt` | `MapViewModel.sanePosition` 856-880, `gateMeasuredSpeed` 1139-1150 | ~45 | copie |
| `presentation/PlaceKeys.kt` | `placeKey` 1434, `nameLocKey` 1439, `plausibleBias` 2278, `streetKey` 5355, `othersAt` 5369 | ~40 | copie |
| `presentation/SearchRank.kt` | `addressFirst` 10174, `endpoint` de `routeBetween` 2127, fusion de `onQueryChange` 1340-1420, `ambientExtra` de `runSearch`, ordre de `offlineSearch` | ~150 | copie |
| `presentation/PlaceMerge.kt` | `mergeDetails` 4117-4140 | ~30 | copie |
| `presentation/ModeEtas.kt` | `modeEtaKeyOf` 7112, `shownDuration` 7121, `transitChipText` 7119 | ~20 | copie |
| `presentation/TransitPick.kt` | `isTransitCategory` 3496-3530, `nearestLiveStop` 3549, `lineLabelMatches` 3759 | ~45 | copie |
| `presentation/NavHelpers.kt` | `NavController.stopArrivals` 329, `navStopsFor` 675, `aheadOf` 1329, `pointAlongPolyline` 1006, `controlsOnRoute` 1547 ; `angleDiff` 10757 | ~70 | copie |
| `presentation/Tuning.kt` | constantes du `companion` 10588-10753 utilisées par les stores, `ambientCap` | ~60 | copie |
| `model/PlaceKind.kt` | `Place.isListing` (`ui/place/PlaceSheet.kt` 5018) | 3 | déplacement |
| `model/PoiGroups.kt` | `PoiIcons` 30-47, 102-140, 399-492 | ~150 | déplacement |
| `presentation/StartFor.kt` | `ui/StartView.kt` 116-159 | ~45 | déplacement |
| `presentation/Categories.kt` | `CategoryQuery.fuel` (pays en paramètre), requêtes de `QuickCategories.catalog`, `QuickChipOrder` | ~60 | déplacement partiel |
| `presentation/UnitFormat.kt` | `formatDistance/Area/Speed/SpeedLimit` (`ui/Format.kt` 36-107), `imperial` en paramètre | ~50 | déplacement |
| `nav/RoadSigns.kt` | `roadSigns`, `routeKey`, `isCompoundNext`, `laneBucket`, `maneuverBucket` (`ui/nav/NavOverlays.kt` 471-700) | ~80 | déplacement, à vérifier |

Total : environ 0,85 k lignes, dont 0,46 k copiées.

### 3.9 Synthèse

| Fonction V1 | (a) déjà `:core` | (b) helpers `:core-common` | (c) store `:ios-shared` | (d) Swift seul |
|---|---|---|---|---|
| Base (session, statut, réseau, miroirs) | `CalibrationStore`, drapeaux | `Tuning` | `MapSession` ~550 | `NWPathMonitor`, cycle de vie |
| Recherche | data source, Photon, stores récents, `QueryIntents`, `AreaNarrow` | `PlaceKeys`, `SearchRank`, `Categories` | `SearchStore` ~500 | barre, liste, épingles |
| Fiche lieu | RPC détails/photos/avis, parseurs, caches | `PlaceMerge`, `PoiGroups`, `PlaceKind` | `PlaceStore` ~600 | fiche, WKWebView de repli |
| Itinéraires | `directions`, Valhalla, OSRM, Transitous | `ModeEtas`, `TransitPick` | `RouteStore` ~550 | chooser, étapes |
| Navigation et voix | `NavSession`, `NavEngine`, `NavStrings`, `VoiceGuide` | `FixFilter`, `NavHelpers`, `RoadSigns`, `UnitFormat` | `NavStore` ~750 + `LocationPipeline` ~250 + voix ~100 | `CLLocationManager`, `AVSpeechSynthesizer`, arrière-plan, bandeau |
| Lieux enregistrés | 7 stores, Takeout | | `SavedStore` ~450 | partage, sélecteurs de fichiers |
| Hors ligne | C-6, C-8 | stores `app/offline` (~1,5 k, à classer) | `OfflineStore` ~500 | `URLSession` background |
| Couches de carte (I-1) | Overpass, `MapDeclutter` | `StartFor` | `LayersStore` ~400 (lieux ambiants, overlays, contrôles) | MapLibre |
| Réglages | drapeaux | | `SettingsStore` ~200 | écrans |

**Taille de `:ios-shared` : environ 4,85 k lignes de code**, plus environ 3 k de tests JVM
(ordre de grandeur des tests actuels de `:core` : 1 ligne de test pour 1,9 ligne de code).
Comparaison : les fonctions V1 de `MapViewModel` et `NavController` font environ 7 k lignes de
code mesurées ; on en reprend un peu plus de la moitié, le reste étant Android, hors V1 ou déjà
dans `:core`.

## 4. Ordre et taille des lots de la phase 4

### 4.1 Ordre

| Ordre | Lot | Taille | Store et contenu `:ios-shared` | Prérequis mesurés ici |
|---|---|---|---|---|
| 0 | V-2 | M | `MapSession` minimal + `SearchStore` minimal (§4.2) | V-1 (`MapDataSource`, `SearchParser`, `SearchPb` en common) |
| 1 | I-8 | M | `SettingsStore`, `PrefFlag`, miroirs ; vérifier les 129 clés `R.string` des stores dans le catalogue | F-3 ; à faire tôt, tous les autres lisent les réglages |
| 2 | I-1 | L | `LayersStore` (caméra de départ `StartFor`, lieux ambiants `maybeLoadAmbientPois` 8470-8639, overlays) ; `MapSession.mode` | W-3 ; mesurer `VelaMapView` et `MapScreen` (§2.2) avant |
| 3 | I-2 | M | `SearchStore` complet (suggestions, récents, plus, branches, ouvert maintenant, hors ligne en dernier) | C-2 (`suggest`, `searchMore`), C-6 (récents), ranger `QueryIntents` et `AreaNarrow` |
| 4 | I-3 | L | `PlaceStore` (RPC d'abord, repli WebView ensuite) | C-2 ; W-2 pour le repli seulement |
| 4 | I-6 | M | `SavedStore` | C-6 ; en parallèle d'I-3 |
| 5 | I-4 | L | `RouteStore` | C-2 (`directions`), C-3, I-1 (tracé) |
| 6 | I-5 | L | `LocationPipeline`, `NavStore`, voix | C-5 avec la coupure `Haptics`, C-7, I-4 |
| 6 | I-7 | L | `OfflineStore` | C-8 + classement des stores `app/offline` ; en parallèle d'I-5 |

Taille (lignes `:ios-shared`) : V-2 ~350, I-8 ~200, I-1 ~400 (+ base ~200), I-2 ~350 de plus,
I-3 ~600, I-6 ~450, I-4 ~550, I-5 ~1 100, I-7 ~500.

### 4.2 V-2 : ce que `SearchStore` doit contenir pour « coffee »

Le chemin mesuré est la branche en ligne, Google activé, de `runSearch` (2540-2907) :
`plausibleBias(mapCenter) ?: plausibleBias(myLocation)` (2278), hauteur de la vue
`LatLng(vp[0], vp[1]).distanceTo(LatLng(vp[2], vp[1]))` (vue `[sud, ouest, nord, est, zoom]`,
`onViewport` 8280), fenêtre élargie à `ADDRESS_SEARCH_SPAN_M` = 40 km si `AddressQuery.parse(q)`
n'est pas nul, `dataSource.search(q, near, spanM, rankFrom = rankBias(near))`, puis mise à jour
de l'état. Tout le reste (adresses locales, Photon, `homeNameHits`, `ambientExtra`, hors ligne)
attend I-2.

```kotlin
// :ios-shared, commonMain
data class SearchState(
    val query: String = "",
    val searching: Boolean = false,
    val results: List<Place> = emptyList(),
    val error: SearchError? = null,
)
sealed interface SearchError {
    data object NoResults : SearchError                         // mapvm_no_results
    data class NeedsRecalibration(val where: String?) : SearchError   // mapvm_search_needs_recalibration
    data class Failed(val reason: String?) : SearchError        // mapvm_search_failed_reason
}
class SearchStore(private val source: MapDataSource, private val scope: CoroutineScope) {
    val state: StateFlow<SearchState>
    fun setQuery(q: String)
    fun submit()                                    // vol unique : annule la recherche précédente
    fun clear()
    fun onViewport(south: Double, west: Double, north: Double, east: Double, zoom: Double)
    fun onLocation(lat: Double, lng: Double)
    fun watch(onChange: (SearchState) -> Unit): Closeable   // repli si SKIE ne suit pas Kotlin 2.4.20
}
```

Règles reprises telles quelles : requête vide ignorée ; `CancellationException` relancée avant
le `catch` générique (sinon une recherche remplacée écrit son erreur) ; `CalibrationNeededException`
distinguée ; un succès met `searching = false`. Source : `MapDataSource` (V-1) avec, côté iOS,
une implémentation qui ne fait que `search` (`SearchPb.build` + `VelaHttp` + `SearchParser`,
l'équivalent de `GoogleMapsDataSource.search` 207-299, 93 lignes, et `searchPage` 183-202) tant
que C-2 n'a pas déplacé `GoogleMapsDataSource` ; les autres méthodes gardent leurs valeurs par
défaut de l'interface. Tests JVM : source factice, recherche remplacée, erreur de calibration,
vue nulle (biais nul), point à moins de 0,5° de 0,0 (biais nul).

## 5. Pièges que les stores iOS doivent respecter

1. **Ordre d'initialisation.** `viewModelScope` est `Main.immediate` : le premier passage d'un
   collecteur lancé dans `init` s'exécute en ligne. L'`init` de 574-849 atteint, par ses appels, 34
   propriétés déclarées plus bas (dont `settingsPrefs` 7355, `ambientCache` 8336,
   `transitLineCache` 9757) ; le code le contourne à la main (commentaires 590 et 1664). Sur iOS :
   constructeurs sans effet, tout le travail dans `MapSession.start()`, et un test JVM qui
   construit puis démarre avec un dispatcher immédiat.
2. **Identité de route.** `NavSession` ne compte les arrêts que si `_state.route` est le même
   objet que `planRoute` (`NavSession.kt` 172-204, `applyEnrichedRoute`). `selectRoute` 6455-6470
   remplace une route par identité (`it === picked`), `NavController.bind` compare
   `nsRoute !== lastRecordedRoute`. Un store ne copie jamais une `Route` (pas de `copy()` pour
   « rafraîchir ») et ne la reconstruit pas à travers Swift : Swift tient des index, pas des
   routes.
3. **Holders process.** Un réglage non démarré lit son défaut à chaque lancement (CLAUDE.md). Les
   miroirs vers `:core` (§2.2) doivent être posés avant la première requête : `NoGoogle` faux par
   défaut veut dire qu'une install « sans Google » parlerait à Google au premier lancement.
4. **État Compose dans la logique.** Le VM et `NavController` lisent des `mutableStateOf` par
   `snapshotFlow` (4 fois) et en écrivent (`AppTheme.navigating`, `NavLegFigures.leg`,
   `TurnArrows`). En common : `StateFlow` uniquement.
5. **Durée de vie.** La nav est nourrie par le collecteur GPS du VM (`navSession.onLocation`
   1106), pas par le service. Sur iOS, `NavStore` et `LocationPipeline` vivent avec le processus
   (`MapSession` unique), jamais avec une vue SwiftUI, et le GPS n'est coupé que hors nav.
6. **Guidage GPS seul.** Un point réseau peut déplacer le point bleu mais jamais guider ; un point
   de précision > 50 m non plus (1105). Sur iOS, `CLLocation` n'a pas de fournisseur :
   `LocationSource` doit dire si le point est GNSS (précision horizontale et `sourceInformation`).
7. **Horloge monotone.** `dt` vient de `elapsedRealtimeNanos` ; un `dt <= 0` est jeté (981).
   Avec `CLLocation.timestamp` (horloge murale), passer par `Clock` monotone de F-2.
8. **Vol unique et gardes.** `searchJob`, `suggestJob`, `routeJob`, `namingJob`, `reviewsJob` ;
   chaque réponse vérifie que l'état attend encore (`stillWanted`, `selected?.id == p.id`,
   `query.trim() == term`). Les reprendre une à une ; ce sont des correctifs de bugs vus.
9. **État caché.** `addressFirst` lit `lastAddressQuery` posé par `runSearch` ; `narrowToView`
   ne vaut que 30 s ; `openDirectionsOnResult` est un coup unique. Les passer en paramètres dans
   les copies.
10. **Regex.** `streetKey` construit trois `Regex` à chaque appel, dans un filtre (CLAUDE.md :
    jamais dans une boucle). Les copies les mettent en constantes. Les regex de Kotlin/Native ne
    sont pas celles de la JVM : tests sur simulateur.
11. **Chaînes.** 129 clés `R.string` ; les stores rendent des clés et des nombres, jamais du texte
    formaté (`formatDuration` passe par `android.icu`).
12. **Préférences.** Mêmes fichiers et mêmes clés (`vela_settings`, `vela_nav_resume`...) pour
    qu'un réglage documenté ait un seul nom ; types constants par clé (`KeyValueStore`).
13. **Dérive.** 40 % du VM et 31 % des lignes nav de `NavController` ont changé en 30 jours.
    Sans surveillance, une copie est fausse en quelques semaines.
14. **Hors lot dans `CORE-MIGRATION.md`.** `QueryIntent`, `AreaNarrow`, `DiagLog` sont tirés par
    la recherche et la nav et n'ont pas de lot ; les stores de `app/offline` hors C-8 non plus.

## 6. Surveillance de la dérive

Chaque store de `:ios-shared` qui reprend une fonction l'indique en commentaire
(`// port of MapViewModel.runSearch`). Le bloc ci-dessous donne, pour les 142 fonctions portées,
une empreinte de leur logique (code sans commentaires, texte des chaînes ni espaces).
`python3 scripts/ios/vm_map.py --check docs/ios/PRESENTATION-MAP.md` liste celles qui ont changé
upstream depuis ; après relecture et mise à jour de la copie, `--md` réécrit le bloc. À lancer à
chaque merge hebdo de `origin/main` dans `ios/main`.

<!-- BEGIN GENERATED: watch -->
| Store | Classe | Fonction | Lignes | Empreinte |
|---|---|---|---|---|
| SearchStore | MapViewModel | `onQueryChange` | 1299-1425 | `9d047645d3` |
| SearchStore | MapViewModel | `fillQuery` | 1429-1432 | `04ed750b9a` |
| SearchStore | MapViewModel | `localMatches` | 1446-1483 | `b98bc74017` |
| SearchStore | MapViewModel | `placeKey` | 1434-1435 | `cbe6478e8b` |
| SearchStore | MapViewModel | `nameLocKey` | 1439-1440 | `0884701abd` |
| SearchStore | MapViewModel | `pickLocalSuggestion` | 1486-1501 | `f80a2805f4` |
| SearchStore | MapViewModel | `removeLocalSuggestion` | 1562-1577 | `9ed90d5a8e` |
| SearchStore | MapViewModel | `clearSearch` | 1582-1603 | `e347fbb1ef` |
| SearchStore | MapViewModel | `searchRecent` | 1610-1613 | `d6a73f7a82` |
| SearchStore | MapViewModel | `search` | 2046-2051 | `f4f532bae0` |
| SearchStore | MapViewModel | `handleQueryIntent` | 2063-2101 | `d34ef030ae` |
| SearchStore | MapViewModel | `routeBetween` | 2106-2145 | `208717c404` |
| SearchStore | MapViewModel | `rankBias` | 2151-2154 | `9caac2bcb7` |
| SearchStore | MapViewModel | `homeSuggestions` | 2158-2167 | `821325f8db` |
| SearchStore | MapViewModel | `homeNameHits` | 2172-2188 | `3c34979eae` |
| SearchStore | MapViewModel | `searchOpenNow` | 2200-2213 | `459c84c3bb` |
| SearchStore | MapViewModel | `searchThisArea` | 2218-2227 | `e25ee2cb60` |
| SearchStore | MapViewModel | `loadMoreResults` | 2240-2273 | `f3672f69f1` |
| SearchStore | MapViewModel | `plausibleBias` | 2278-2279 | `129ab60e8e` |
| SearchStore | MapViewModel | `runSearch` | 2540-2907 | `7d0b65982a` |
| SearchStore | MapViewModel | `offlineSearch` | 2941-2946 | `c04377b217` |
| SearchStore | MapViewModel | `archivePlaces` | 2915-2930 | `42164104a6` |
| SearchStore | MapViewModel | `googleFreeLocal` | 2937-2939 | `d8e147b1ab` |
| SearchStore | MapViewModel | `addressFirst` | 10174-10185 | `eac76d410e` |
| SearchStore | MapViewModel | `searchAlongRoute` | 2951-2995 | `b1ca1ceb7e` |
| SearchStore | MapViewModel | `isConnectivityError` | 2524-2534 | `5234cf34ae` |
| SearchStore | MapViewModel | `quickSearch` | 5540-5543 | `6253a2d03b` |
| SearchStore | MapViewModel | `rememberRecentPlace` | 1827-1830 | `65da010209` |
| PlaceStore | MapViewModel | `selectPlace` | 3346-3407 | `0de121be9e` |
| PlaceStore | MapViewModel | `clearSelection` | 4606-4637 | `edd07eba69` |
| PlaceStore | MapViewModel | `fetchPlaceDetails` | 4034-4092 | `1a53f51e38` |
| PlaceStore | MapViewModel | `mergeDetails` | 4117-4152 | `68448b137b` |
| PlaceStore | MapViewModel | `fetchPhotos` | 4221-4371 | `b4d8247c8a` |
| PlaceStore | MapViewModel | `loadAllPhotos` | 4160-4205 | `f5b95bece0` |
| PlaceStore | MapViewModel | `requestReviews` | 4439-4448 | `e154491ec6` |
| PlaceStore | MapViewModel | `fetchReviews` | 4476-4596 | `b828bf018a` |
| PlaceStore | MapViewModel | `loadMoreReviews` | 4406-4425 | `6c6be14156` |
| PlaceStore | MapViewModel | `othersAt` | 5369-5381 | `ca2fb95a7f` |
| PlaceStore | MapViewModel | `streetKey` | 5355-5363 | `b425f5dfcc` |
| PlaceStore | MapViewModel | `nameAgrees` | 5345-5346 | `ed23ffaaa3` |
| PlaceStore | MapViewModel | `onPoiTap` | 4838-5245 | `02c1ab5f78` |
| PlaceStore | MapViewModel | `onMapLongPress` | 5385-5464 | `1b35194f0a` |
| PlaceStore | MapViewModel | `onAddressLabelTap` | 5472-5538 | `f7644954b9` |
| PlaceStore | MapViewModel | `backfillOfflineAddress` | 3994-4012 | `c788bef1d2` |
| PlaceStore | MapViewModel | `thumbPano` | 4102-4114 | `88b13e311f` |
| PlaceStore | MapViewModel | `placeCacheGet` | 4383-4385 | `763a465533` |
| PlaceStore | MapViewModel | `placeCachePut` | 4386-4388 | `da2065df91` |
| PlaceStore | MapViewModel | `placeRetryWait` | 4393-4395 | `1d6ddbddbd` |
| PlaceStore | MapViewModel | `placeTries` | 4398-4399 | `b0002b2615` |
| PlaceStore | MapViewModel | `isPlaceholder` | 5250-5251 | `26e66010f7` |
| RouteStore | MapViewModel | `route` | 6560-6633 | `dde0a6e922` |
| RouteStore | MapViewModel | `routeToSelected` | 5595-5625 | `a1989cef2c` |
| RouteStore | MapViewModel | `directionsTo` | 5588-5593 | `f8a6fcd4f6` |
| RouteStore | MapViewModel | `selectRoute` | 6455-6470 | `e46b35bd98` |
| RouteStore | MapViewModel | `nameIfNeeded` | 6476-6482 | `d011bc0128` |
| RouteStore | MapViewModel | `setTravelMode` | 6484-6493 | `58d54e822f` |
| RouteStore | MapViewModel | `setAvoidTolls` | 6504-6511 | `b941192735` |
| RouteStore | MapViewModel | `setAvoidHighways` | 6513-6520 | `f8a3b92c1e` |
| RouteStore | MapViewModel | `setAvoidFerries` | 6522-6529 | `c186a6710d` |
| RouteStore | MapViewModel | `stickyAvoid` | 6533-6536 | `3274af79ae` |
| RouteStore | MapViewModel | `stickyTravelMode` | 6539-6544 | `21d44bf329` |
| RouteStore | MapViewModel | `syncRoutingAvoid` | 6497-6502 | `8a93f38a0a` |
| RouteStore | MapViewModel | `setDirectionsTime` | 6548-6558 | `74f93e02fb` |
| RouteStore | MapViewModel | `swapDirections` | 6110-6118 | `42f155e23d` |
| RouteStore | MapViewModel | `setDirectionsOrigin` | 6179-6182 | `e04058dacb` |
| RouteStore | MapViewModel | `setDirectionsDestination` | 6143-6155 | `d62ff65773` |
| RouteStore | MapViewModel | `addStop` | 6415-6450 | `d4cf5d226b` |
| RouteStore | MapViewModel | `applyStops` | 6269-6281 | `0fc31d64ef` |
| RouteStore | MapViewModel | `clearRoute` | 4672-4691 | `dc47dc03ce` |
| RouteStore | MapViewModel | `modeEtaKeyOf` | 7112-7115 | `eb6fce015f` |
| RouteStore | MapViewModel | `beginModeEtas` | 7125-7129 | `e1190e5df9` |
| RouteStore | MapViewModel | `publishModeEta` | 7131-7134 | `ed715ae83c` |
| RouteStore | MapViewModel | `prefetchModeEtas` | 7136-7158 | `3c0543ba62` |
| RouteStore | MapViewModel | `shownDuration` | 7121-7122 | `f078a47ad9` |
| RouteStore | MapViewModel | `routeTransit` | 7081-7101 | `c47486cca5` |
| RouteStore | MapViewModel | `offerSavedRoutes` | 6648-6698 | `31001d7049` |
| NavStore | MapViewModel | `startNav` | 7262-7275 | `648d5d7610` |
| NavStore | MapViewModel | `startLocation` | 882-1124 | `a1760177e3` |
| NavStore | MapViewModel | `sanePosition` | 856-880 | `3fccd29252` |
| NavStore | MapViewModel | `gateMeasuredSpeed` | 1139-1150 | `6b40ae872f` |
| NavStore | MapViewModel | `bearingBetween` | 1154-1161 | `27ce5ec51e` |
| NavStore | MapViewModel | `restartStaleTimer` | 1176-1188 | `97c2a46226` |
| NavStore | MapViewModel | `updateSpeedLimit` | 1197-1220 | `12c0758fa2` |
| NavStore | MapViewModel | `toggleNavPause` | 7307-7311 | `bee25e8e23` |
| NavStore | MapViewModel | `setVoiceMode` | 7325-7334 | `34f3951c04` |
| NavStore | MapViewModel | `toggleVoice` | 7314-7318 | `41576b1e11` |
| NavStore | MapViewModel | `addStopDuringNav` | 6349-6349 | `b4e0b9a10b` |
| NavStore | NavController | `bind` | 109-278 | `f0265fe01c` |
| NavStore | NavController | `startNav` | 282-307 | `22a8f61a7f` |
| NavStore | NavController | `launchNav` | 563-591 | `243311356b` |
| NavStore | NavController | `stopNav` | 593-627 | `da46ef39c3` |
| NavStore | NavController | `maybeWarnClosingSoon` | 314-322 | `4a489678f9` |
| NavStore | NavController | `stopArrivals` | 329-339 | `95c3afa8a2` |
| NavStore | NavController | `closingMessage` | 357-372 | `ece6603cf2` |
| NavStore | NavController | `tunnelDeadReckonLoop` | 951-1003 | `a92448fe24` |
| NavStore | NavController | `maybeOfferResume` | 896-906 | `82f467c84e` |
| NavStore | NavController | `resumeNav` | 910-942 | `360142bb44` |
| NavStore | NavController | `persistNav` | 877-883 | `31f9232df0` |
| NavStore | NavController | `updateRouteBar` | 1042-1104 | `5155511166` |
| NavStore | NavController | `refreshRouteSpeedCams` | 1126-1174 | `b454dfe000` |
| NavStore | NavController | `refreshRouteFlock` | 1194-1227 | `887f61b202` |
| NavStore | NavController | `maybeWarnFlock` | 1231-1243 | `49a40cd1ca` |
| NavStore | NavController | `maybeWarnSpeeding` | 1348-1357 | `b0a856ca24` |
| NavStore | NavController | `maybeWarnCamera` | 1360-1374 | `33e2741db6` |
| NavStore | NavController | `lightCues` | 509-518 | `6e512b7fb1` |
| NavStore | NavController | `onNavPanned` | 632-638 | `2d9b1a6747` |
| NavStore | NavController | `recenterNav` | 643-643 | `230abf48b9` |
| NavStore | NavController | `navOverview` | 649-649 | `b4c040c60a` |
| NavStore | NavController | `toggleNavNorthUp` | 653-659 | `fde92ab2ff` |
| SavedStore | MapViewModel | `toggleSave` | 1965-1972 | `08715550af` |
| SavedStore | MapViewModel | `pinSavedAs` | 1894-1902 | `cc883a7d71` |
| SavedStore | MapViewModel | `removeSaved` | 1905-1908 | `5dcf3cfdf4` |
| SavedStore | MapViewModel | `renamePlace` | 1912-1951 | `c636c548b9` |
| SavedStore | MapViewModel | `selectSaved` | 1974-2041 | `ace2fb29ab` |
| SavedStore | MapViewModel | `createList` | 5667-5671 | `6da979a750` |
| SavedStore | MapViewModel | `updateList` | 5673-5675 | `836151d3d6` |
| SavedStore | MapViewModel | `moveList` | 5678-5680 | `4718ecb4da` |
| SavedStore | MapViewModel | `deleteList` | 5682-5692 | `770aa412e5` |
| SavedStore | MapViewModel | `addPlaceToList` | 5694-5696 | `afc50e3e7a` |
| SavedStore | MapViewModel | `removePlaceFromList` | 5698-5701 | `34a381e565` |
| SavedStore | MapViewModel | `saveParkingSpot` | 5634-5640 | `4a9aefc9d9` |
| SavedStore | MapViewModel | `clearParkingSpot` | 5642-5646 | `f5bf0b9ce2` |
| SavedStore | MapViewModel | `showParkedCar` | 6070-6091 | `dccfc702e8` |
| SavedStore | MapViewModel | `beginAssignShortcut` | 1836-1837 | `923ccf7341` |
| SavedStore | MapViewModel | `consumeAssign` | 1852-1864 | `e4268ddd59` |
| SavedStore | MapViewModel | `openShortcut` | 1871-1878 | `e10c2c6ca3` |
| SavedStore | MapViewModel | `clearShortcut` | 1880-1885 | `65381cb246` |
| SavedStore | MapViewModel | `importTakeoutRows` | 7630-7696 | `561614b6de` |
| SavedStore | MapViewModel | `saveActiveRoute` | 6703-6733 | `5ccb4ecb5e` |
| SavedStore | MapViewModel | `openSavedRoute` | 6753-6765 | `d90e5f8643` |
| OfflineStore | MapViewModel | `refreshRoutingRegions` | 10093-10111 | `faadaeb811` |
| OfflineStore | MapViewModel | `downloadPoiPack` | 10188-10223 | `916c6ecaf8` |
| OfflineStore | MapViewModel | `fetchRegionArchives` | 10239-10256 | `63d7eac9a3` |
| OfflineStore | MapViewModel | `refreshRegionUpdates` | 10264-10287 | `f070caf764` |
| OfflineStore | MapViewModel | `updateRegionNow` | 10385-10423 | `38161713ae` |
| OfflineStore | MapViewModel | `pickBasemapArchive` | 9285-9348 | `e08e56520f` |
| OfflineStore | MapViewModel | `refreshBasemapArchive` | 9273-9279 | `7c1a6b3919` |
| OfflineStore | MapViewModel | `downloadOfflinePois` | 10488-10553 | `1cb6902cbc` |
| OfflineStore | MapViewModel | `areaDownloadPlan` | 8946-8985 | `49c42777e7` |
| OfflineStore | MapViewModel | `downloadPickedArea` | 9011-9052 | `998b3f32db` |
| OfflineStore | MapViewModel | `offlineStorageBreakdown` | 8710-8732 | `62bfb7487f` |
| OfflineStore | MapViewModel | `deleteAllOfflineData` | 8819-8859 | `caf435d4b5` |
<!-- END GENERATED: watch -->
