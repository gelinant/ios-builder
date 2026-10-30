# Options d'itinéraire iOS

Ce document couvre la planification de R-1, le choix d'itinéraire de RTE-PICKER, l'évitement des
caméras de RTE-CAM et le focus d'une étape de RTE-STEP. Le guidage et les arrêts pendant la conduite
restent dans le lot de navigation.

## Présentations du choix

Le choix d'itinéraire iOS reprend les deux présentations d'Android dans la même carte au-dessus de
la carte géographique :

- la présentation compacte montre la destination, l'origine, les modes avec leur durée, la route
  sélectionnée avec son temps, sa distance, sa raison d'être choisie et sa ligne de trafic, puis
  Start et Steps ;
- la présentation étendue ajoute, dans le même ordre, les heures de départ et d'arrivée, les arrêts,
  les évitements, puis toutes les alternatives avec leurs libellés.

La poignée de la feuille est le bouton de bascule, avec `route-expand`, une valeur
`compact` ou `expanded` et une cible de 44 pt. Les deux présentations gardent les modes collés en
haut, les mêmes actions Start et Steps en bas et le même identifiant `route-scroll`. En grands
textes ou en paysage, tout le contenu passe dans un seul `route-scroll`, comme le lot Q-2 l'avait
établi. La présentation n'est pas persistée : chaque ouverture repart en compact.

Les libellés des alternatives suivent Android : « Fastest route now » pour la plus rapide d'au moins
deux propositions, « About the same time » à moins d'une minute, puis « X slower than the fastest
route ». Le libellé est calculé sur la route la plus rapide réelle, pas sur la première ligne. Les
clés persistantes du mode et des trois évitements ne changent pas.

## Trafic à la demande

Un trajet en voiture part du routeur ouvert tant que « Show traffic » n'a pas été touché. La ligne
de trafic de la présentation compacte le dit : « Times without live traffic. ». Le bouton
`route-traffic-show` ouvre une porte par trajet, relance une seule fois le calcul et laisse Google
répondre. Le drapeau `RoutingPrefs.googleTraffic` reste faux tant que la porte est fermée : la
requête Google n'est pas seulement cachée, elle n'est pas envoyée.

La ligne ne prétend jamais à du direct sans réponse de Google :

- `durationInTrafficSeconds` présent : « Live traffic: X slower than usual » ou « Live traffic, no
  delays right now », avec `route-traffic-live` ;
- seulement `typicalRangeSeconds` : « Typical X to Y, not live traffic », avec
  `route-traffic-typical` ;
- aucune des deux réponses : « Times without live traffic. Google returned no live ETA for this
  trip. ».

La ligne n'existe pas en transport, à pied ou à vélo, et pas quand « Utiliser Vela sans Google »
est actif. Dans ce dernier cas le bouton ne peut pas rouvrir Google : `requestTraffic` vérifie
`NoGoogle.enabled` avant toute chose. La préférence Android `route_traffic_on_tap` est lue sous la
même clé ; en son absence, iOS l'active par défaut, faute de ligne de réglages dédiée dans ce lot.
`setTrafficOnTap` persiste déjà la valeur pour le lot de réglages qui l'exposera.

Un nouveau trajet referme la porte : `trafficRequested` repasse à faux, donc une destination
suivante ne réutilise pas le choix de la précédente. À la fermeture du choix et au départ de la
navigation, `RoutingPrefs.googleTraffic` revient à vrai : les revérifications de conduite gardent
leur propre politique (L297), distincte de la porte du choix.

## Évitement des caméras

Le choix d'itinéraire reprend « Avoid surveillance cameras » (L109) et « Try side streets around
cameras » (L203) d'Android. Les deux interrupteurs vivent dans le choix étendu, sous les trois
évitements, et seulement quand le routeur et la source de caméras sont joignables. Le premier
compte les caméras de chaque route ; le second tente les rues latérales et n'existe qu'en voiture.

