# Essai Mapbox (étape 1)

Ce document décrit l'écran d'essai Mapbox du build Debug iOS et ses mesures face à la carte
actuelle ([WEBMAP.md](WEBMAP.md)). Il ne remplace rien : la carte principale reste MapLibre GL JS
dans une `WKWebView`. Le remplacement du shim est l'étape 2.

## Ce qui est construit

- `iosApp/Vela/Map/Mapbox/MapboxSpikeScreen.swift`, compilé en Debug seulement. Avec
  `-VelaMapboxSpike YES`, l'app ouvre cet écran à la place de la carte.
- Mapbox Maps SDK for iOS 11.34.2 (SPM, `https://github.com/mapbox/mapbox-maps-ios.git`, version
  exacte), avec MapboxCoreMaps 11.34.2, MapboxCommon 24.34.2 et Turf 4.1.0. C'était la dernière
  11.x stable le 9 novembre 2026.
- Style Mapbox Standard, sans réglage : ciel, atmosphère, éclairage et bâtiments 3D sont ceux du
  style.
- Terrain : source `raster-dem` `mapbox://mapbox.mapbox-terrain-dem-v1` (`mapbox-dem`, 514 px,
  maxzoom 14), exagération 1,2 comme `Map3D.terrainExaggeration`.
- Trois caméras, cap 200 et inclinaison 60 : `twinpeaks-z15` et `twinpeaks-z17` (Twin Peaks,
  37.7544,-122.4477), `downtown-z16` (centre-ville, 37.7915,-122.3990). Aucune position de
  l'utilisateur n'est lue.
