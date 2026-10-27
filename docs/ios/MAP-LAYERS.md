# Couches de carte iOS (lot I-1b)

État au 2026-10-26 sur la branche `ios/i1b-map-layers`. Ce document dit ce que le panneau de
couches iOS dessine, d'où vient chaque donnée, quand elle est demandée, et ce qui reste
volontairement absent.

## Panneau

Le bouton `layers-button` (icône d'empilement, à droite de la carte) ouvre `LayersView`. Chaque
interrupteur est indépendant, persistant dans `vela_settings`, et n'entraîne aucune requête avant
d'être activé. Une ligne d'état dit `chargement`, `N affichés`, `zoomez`, `échec, déplacez la
carte` ou `indisponible dans ce pays`.

La ligne de debug `layers-debug` (Debug seulement) reprend les mêmes états pour les scénarios :

```
layers painted=ready:120 speed=ready:3 alpr=ready:2 controls=ready:18 fuel=off:0 bridges=off:0 poi=food,fuel,transit,parking,other density=normal zoom=17.0
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

Les styles de carte alternatifs, les lignes de transport colorées et le terrain restent également
hors de ce lot.

## Hors ligne

Chaque couche ajoute seulement un `MLNShapeSource` en mémoire. Aucune source distante, aucun
glyphe ni sprite supplémentaire n'entre dans le style. Le fichier de style hors ligne de
`OfflineStyleFactory` n'est pas modifié, donc son compte `remote` reste zéro ; le test Swift
`OfflineTests.testOfflineStyleHasOnlyLocalResources` continue de le vérifier. Une couche activée
sans réseau passe à `error` et n'invente aucun point ; la carte téléchargée reste affichée.

## Tests

- JVM : `app.vela.ios.map.LayersStoreTest` couvre la persistance, l'absence de requête avant
  activation, le zoom minimal, la réutilisation de la boîte, le réessai après échec, le
  regroupement des contrôles, les catégories de POI et l'indisponibilité hors UK/Pays-Bas.
- Simulateur : `MapLayersUITests.testLayerSheetLoadsOverlaysAtCloseZoom` ouvre la feuille sur San
  Francisco au zoom 17 avec `-VelaMapLayersFixture YES`, active les quatre couches à données
  déterministes et capture `layers.png` puis `camera-layer.png`. Les réponses de fixture dérivent
  de la boîte demandée, comme `NavAlertTestSupport`, et n'existent qu'en Debug.
- Le compte `layers_*` est écrit dans le résumé du run.

## Limites assumées

- Pas de données DeFlock ni de road-features embarquées : les caméras et contrôles viennent
  d'Overpass et sont donc soumis à la couverture et à la disponibilité des miroirs.
- Les flèches de voie peintes ne sont pas rendues ; les autres marques le sont.
- Les prix UK et les ponts NL sont inutiles hors de leur pays et le panneau le dit.
- Aucune validation iPhone n'a encore été faite pour ces couches.