Le comptage applique la règle d'Android, désormais dans `core-common` :
`CameraDetour.onRoute` garde une caméra à moins de 45 m de la ligne et, quand son cap est connu,
orientée à moins de 50 degrés de l'axe de la route à cet endroit. Une caméra qui regarde la route
transversale ne compte pas. iOS l'appelle directement ; Android garde son `FlockCameras.along`,
qui applique le même seuil et la même règle d'orientation sur son jeu embarqué. Sur iOS les
caméras viennent d'Overpass (DeFlock dans OpenStreetMap), avec un corridor de 250 m autour de la
route ; les deux plateformes arrivent donc au même compte pour les mêmes caméras.

Le choix est honnête par construction :

- `CameraDetour.choose` ne fait passer une route devant que si elle passe strictement moins de
  caméras et coûte au plus `CameraDetour.cap` : un quart de la route la plus rapide, plafonné à
  dix minutes ;
- `CameraDetour.sameRoute` rejette une réponse du routeur qui suit la même ligne (50 m d'écart de
  longueur, 20 m à cinq points). Le choix peut donc appeler un détour sans jamais l'afficher ;
- le choix étendu affiche les caméras de chaque ligne et la ligne compacte celle de la route
  sélectionnée ; la ligne verte n'apparaît que si la route active passe réellement moins de
  caméras que celle qui la précédait, avec le temps et la distance ajoutés mesurés sur la route la
  plus rapide. Quand le routeur ne trouve pas mieux, aucun évitement n'est annoncé.

Les préférences sont persistées sous les clés Android `flock_route_alert_on` et `flock_detour`,
fausses par défaut. `RouteStore.start` les lit avant la première demande d'itinéraire de la
session : un utilisateur qui avait laissé l'évitement actif le retrouve dès la première ouverture.
La porte du trafic reste indépendante.

Sans Google, les caméras restent disponibles : Overpass est un service ouvert et le routeur ouvert
suffit. Le comptage et le détour ne demandent donc jamais Google. Hors ligne, iOS n'a pas de
routeur local (D7) : `canAvoidCameras` passe à faux et l'interrupteur disparaît au lieu de
promettre un détour impossible. Un échec de la source de caméras laisse les routes telles quelles
et n'affiche aucun compte.

Les tests JVM `CameraDetourTest` couvrent le comptage directionnel, le plafond, l'ordre du choix
et la reconnaissance de la même route ; `RouteAvoidCamerasTest` couvre la préférence lue au
démarrage, le reclassement dans le plafond, le refus hors plafond, les rues latérales, la même
route renvoyée par le routeur, NoGoogle, le mode hors ligne et la persistance des deux clés.
`DirectionsUITests.testAvoidCameras` produit `route-cameras.png` et lit `camera_avoided`,
`camera_on_active`, `camera_extra_seconds` et `camera_extra_meters`.

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

`TIME-1` remplace `RouteTimeOptions` par le contrôle partagé `TimeChoiceBar`, décrit dans
`docs/ios/TRANSIT.md`. Les identifiants `route-time-NOW`, `route-time-DEPART`, `route-time-ARRIVE`,
`route-time-date`, `route-time-plus` et `route-time-apply` ne changent pas ; la ligne de requête est
publiée sous `route-time-query`, et le résumé de conduite garde `route-time-summary` et
`route-time-note`.

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

`RouteTrafficOnDemandTest` couvre la porte du trafic : premier calcul sans Google, ouverture par
`requestTraffic`, nouveau calcul après le tap, fermeture de la porte au trajet suivant, refus quand
Google est coupé, absence de porte quand la préférence est à faux, et exposition d'une plage typique
sans `hasTraffic`. `DirectionsUITests.testRoutePickerStyleAndTrafficOnDemand` produit
`route-picker-compact.png`, `route-picker-expanded.png` et `route-picker-traffic.png`, et vérifie
`trafficOnTap=1`, `trafficRequested=0` avant le tap puis `1`, la présence des deux actions dans les
deux présentations, et les identifiants de la ligne de trafic.

`CameraDetourTest` (commun, JVM et simulateur iOS) couvre le comptage à 45 m avec l'orientation, le
plafond du détour, l'ordre du reclassement et la même route. `RouteAvoidCamerasTest` (JVM) couvre
la préférence lue avant la première demande, le reclassement dans le plafond, le refus hors
plafond, les rues latérales, la même route renvoyée par le routeur, NoGoogle, hors ligne et la
persistance. `DirectionsUITests.testAvoidCameras` produit `route-cameras.png` avec la ligne de
caméras et le compte évité.

