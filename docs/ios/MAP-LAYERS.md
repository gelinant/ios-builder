# Couches de carte iOS (lots I-1b et I-1c)

État au 2026-10-27 sur la branche `ios/i1c-google-layers`. Ce document dit ce que le panneau de
couches iOS dessine, d'où vient chaque donnée, quand elle est demandée, et ce qui reste
volontairement absent.

## Panneau

Le bouton `layers-button` (icône d'empilement, à droite de la carte) ouvre `LayersView`. Chaque
interrupteur est indépendant, persistant dans `vela_settings`, et n'entraîne aucune requête avant
d'être activé. Une ligne d'état dit `chargement`, `N affichés`, `zoomez`, `échec, déplacez la
carte` ou `indisponible dans ce pays`.

La ligne de debug `layers-debug` (Debug seulement) reprend les mêmes états pour les scénarios :

```
layers painted=ready:120 speed=ready:3 alpr=ready:2 controls=ready:18 fuel=off:0 bridges=off:0 poi=food,fuel,transit,parking,other density=normal icon=1.00 traffic=off satellite=off raster=none tiles=0 zoom=17.0
```

`tiles` compte les requêtes vues par le crochet HTTP de MapLibre vers Google ou Esri, jamais les
tuiles OpenFreeMap, les glyphes ou les sprites. `raster` nomme les couches réellement présentes
dans le style. Les deux champs sont calculés avant que la carte applique un interrupteur, donc ils
peuvent retarder d'un rendu ; rouvrir la feuille les rafraîchit. Les captures du scénario restent
la preuve visuelle.

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

## Trafic et satellite Google

Les deux raster sont proposés dans la feuille. Leurs modèles d'URL vivent dans `:core-common`
(`app.vela.core.data.tiles.RasterTiles`) et Android les lit au même endroit ; aucune copie Swift
n'existe. Les octets sont ceux d'Android, vérifiés par `RasterTilesTest`.

| Couche | Modèle | Ordre | Limites |
|---|---|---|---|
| Trafic | `https://www.google.com/maps/vt/pb=...!1i{z}!2i{x}!3i{y}...!2straffic...` | au-dessus du bâti et du satellite, sous les libellés | zoom source 16, opacité 0,6, fondu 900 ms |
| Satellite | `https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}` | au-dessus de la géométrie vectorielle, sous les libellés | zoom source 19, luminosité 0,80, saturation -0,1 |
| Satellite profond | `https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}` | au-dessus du satellite de base | zoom 18,6 à 21, opacité 0 à 18,6 puis 1 à 19,6 |

Le trafic est l'overlay de congestion de Google, sans clé. Sa langue et sa région sont figées dans
l'URL (`3m8!2sen!3sus`), comme sur Android ; il n'y a pas de paramètre d'échelle. Le satellite de
base est Esri World Imagery, le service ouvert qu'Android utilise ; le raster Google ne sert qu'au
delà de z19, avec un fondu d'un niveau pour masquer le changement de campagne de prise de vue.

Le satellite est un raster posé sur la carte vectorielle, pas un changement de style : si une
tuile échoue ou n'arrive pas, Liberty reste visible dessous. C'est le repli, sans écran blanc et
sans rechargement. Des routes fantômes blanches à 55 % reprennent les lignes `transportation` du
fond, comme le mode hybride de Google, pour que le réseau routier reste lisible sur la photo.

### En-têtes des tuiles

MapLibre iOS charge ses tuiles avec son propre `NSURLSession`, pas avec le client Vela, donc les
en-têtes de calibration ne l'atteignent pas tout seuls. `MLNNetworkConfiguration` expose un
délégué `willSendRequest:` ; `MapTileNetwork` y ajoute l'identité Safari (User-Agent, Accept,
Accept-Language, Sec-Fetch-*, Referer `https://www.google.com/maps`) uniquement pour les hôtes
`*.google.com`. Les requêtes OpenFreeMap, glyphes et sprites ne sont pas touchées. Android
n'ajoute aucun en-tête à ses propres requêtes MapLibre : cette identité est donc un plus iOS, pas
une condition de parité. Si le délégué disparaît d'une version de MapLibre, les tuiles partent
avec l'URL seule, comme sur Android.

### Hors ligne

