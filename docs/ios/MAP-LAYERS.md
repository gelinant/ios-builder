# iOS map layers and styles (lots I-1b, I-1c, MAP-STYLE and MAP-POI)

State on 2026-10-28, on branch `ios/map-poi` from `ios/main` (`d312348e`). This document says what the
iOS layers sheet draws, which style the map loads, where each piece of data comes from, when it is
requested, and what is deliberately absent.

## Styles

The map no longer fetches a style document from OpenFreeMap. `scripts/ios/gen-map-styles.py`
builds six local files from `liberty-roboto.json`: `style-vela-light.json`, `style-vela-dark.json`,
`style-bright.json`, `style-positron.json`, `style-fiord.json` and `style-black.json`. The sheet
offers the five Android looks (Vela, Bright, Positron, Fiord, Black); Vela follows the system or is
fixed to light or dark. The palettes reuse those of `LayersPanel.kt` and
`VelaMapView.applyLight/applyDark`.

Generation touches neither layer order, nor filters, nor minimum zooms: it repaints backgrounds,
water, vegetation, buildings and roads, replaces the Roboto fonts with the Noto Sans served by the
glyph host, and points place icons at the OpenFreeMap sprite images (`restaurant`, `hospital`, etc.
instead of the `vela-poi-*` images Android creates at runtime). Vector tiles, the sprite and the
glyphs stay remote for the online map; the style document itself is local.

`MapStyleBuilder` then applies the sheet's choices to the loaded document: name mode and
house-number threshold. A change reloads the style through the same path as the offline map. The
cache key includes the look, the mode, the threshold, the language and the date of the generated
file.

Changing the look or appearance while a raster is on reloads the style, and `MapController.styleDidLoad`
replays the stored layer data, so the traffic or satellite layers are inserted again below the
labels of the new variant. `MapLayers.labelAnchor` picks the first symbol layer after the last
`bridge*` layer; in the six bundled variants that is `waterway_line_label`, and
`scripts/ios/test_gen_map_styles.py` pins it so a future palette cannot silently lose the anchor
and drop the rasters above the labels.

## Panel

The `layers-button` (stack icon, right of the map) opens `LayersView`. Every switch is independent,
persists in `vela_settings`, and triggers no request before it is turned on. A status line says
`Loading`, `N shown`, `Zoom in to load`, `Failed. Pan the map to retry.` or `Only available in the
UK` / `Only available in the Netherlands`.

The `layers-debug` line (Debug builds only) repeats those states for the scenarios:

```
layers painted=ready:120 speed=ready:3 alpr=ready:2 controls=ready:18 fuel=off:0 bridges=off:0 poi=both cats=food,fuel,transit,parking,other pack=337 density=normal icon=1.00 look=vela appearance=system names=english_latin house=normal traffic=off satellite=off raster=none tiles=0 zoom=17.0
```

`tiles` counts the requests seen by the MapLibre HTTP hook towards Google or Esri, never the
OpenFreeMap tiles, glyphs or sprites. `poi` names the place source (`vela`, `tiles` or `both`),
`cats` the enabled sheet categories and `pack` the number of places in the bundled Vela pack.
`raster` names the layers actually present in the style. Both fields are computed before the map
applies a switch, so they can lag one render; reopening the sheet refreshes them. The scenario
screenshots remain the visual proof.

## Drawn layers

| Layer | Common source | Minimum zoom | Note |
|---|---|---|---|
| Painted road markings | `PaintedRoads.fetch` then `build`; paquet PMTiles optionnel | 16,5 | surface, median, centre, voies, voies vélo, voies bus, passages piétons, lignes d'arrêt, flèches de tourne et flèches de sens unique |
| Fixed speed cameras | `OverpassSpeedCameras.fetchInBox` | 11.0 (drawn 13.5) | red dots; OSM only, no embedded DeFlock data |
| ALPR cameras | `OverpassAlprCameras.fetchInBox` | 11.0 (drawn 13.5) | purple dots; DeFlock data inside OSM, no embedded file |
| Signals, stop signs, level crossings, speed humps | `OverpassTrafficSignals.fetchControlsInBox` | 16.0 | one glyph per junction after 30 m clustering, cap 400 |
| UK fuel prices | `FuelGbStore` and `FuelGb` | none | only when the view center is in the United Kingdom; Fuel Finder file cached by the store |
| Dutch bridge openings | `NdwBridgeOpenings.fetch` | none | only in the Netherlands; open in red, planned in orange, 5 min cache |

Every layer is off by default on iOS. Android enables ALPR cameras by default; iOS prefers not to
fire an Overpass request on every launch until the user asks for the layer. The Android key
`flock_cameras_on` is kept, so an explicit choice stays compatible.

### Requests and cache

- The viewport comes from `MapController.regionDidChange`, never from a display link.
- An active layer asks for a box widened by 50 % on each side. As long as the center stays inside
  the inner half of the covered box, no new call is made.
- A failure is never cached as "nothing here": the state becomes `error` and the next viewport
  retries.
- One request per layer at a time; a new generation cancels the previous response.
- Cameras are clustered at 20 m and controls at 30 m per type; the caps are 600 cameras and 400
  controls, nearest to the center first.
- Below the minimum zoom the layer is hidden and no request is sent.

## Places on the map

The sheet controls the Liberty layers `poi_r1`, `poi_r7`, `poi_r20` and `poi_transit`:

- `Show places` hides or shows all four layers;
- the `food`, `fuel`, `transit`, `parking` and `other` categories filter the OSM `class` property
  with a predicate combined with the style's own filter;
- `Compact` raises by one level the zoom at which low-priority groups appear (`poi_r1` from 16,
  `poi_r7` from 18, `poi_r20` from 19);
- label collision stays MapLibre's, so there is no per-frame work.

The GTFS Transitous stops drawn by T-1 are not concerned: that layer keeps its own switch.

The four Liberty place layers have constant `icon-size` and `text-size` values in the style: 0.5
and 12, except `poi_transit` at 0.7. iOS multiplies those constants by the icon-size setting, the
same way Android applies `poiIconScale` to icons and `poiLabelScale` to labels. A Liberty version
that changed those constants would make the factor relative to the old value; those four layers
only exist on Liberty. Street and place labels of the basemap are not concerned.

## Google traffic and satellite

Both rasters are offered in the sheet. Their URL templates live in `:core-common`
(`app.vela.core.data.tiles.RasterTiles`) and Android reads them from the same place; no Swift copy
exists. The bytes are Android's, pinned by `RasterTilesTest`.

| Layer | Template | Order | Limits |
|---|---|---|---|
| Traffic | `https://www.google.com/maps/vt/pb=...!1i{z}!2i{x}!3i{y}...!2straffic...` | above buildings and satellite, below labels | source zoom 16, opacity 0.6, 900 ms fade |
| Satellite | `https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}` | above the vector geometry, below labels | source zoom 19, brightness 0.80, saturation -0.1 |
| Deep satellite | `https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}` | above the base satellite | zoom 18.6 to 21, opacity 0 to 18.6 then 1 at 19.6 |

Traffic is Google's congestion overlay, without a key. Its language and region are frozen in the
URL (`3m8!2sen!3sus`), as on Android; there is no scale parameter. The base satellite is Esri World
Imagery, the open service Android uses; the Google raster is only used past z19, with a one-level
fade to hide the change of imagery campaign.

Satellite is a raster laid over the vector map, not a style change: if a tile fails or never
arrives, Liberty stays visible underneath. That is the fallback, with no white screen and no
reload. White ghost roads at 55 % repeat the basemap's `transportation` lines, like Google's hybrid
mode, so the road network stays readable over the photo.

Each layer adds only an in-memory `MLNShapeSource` or raster source. No additional glyph or sprite
enters the style.

### Tile headers

