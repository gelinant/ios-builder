# Couches et styles de carte iOS (lots I-1b et MAP-STYLE)

État au 2026-10-27 sur la branche `ios/map-style`. Ce document dit ce que le panneau de couches iOS
dessine et quel style la carte charge, d'où vient chaque donnée, quand elle est demandée, et ce qui
reste volontairement absent.

## Styles

La carte ne demande plus de document de style à OpenFreeMap. `scripts/ios/gen-map-styles.py`
construit six fichiers locaux depuis `liberty-roboto.json` : `style-vela-light.json`,
`style-vela-dark.json`, `style-bright.json`, `style-positron.json`, `style-fiord.json` et
`style-black.json`. La feuille propose les cinq aspects Android (Vela, Bright, Positron, Fiord,
Black) ; le Vela suit le système ou se fixe clair ou sombre. Les palettes reprennent celles de
`LayersPanel.kt` et `VelaMapView.applyLight/applyDark`.

La génération ne touche ni l'ordre des couches, ni leurs filtres, ni leur zoom minimal : elle
repeint les fonds, l'eau, la végétation, les bâtiments et les routes, remplace les polices Roboto par
les Noto Sans que sert le serveur de glyphes et pointe les icônes de lieux vers les images du sprite
OpenFreeMap (`restaurant`, `hospital`, etc., à la place des `vela-poi-*` créés par Android à
l'exécution). Les tuiles vectorielles, le sprite et les glyphes restent distants pour la carte en
ligne ; le document de style, lui, est local.

`MapStyleBuilder` applique ensuite les choix de la feuille au document chargé : mode de noms et
seuil des numéros. Un changement recharge le style par le même chemin que le hors-ligne. La clé de
cache inclut l'aspect, le mode, le seuil, la langue et la date du fichier généré.

## Numéros et écussons

Liberty ne dessine ni les numéros de maisons ni les numéros de sortie. Le générateur ajoute deux
couches, uniquement sur les champs que la source vectorielle porte réellement :

| Couche | `source-layer` | Champ | Zoom |
|---|---|---|---|
| `vela-housenumber` | `housenumber` | `housenumber` | 17,3 à 18,3 selon le réglage, fondu sur 0,6 |
| `vela-exit-shield` | `transportation_name` | `subclass = junction`, `ref`, `ref_length <= 4` | 12,5 |

Les numéros de maisons ne participent pas à l'index de collision (`text-ignore-placement`) : ils ne
peuvent pas évincer une icône de lieu. Les sorties sont des pastilles vertes dessinées au chargement
par `MapStyleImages`, comme `RoadShields` sur Android ; sans image, le numéro reste lisible en texte.
Les écussons de route existaient déjà dans le style Liberty (`us-interstate_N`, `us-highway_N`,
`us-state_N`, `road_N`) et sont conservés : aucune route sans `ref` n'est inventée.

Les bâtiments plats passent de z13-z14 à z16-z24 et l'extrusion commence à z17, comme Android. La
complétion des bâtiments absents demanderait un jeu OpenAddresses ou équivalent : elle n'est pas
livrée par ce lot.

## Noms sur la carte

Les quatre valeurs Android sont reprises avec les mêmes seuils et la même précédence :

- `english_latin` (défaut) : `name:en`, puis `name:latin`, puis `name`, avec la langue de l'app
  essayée d'abord ;
- `english_local` : `name:en`, sinon le nom local ;
- `local` : le nom local seul ;
- `local_english` : le nom local, puis l'anglais sur une seconde ligne pour un lieu et sur la même
  ligne pour une rue, qui ne peut pas se couper.

Une interface dont l'écriture n'est pas latine garde le nom local quel que soit le mode, comme
Android. Le raccourcissement des noms de rue de `VelaCoreCheck` n'est pas modifié.

## Panneau

Le bouton `layers-button` (icône d'empilement, à droite de la carte) ouvre `LayersView`. Chaque
interrupteur est indépendant, persistant dans `vela_settings`, et n'entraîne aucune requête avant
d'être activé. Une ligne d'état dit `chargement`, `N affichés`, `zoomez`, `échec, déplacez la
carte` ou `indisponible dans ce pays`.

La ligne de debug `layers-debug` (Debug seulement) reprend les mêmes états pour les scénarios :

```
layers painted=ready:120 speed=ready:3 alpr=ready:2 controls=ready:18 fuel=off:0 bridges=off:0 poi=food,fuel,transit,parking,other density=normal zoom=17.0 look=vela appearance=system names=english_latin house=normal
```

## Couches dessinées

| Couche | Source commune | Zoom minimal | Remarque |
|---|---|---|---|
| Marques de chaussée | `PaintedRoads.fetch` puis `build` | 16,0 | lignes centrales, voies, pistes cyclables, passages piétons et lignes d'arrêt ; les flèches de voie ne sont pas dessinées (pas de jeu d'images iOS) |
| Radars fixes | `OverpassSpeedCameras.fetchInBox` | 11,0 (dessin 13,5) | points rouges ; OSM seulement, pas de DeFlock embarqué |
| Caméras ALPR | `OverpassAlprCameras.fetchInBox` | 11,0 (dessin 13,5) | points violets ; DeFlock dans OSM, pas de fichier embarqué |
| Feux, stops, passages à niveau, ralentisseurs | `OverpassTrafficSignals.fetchControlsInBox` | 16,0 | un glyphe par carrefour après regroupement à 30 m, plafond 400 |
| Prix carburant UK | `FuelGbStore` et `FuelGb` | aucune | seulement si le milieu de la vue est au Royaume-Uni ; fichier Fuel Finder mis en cache par le store |
| Ouvertures de ponts NL | `NdwBridgeOpenings.fetch` | aucune | seulement aux Pays-Bas ; ouvert en rouge, prévu en orange, cache 5 min |

Toutes les couches sont coupées par défaut sur iOS. Android active les caméras ALPR par défaut ;
iOS préfère ne pas lancer une requête Overpass à chaque ouverture tant que l'utilisateur n'a pas
demandé la couche. La clé Android `flock_cameras_on` est conservée, donc un choix explicite reste
compatible.

### Demandes et cache

- Le viewport vient de `MapController.regionDidChange`, jamais d'une boucle d'affichage.
- Une couche active demande une boîte élargie de 50 % sur chaque côté. Tant que le milieu reste
  dans la moitié intérieure de la boîte couverte, aucun nouvel appel n'est fait.
- Un échec n'est jamais mis en cache comme « rien ici » : l'état passe à `error` et le prochain
  viewport réessaie.
- Une seule requête par couche à la fois ; une génération annule la réponse précédente.
- Les radars et caméras sont regroupés à 20 m, les contrôles à 30 m par type ; les plafonds sont
  600 caméras et 400 contrôles, les plus proches du milieu d'abord.
- Sous le zoom minimal, la couche est masquée et aucune requête n'est lancée.

## Lieux sur la carte

La feuille contrôle les couches Liberty `poi_r1`, `poi_r7`, `poi_r20` et `poi_transit` :

- `Show places` masque ou réaffiche les quatre couches ;
- les catégories `food`, `fuel`, `transit`, `parking` et `other` filtrent la propriété OSM `class`
  avec un prédicat combiné au filtre d'origine du style ;
- `Compact` relève d'un niveau le zoom d'apparition des groupes de priorité basse (`poi_r1` à
  partir de 16, `poi_r7` à partir de 18, `poi_r20` à partir de 19) ;
- la collision des libellés reste celle de MapLibre, donc aucun travail par image.

Les arrêts GTFS Transitous dessinés par T-1 ne sont pas concernés : cette couche garde son propre
interrupteur.

## Trafic et satellite Google : absents, et pourquoi

Les deux raster Google ne sont pas proposés. Leurs URL de tuiles sont des constantes du module
Android `:app` (`TRAFFIC_TILES` et `SAT_TILES` dans `ui/map/VelaMapView.kt`). Aucun code commun
`core-common` ou `ios-shared` ne les expose, et les recopier dans Swift aurait créé une deuxième
source de vérité non testée pour un service non contractuel. La feuille affiche donc deux lignes
`Not in this build` avec la raison, au lieu d'un interrupteur qui ne dessinerait rien. Les tronçons
de trafic d'un itinéraire restent dessinés par `RouteLayers` avec les données de Google Directions.

Les lignes de transport colorées et le terrain restent hors de ce lot.

## Hors ligne

Chaque couche ajoute seulement un `MLNShapeSource` en mémoire. Aucune source distante, aucun
glyphe ni sprite supplémentaire n'entre dans le style. `OfflineStyleFactory` part du style généré
de l'aspect choisi, applique le mode de noms et le seuil des numéros, puis remplace la source
distante par l'archive PMTiles et le sprite par les fichiers embarqués. Son compte `remote` reste
zéro pour les six aspects ; `OfflineTests` et `MapStyleTests` le vérifient. Une couche activée sans
réseau passe à `error` et n'invente aucun point ; la carte téléchargée reste affichée.

## Tests

- Script : `python3 scripts/ios/test_gen_map_styles.py` vérifie les six styles, l'absence d'URL de
  document de style, la présence des couches `housenumber` et `transportation_name`, les polices
  Noto, les bâtiments à z16 et les identifiants de POI que filtre I-1b.
- JVM : `app.vela.ios.map.LayersStoreTest` couvre la persistance, l'absence de requête avant
  activation, le zoom minimal, la réutilisation de la boîte, le réessai après échec, le
  regroupement des contrôles, les catégories de POI et l'indisponibilité hors UK/Pays-Bas.
- Simulateur : `MapStyleTests` couvre les six styles générés, les modes de noms, les trois seuils de
  numéros et le hors-ligne sans URL distante. `OfflineTests` garde le contrôle historique à zéro URL.
- Simulateur : `MapLayersUITests.testStyleVariantsRender` capture `style-vela-light.png`,
  `style-vela-dark.png`, `style-bright.png`, `style-positron.png`, `style-fiord.png` et
  `style-black.png`, puis vérifie la ligne de debug de la feuille. `testNamesModesHouseNumbersAndExits`
  capture `names-english.png`, `names-local.png`, `names-local-english.png`, `map-house-numbers.png`
  et `map-exit-numbers.png` (Chinatown, un pâté de maisons à z18 et l'échangeur I-80 à z15).
- Simulateur : `MapLayersUITests.testLayerSheetLoadsOverlaysAtCloseZoom` ouvre la feuille sur San
  Francisco au zoom 17 avec `-VelaMapLayersFixture YES`, active les quatre couches à données
  déterministes et capture `layers.png` puis `camera-layer.png`.
- Le compte `layers_*` est écrit dans le résumé du run.

## Limites assumées

- Pas de données DeFlock ni de road-features embarquées : les caméras et contrôles viennent
  d'Overpass et sont donc soumis à la couverture et à la disponibilité des miroirs.
- Les flèches de voie peintes ne sont pas rendues ; les autres marques le sont.
- Les prix UK et les ponts NL sont inutiles hors de leur pays et le panneau le dit.
- Aucune validation iPhone n'a encore été faite pour ces couches.