`MapRasterLayers.Plan.make` renvoie un plan vide dès qu'une région téléchargée possède le style.
Aucune source raster n'est ajoutée, aucun nom d'hôte Google ou Esri n'entre dans le style hors
ligne généré, et un basculement vers une région pendant que les deux interrupteurs sont actifs
retire les couches au chargement du style local. `OfflineTests` vérifie le compte distant à zéro
avec les deux interrupteurs actifs.

## Réglages de la feuille

Les clés Android sont conservées quand elles existent :

| Réglage | Clé | Défaut |
|---|---|---|
| Trafic | `traffic_on` | non |
| Satellite | `satellite_on` | non |
| Taille des icônes de lieux | `map_poi_icon_scale` (`MapPoiPrefs.KEY_SCALE`) | 1,0 |
| Densité des lieux | `map_poi_density` | `normal` |

La feuille propose trois tailles, comme Android : 0,7 petit, 1,0 normal, 1,25 grand. La valeur est
bornée entre 0,5 et 2,0. Android n'a pas de clé `poi_icons` ; `map_poi_icon_scale` est la sienne.

Les quatre couches Liberty de lieux (`poi_r1`, `poi_r7`, `poi_r20`, `poi_transit`) ont des
`icon-size` et `text-size` constants dans le style : 0,5 et 12, sauf `poi_transit` à 0,7. iOS
multiplie ces constantes par le réglage, comme Android applique `poiIconScale` aux icônes et
`poiLabelScale` aux libellés. Une version de Liberty qui changerait ces constantes rendrait le
facteur relatif à l'ancienne valeur ; ces quatre couches n'existent que sur Liberty. Les libellés
de rues et de lieux du fond ne sont pas concernés.

## Tests

- JVM : `app.vela.ios.map.LayersStoreTest` couvre la persistance, l'absence de requête avant
  activation, le zoom minimal, la réutilisation de la boîte, le réessai après échec, le
  regroupement des contrôles, les catégories de POI, l'indisponibilité hors UK/Pays-Bas et les clés
  `traffic_on`, `satellite_on`, `map_poi_icon_scale`.
- JVM : `app.vela.core.data.tiles.RasterTilesTest` fige les trois modèles, l'ordre z/x/y du trafic
  et z/y/x d'Esri, l'ordre x/y/z de Google et les zooms maximaux.
- Swift : `MapLayersTests` vérifie que les deux raster ne rejoignent jamais la liste des sources
  locales, que le plan est vide hors ligne, les limites Android et l'identité Safari des tuiles
  Google. `OfflineTests.testOfflineStyleStaysRemoteFreeWithTrafficAndSatelliteOn` ouvre les deux
  interrupteurs et vérifie que le style hors ligne garde `remote=0` et ne nomme aucun hôte raster.
- Simulateur : `MapLayersUITests.testLayerSheetLoadsOverlaysAtCloseZoom` ouvre la feuille sur San
  Francisco au zoom 17 avec `-VelaMapLayersFixture YES`, active les quatre couches à données
  déterministes et capture `layers.png` puis `camera-layer.png`.
  `MapLayersUITests.testGoogleTrafficAndSatelliteOverSanFrancisco` active le trafic seul, attend
  20 s que les tuiles arrivent, capture `traffic-layer.png`, puis passe au satellite seul et
  capture `satellite-layer.png`. Les réponses de fixture dérivent de la boîte demandée, comme
  `NavAlertTestSupport`, et n'existent qu'en Debug.
- Le compte `layers_*` est écrit dans le résumé du run. Le run `i1c-google-layers-20261027-132334-4563`
  fait passer les deux scénarios MapLayers (60,9 s et 16,7 s) et produit les deux captures ; le
  trafic vert, ambre et rouge est visible sur la carte vectorielle, le satellite sur les photos
  avec les routes fantômes et les libellés au-dessus.

## Limites assumées

- Pas de données DeFlock ni de road-features embarquées : les caméras et contrôles viennent
  d'Overpass et sont donc soumis à la couverture et à la disponibilité des miroirs.
- Les flèches de voie peintes ne sont pas rendues ; les autres marques le sont.
- Les prix UK et les ponts NL sont inutiles hors de leur pays et le panneau le dit.
- Les deux raster Google sont des services non contractuels, sans clé : une panne ou un
  changement de réponse laisse la carte vectorielle, sans repli hors ligne.
- Aucune validation iPhone n'a encore été faite pour ces couches, y compris les deux raster.