Le scénario `DirectionsUITests.testWaypointAndDepartureTime` cherche une destination, ajoute
« Embarcadero Station », exige une route avec `stops=1`, applique un départ futur et vérifie que
l'arrêt est conservé. Il produit `route-waypoint.png` et `route-depart.png`, ainsi que les lignes
`UITEST route_waypoints=`, `route_waypoint_routes=`, `route_time_mode=` et `route_time_epoch=`.
Les scénarios Directions existants continuent de couvrir les alternatives, les étapes hybrides,
la marche et Transitous.

## Preuves Mac

- `rte-bike-20261028-004741-27076` et `rte-bike-20261028-001302-28228` : Gradle, build simulateur et
  lancement verts, avec `bike-settings.png` qui montre la section vélo, l'interrupteur et les trois
  limites. Le scénario `BikeProfileUITests.testBikePreferencesChangeTheRoute` lit
  `bike_settings_default=1`, `bike_fast_seconds=600` et `bike_fast_profile=0`, puis échoue avant le
  changement de profil : le bouton `route-bike-profile-safe` restait sous les actions fixes, donc
  non cliquable. Le profil est désormais dans le résumé du choix, au-dessus de la zone défilante.
  Ce déplacement n'a pas été rejoué sur le runner, faute de run Mac restant pour ce lot.

- `rte-cam-20261027-212927-24068` : run ciblé `DirectionsUITests` sur le runner GitHub.
  `testAvoidCameras` est vert en 85 s. Gradle est vert (296 tests JVM, 240 tests Kotlin simulateur
  iOS), le build simulateur aussi. Le scénario lit `camera_avoided=2`, `camera_on_active=0`,
  `camera_extra_seconds=38`, `camera_extra_meters=0` et `camera_side_streets=0` : le reclassement
  a suffi, sans rue latérale, et `route-cameras.png` montre la ligne de caméras et le compte
  évité. `testRoutePickerStyleAndTrafficOnDemand`, `testBikeRouteUsesTheSafetyProfile` et
  `testNoGoogleDriveNeverAsksGoogle` restent verts. Le step `tests` échoue toujours pour
  `IncomingLinksTests.testMoreStopsThanTheCapKeepTheFirstOnes`, hors lot. Les deux scénarios
  Directions qui restaient à rejouer échouent sur un glissement de la feuille au lieu de
  `route-scroll` ; ce glissement est corrigé après ce run et n'est donc pas vérifié.
- `rte-cam-20261027-204025-11151` : premier run, rouge. Le compilateur Kotlin/Native refuse une
  virgule dans un nom de test de `StreetViewHistoryTest`, ce qui empêchait la compilation des tests
  simulateur ; la virgule est retirée dans ce lot. `testAvoidCameras` échouait aussi parce que
  l'interrupteur était dans la partie défilante étendue : il est passé dans la présentation
  compacte, au-dessus de la ligne de trafic.

- `rte-picker-compile-20261027-152631` : `ci-compile.sh` vert sur le Mac du LAN (voice framework,
  catalogue de chaînes, XcodeGen, build simulateur) avec un `DerivedData` dédié. Le run UI ciblé
  n'a pas pu être lancé sur ce Mac : il a redémarré sous la charge de la ruche puis a refusé la clé
  SSH. Le lancement de secours a donc utilisé le runner GitHub.
- `rte-picker-20261027-193300-31773` : run ciblé `DirectionsUITests` sur le runner.
  `testRoutePickerStyleAndTrafficOnDemand` est vert en 50 s et produit `route-picker-compact.png`,
  `route-picker-expanded.png` et `route-picker-traffic.png`, avec `picker_traffic_on_tap=1`,
  `picker_traffic_requested_before=0`, `picker_traffic_live=1` et
  `picker_expanded_alternatives=2`. `testBikeRouteUsesTheSafetyProfile` et
  `testNoGoogleDriveNeverAsksGoogle` passent aussi (`nogoogle_google_requests=0`,
  `nogoogle_open_requests=7`). Les deux autres scénarios Directions ont échoué parce qu'ils
  cherchaient les lignes et le bouton d'arrêt dans la présentation compacte ; ils appellent
  maintenant `expandRoute` avant ces actions et restent à rejouer. Le step `tests` échoue pour
  `IncomingLinksTests.testMoreStopsThanTheCapKeepTheFirstOnes`, hors de ce lot.
