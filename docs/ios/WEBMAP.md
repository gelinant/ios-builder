# La carte principale en MapLibre GL JS

La carte principale de l'app iOS est rendue par MapLibre GL JS 5.24.0 dans une `WKWebView`, avec
le relief 3D (terrain déformé), un ciel et le globe. MapLibre Native n'est plus lié : il ne sait
pas déformer le terrain. Le reste de l'écran (recherche, boutons, fiches, navigation) est inchangé
et reste en SwiftUI au-dessus de la carte.

## Fichiers

| Fichier | Rôle |
|---|---|
| `iosApp/Vela/Map/Web/WebMapView.swift` | `MLNMapView` : la vue, la `WKWebView`, la caméra, la projection, les annotations, la position, le pont JS |
| `iosApp/Vela/Map/Web/WebMapStyle.swift` | `MLNStyle`, les sources, les couches et leurs propriétés, l'encodage des images |
| `iosApp/Vela/Map/Web/WebMapGeometry.swift` | formes, features, annotations, conversion GeoJSON |
| `iosApp/Vela/Map/Web/WebMapExpressions.swift` | `NSExpression` et `NSPredicate` vers le JSON du style-spec |
| `iosApp/Vela/Map/Web/WebMapResources.swift` | fichiers locaux, tuiles PMTiles et hôtes sans CORS, servis par Swift |
| `iosApp/Vela/Resources/webmap/webmap.html`, `webmap.js` | la page : carte GL JS, terrain, ciel, marqueurs, point de position |

Le moteur (`maplibre-gl.js`, `maplibre-gl.css`) est celui de `Resources/terrain/`, épinglé dans
`VERSION`. La page est assemblée en une chaîne et chargée avec l'origine
`https://tiles.openfreemap.org/`, comme l'écran Relief.

Les classes Swift gardent les noms et le sous-ensemble de l'API MapLibre Native que l'app
utilisait (`MLNMapView`, `MLNStyle`, `MLNShapeSource`, `MLNLineStyleLayer`...). Les couches de
`Map/Layers/`, les itinéraires, les transports et le registre des taps n'ont pas changé de logique.

## Qui possède quoi

- Swift possède le modèle : la caméra, le document de style, chaque source, couche et image, et
  les annotations. Chaque mutation part vers la page comme une commande, regroupées par passage
  de boucle (`vela.run([...])`).
- La page possède le rendu et les gestes. Elle renvoie la caméra (`move`, `moveend`), le début
  d'un geste, et les features sous un doigt dès qu'il se pose.
- Un nouveau processus web (plantage du contenu) reçoit tout l'état d'un coup : carte, document,
  images, marqueurs, formes, point de position.

## Caméra et projection

- Chaque commande de caméra porte un numéro de séquence. Un rapport de la page avec un numéro plus
  ancien est ignoré, donc une animation interrompue ne réécrit pas la caméra demandée.
- `convert`, `visibleCoordinateBounds`, `metersPerPoint` et `cameraThatFitsCoordinateBounds` sont
  calculés en Swift avec la caméra Mercator de GL JS : monde de 512 points à z0, champ vertical de
  36,87 degrés, point principal au centre de la zone hors `contentInset`. Sur Chamonix (z13,
  inclinaison 55, cap 342), le point Swift et `map.project` de GL JS diffèrent de moins de
  1 point avec le terrain, de 0 sans.
- Le cadrage d'un rectangle est résolu sur la vraie projection (dix itérations au plus), donc une
  caméra inclinée cadre aussi.
- En globe, les calculs Swift restent en Mercator : à faible zoom, un tap ou un cadrage est
  approximatif.
- `contentInset` devient le `padding` de GL JS. Une animation dure 0,3 s, comme dans MapLibre
  Native.

## Taps et features

UIKit décide du sens d'un tap, de façon synchrone. Pour que `visibleFeatures` réponde tout de suite :

- au `touchstart` d'un seul doigt, la page interroge les features au point et dans des boîtes de
  10 et 22 points autour, et les envoie avec la coordonnée sous le doigt (terrain compris) ;
- un tap simple attend l'échec d'un double tap (`doubleTapGate`), comme avec les recognizers de
  MapLibre Native ; la réponse de la page est donc arrivée quand le handler interroge ;
