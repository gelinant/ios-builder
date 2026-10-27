# iOS map layers and styles (lots I-1b, I-1c and MAP-STYLE)

State on 2026-10-27, on branch `ios/map-style` merged with `ios/main`. This document says what the
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
| Painted road markings | `PaintedRoads.fetch` then `build` | 16.0 | center lines, lanes, bike lanes, crossings and stop lines; lane arrows are not drawn (no iOS image set) |
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
  `poi-icons-default.png`, `poi-icons-large.png`.
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
- Painted lane arrows are not rendered; the other markings are.
- UK prices and Dutch bridges are useless outside their country and the panel says so.
- Colored transit lines and terrain stay out of these lots.
- Le paquet Vela ne couvre que Davis et ses 337 lieux nommés : il prouve la source et la taille,
  pas une couverture mondiale. Aucune source Google de POI n'existe sur iOS ; `tiles` reste
  OpenFreeMap.
- The two Google rasters are non-contractual services without a key: an outage or a response change
  leaves the vector map, with no offline fallback.
- No iPhone validation of these layers has been done yet, including the two rasters.