MapLibre iOS loads its tiles with its own `NSURLSession`, not with the Vela client, so the
calibration headers never reach it on their own. `MLNNetworkConfiguration` exposes a
`willSendRequest:` delegate; `MapTileNetwork` adds the Safari identity (User-Agent, Accept,
Accept-Language, Sec-Fetch-*, Referer `https://www.google.com/maps`) only for `*.google.com`
hosts. OpenFreeMap, glyph and sprite requests are not touched. Android adds no header to its own
MapLibre requests, so this identity is an iOS advantage, not a parity condition. If the delegate
disappears from a MapLibre release, the tiles go out with the bare URL, as on Android.

### Offline

`MapRasterLayers.Plan.make` returns an empty plan as soon as a downloaded region owns the style. No
raster source is added, no Google or Esri host name enters the generated offline style, and
switching to a region while both switches are on removes the layers when the local style loads.
`OfflineTests` checks the remote count is zero with both switches on.

Local overlays keep their own rule: each one adds only an in-memory `MLNShapeSource`.
`OfflineStyleFactory` starts from the generated style of the chosen look, applies the name mode and
the house-number threshold, then replaces the remote source with the PMTiles archive and the
sprite with the embedded files. Its `remote` count stays zero for the six looks; `OfflineTests`
and `MapStyleTests` check that. An enabled layer without a network goes to `error` and invents no
point; the downloaded map stays visible.

## House numbers and exit shields

Liberty draws neither house numbers nor exit numbers. The generator adds two layers, only on fields
the vector source actually carries:

| Layer | `source-layer` | Field | Zoom |
|---|---|---|---|
| `vela-housenumber` | `housenumber` | `housenumber` | 17.3 to 18.3 depending on the setting, 0.6 fade |
| `vela-exit-shield` | `transportation_name` | `subclass = junction`, `ref`, `ref_length <= 4` | 12.5 |

House numbers do not take part in the collision index (`text-ignore-placement`): they cannot evict
a place icon. Exits are green badges drawn at load time by `MapStyleImages`, like `RoadShields` on
Android; without the image the number stays readable as text. The road shields already in the
Liberty style (`us-interstate_N`, `us-highway_N`, `us-state_N`, `road_N`) are kept: no road without
a `ref` is invented.

The exit filter also requires `ref_length <= 4`, so long junction references never get a badge.
That is the OpenMapTiles field, not the `ref` length: the Sacramento capture at
`38.5930,-121.4800` sees junctions `46A` and `46B` carrying a longer `ref_length`, so it shows the
route shields and no exit badge, while tiles whose junctions carry short references (San Jose, for
example) do match. The generator test pins the filter, but the screenshot does not prove a badge.

Flat buildings move from z13-z14 to z16-z24 and extrusion starts at z17, as on Android. Filling in
missing buildings would need an OpenAddresses or equivalent dataset: it is not part of this lot.

## Names on the map

The four Android values are reused with the same thresholds and precedence:

- `english_latin` (default): `name:en`, then `name:latin`, then `name`, with the app language tried
  first;
- `english_local`: `name:en`, otherwise the local name;
- `local`: the local name only;
- `local_english`: the local name, then English on a second line for a place and on the same line
  for a street, which cannot wrap.

An interface whose script is not Latin keeps the local name whatever the mode, as on Android. The
street-name shortening in `VelaCoreCheck` is unchanged.

## Sheet settings

The Android keys are kept where they exist:

| Setting | Key | Default |
|---|---|---|
| Traffic | `traffic_on` | off |
| Satellite | `satellite_on` | off |
| Place source | `map_places_source` (`MapPoiPrefs.KEY_PLACES_SOURCE`) | `both` |
| Place icon size | `map_poi_icon_scale` (`MapPoiPrefs.KEY_SCALE`) | 1.0 |
| Place density | `map_poi_density` | `normal` |

The sheet offers three sizes, as on Android: 0.7 small, 1.0 default, 1.25 large. The value is
clamped between 0.5 and 2.0. Android has no `poi_icons` key; `map_poi_icon_scale` is its own.

## Sources de POI

La feuille offre les trois sources d'Android sous la clé `map_places_source` : `vela` (le paquet
embarqué), `tiles` (les lieux déjà présents dans les tuiles vectorielles OpenFreeMap) et `both`.
Android écrit `open`, `google` et `both` ; iOS lit encore `open` et `google` et les convertit en
`vela` et `tiles`, donc un fichier de réglages de l'une ou l'autre application reste valable. iOS
n'a pas de source Google pour les POI : `tiles` dessine les couches `poi_r1`, `poi_r7`, `poi_r20`
et `poi_transit` de Liberty, pas une requête Google. Le défaut est `both`, parce que le paquet Vela
ne couvre qu'une ville alors que les tuiles dessinent partout.

Le paquet Vela est réel et déjà versionné : `iosApp/Vela/Resources/poi-davis.json` est produit par
`scripts/ios/gen-poi-pack.py` à partir de
`core/src/test/resources/tiles/davis-14-2651-6288.pbf`, la tuile OpenMapTiles de Davis (Californie)
que les tests de `:core` décodent déjà. Le script garde les 337 lieux nommés, calcule leur latitude
et longitude depuis la géométrie de la tuile, et range chacun dans une des cinq catégories de la
feuille (`food`, `fuel`, `transit`, `parking`, `other`) avec les mêmes listes de classes OSM que
`PoiClasses`. Ce n'est pas l'archive Overture d'Android, qui est téléchargée par région et n'a
aucun équivalent embarqué : le paquet iOS ne couvre donc que Davis. Sélectionner `vela` ailleurs ne
dessine aucun lieu, ce que la feuille dit dans son pied de page.

La couche du paquet est une `MLNShapeSource` en mémoire, comme les autres surcouches. Elle
n'ajoute aucune URL au style et reste donc disponible sur une région téléchargée ; les icônes sont
peintes par `VelaPoiImages` avec un symbole SF, jamais dans le sprite distant. La taille
`map_poi_icon_scale` multiplie à la fois les quatre couches de Liberty et le marqueur du paquet
(28 pt à 1.0) ainsi que leurs étiquettes (12 pt à 1.0), pour les trois sources.

## Tests

- Script: `python3 scripts/ios/test_gen_map_styles.py` checks the six styles, the absence of a
  style document URL, the presence of the `housenumber` and `transportation_name` layers, the Noto
  fonts, buildings at z16, the POI ids and icon sizes I-1b filters, and the label anchor the
  Google rasters insert below (`waterway_line_label`, present in every look, so traffic on a style
  variant still lands under the labels).
- JVM: `app.vela.ios.map.LayersStoreTest` covers persistence, no request before activation, the
  minimum zoom, box reuse, retry after failure, control clustering, POI categories, unavailability
  outside the UK and the Netherlands, and the `traffic_on`, `satellite_on` and `map_poi_icon_scale`
  keys. MAP-POI ajoute les trois sources, la migration de `open` et `google`, le fait que la taille
  d'icône ne dépend pas de la source, et les groupes de catégories du paquet.
- JVM: `app.vela.core.data.tiles.RasterTilesTest` pins the three templates, the traffic z/x/y order,
  the Esri z/y/x order, the Google x/y/z order and the maximum zooms.
- Swift: `MapLayersTests` checks that the two rasters never join the list of local sources, that the
  plan is empty offline, the Android limits and the Safari identity of Google tiles.
  `OfflineTests.testOfflineStyleStaysRemoteFreeWithTrafficAndSatelliteOn` turns both switches on and
  checks the offline style keeps `remote=0` and names no raster host.