- `visibleFeatures(in:)` lit la boîte stockée la plus proche de la taille demandée. Une feature
  ponctuelle d'une boîte plus grande doit tomber dans le rectangle demandé ;
- le rotor VoiceOver « Select feature at map center » demande d'abord les features à la page
  (`queryFeatures(at:)`), puis appelle le même handler.

## Annotations et position

- Une annotation ponctuelle est un marqueur HTML de GL JS, qui suit le terrain. Sa vue
  `MLNAnnotationView` est dessinée en bitmap ; un changement de cadre, de décalage ou de contenu la
  redessine. Sans vue, l'épingle rouge par défaut est dessinée par Swift.
- Les vues d'annotation ne sont plus des vues UIKit dans la hiérarchie : XCUITest ne les voit pas.
- Une polyligne ou un polygone en annotation passe dans une source GeoJSON de la page, avec les
  couleurs et largeurs du délégué.
- La bulle d'une annotation est un popup GL JS (titre, sous-titre).
- La position vient d'un `CLLocationManager` propre à la vue, comme dans MapLibre Native, et est
  dessinée par la page (point, halo de précision, cône de cap). Le suivi s'arrête sur un
  glissement (et sur une rotation en mode cap).

## Données

| Schéma dans la page | Servi par | Usage |
|---|---|---|
| `https://tiles.openfreemap.org/...` | la page, même origine | style TileJSON, tuiles, glyphes, sprites |
| `vela-file://<chemin>` | `WebMapResources`, lecture de fichier | style hors ligne : glyphes, sprites |
| `vela-pmtiles://<archive>/{z}/{x}/{y}` | `PmtilesReader.Archive` (Kotlin) | région téléchargée, marquages au sol |
| `vela-nets://`, `vela-net://` | URLSession | tuiles d'élévation Mapterhorn, rasters Google et Esri |

`fetch` refuse les schémas d'un `WKURLSchemeHandler`, d'où le passage par `addProtocol` de GL JS
et le base64 ; une tuile PMTiles absente est une tuile vide. Les requêtes Google reçoivent les
en-têtes de navigateur calibrés (`MapTileNetwork.prepare`). Le cache disque des hôtes servis par
URLSession fait 256 Mio (`Caches/VelaWebMapTiles`).

## Relief 3D

- Le terrain est toujours actif sur la carte principale : source `raster-dem` terrarium Mapterhorn
  (`tiles.mapterhorn.com`, WebP 512 px, `Map3D.demURL`), exagération 1,2
  (`Map3D.terrainExaggeration`). Résolution : 30 m partout, 0,5 à 10 m là où un modèle national
  existe (France 5 m, Suisse 2 m, Autriche 1 m). Le zoom le plus profond dépend de la zone (z12 à
  z17, `Map3D.demMaxZoom`) ; au-delà, la tuile répond 404, la page ne le signale pas et GL JS
  dessine la tuile parente.
- La source du terrain déclare 256 px pour des images de 512 px. GL JS double la taille de tuile
  d'une source de terrain ; ainsi il charge le zoom dont les pixels d'élévation correspondent à
  l'écran, et non un zoom en dessous. Le relief ombré déclare 512 px, sa taille réelle.
- Sans réseau, les tuiles d'élévation manquent et la carte reste plate.
- Le ciel et le brouillard suivent la clarté du fond du style.
- L'interrupteur 3D (`buildings_3d`, activé par défaut) ajoute les bâtiments extrudés, le relief
  ombré et l'inclinaison. Au premier chargement, une caméra plate s'incline à 45 degrés
  (`Map3D.defaultTilt`), sauf avec `-VelaMapPitch` ou `-VelaDeterministic`. La fin d'une
  navigation revient aussi à 45 degrés.
- L'inclinaison reste plafonnée à 60 degrés (`Map3D.maximumPitch`).

## Limites connues

- Les filtres hérités d'un style sont convertis en expressions dans la page, pour pouvoir les
  combiner avec ceux de Swift.
- La mémoire, les fps et la batterie d'une `WKWebView` WebGL en carte principale ne sont pas
  mesurés sur iPhone.