- `rte-picker-20261027-184548-11335` : premier run ciblé, tous les scénarios Directions rouges
  parce que `MapScreen` cache son bloc de debug quand une feuille est ouverte, donc `route-debug`
  était absent. La feuille du choix porte désormais sa propre ligne `route-debug`, et le run
  suivant lit l'état.

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
- `r1-route-options-20261026-170234-2789` : quatrième et dernier essai de suite complète, annulé
  par le runner après 15 minutes. Aucun `STATUS` ni artefact n'est publié. Il ne donne donc aucun
  verdict sur le merge alors présent, et l'IPA du run ciblé vert reste la référence R-1.

## Limites

- La ligne Réglages « Live traffic only when I tap » n'existe pas encore ; la préférence est lue et
  écrite sous la clé Android, et la porte est active par défaut sur iOS. Le lot de réglages qui
  l'exposera pourra la désactiver et retrouver le trafic Google dès l'ouverture.
- Les deux interrupteurs de caméras n'ont pas non plus de ligne dans les réglages iOS : ils vivent
  dans le choix d'itinéraire, sous les mêmes clés Android. Un lot de réglages pourra les y exposer.
- iOS n'embarque pas encore le jeu DeFlock d'Android : chaque trajet compte les caméras par une
  requête Overpass dans un corridor de 250 m. Un comptage exige donc le réseau ; hors ligne
  l'interrupteur disparaît. La couverture est celle d'OpenStreetMap, plus faible que le jeu embarqué
  dans certaines villes. `OFF-CAM` doit livrer des caméras locales.
- Les rues latérales coûtent jusqu'à six requêtes d'itinéraire et autant de comptages Overpass par
  trajet, plafonnées comme sur Android. Le choix reste réactif parce que le comptage arrive après
  l'affichage des routes, mais un détour peut apparaître une ou deux secondes après l'ouverture.
- La reconnaissance de la même route échantillonne cinq points et tolère 20 m : deux tracés qui
  partagent une longue section mais divergent ailleurs restent distincts, ce qui est voulu. Elle ne
  remplace pas une comparaison exacte de graphe.
- Aucun détour n'est promis quand le routeur ne trouve pas mieux : le choix affiche alors le compte
  des caméras sans ligne d'évitement. C'est le comportement attendu, pas un échec.
- La présentation compacte et la présentation étendue vivent dans la même carte : la hauteur est
  fixée par `MapScreen`, donc la partie étendue défile dans cette hauteur au lieu d'agrandir la
  feuille. Un futur lot de carte pourra donner à la présentation étendue une plus grande détente.
- Le trafic vivant ne vient que de Google. Une réponse typique n'est jamais transformée en direct,
  et une réponse absente affiche une estimation sans trafic.
- Les revérifications de navigation restent hors de ce lot : la porte du choix rend le drapeau à
  vrai au départ, mais leur interrupteur appartient à SET-PRIVACY.

Sur iPhone, il reste à vérifier le sélecteur avec de grands textes, le réordonnancement de plusieurs
arrêts sur le tracé, une origine enregistrée, les fuseaux et changements de date, ainsi que des
horaires de transport avec et sans retard réel. Pour RTE-PICKER, il reste à vérifier le tap
« Show traffic » sur un vrai réseau, une heure typique sans direct, et la bascule compacte vers
étendue avec VoiceOver. Pour RTE-CAM, il reste à vérifier un trajet réel avec des caméras DeFlock
sur un iPhone, la disparition de l'interrupteur en mode avion, et un détour de rue latérale que le
routeur accepte sans reprendre la même route.

## Profil vélo

RTE-BIKE expose la préférence vélo que propose Android, sous la même clé `bike_safe` de
`vela_settings`. La ligne des réglages et l'étape du choix d'itinéraire écrivent toutes deux par
`RouteStore.setBikeSafe`, qui persiste la valeur et la recopie dans `RoutingPrefs.bikeSafe`. Un
utilisateur qui avait choisi le profil le plus rapide le retrouve au lancement suivant.