- Swift: `MapStyleTests` covers the six generated styles, the name modes, the three house-number
  thresholds and the offline map with no remote URL. `OfflineTests` keeps the historical zero-URL
  check, désormais avec la source `vela` active et l'assertion que le paquet n'entre pas dans le
  document de style. `MapLayersTests` vérifie les 337 lieux du paquet, leurs coordonnées de Davis,
  ses groupes, la source locale `vela-poi-src` et la clé `map_places_source`.
- Simulator: `MapLayersUITests.testStyleVariantsRender` captures `style-vela-light.png`,
  `style-vela-dark.png`, `style-bright.png`, `style-positron.png`, `style-fiord.png` and
  `style-black.png`, then checks the sheet's debug line.
  `testNamesModesHouseNumbersAndExits` captures `names-english.png`, `names-local.png`,
  `names-local-english.png`, `map-house-numbers.png` and `map-exit-numbers.png` (Chinatown, a
  residential block at z18 and the Sacramento junction at z15, whose long junction refs are
  filtered; see the exit note above). Both scenarios launch with
  `-VelaResetSettings YES`: I-1c's raster switches persist in the settings suite, and a satellite
  left on by an earlier scenario would cover the style, name or number the capture is meant to
  show.
- Simulator: `MapPoiUITests.testPoiSourceAndIconSize` ouvre la feuille sur Davis, bascule les trois
  sources, déplace la carte avec `vela` actif et exige `poi=vela` avec `tiles=0` et `pack=337`. Il
  capture `poi-source-tiles.png`, `poi-source-vela.png` et les trois tailles `poi-icons-small.png`,
  `poi-icons-default.png`, `poi-icons-large.png`. Le run `map-poi-20261027-232514-13417` passe le
  scénario en 148,9 s et rend `poi_pack=337`, `poi_source=vela`, `poi_tiles=0` ; les cinq captures
  montrent les marqueurs du paquet aux trois tailles et les arrêts des tuiles quand `tiles` est
  choisi. Le même run passe 134 tests Swift, 325 tests JVM et 267 tests Kotlin simulateur.
- Simulator: `MapLayersUITests.testLayerSheetLoadsOverlaysAtCloseZoom` opens the sheet over San
  Francisco at zoom 17 with `-VelaMapLayersFixture YES`, enables the four deterministic-data layers
  and captures `layers.png` then `camera-layer.png`.
  `MapLayersUITests.testGoogleTrafficAndSatelliteOverSanFrancisco` turns traffic on alone, waits
  20 s for tiles, captures `traffic-layer.png`, then switches to satellite alone and captures
  `satellite-layer.png`. Fixture answers derive from the requested box, like
  `NavAlertTestSupport`, and only exist in Debug.
- The `layers_*` counts are written to the run summary. The I-1c run
  `i1c-google-layers-20261027-132334-4563` passed both MapLayers scenarios it had (60.9 s and
  16.7 s) and produced its two screenshots; green, amber and red traffic were visible over the
  vector map, and satellite over the photos with the ghost roads and labels on top.
- The combined run on this merge, `map-style-merge-20261027-212845-17394`, passed all four
  MapLayers scenarios (83.9 s, 29.6 s, 108.6 s and 111.5 s) with 130 Swift unit tests and 296 JVM
  tests green. It produced `layers.png`, `camera-layer.png`, `traffic-layer.png`,
  `satellite-layer.png`, the six `style-*.png`, the three `names-*.png`,
  `map-house-numbers.png` and `map-exit-numbers.png`.

## Assumed limits

- No embedded DeFlock or road-feature data: cameras and controls come from Overpass and depend on
  mirror coverage and availability.
- Les flèches peintes sont dessinées ; hors zone couverte par les données OSM, la chaussée reste nue.
- UK prices and Dutch bridges are useless outside their country and the panel says so.
- Colored transit lines and terrain stay out of these lots.
- Le paquet Vela ne couvre que Davis et ses 337 lieux nommés : il prouve la source et la taille,
  pas une couverture mondiale. Aucune source Google de POI n'existe sur iOS ; `tiles` reste
  OpenFreeMap.
- The two Google rasters are non-contractual services without a key: an outage or a response change
  leaves the vector map, with no offline fallback.
- No iPhone validation of these layers has been done yet, including the two rasters.

## Caméras hors ligne (OFF-CAM)

Les deux couches de caméras se dessinent aussi dans une région téléchargée sans réseau. Le panneau nomme
la source au lieu de laisser croire à une requête Overpass.

### Paquet embarqué

`iosApp/Vela/Resources/camera-pack.json` est construit par `scripts/ios/gen-camera-pack.py` depuis
`app/src/main/assets/flock_cameras.bin`, le fichier DeFlock déjà livré à Android (`lat`, `lon`,
`operator`, `direction`, version `20260721`). Le script ne télécharge rien : il arrondit à cinq
décimales, trie et dédoublonne.

| Donnée | Valeur |
|---|---|
| Taille du fichier | 2 663 111 octets (2,66 Mo), compressé dans l'IPA |
| Points livrés | 127 264 (128 773 lignes brutes, doublons retirés) |
| Date des données | 2026-07-21, lue dans `flock_cameras_version.txt` |
| Source | nœuds ALPR DeFlock dans OpenStreetMap, ODbL 1.0 |
| Couverture | mondiale, aucune garantie d'exhaustivité |
| Types | caméras de plaque uniquement |

Comptes par boîte grossière, donnés pour situer la couverture et non comme un total par pays (les
boîtes se chevauchent) : États-Unis 118 151, Canada 18 981, France 2 357, Royaume-Uni 1 297,
Allemagne 951. Le reste est dispersé dans les pays où DeFlock cartographie des lecteurs de plaques.

Aucun radar fixe n'est embarqué : le dépôt ne contient pas de jeu de radars. Android les sort de
`RoadFeatures`, téléchargé par région, qui n'a pas d'équivalent livré ici.

### Paquet de région

À la fin d'un téléchargement de région, `OfflineStore.kt` interroge Overpass une fois sur la boîte
de la région, en vitesse et en plaque, puis écrit `NoBackup/offline/camera-packs/<id>.json`. Le
fichier est daté du jour de la réponse et couvert par la boîte de la région. Limites : 2 000 points
par type, aucun paquet si la boîte dépasse 12 degrés, et aucune écriture si les deux requêtes
échouent. L'écriture est lancée après la fin du téléchargement : un miroir lent ou mort ne bloque
jamais l'installation, et l'absence de paquet est un résultat valide. Supprimer la région supprime
son paquet.

### Règle de fraîcheur

Un paquet de plus de 365 jours ne dessine rien. Une date illisible compte comme périmée. Le
panneau écrit la date et l'âge, et le rendu ne montre aucun point plutôt qu'un point plausible mais
faux. Conséquence assumée : une installation qui n'a pas été mise à jour pendant plus d'un an perd
les caméras de plaque hors ligne jusqu'à la prochaine version de l'application, et une région
téléchargée il y a plus d'un an doit être retéléchargée pour retrouver ses radars.

### Source explicite dans le panneau

`Camera source` propose trois choix, persistés sous `camera_source` :

| Valeur | Comportement |
|---|---|
| `auto` (défaut) | requête Overpass quand la carte est en ligne, paquet quand le style vient d'une région téléchargée |
| `live` | Overpass seulement, même hors ligne ; sans réseau la couche ne dessine rien |
| `pack` | paquet seulement, en ligne comme hors ligne ; `LayersStore` ne fait alors aucune requête Overpass pour les deux types |

`live` et `pack` ne retombent jamais l'un sur l'autre. Le panneau affiche le paquet retenu, sa
date et le nombre de caméras dans la vue, ou dit qu'aucun paquet ne couvre la vue, ou que le
dernier paquet est périmé. La ligne de débogage ajoute un jeton :

```
cam=pack:camera-pack-2026-07-21:504
cam=live
cam=stale:2025-01-01
```