- Ligne d'état `mapbox-spike-debug` : `token=0|1 sdk=<version> style=0|1 style_ms=<n>
  loaded_ms=<n> terrain=0|1 elevation=<m> peak=<m> camera=<nom> idle=0|1 errors=<n> error=<texte>
  fps=<n> frames=<n> ticks=<n> seconds=<s>`. `terrain=1` exige une altitude de plus de 50 m sous
  une caméra (`MapboxMap.elevation(at:)`) : Twin Peaks est à environ 280 m.
- Boutons `spike-camera-<nom>` (change de caméra) et `spike-fps-run` (le mouvement des fps sur
  la caméra courante).

## SPM et jeton

- Le paquet SPM n'a pas besoin de jeton secret (`sk.`) ni de `.netrc`. Les binaires de
  MapboxCoreMaps et MapboxCommon se téléchargent depuis `api.mapbox.com/downloads/v2/...` sans
  authentification (vérifié par `curl`, réponse 200).
- Le style Standard et les tuiles demandent un jeton public (`pk.`), donc un compte Mapbox.
- Le jeton public de Vela est versionné dans `iosApp/Config/MapboxToken.xcconfig`, inclus par
  `Vela-Debug.xcconfig` et `Vela-Release.xcconfig`. La valeur arrive dans `MBXAccessToken` de
  l'Info.plist, donc dans chaque IPA. L'étape IPA de `ci-ipa.sh` échoue si elle est vide.
- `iosApp/Config/Mapbox.xcconfig`, ignoré par git, remplace ce jeton s'il existe. Sur le runner,
  `ci-ipa.sh` y écrit le secret `MAPBOX_ACCESS_TOKEN` du workflow quand il est défini. Le jeton
  n'est jamais affiché ; le résumé dit `mapbox_token=1` et sa source. Un secret qui ne commence
  pas par `pk.` est ignoré.
- Sans jeton, l'écran affiche « No Mapbox token » (`mapbox-no-token`) et ne crée pas de carte.

Pour activer le rendu :

1. Créer un compte Mapbox et copier le jeton public par défaut (ou un jeton `pk.` sans scope
   secret).
2. Runner : `gh secret set MAPBOX_ACCESS_TOKEN -R gelinant/ios-builder`, puis coller le jeton.
3. Mac local : écrire `VELA_MAPBOX_TOKEN = pk.<jeton>` dans `iosApp/Config/Mapbox.xcconfig`.

## Télémétrie

- Le SDK lit la clé `MGLMapboxMetricsEnabled` des `UserDefaults` et enregistre `true` comme
  défaut. L'écran écrit `false` avant la première carte quand aucune valeur n'est stockée. Le menu
  d'attribution de Mapbox reste visible et peut la changer.
- Les conditions Mapbox exigent un moyen de refuser la télémétrie ; le menu d'attribution le
  fournit.
- Le SDK envoie toujours, à la création de chaque carte, un événement « turnstile » (comptage des
  utilisateurs actifs pour la facturation) et un événement de chargement de carte
  (`MapView.sendInitialTelemetryEvents`, `EventsManager.swift`). Le réglage ne les coupe pas.
- Hôtes : `api.mapbox.com` (style, tuiles, glyphes, terrain), `events.mapbox.com` (événements),
  `config.mapbox.com` (configuration du SDK). Ils sont dans l'entrée `mapbox` de
  `iosApp/Vela/Settings/Notices.json`, licence « Mapbox Terms of Service ».

## Manifeste de confidentialité

Le SDK apporte ses propres `PrivacyInfo.xcprivacy` (MapboxMaps, MapboxCoreMaps, MapboxCommon).
MapboxCommon y déclare la position précise et approximative, un identifiant, l'interaction
produit, l'usage, la performance et le diagnostic, non liés et sans pistage. Hormis
`MBXAccessToken`, le SDK ne demande aucune clé `Info.plist` pour une carte sans position. Une app publiée sur
l'App Store devrait reprendre ces types dans sa fiche de confidentialité.

## Mesures

Le simulateur n'est pas un iPhone. Il rend Metal et WebGL sur le GPU du Mac du runner, sans
ProMotion et sans limite thermique. Les fps ci-dessous comparent les deux moteurs sur la même
machine et la même caméra ; ils ne disent pas les fps d'un iPhone.

Mouvement commun, sur chacune des trois caméras une fois la vue chargée : cap +360 degrés en
10 s à partir de 200, inclinaison 60, un pas de caméra par image affichée (`CADisplayLink` pour
Mapbox, `requestAnimationFrame` pour la carte actuelle). On compte les images rendues :
`onRenderFrameFinished` pour Mapbox, l'événement `render` de GL JS pour la carte actuelle
(`-VelaFpsProbe`, `MapFpsProbe.swift`, ligne `map-fps-debug`). « Vue chargée » veut dire
l'événement `onMapIdle` pour Mapbox et `map.loaded()` ou `idle` pour GL JS.

Run `mapbox-20261109-133025-21826` (commit `3950f08a`, iPhone 17, iOS 26.5, Xcode 26.6), sans
jeton Mapbox :

| Caméra | Carte actuelle : fps | images / pas rAF en 10 s | attente des tuiles | Mapbox : fps |
|---|---|---|---|---|
| `twinpeaks-z15` | 0,7 | 8 / 9 | 12,9 s | non mesuré (pas de jeton) |
| `twinpeaks-z17` | 4,3 | 44 / 45 | 6,7 s | non mesuré |
| `downtown-z16` | 2,0 | 20 / 21 | 2,1 s | non mesuré |

- La carte actuelle attend que toutes les tuiles de la vue soient chargées (`map.loaded()` ou
  l'événement `idle` de GL JS), puis 3 s, puis tourne. Les trois vues ont atteint cet état.
- Le nombre de pas `requestAnimationFrame` suit celui des images : la page WebGL ne reçoit
  qu'une image par seconde environ pendant la rotation à Twin Peaks z15, sur ce simulateur.
- Le compteur `fps=` affiché en bas de la carte actuelle mesure l'interface UIKit, pas la page
  WebGL : il montrait 25 à 57 pendant les mêmes vues.
- Mapbox : le test s'arrête sur `XCTSkip` sans jeton. Les fps, le temps de chargement du style
  (`style_ms`, `loaded_ms`) et l'altitude du terrain restent à mesurer.

Taille (archive Release sans signature, run `mapbox-20261109-124027-29495` contre
`merge-1109-20261109-113803-29887`, même base `6b83876b`) :

| | Avant | Avec Mapbox | Écart |
|---|---|---|---|
| IPA | 24 317 019 octets | 36 413 270 octets | +12 096 251 (+49,7 %) |
| Binaire `Vela` | 27 549 640 octets | 31 924 680 octets | +4 375 040 |
| `MapboxCoreMaps.framework` | | 15 036 Kio | |
| `MapboxCommon.framework` | | 7 904 Kio | |
| `Turf.framework` | | 368 Kio | |

Le binaire grandit alors que l'écran n'existe qu'en Debug : le module Swift MapboxMaps, compilé
depuis le paquet, est lié aussi en Release. Les trois frameworks dynamiques sont embarqués dans
toutes les configurations.

## Captures

Run `mapbox-20261109-133025-21826` :

- `webmap-twinpeaks-z15.png` : relief ombré et terrain de Twin Peaks, Twin Peaks Boulevard, le
  réservoir, les arrêts de transport ; vue inclinée, cap 200.
- `webmap-twinpeaks-z17.png` : pente des Twin Peaks en gros plan, sentiers, maisons extrudées en
  haut de l'écran.
- `webmap-downtown-z16.png` : Financial District, immeubles extrudés gris, noms de rues.
- `webmap-fps-end.png` : Twin Peaks z15 après le tour complet.
- `mapbox-no-token.png` : l'écran d'essai, la ligne d'état (`token=0 sdk=11.34.2 style=0 ...`), les
  quatre boutons et « No Mapbox token ».

Les captures `mapbox-twinpeaks-z15.png`, `mapbox-twinpeaks-z17.png` et `mapbox-downtown-z16.png`
ne sont produites qu'avec un jeton.

Dans le run `mapbox-20261109-124027-29495`, les captures de la carte actuelle étaient prises 12 s
après le lancement : la carte était encore vide. La sonde attend maintenant les tuiles.

## Catalyst

- La documentation de Mapbox Maps SDK for iOS ne cite pas Mac Catalyst comme plateforme. La page
  des exigences donne iOS 14 ou plus récent, et il existe une page visionOS
  (<https://docs.mapbox.com/ios/maps/guides/>, <https://docs.mapbox.com/ios/maps/llms.txt>).
- Les xcframeworks 11.34.2 de MapboxCoreMaps et MapboxCommon contiennent une tranche
  `ios-arm64_x86_64-maccatalyst` (vérifié dans les zip téléchargés).
- Le changelog de 11.6.0-beta.1 dit : « MapboxMaps XCFramework structure now properly constructed
  for `maccatalyst` platform and code signing issues was eliminated »
  (<https://github.com/mapbox/mapbox-maps-ios/blob/main/CHANGELOG.md>).
- Le ticket « Code signing fails for Mac Catalyst target apps » (11.2.0) est encore ouvert
  (<https://github.com/mapbox/mapbox-maps-ios/issues/2140>), comme « Ambiguous type for Polygon on
  Mac Catalyst target » (<https://github.com/mapbox/mapbox-maps-ios/issues/1997>).
- Réponse : Catalyst n'est pas une plateforme documentée. Les binaires en ont la tranche, sans
  engagement de Mapbox. Aucun build Catalyst de Vela n'a été fait ici.

## Licences

- Mapbox Maps SDK for iOS v11 est sous les Mapbox Terms of Service
  (<https://www.mapbox.com/legal/tos>). Ce n'est pas une licence open source.
- Vela est sous GPLv3. Son README dit que l'app n'utilise ni compte ni clé.
- Le style Standard demande un jeton d'accès, donc un compte Mapbox.
- Les conditions Mapbox exigent le logo Mapbox et l'attribution visibles sur la carte.

## Reste pour l'étape 2

- Avant tout : poser le secret `MAPBOX_ACCESS_TOKEN` et relancer `MapboxSpikeUITests` pour avoir
  les captures Mapbox, ses fps, `style_ms` et `mapbox_terrain=1`. Le rendu Mapbox n'a encore
  jamais été vu.
- Remplacer l'intérieur de `WebMapView`, `WebMapStyle`, `WebMapGeometry` et `WebMapExpressions` par
  Mapbox v11, en gardant l'API `MLN*` utilisée par `Map/Layers/`, les itinéraires, les transports
  et le registre des taps.
- Passer le JSON d'expressions déjà produit pour GL JS au style-spec de Mapbox.
- Hors ligne : PMTiles et fonds téléchargés vers TileStore/OfflineManager, ou sources vectorielles
  personnalisées ; `vela-file://`, `vela-pmtiles://` et `vela-nets://` deviennent des sources
  natives.
- Terrain : garder Mapterhorn (terrarium) ou passer à `mapbox-dem`.
- Le jeton en Release : une carte Mapbox en Release a besoin du jeton dans l'IPA, et
  `ci-ipa.sh` refuse aujourd'hui une IPA qui le porte.
- Réglage de télémétrie visible dans les réglages de Vela, et mention dans les notices.
- Mesure sur un vrai iPhone (fps, mémoire, batterie, chaleur).