La préférence est lue par `RouteStore.start` avant la première demande d'itinéraire, comme les
évitements et les caméras. Le profil sûr garde le routeur Valhalla et son `use_roads` à 0,1, le
profil le plus rapide passe par la chaîne vélo ouverte. R-2 reste donc intact : le profil sûr ne
demande jamais Google, et « Utiliser Vela sans Google » continue de couper Google pour tous les
modes.

L'étape « Bike profile » du choix apparaît en mode vélo, dans la présentation étendue. Ses deux
boutons, `route-bike-profile-safe` et `route-bike-profile-fast`, relancent le calcul du trajet
courant sans toucher au mode : `setBikeSafe` ne replanifie que lorsque le mode est déjà `BICYCLE`.
Aucun geste ne peut donc transformer silencieusement une balade en trajet en voiture. Les lignes de
caméras de RTE-CAM et leurs deux interrupteurs ne changent pas.

Trois réglages d'Android n'ont pas d'équivalent que ce routeur puisse honorer : éviter les côtes,
éviter les escaliers et éviter les surfaces non revêtues. Valhalla garde `use_hills` fixe à 0,5 et
`bicycle_type` fixe à Hybrid, et le repli OSRM n'a aucun de ces paramètres. Les réglages affichent
donc ces trois lignes avec « Not supported by this open router » au lieu d'interrupteurs qui ne
feraient rien. Le choix d'itinéraire répète la limite sous le profil.

Le scénario `BikeProfileUITests.testBikePreferencesChangeTheRoute` part du profil sûr, coupe
l'interrupteur des réglages, ouvre un trajet vélo vers Ferry Building et vérifie le temps du profil
le plus rapide. Il déplie ensuite le choix, touche `route-bike-profile-safe` et exige un temps
différent avec `mode=BICYCLE` et `bikeSafe=1`. Il produit `bike-settings.png`, qui montre la ligne
et les trois limites, puis `bike-profile-route.png`, qui montre le trajet replanifié. Le runner ne
peut pas garantir que les deux profils donnent deux routes différentes sur un trajet réel :
l'argument de debug `-VelaBikeProfileFixture YES` remplace seulement la réponse du routeur par deux
tracés déterministes, alors que la préférence, sa persistance et la replanification restent celles
du code de production. Aucun build de production n'active cette fixture.

Les tests JVM `RouteStoreTest.storedBikeProfileIsAppliedBeforeTheFirstRequest` et
`RouteStoreTest.bikeProfileChangeReplansWithoutSwitchingMode` couvrent la lecture avant la première
requête, la clé `bike_safe`, la replanification et le mode inchangé. `BikeNoGoogleRoutingTest`
garde la preuve du corps Valhalla (`costing`, `use_roads`, `use_hills`, `bicycle_type`) et du repli
OSRM quand le profil sûr est coupé.

## Focus sur une étape (RTE-STEP)

La liste d'étapes de la feuille d'itinéraire est désormais un sélecteur de carte. Toucher une ligne
`step-row` cadre la manœuvre sur la carte et laisse la feuille ouverte sous forme de carte
compacte ; aucun guidage ne démarre. Ce comportement reprend `MapViewModel.previewStep` et le
mouvement de caméra de `VelaMapView` sur Android, sans la partie conduite.

### Caméra

Le point de la manœuvre vient de `Maneuver.location`, désormais transporté par `StepRow` en
`lat` et `lng`, puis recopié dans `RouteStep`. La carte reçoit donc le point exact du routeur, pas
une position déduite de la longueur des étapes.

Le cadrage est celui d'Android :

| Valeur | Réglage |
|---|---|
| Zoom | 16,5 |
| Inclinaison | 0° |
| Cap | 0°, nord en haut |
| Centre | la coordonnée de la manœuvre |

Le mouvement suit `LaunchOptions.animates`, donc il est animé sur un appareil normal et immédiat
dans les scénarios qui coupent les animations. Un guidage actif n'est pas modifié : le prochain
point de conduite reprend la caméra, comme le prévoit la pause de `NAV-CAMERA`.

### Surbrillance