Le rendu garde les mêmes sources en mémoire (`vela-speed-src`, `vela-alpr-src`), donc le style
hors ligne reste à zéro URL distante avec le paquet activé. `CameraPackTests` vérifie ce zéro et
l'absence du nom du paquet dans le document de style : le paquet est une source de forme, jamais
une URL.

### Preuves

- `CameraPackTests` : lecture du paquet livré (127 264 points, date 2026-07-21, couverture Davis et
  San Francisco), objets et paires, points invalides ignorés, paquet de 400 jours périmé et sans
  point, paquet frais seul retenu, filtrage par vue et plafond de 600, choix de source sans
  repli, style hors ligne à zéro URL distante avec les deux couches et le mode paquet.
- `LayersStoreTest` : le mode paquet n'émet aucune requête, le retour en direct en émet une, la
  valeur persiste et une valeur inconnue revient à `auto`.
- `MapLayersUITests.testOfflineCameraPackDraws` : San Francisco au zoom 15,5, réseau coupé par le
  bouton de test, source paquet, capture `offline-camera-pack.png`, lignes de rapport
  `cameras_pack=camera-pack-2026-07-21`, `cameras_pack_date=2026-07-21` et
  `cameras_pack_count=N` avec N supérieur à zéro.

### Limites connues

- Le paquet livré ne contient pas de radars ; hors ligne, ils n'existent que dans une région dont
  le téléchargement a reçu une réponse Overpass.
- La couverture est celle d'OSM et de DeFlock, pas celle d'un organisme officiel : les pays peu
  cartographiés restent vides, et un point retiré d'OSM reste dans le paquet jusqu'à sa prochaine
  génération.
- Pas d'orientation des caméras dans ce lot : les cônes de `MAP-CAM` restent à faire.
- Le paquet n'est pas rafraîchi en arrière-plan ; il change avec une version de l'application ou
  avec un nouveau téléchargement de région.

## Orientation des caméras (MAP-CAM)

Cette section lève la limite « Pas d'orientation des caméras » ci-dessus.

### Données et précision

Les deux couches de caméras gardent leur source et leur interrupteur. Le cap vient du champ
`direction` d'OpenStreetMap, en degrés dans le sens des aiguilles d'une montre depuis le nord.

- En direct, `OverpassAlprCameras` normalise déjà `direction` ou `camera:direction` (degrés ou
  rose des vents) en degrés. `LayersStore` le transmet désormais dans `MapPoint.direction`.
- Dans le paquet embarqué, `scripts/ios/gen-camera-pack.py` lit la quatrième colonne de
  `app/src/main/assets/flock_cameras.bin`. Un point devient `[lat, lng, cap]` quand le cap
  existe, et reste `[lat, lng]` sinon. Le script écrit aussi `precisionM` (1,1 m, cinq
  décimales), `bearingPrecisionDeg` (1), `oriented` et `unoriented`.
- Sur les 127 264 caméras du paquet daté du 2026-07-21, **118 504 portent un cap** et 8 760
  n'en portent pas. Le fichier passe de 2 663 111 à 3 092 914 octets.
- Le lecteur Swift accepte les paires, les triplets et l'objet de paquet de région
  `{"lat":..,"lng":..,"kind":..,"direction":..}`. Un cap absent, `NaN` ou infini ne dessine
  aucun cône : le point reste nu plutôt qu'une orientation inventée.

### Dessin

Le cône est un polygone construit dans le repère monde, ancré sur la coordonnée stockée, puis
ajouté à une `MLNShapeSource` en mémoire (`vela-alpr-cone-src`, couche `vela-alpr-cone`). Il est
donc solidaire de la carte : une rotation de la carte le fait tourner sans calcul de cap écran.
`CameraCones.screenBearing` donne l'angle écran équivalent (cap monde moins cap carte) et
`MapCamTests` le fixe.

| Paramètre | Valeur | Raison |
|---|---|---|
| Ouverture | 36° (18° de chaque côté) | OSM donne un cap, pas un champ de vision : le cône indique une direction |
| Longueur nominale | 30 m | environ huit longueurs de voiture, très au-dessus de l'erreur d'arrondi de 1,1 m |
| Longueur minimale à l'écran | 18 pt | reste visible aux niveaux de zoom où les points apparaissent |
| Longueur maximale à l'écran | 120 pt | au-delà, le cône rétrécit au sol au lieu de grandir avec l'écran |

Entre environ z17 et z19 le cône fait 30 m au sol. Plus loin, le minimum de 18 pt le rend plus
long en mètres pour rester lisible ; plus près, le plafond de 120 pt le raccourcit à environ 18 m
à z20 et moins de 4 m à z22. À z22, cinq décimales restent donc visibles à l'échelle du cône :
le dessin ne prétend ni une portée mesurée ni un champ de vision mesuré. Le cône est sous le
point, partage son interrupteur et le même seuil de zoom 13,5. Aucun cône n'est dessiné pour une
caméra sans cap.

Le style hors ligne reste sans URL distante : le polygone est une source de forme en mémoire,
comme les autres surcouches. `CameraPackTests` et `OfflineTests` continuent de vérifier
`remote=0` avec la couche active.

### Différences avec Android

