# Options d'itinéraire iOS

Ce document couvre la planification de R-1. Le guidage et les arrêts pendant la conduite restent dans
le lot de navigation.

## Origine et inversion

La ligne « from » du choix d'itinéraire ouvre un sélecteur indépendant de la recherche principale.
L'origine peut être la position actuelle, une épingle au milieu de la carte, un résultat de recherche
ou un lieu enregistré. Les lieux enregistrés comprennent les favoris, les entrées de listes et le
stationnement. La recherche du sélecteur ne remplace ni la requête ni les résultats affichés sur la
carte.

L'inversion échange les deux extrémités et inverse aussi l'ordre des arrêts. L'ordre affiché reste
donc l'ordre du trajet. Après une inversion, le sélecteur modifie bien l'origine visible : le store
représente d'abord le même trajet dans le sens direct, puis change cette origine. Les `Route` restent
des objets Kotlin et la sélection continue d'utiliser leur identité, jamais une copie reconstruite par
Swift.

## Arrêts intermédiaires

Le choix d'itinéraire permet d'ajouter jusqu'à dix arrêts, de les déplacer avec les flèches et de les
supprimer. Chaque modification relance le calcul avec la liste complète, dans l'ordre affiché. Les
points sont transmis à `MapDataSource.directions`, puis à `DirectionsPb.withWaypoints` et au routeur
ouvert. Le tracé sélectionné passe par ces arrêts et la carte marque les extrémités et les arrêts.

`DirectionsPb` et `GoogleMapsDataSource.directions` prenaient déjà en charge ce paramètre. R-1 ne
change donc pas le protobuf commun. Les tests `DirectionsPbWaypointsTest` vérifient l'ordre des
groupes et la conservation des trois évitements dans la requête.

Transitous ne prend pas d'arrêts intermédiaires dans `plan`. En mode transport, le calcul reste entre
les deux extrémités et l'interface le dit. Les arrêts sont conservés pour un retour à la voiture, à la
marche ou au vélo. Leur ajout est désactivé en mode transport.

## Heures de départ et d'arrivée

Les trois choix sont « Leave now », « Depart at » et « Arrive by ». La date reste locale à l'éditeur
jusqu'à « Apply time », afin qu'un déplacement dans le sélecteur de date n'envoie pas une requête à
chaque valeur intermédiaire. Le bouton « +15 min » facilite aussi le scénario automatique.

En voiture, le point de terminaison anonyme de Google n'a aucun champ de départ exploitable. Changer
l'heure ne relance donc pas la requête. « Leave now » affiche une arrivée fondée sur le trafic réel
uniquement si la route contient `durationInTrafficSeconds`. Pour un départ ou une arrivée future,
l'interface utilise `typicalRangeSeconds` quand Google l'a fourni, sinon la durée estimée de la route.
Elle indique explicitement « Typical traffic range, not a live departure forecast » ou « Estimate
only, no live departure forecast ». Aucun temps réel futur n'est inventé.

En transport, iOS utilise uniquement Transitous et ne prétend pas interroger la page Google Transit.
Le store transmet `timeMode` et `timeEpochSec` à `Transitous.plan` : mode 0 sans `time`, mode 1 avec
`time`, mode 2 avec `time` et `arriveBy=true`. La carte indique que les heures sont planifiées et que
les retards affichés sont réels. Le choix horaire appartient au trajet courant ; il est remis à « Leave
now » à l'ouverture d'un autre itinéraire. Les modes et évitements gardent leurs clés persistantes
`vela_settings`.

## Vérifications

Sous Linux :

```
source ~/opt/env.sh
flock /tmp/opencode/gradle.lock ./gradlew --no-daemon -Pvela.iosOnly=true \
  :core-common:jvmTest :ios-shared:jvmTest :ios-shared:compileKotlinIosSimulatorArm64
```

`RouteStoreTest` couvre les origines après inversion, l'ajout, la réorganisation et la suppression
des arrêts, leur ordre dans chaque requête, la persistance du mode et des trois évitements, ainsi que
les paramètres de départ et d'arrivée. `DirectionsPbWaypointsTest` vérifie la construction protobuf.
`TransitousPlanTest` conserve la preuve de l'URL `time` et `arriveBy`.

Le scénario `DirectionsUITests.testWaypointAndDepartureTime` cherche une destination, ajoute
« Embarcadero Station », exige une route avec `stops=1`, applique un départ futur et vérifie que
l'arrêt est conservé. Il produit `route-waypoint.png` et `route-depart.png`, ainsi que les lignes
`UITEST route_waypoints=`, `route_waypoint_routes=`, `route_time_mode=` et `route_time_epoch=`.
Les scénarios Directions existants continuent de couvrir les alternatives, les étapes hybrides,
la marche et Transitous.

## Preuves Mac

- `r1-route-options-20261026-142911-13338` : les deux scénarios Directions, les 116 tests JVM,
  les 95 tests Kotlin simulateur et les 50 tests Swift sont verts dans la suite complète. Le statut
  global reste `failed` pour deux scénarios hors R-1 : l'index Spotlight reste vide dans
  `IntentsUITests.testSpotlightFixtureAddsAndDeletesThroughRealIndex`, puis
  `SavedUITests.testSavedPlaceListAndRecentsPersist` perd ses récents au relancement.
- `r1-route-options-20261026-152537-13672` : les deux scénarios Directions sont de nouveau verts,
  mais `NavStoreTest.trafficOfferIsMirroredAndAcceptanceAdoptsTheCandidate` échoue une fois sur
  simulateur Kotlin. Ce test hors R-1 repasse au run suivant sans changement de source.
- `r1-route-options-20261026-155652-14395` : run ciblé `DirectionsUITests` entièrement vert, avec
  Gradle, 116 tests JVM, 95 tests Kotlin simulateur, 50 tests Swift et les deux scénarios. Le test
  R-1 rapporte `route_waypoints=1`, `route_waypoint_routes=1`, `route_time_mode=1` et une heure
  future. Les deux captures ont été relues : le tracé et le point orange de l'arrêt sont visibles,
  puis la plage typique et l'avertissement qui la distingue du réel. L'IPA est
  `results:r1-route-options-20261026-155652-14395/Vela-unsigned.ipa`, 9 978 577 octets.

Sur iPhone, il reste à vérifier le sélecteur avec de grands textes, le réordonnancement de plusieurs
arrêts sur le tracé, une origine enregistrée, les fuseaux et changements de date, ainsi que des
horaires de transport avec et sans retard réel.