Le tronçon qui mène à la manœuvre est surligné en ambre (`vela-step-focus`, 11 points, opacité
0,92) pendant cinq secondes. Il couvre 220 m avant le point et 40 m après, pour que le carrefour
reste visible sous l'extrémité arrondie du trait. `StepFocusGeometry` choisit le sommet du tracé le
plus proche de la manœuvre, remonte la ligne selon la distance réelle, puis redescend un peu.
La couche est une source de forme en mémoire ; elle ne fait aucune requête et ne survit pas au
délai. Un second toucher annule le délai et remplace le tronçon au lieu d'en empiler un autre.
L'identifiant est inscrit dans `RouteLayers.layerIdentifiers` et dans `MapTapRegistry` avec le
gestionnaire `.none`, donc un toucher sur la surbrillance traverse jusqu'à la ligne de route.

### Feuille et marche d'étape

Après le toucher, la liste se replie sur la seule étape choisie, ancrée en bas de la zone allouée
par `MapScreen`, et laisse la carte visible au-dessus. La carte compacte porte :

- le titre « Step X of N » et l'instruction complète avec ses voies ;
- `step-previous` et `step-next`, qui déplacent la caméra et la surbrillance d'une étape à l'autre ;
- `step-whole-route`, qui quitte le focus, remet la liste complète et recadre toute la ligne avec
  une marge basse de 55 % de la hauteur pour laisser la feuille au-dessus de la carte ;
- `steps-close`, inchangé, pour fermer la liste.

Le déplacement d'une étape à l'autre ne touche ni au mode, ni aux routes, ni au bouton Start. La
ligne `step-focus-debug` (Debug seulement) publie `step_focus=0|1`, `step_index` et `step_zoom`.
`MapController` renvoie le zoom effectivement demandé par la notification `focusApplied`, ce qui
permet au scénario de lire la valeur de caméra sans passer par la carte.

### Preuves

`DirectionsUITests.testStepTapFocusesMap` ouvre un trajet vers Ferry Building, affiche les étapes,
touche la deuxième ligne, exige `step_focus=1` et `step_zoom=16.5`, capture
`route-step-focus.png`, avance avec `step-next`, puis revient avec `step-whole-route`. Les lignes
`step_focus`, `step_zoom`, `step_next` et `step_whole_route` sont ajoutées au résumé du run. Les six
autres scénarios `DirectionsUITests` gardent leurs assertions.

### Limites

- La ligne d'arrivée synthétique ajoutée quand le routeur ne fournit pas `ARRIVE` n'a pas de
  coordonnée : elle reste informative et ne se cadre pas.
- Les étapes de transport ne portent pas de point de manœuvre et ne sont pas focalisables ; seul
  le détail de transport reste leur surface.
- La surbrillance dure cinq secondes et n'est pas conservée après la fermeture de la feuille.
- Le focus ne démarre jamais le guidage et ne modifie pas `NavModel`.

## Defilement du choix unifie (SCROLL-FIX)

En grands textes ou en paysage, la feuille du choix est un seul defilement pour toutes les lignes
sous la poignee. Les lignes de debug sont dans ce defilement, et non au-dessus : a AX5 elles
consommaient la demi-feuille et la zone defilante n'avait presque plus de hauteur, donc les options
d'evitement ne pouvaient pas etre atteintes. La poignee reste epinglee, parce qu'elle est le second
enfant accessible dont la feuille a besoin : seule, elle laissait SwiftUI poser `route-sheet` sur le
`ScrollView` lui-meme et effacer `route-scroll` (SCROLL-AX3). Le `ScrollView` est enveloppe dans un
conteneur mesure qui porte `route-scroll` avec un cadre reel ; le scenario peut donc le faire
glisser directement au lieu de viser la feuille entiere. En portrait a texte normal, le `ScrollView`
interne de `splitBody` garde le meme identifiant.

`DirectionsUITests.testRouteAvoidOptionsScrollAtLargeText` deplie la feuille, lit
`route_scroll_frame` et `route-scroll-debug`, fait glisser `route-scroll` et exige
`route-avoid-highways` hittable apres au plus trois glissements. Il publie
`route_avoid_swipes=<n>` et produit `route-avoid-reachable.png`. Les sept scenarios Directions
existants gardent leurs assertions et leurs captures ; le scenario QUALITY-REG de paysage garde son
propre defilement.