Android dessine un bitmap de 160 × 150 px (environ 47° d'ouverture) agrandi de 0,55 à 1,35 selon
le zoom, aligné sur la carte et ancré en bas. Il regroupe les têtes à 40 m et dessine une pastille
avec le nombre de têtes, puis un cône par tête qui porte un cap. iOS ne fait pas ce regroupement
visuel : il garde son dédoublonnage existant à 20 m, un point et un cône par point retenu. Android
peut donc montrer plusieurs cônes partant d'une pastille là où iOS en montre un ; Android garde
aussi une taille en pixels à tous les zooms, donc un cône très large au sol de loin, alors que le
cône iOS se raccourcit en mètres aux zooms élevés.

### Preuves

- `python3 scripts/ios/test_gen_camera_pack.py` : paires et triplets, doublon qui apporte le seul
  cap, cap absent, `360` ramené à `0`, `-90` ramené à `270`, sortie reproductible, 127 264
  caméras dont 118 504 orientées, cinq décimales conservées.
- JVM : `LayersStoreTest.liveCameraFacingReachesTheState` vérifie le cap venu d'Overpass et
  l'absence de cap inventé ; `declutterKeepsTheOnlyFacing` vérifie qu'un doublon ne perd pas le
  seul cap.
- Swift : `MapCamTests` couvre la rotation écran, la direction du polygone, le cap absent, les
  118 504 caméras orientées du paquet, le seuil de zoom 13,5 et le raccourcissement au sol à z20
  et z22.
- Simulateur : `MapLayersUITests.testCameraConesFollowTheMap` ouvre la feuille au zoom 17 avec la
  fixture, active les caméras de plaque, exige `alpr=ready:2` et
  `oriented=1 unoriented=1`, puis capture `camera-cones.png`, tourne la carte et capture
  `camera-cones-rotated.png`. Les lignes de rapport `cameras_oriented=1` et
  `cameras_unoriented=1` sont ajoutées au résumé du run. Le scénario remet l'interrupteur des
  caméras à zéro avant de rendre la main, parce qu'il s'exécute avant le scénario des surcouches
  et que les réglages persistent d'un lancement à l'autre.
- Run Mac `map-cam-20261028-081732-9944` : les six scénarios `MapLayersUITests` passent
  (`testCameraConesFollowTheMap` 43,4 s, `testLayerSheetLoadsOverlaysAtCloseZoom` 29,9 s,
  `testGoogleTrafficAndSatelliteOverSanFrancisco` 74,1 s, `testNamesModesHouseNumbersAndExits`
  104,6 s, `testOfflineCameraPackDraws` 45,2 s, `testStyleVariantsRender` 112,5 s), avec 151
  tests Swift, 409 tests JVM et 332 tests Kotlin simulateur sans échec. Le résumé rend
  `cameras_oriented=1`, `cameras_unoriented=1` et `cameras_pack_count=11`. La capture
  `camera-cones-rotated.png` montre la carte tournée et le cône du point violet toujours ancré
  sur la caméra.

### Limites connues

- Les paquets de région écrits par `OfflineStore.kt` ne stockent pas encore le cap : leurs points
  restent nus. Le lecteur Swift acceptera un champ `direction` dès que l'écrivain l'ajoutera.
- Le cap OSM est entier et parfois absent ; le cône indique une direction, jamais une portée.
- iOS ne dessine pas un cône par tête d'un même support, contrairement à Android.

## MAP-TAP : ce qui est dessiné est cliquable

Le toucher ne dépend plus d'une liste de POI tenue à part. `MapTapRegistry` est la source de
vérité unique : chaque identifiant de couche que l'application ajoute au style y est associé à un
gestionnaire typé. Les classes de couches exposent leurs identifiants (`MapLayers.layerIdentifiers`,
`RouteLayers.layerIdentifiers`, `AviationLayer.mapLayerIdentifiers`, etc.) et le test
`MapTapRegistryTests` compare cet ensemble dessiné à l'ensemble enregistré. Une couche ajoutée plus
tard sans règle fait donc échouer le test avant de devenir une zone morte.

Le toucher interroge `visibleFeatures(in:styleLayerIdentifiers:)`, l'équivalent MapLibre de
`queryRenderedFeatures`, avec une boîte de 10 points, portée à 22 points pour les symboles denses
(POI, caméras, avions, navires, articles, arrêts). Chaque couche est interrogée séparément parce
que la feature MapLibre ne porte pas le nom de sa couche ; l'index de la couche rétablit ensuite
l'ordre d'affichage et la feature la plus haute gagne. Les annotations (résultats, lieux
enregistrés, arrêts Transitous) et la route alternative gardent leur priorité existante. Un second
toucher à moins de 8 points et 0,35 s est ignoré, et un toucher sur un contrôle ou sous une feuille
ne déclenche rien.

### Événements et gestionnaires

| Événement | Gestionnaire actuel |
|---|---|
| `place` | `onPoiTap`, puis `MapPoiModel.tap` ou le tableau Transitous |
| `camera` | carte minimale `MapTapCards` (aucune fiche caméra n'existe encore) |
| `aircraft` | notification `WorldLayers.focusNotification`, la carte de `AviationLayer` |
| `ship` | carte minimale, alimentée par la ligne `maritime-ship-<mmsi>` du hub |
| `wiki` | notification `WorldLayers.focusNotification`, l'article de `WikiLayer` |
| `transitStop` | `onTransitStopTap` (arrêt ou ligne dessinée), sinon le tableau au point |
| `savedPlace` | `onSavedTap` |
| `savedShape` | carte minimale, le nom et la liste venant de `SavedShapeLayer` |
| route, route alternative | `onRouteTap`, sinon carte minimale |
| routes peintes, contrôles, carburant, ponts, rasters | carte minimale ou aucune action inscrite |

Une feature sans nom, sans identifiant ou absente du dernier état ouvre la carte minimale de son
type : nom si la couche en a un, catégorie, coordonnées et la donnée qui manque. Aucun nom n'est
repris d'une feature voisine et aucun identifiant n'est fabriqué.

### Accroches à faire dans `MapScreen`

Deux fiches n'existent pas encore hors de `MapScreen` : une fiche caméra et une fiche de ligne ou
de zone enregistrée. Le registre publie bien leurs événements et ouvre une carte minimale, mais
une vraie fiche demandera une accroche `MapController.onCameraTap` et `onSavedShapeTap` dans
`MapScreen`, sur le modèle de `onSavedTap`. `MapPoiModel.tap` ne reçoit pas encore l'identifiant OSM
porté par l'événement `place`.

`AviationLayer` garde son propre `UITapGestureRecognizer` pour la carte avion. Le registre publie
désormais le même toucher par la notification de focus, donc la carte s'ouvre encore ; supprimer
ce recognizer éviterait deux chemins pour le même geste.

### Preuves

- `MapTapRegistryTests` compare les identifiants dessinés et enregistrés, vérifie les familles
  dynamiques (`vela-transit-line-`, `vela-saved-shape-`), les canaux d'annotations et les
  événements d'une feature sans identifiant.
- `MapTapUITests.testTapEachKindOpensItsSheet` ouvre les quatre fiches demandées et produit
  `tap-place.png`, `tap-camera.png`, `tap-aircraft.png` et `tap-saved.png`, avec les lignes
  `tap_kind=place`, `tap_kind=camera`, `tap_kind=aircraft` et `tap_kind=saved`.

### Limites connues

- Une couche inconnue reste cliquable par la règle de secours, mais la carte minimale ne peut
  afficher que les attributs qu'elle porte.
- Les rasters Google et Esri ne sont pas interrogeables par MapLibre ; ils sont enregistrés comme
  sans action, ce qui est leur comportement attendu.
- Le toucher ne s'applique pas pendant la navigation ou dans un onglet masqué : les fermetures
  `MapScreen` existantes gardent ce filtrage pour les lieux, les arrêts et les lieux enregistrés.
  Les cartes caméra, navire et forme enregistrée ne connaissent pas encore cet état.
## Caméra de lancement (START-LOCATION)

Au lancement, la carte ne reste plus sur San Francisco dès qu'une position est connue. `StartCamera`
décide en un seul endroit, dans cet ordre : une cible explicite (`-VelaStartCamera`, lien entrant,
lieu enregistré, itinéraire, rejeu d'un trajet ou `-VelaFollowUser`) ; sinon la position de
l'utilisateur si l'autorisation est déjà accordée et qu'un point arrive en moins de deux secondes,
au zoom 14 ; sinon la dernière caméra quittée, enregistrée sous la clé versionnée
`app.vela.ios.map.last_camera.v1` ; sinon San Francisco au zoom 12.

Le premier écran n'attend jamais la position : il affiche tout de suite la dernière caméra ou la
caméra par défaut. Un point tardif déplace la carte une seule fois, en douceur. Si l'utilisateur a
déjà déplacé la carte, ou si une cible explicite est arrivée, la caméra ne bouge plus. Quand
l'autorisation n'est pas encore décidée, la fenêtre système ne bloque pas le lancement ; une
autorisation accordée plus tard ouvre une nouvelle fenêtre de deux secondes pour rejoindre la
position. Un refus laisse la dernière caméra en place, sans indicateur de chargement ni vue vide,
et le bouton de localisation garde son message calme. Une caméra invalide, à (0,0) ou hors bornes,
n'est jamais enregistrée ni restaurée.

Preuves : `StartCameraTests` couvre chaque rang de priorité, la fenêtre de deux secondes, les deux
annulations (déplacement de l'utilisateur, cible explicite), le zoom de ville et la caméra
persistée. `StartLocationUITests.testOpensOnTheSimulatedPosition` vérifie que le centre est à moins
de 150 m du point simulé et capture `start-location.png` ;
`StartLocationUITests.testIncomingLinkWinsOverThePosition` vérifie qu'un lien entrant garde la
caméra. Les lignes `start_camera=position|last|default|explicit` et `start_distance_m=<n>`
accompagnent chaque scénario.

Run Mac `start-location-20261028-182329-30819` : 167 tests Swift et les quatre scénarios
d'interface passent. `testOpensOnTheSimulatedPosition` (7,7 s) rend
`start_camera=position`, `start_distance_m=0`, centre 37,77490,-122,41940 au zoom 14, et capture
`start-location.png` ; `testIncomingLinkWinsOverThePosition` (7,6 s) rend
`start_camera=explicit` avec le centre à Davis au zoom 12, et capture `start-location-link.png`.
Les deux captures sont publiées avec le run.
## Arbres et couvert forestier (TREES-LAYER)

### Verdict honnête sur la 3D

MapLibre Native dans ce projet sait extruder des bâtiments (`fill-extrusion`), mais il n'a ni
primitive de modèle 3D, ni billboard avec profondeur. Un vrai houppier en volume, une couronne
texturée qui tourne avec la caméra ou une forêt instanciée en 3D ne sont donc pas réalisables dans
la pile actuelle. Les décisions D13 et D14 refusent un moteur de carte maison, et un calque
Metal personnalisé pour les arbres rouvrirait exactement ce que ces décisions ferment. Ce lot ne
prétend pas faire de la 3D : il dessine un couvert vu du dessus, à plat.

### Ce qui est dessiné

| Élément | Source | Seuil | Note |
|---|---|---|---|
| Forêt, bois et parc | tuiles vectorielles OpenFreeMap, couches `park`, `landcover_wood`, `landcover_grass` | le zoom des tuiles | vert data-driven, motif de feuillage tuilé peint localement, aucun fichier distant |
| Arbres isolés | Overpass, `node[natural=tree]` | 17,0 | disque de houppier doux avec une ombre légère, taille réelle quand la donnée la porte |
| Taille d'un arbre | `diameter_crown`, sinon `height` | aucune | sans étiquette, un disque de taille visuelle fixe, jamais un arbre « grand » inventé |

Le disque est un `MLNCircleStyleLayer` en mémoire, pas un sprite : il n'ajoute aucune URL au
style et reste donc compatible avec une région téléchargée. Son rayon est calculé en points à
partir du diamètre connu et du zoom, puis plafonné, pour qu'un arbre de 15 m ne devienne pas une
tache de 200 px à z19. L'ombre est un second disque décalé de 1,5 pt, très peu opaque.

Les polygones ne sont pas une nouvelle source : quand l'interrupteur est allumé, `TreesLayer`
repeint les trois couches de végétation existantes et installe un motif de 64 px généré en
mémoire. Elles retrouvent leurs couleurs et leurs motifs d'origine quand l'interrupteur est
coupé. Aucun nom d'hôte n'entre dans le document de style.

### Plafond, densité et coût

- Cache : une entrée par tuile z14, valable 30 minutes. La boîte interrogée est la tuile
  contenue dans le centre de la vue, élargie de 25 % de chaque côté pour couvrir une vue z17
  même en paysage. Huit entrées au plus, les plus anciennes sont évincées.
- Une seule requête à la fois ; une nouvelle vue annule la réponse précédente ; un échec n'est
  jamais mis en cache comme « aucun arbre ici ».
- Plafond absolu : 500 arbres. Plafond par écran : `min(500, max(120, 320 × km²))`, donc une
  forêt dense ne coûte jamais des milliers de symboles. Les arbres les plus proches du centre
  sont gardés.
- Aucun arbre sous z17 : la couche est cachée et aucune requête n'est envoyée. Les polygones,
  eux, restent visibles au zoom où les tuiles les portent.
- Le coût par déplacement est une requête Overpass par nouvelle tuile z14, au plus une toutes
  les 30 minutes pour la même tuile. Un panoramique de quelques centaines de mètres dans la même
  tuile ne redemande rien.

### Hors ligne

Dans une région téléchargée, l'interrupteur garde les polygones et ne fait aucune requête
Overpass : `LayersModel` signale l'état hors ligne à `LayersStore`, qui vide les arbres isolés et
affiche « Downloaded region: canopy only ». Le style hors ligne reste à zéro URL distante.

### Réglage

Un seul interrupteur, « Trees and canopy », sous la clé `trees_canopy_on`, coupé par défaut. Rien
n'est demandé tant qu'il est coupé. La ligne de débogage ajoute `trees=phase:count` et
`tree_source=fixture|overpass|none`.

### Différences avec Android

Android n'a pas de couche arbres équivalente dans ce dépôt. Ce lot est propre à iOS et ne change
aucune clé Android existante.

### Limites connues

- Ce n'est pas de la 3D : les houppiers sont des disques au sol, sans volume ni occlusion.
- La couverture est celle d'OSM. `natural=tree` est dense dans certains parcs européens et
  presque absent ailleurs ; les polygones restent la seule information visible dans ce cas.
- `height` sans `diameter_crown` donne un diamètre estimé à la moitié de la hauteur, entre 1,5 et
  20 m. C'est une relation documentée, pas une mesure.
- Le motif de feuillage est décoratif ; il ne représente pas les essences.

### Preuves

- JVM : `app.vela.ios.layers.TreesTest` couvre le parseur Overpass (coordonnées invalides ignorées,
  `diameter_crown`, repli sur `height`, absence d'étiquette), le plafond de 500 avec priorité au
  centre, le plancher de densité par écran, le seuil z17, le cache de 30 minutes par tuile z14,
  l'expiration, la non-réponse hors de la boîte et le fixture déterministe.
- Simulateur : `TreesUITests.testTreesAndCanopyAtHighZoom` ouvre la feuille, vérifie que
  l'interrupteur est coupé par défaut, l'allume, attend `trees=ready:` avec
  `tree_source=fixture`, capture `trees.png` à z17,6, relance à z15,2, vérifie que la couche
  retombe en `trees=zoom:` et capture `trees-forest.png`.
- Run Mac `trees-layer-20261029-003202-16603` : 561 tests JVM, 460 tests Kotlin simulateur,
  172 tests Swift et les sept scénarios d'interface passent (les six `MapLayersUITests` et
  `TreesUITests` en 129,7 s). Le résumé rend `trees_count=8`, `trees_source=fixture` et
  `trees_zoom_gate=1`.
- `trees.png` montre les disques verts du fixture à z17,6 ; une partie est derrière la ligne de
  débogage, qui occupe le centre de l'écran en Debug. `trees-forest.png` montre le zoom 15,2 où
  aucun arbre isolé n'est dessiné. À cet endroit les tuiles ne portent qu'une mince tache de bois
  à z15, donc la capture prouve le seuil et le polygone, pas une forêt entière.

## Marquages au sol (ROAD-MARKINGS)

### Pourquoi rien ne s'affichait

Les données arrivaient bien : la ligne de débogage affichait `painted=ready:120` alors que la
carte restait vide. Le défaut était donc dans le rendu Swift, pas dans la requête. Quatre causes
se cumulaient :

- `updateShapes` écartait toute marque de moins de deux points. Les flèches sont des points
  uniques : aucune flèche n'a jamais atteint le style.
- `PaintedRoads.Kind.ARROW` et `SURFACE` n'avaient aucune couche de style. La chaussée n'était
  donc jamais repeinte et les flèches n'avaient pas de destination.
- La couche `vela-paint-median` n'avait aucun prédicat : elle dessinait **toutes** les marques en
  gris clair de 4 points, puis les couches colorées passaient par-dessus. Le résultat se lisait
  comme une route grise, pas comme un marquage.
- Les largeurs étaient des constantes en points, alors que les données portent des mètres. À
  z16, une ligne de voie de 1 point blanc sur une chaussée claire est invisible.

La couche était aussi coupée à z16,0 alors qu'Android dessine à partir de 16,5.

### Ce qui est dessiné maintenant

`PaintedMarksLayer.swift` insère, de bas en haut et toujours sous le premier calque d'étiquettes
(donc jamais sur un nom de rue) :

| Marque | Source OSM | Forme |
|---|---|---|
| surface | `lanes`, `lanes:forward/backward`, `turn:lanes`, ou voie vélo/bus | bande à la largeur réelle des voies |
| median | deux demi-chaussées du même nom, 8 à 40 m d'écart | bande entre les deux |
| center | rue à double sens peinte | trait jaune continu |
| lane | nombre de voies ou `turn:lanes` | pointillés blancs entre voies |
| bike | `cycleway`, `cycleway:left/right/both` = `lane` ou `track` | trait vert à l'extérieur de la chaussée |
| bus | `busway`, `busway:left/right/both` | bande rouge translucide dans la voie bus |
| crosswalk | `footway=crossing` ou nœud `highway=crossing` peint | zébrures |
| stop | nœud `highway=stop`/`traffic_signals` | ligne blanche derrière le passage |
| arrow | `turn:lanes` | une flèche par voie, à 18 m du carrefour |
| arrow | `oneway` sans `turn:lanes` | flèche « tout droit » tous les 70 m |

Les largeurs sont recalculées tous les demi-niveaux de zoom avec la règle d'Android
(`mètres × 2^z / 59960`), ce qui garde une voie vélo lisible de z16,5 à z19. Les flèches sont des
images dessinées à l'exécution (contour blanc, glyphe ardoise) : aucun sprite distant n'est
nécessaire et l'icône reste lisible sur chaussée claire comme sombre.

### Deux sources, jamais d'invention

- `pack` : le paquet PMTiles optionnel `painted-roads` (bake Californie, 66 Mo). La feuille
  affiche « Painted pack » et le propose au téléchargement uniquement s'il est absent ; hors
  Californie ses tuiles sont vides.
- `tiles` : la réponse OSM vivante de la vue (`PaintedRoads.fetch` puis `build`). C'est la source
  par défaut, parce que le paquet n'est pas embarqué.

Si aucune des deux ne donne de marque (Overpass indisponible), les flèches de sens unique déjà
présentes dans les tuiles vectorielles (`road_one_way_arrow`, `road_one_way_arrow_opposite`) sont
réactivées à z16,5. La feuille indique toujours la source active et la couverture. Aucune marque
n'est inventée : une route sans `lanes`, `cycleway`, `busway` ni `oneway` reste nue.

La couche reste sans requête distante : la source du paquet est un fichier local et la source
vivante est une `MLNShapeSource` en mémoire. Interrupteur éteint : aucune requête, aucune couche
visible, et les flèches de base retrouvent leur visibilité d'origine.

### Tests

- JVM `PaintedRoadsTest` : voie vélo `lane` et `track`, voie bus à droite et à gauche, flèches de
  sens unique (et absence quand `turn:lanes` existe), lignes d'arrêt, passage peint.
- JVM `LayersStoreTest` : seuil 16,5 (aucune requête à 16,4), choix `pack`/`tiles` et repli sur
  les flèches vectorielles.
- UI `RoadMarkingsUITests.testPaintedMarksAtStreetZoom` : captures `road-markings.png`,
  `road-bike-lane.png`, `road-oneway.png`, lignes `marks_source=pack|tiles`, `marks_count=<n>`,
  `marks_zoom=<z>`.

### Limites de couverture

OSM cartographie les voies et le sens unique presque partout, mais les largeurs, `turn:lanes`, les
bandes cyclables et les voies bus sont surtout renseignés en Europe de l'Ouest et en Amérique du
Nord. En France, les bandes cyclables et les doubles sens cyclables sont bien couverts ; les
petites rues résidentielles sans `lanes` restent nues. Ailleurs, seule la flèche de sens unique
apparaît souvent. Le paquet Californie ne couvre que la Californie.

### Run Mac

Run `road-markings-20261029-015102-26655` : build simulateur, 536 tests JVM et 440 tests Kotlin
simulateur sans échec. Les sept scénarios UI passent, dont
`RoadMarkingsUITests.testPaintedMarksAtStreetZoom` (49,8 s) et les six `MapLayersUITests`
(caméras 20,4 s, rasters 58,1 s, surcouches 17,1 s, noms 77,7 s, pack hors ligne 31,9 s, styles
89,1 s). Lignes de rapport : `marks_source=tiles`, `marks_count=23`, `marks_zoom=17.0`,
`paint_layers=9`, `paint_built=23`. Captures : `road-markings.png` (ligne jaune, voies,
flèches de sens unique, bande bus), `road-bike-lane.png` (trait vert), `road-oneway.png`.

Deux défauts de rendu ont été trouvés par cette campagne et corrigés dans le lot :

- une collection de formes mélangeant points et polylignes arrivait vide dans MapLibre ; les
  lignes et les flèches ont maintenant deux sources distinctes et homogènes.
- une réponse arrivée pendant que la feuille des calques était ouverte n'atteignait pas la carte
  au moment de la fermeture (`onChange` ne rejouait pas la valeur) ; `LayersModel.republish()`
  réémet les données à la fermeture.

## Naviguer : route congestionnée, flèches et voies

NAV-RENDER ajoute un groupe de couches propre à la conduite, dans `RouteLayers.swift`. Il ne
remplace pas les couches d'aperçu d'itinéraire : celles-ci restent utilisées par la feuille de
route, le groupe de navigation ne vit que pendant un guidage actif.

### Identifiants

| identifiant | rôle |
|---|---|
| `vela-nav-casing` | liseré de 10 points sous toutes les pièces |
| `vela-nav-traveled` | partie parcourue, grise (`level == -1`) |
| `vela-nav-free` | reste de la route au flux libre (`level == 0`) |
| `vela-nav-slow` | congestion modérée (`level == 1`) |
| `vela-nav-heavy` | congestion forte (`level == 2`) |
| `vela-nav-severe` | congestion sévère (`level >= 3`) |
| `vela-nav-arrow` | flèche de la prochaine manœuvre et de la suivante |
| `vela-nav-lane` | une flèche par voie à l'approche |

Les huit identifiants sont dans `RouteLayers.layerIdentifiers` et donc dans l'audit de
`MapTapRegistry`. Les six lignes gardent le gestionnaire `routeSelected` existant, avec un attribut
`index` à 0, comme la ligne d'aperçu. Les deux couches de symboles sont enregistrées `.none` :
un appui sur une flèche traverse jusqu'à la ligne de route en dessous.

### Ordre de dessin

De bas en haut, dans l'ordre réel du style : routes de base, groupe de navigation (liseré, gris,
puis niveaux de congestion), rasters de trafic, caméras et surcouches de `MapLayers`, marques
peintes de ROAD-MARKINGS, puis les deux couches de symboles de navigation, puis les libellés. Les
flèches et voies sont remontées une seule fois au-dessus des marques peintes, à leur première
utilisation, pour que les tirets de voie ne les coupent pas. Les rasters et les caméras gardent
donc leur place actuelle, et le liseré reste sous les marques peintes : aucune ligne de voie ni
flèche de sens unique n'est recouverte.

Le liseré et la ligne font 10 et 7 points à tout zoom de z16 à z19, assez larges pour rester
lisibles sans envahir la chaussée. Les couleurs reprennent celles d'Android : gris `#9AA0A6`,
bleu `#2F7BF0`, orange `#F2A33A`, rouge `#E5483B`, rouge sombre `#9E1C1C`.

### Sources

Trois `MLNShapeSource` en mémoire, `vela-nav-piece`, `vela-nav-arrow` et `vela-nav-lane`. Aucune
requête distante et aucun sprite : les glyphes sont dessinés à l'exécution avec les mêmes noms SF
Symbol que `StepsSheet.symbol` pour les manœuvres et que les cellules de voie du bandeau. Un style
hors ligne les affiche donc aussi.

### Cycle de vie

- La carte reçoit un `NavRouteDraw` complet à chaque changement utile : révision de route, point
  parcouru à 8 m près, étape, aperçu ou approche des voies. Une source n'est réécrite que dans ce
  cas, jamais à chaque image GPS.
- À la fin du guidage, à l'arrivée terminée par `Done`, à l'entrée en conduite libre et au
  `styleDidLoad`, les trois sources sont remises à vide. Un changement de style recrée les
  couches puis rejoue le dernier `NavRouteDraw` mémorisé.
- La conduite libre ne dessine aucun de ces éléments, y compris en carte simple ; les caméras et
  les alertes restent visibles comme avant.

### Tests

- JVM `RouteRenderTest` : découpe du gris et des spans, chevauchement, sélection des deux flèches,
  porte des voies et ordre gauche à droite des glyphes.
- UI `NavRenderUITests.testCongestionGreyAndRoadAhead` : `nav-congestion.png`,
  `nav-road-ahead.png`, `nav-lanes-map.png` ; lignes `nav_route_segments`, `nav_congestion`,
  `nav_road_ahead` et `nav_lanes_map` dans la sortie de test.

### Run Mac

Run `nav-render-20261029-033244-31859` : build simulateur et 182 tests unitaires iOS sans échec.
Les cinq scénarios UI passent, dont `NavRenderUITests.testCongestionGreyAndRoadAhead` et les quatre
`NavBannerUITests`. Lignes de rapport : `nav_route_segments=3`, `nav_congestion=1`,
`nav_road_ahead=2`, `nav_lanes_map=4`. Captures : `nav-congestion.png`, `nav-road-ahead.png` et
`nav-lanes-map.png`.

## Gestes, nord et chrome de carte (MAP-GESTE)

Ce lot ferme L16-L18, L38-L40 et L264. Il ne change ni le style, ni les couches, ni le toucher :
il ajoute la rotation, le verrou nord, le chrome de la carte et l'épingle d'appui long.

### Rotation et nord

MapLibre porte le geste à deux doigts. iOS règle `toleranceForSnappingToNorth` à 12 degrés, la
valeur d'Android `BROWSE_TURN_KEEP_MIN_DEG` : un tour qui s'arrête à moins de 12 degrés du nord
revient au nord au relâchement, un tour plus large reste incliné. La boussole du chrome affiche le
cap courant par l'angle de son aiguille, et son `accessibilityValue` donne le cap en degrés. Un
appui sur la boussole remet la carte au nord avec l'animation de caméra habituelle, coupée par
`-VelaDeterministic`.

Le réglage « Keep north up » (`keep_north_up`, faux par défaut) coupe `rotateEnabled`, remet la
carte au nord dès qu'une position au repos s'écarte de plus de 0,05 degré, et force le cap zéro
dans la caméra de conduite (`updateNavigation`). Il reste donc north-up en navigation comme à
l'arrêt. Le choix est écrit dans la suite `app.vela.ios.vela_settings` et relu au lancement
suivant ; un changement s'applique sans relancer l'app, par la notification
`VelaMapGestureSettingsChanged`.

### Position de départ

Le réglage « Where the map opens » (`start_view`) prend trois valeurs et ne change pas l'ordre de
START-LOCATION :

| Valeur | Ordre appliqué |
|---|---|
| `here` (défaut) | cible explicite, puis position dans les deux secondes, puis dernière caméra, puis la ville par défaut |
| `last` | cible explicite, puis dernière caméra, puis la ville par défaut ; la position ne déplace jamais la caméra |
| `city` | cible explicite, puis la ville par défaut ; ni la position ni la dernière caméra ne s'appliquent |

Une cible explicite (`-VelaStartCamera`, lien entrant, lieu enregistré, itinéraire, rejeu) garde la
priorité dans les trois cas. La carte s'ouvre toujours north-up, à la caméra de la ville au zoom 12
quand `city` est choisi. Les lignes de preuve `start_camera=...` et `start_center=...` ne changent
pas de forme.

### Chrome

| Élément | Règle |
|---|---|
| Échelle | distance ronde en mètres réels, calculée par `metersPerPoint(atLatitude:)` à la latitude du centre, jamais par une table de zoom ; barre de 96 points au plus, unités métriques ou impériales selon le réglage |
| Boussole | bouton de 48 points, aiguille tournée par le cap, valeur VoiceOver en degrés, appui vers le nord |
| Zoom | deux boutons de 48 points sous la boussole, affichés par « Prefer buttons over swipes » (`prefer_buttons`), comme `PreferButtons` sur Android |
| Forme | « Map buttons » (`map_button_shape`) dessine la boussole, le zoom, le bouton de localisation et celui du stationnement ronds, la valeur par défaut de `Design.Chrome.actionSize`, ou à coins carrés de 16 points ; l'option est celle de L264 |
| Cibles | tous les boutons mesurent 48 points, au-dessus du minimum de 44 de `Design.Size.hitTarget`, et portent un libellé VoiceOver |

Les jetons de `DESIGN.md` sont utilisés pour les écarts, les rayons, les ombres, la typographie et
les couleurs du panneau de l'épingle. La barre d'échelle remplace celle de MapLibre, cachée avec la
boussole native : les deux valeurs viennent de la même caméra MapLibre et restent donc cohérentes
avec la carte. Le bloc de débogage `gesture-debug` publie
`gesture_bearing=<deg> gesture_north=<0|1> gesture_scale=<texte>`.

### Appui long

Un appui long déclenche un retour haptique moyen, dépose immédiatement une épingle locale et ouvre
une fiche qui affiche la coordonnée à cinq décimales et deux actions : « Directions » et « Look up
address ». Aucune requête ne part au dépôt de l'épingle ; « Directions » passe par le planificateur
d'itinéraire, « Look up address » est le seul chemin qui peut demander un géocodage, et il reste
soumis aux réglages Google et à Look up tapped places. L'action VoiceOver « Drop pin at map center »
suit le même chemin. En navigation, en conduite libre ou en transports, l'épingle est retirée : le
chrome de conduite garde la main.

### Preuves

- Simulateur : `MapGestureUITests.testRotationReturnsNorth` tourne la carte à deux doigts, lit
  `gesture_bearing`, appuie sur `map-compass`, exige un cap nul et capture `north.png`.
- Simulateur : `MapGestureUITests.testKeepNorthUp` allume le réglage, relance sans remise à zéro,
  tourne la carte et exige un cap nul après deux secondes, capture `north-locked.png`.
- Simulateur : `MapGestureUITests.testStartPosition` choisit « A city view » et « Square », relance
  sans `-VelaStartCamera`, exige `start_camera=default`, le centre de la ville au zoom 12 et un cap
  nul, puis lit `gesture_scale` et capture `scale.png` avec les boutons carrés.
- Simulateur : `MapGestureUITests.testLongPressDropsPin` appuie longuement au centre, exige la
  fiche `dropped-pin-card`, sa coordonnée et son action Directions, et capture `long-press.png`.
- Les lignes de rapport `gesture_bearing`, `gesture_north` et `gesture_scale` sont ajoutées au
  résumé du run.

### Limites connues

- Le geste de rotation dépend de MapLibre iOS ; le test le synthétise par `rotate`, un doigt réel
  peut demander un tour plus franc.
- La boussole affiche le cap par l'aiguille et par VoiceOver, sans nombre visible, pour rester
  dans une cible de 48 points sans texte fixe.
- « Keep north up » ne fige pas un cap imposé par un panoramique programmatique d'un autre lot ;
  il corrige au repos, comme Android.
- Aucun réglage de clavier de zoom n'est repris : iOS n'a pas la même notion de touches matérielles.

### État de validation

Le run Mac `map-geste-20261029-025922-25423` a arrêté la compilation Swift sur
`isRotateEnabled` (nom MapLibre renommé), corrigé au commit suivant. Le run
`map-geste-20261029-031639-879` a ensuite arrêté la compilation du test sur l'accès à la propriété
`app` de `VelaUITestCase`, elle aussi corrigée. Aucun run vert ne couvre encore ce lot : les deux
scénarios `MapGestureUITests` et `StartLocationUITests` restent à rejouer sur le runner.
