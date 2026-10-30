# Navigation : arrivée, étapes et parking

Ce document décrit la fin de conduite iOS livrée par N-4, sur `iosApp/Vela/Nav/` et
`ios-shared/.../ios/nav/`. Il distingue ce que le moteur commun fournit déjà de ce qui reste absent.

## Arrivée à destination

- `NavSession` passe en état `arrived` au dernier point du trajet. La route et la caméra restent en
  place : `NavUiState.active` vaut vrai tant que l'arrivée est affichée, donc le trajet reste dessiné
  et la Live Activity ouverte.
- `NavChrome.arrival` affiche le nom et l'adresse de destination, le temps de trajet et la distance
  parcourue, puis `Done`. `Done` appelle `NavStore.stop()` : la session commune est arrêtée, la route
  disparaît, la Live Activity se termine et le navigateur de carte revient. La caméra reste centrée
  sur la dernière position connue avec le zoom de conduite, orientée au nord ; elle ne revient ni au
  départ ni à un cadrage de recherche.
- La confirmation de fin existante (`End navigation?`) n'est pas contournée : `End` en pleine
  conduite demande toujours confirmation, `Done` après arrivée non, comme sur Android.

## Proposition de stationnement

- `NavUiState.parkingOffer` vaut vrai seulement pour une conduite (`travelMode == DRIVE`), à
  l'arrivée, avec une position publiée. Une marche ou un vélo ne proposent rien, et une position
  absente ne fabrique pas de point de stationnement.
- Le bouton `nav-save-parking` écrit avec `SavedStore.saveParking(at:)`, le même `ParkingStore` que
  le bouton parking de la carte, puis affiche `nav-parking-saved`. La confirmation est locale à la
  carte d'arrivée ; `parked=1` dans la ligne de débogage le prouve.
- `Find my car` (distance, itinéraire vers la voiture, âge du stationnement) reste hors de ce lot.
  L'historique et la restauration existent déjà dans les lieux enregistrés.

## Arrivée à une étape

- `NavStore.startNavigation` transmet désormais les étapes R-1 à la session commune
  (`NavSession.NavStop`, dans l'ordre de conduite). Sans cela, la session ne connaissait aucun arrêt
  et ne pouvait ni annoncer ni compter les étapes.
- La voix commune dit « Vous êtes arrivé à … » au passage de chaque marque d'étape. `NavStore`
  observe la liste des étapes restantes et publie `reachedStopLabel` avec un compteur
  `reachedStopSerial`.
- `NavChrome` affiche alors la carte `nav-waypoint`, avec le nom de l'étape, l'étape suivante et
  `Continue`. Elle se retire seule après dix secondes, et `Continue` la ferme sans toucher au guidage :
  même session, même route, même Live Activity, aucun nouveau calcul d'itinéraire.
- La barre basse affiche « Vers … » sous les chiffres quand une étape reste à venir
  (`nav-next-stop`), comme la barre Android. Les chiffres restent ceux du trajet entier ; la
  ventilation chiffres par étape d'Android n'est pas portée.
- Ajouter ou modifier une étape pendant la conduite reste absent : `MapScreen` ferme les surfaces de
  recherche et d'édition quand `nav.active` est vrai. Ce n'est pas ce lot.

## Parking dans le guidage

Le moteur commun fournit déjà les deux phrases, sans données inventées :

- `ParkingLotTurn.wordDestination` change le dernier virage sans nom en « Tournez à gauche dans le
  parking » quand les tuiles montrent un `service=parking_aisle`. Le routeur hybride iOS
  (`GoogleMapsDataSource.directions`, puis `nameRoute` pour une alternative provisoire) l'applique
  aux routes `DRIVE`, donc le bandeau, la liste des étapes et la voix portent la phrase.
- Pour une étape, `NavSession.lotTurn` cherche le virage sans nom avant la marque et vérifie les
  tuiles via `RoadNameTiles` ; iOS installe `IosRoadNameTiles` avant toute requête. La phrase
  « … puis <étape> est sur votre droite » vient alors de `NavStrings.intoLotThen`.
- Quand les tuiles ne répondent pas, ou que la route ne porte pas de virage sans nom, la phrase
  ordinaire reste : rien n'est supposé. `ParkingLotTurnTest` couvre le virage reformulé, le refus
  d'une rue, d'une allée ou d'un simple driveway, et l'absence de données.

Reste à faire : aucune capture iOS ne prouve encore un vrai parking de destination, le runner ne
pouvant pas garantir que les tuiles répondent sur le trajet de test. La validation iPhone en
conduite reste nécessaire.

## Détour caméra et alertes d'étapes

- Les alertes caméra et limitation de vitesse viennent de N-2 et restent inchangées.
- Le détour automatique par caméra (`CameraDetour`, `MapViewModel` Android) n'a pas de chemin iOS :
  la logique de choix et de fusion vit dans le module Android `:app`, pas dans `:core-common`. Ce lot
  ne l'invente pas.
- Les alertes de lieux enregistrés (`PassAlerts`) restent sans abonnement côté iOS ; L-2 les couvre.

## Bandeau de manœuvre

Le lot NAV-BANNER enrichit le bandeau supérieur sans changer la session commune.

### Voies

- `NavStore` recopie désormais `Maneuver.lanes` dans `NavManeuver.lanes` (`NavLane`: indications et
  `valid`). `NavChrome` dessine une cellule par voie, avec la flèche de chaque indication. Les voies
  qui servent la manœuvre sont blanches et sur un fond clair, les autres sont grisées.
- La bande apparaît seulement sous 800 m de la manœuvre, ou plus tôt à vitesse élevée
  (`max(800, vitesse × 30 s)`), et toujours pendant une prévisualisation. Comme sur Android, elle
  ne s'affiche pas des kilomètres avant un échangeur.
- Si la route ne porte aucune voie par voie, la bande est absente. `laneHint` n'est pas utilisé
  pour fabriquer des flèches : le texte « Use the left 2 lanes » de Google ne dit pas quelle voie
  va où. Les routes Google sans données de voies n'affichent donc rien, ce qui est le compromis
  demandé.

### Écussons et numéros de route

- Le bandeau affiche l'écusson du `ref` de la manœuvre, un onglet vert pour un numéro de sortie
  lu dans l'instruction, et l'écusson persistant de la route parcourue quand il diffère de celui de
  la manœuvre. La ligne « puis » du bandeau porte aussi l'écusson de la manœuvre suivante.
- Les formes états-uniennes et canadiennes reprennent les familles de `parseRouteRef` : Interstate,
  US Route, État ou province, et puce générique en repli. Le modèle commun ne porte pas
  de pays : le style français ou britannique suit la région de l'appareil. France : A en bleu
  (autoroute), N en rouge (nationale), D en jaune (départementale). Royaume-Uni : M en bleu
  (motorway), A en blanc bordé de noir, A1(M) en bleu.
- Limite assumée : un trajet qui traverse une frontière garde le style de l'appareil. Une route
  `A7` n'est pas distinguable entre une autoroute française et une route britannique sans un champ
  pays dans la manœuvre partagée.

### Route actuelle et « Road numbers first »

- `NavUiState.currentRoadLabel` et `currentRoadRef` viennent de `Maneuver.roadAt(...)`, des
  renommages silencieux et de `roadLabel` / `signedHeading` du module commun. Une autoroute montre
  donc son numéro, avec la direction signée quand les panneaux la donnent.
- Le nom s'affiche dans une pastille au-dessus de la barre basse, avec l'identifiant
  `nav-current-road`. Les quatre placements d'Android ne sont pas portés : iOS n'a pas encore de
  réglage correspondant.
- `RoadNumbers.preferred` est appliqué au démarrage depuis la clé `road_numbers` des préférences
  standard, si elle existe. Aucune ligne de réglages iOS ne l'écrit encore : le bandeau suit la
  préférence partagée dès qu'un lot de réglages l'expose.

### Balayage et retour au guidage

- Un balayage horizontal de plus de 110 points fait glisser la carte, comme un pager. Vers la
  gauche, l'étape suivante est prévisualisée ; vers la droite, l'étape précédente. La carte devient
  grise, les voies de l'étape restent visibles et la mention `nav_preview_tap_resume` rappelle le
  retour.
- `NavStore.preview(stepOffset:)` garde l'index prévisualisé dans `NavUiState` et le recalcule à
  chaque publication. `exitPreview()` rend le guidage en direct, sans nouvelle session, sans
  nouvelle route et sans toucher à la voix.
- Pendant la prévisualisation, `NavModel` place la carte sur le point de la manœuvre et arrête la
  caméra poursuivante ; un appui sur la carte restaure le suivi. Le marqueur de prévisualisation
  d'Android n'existe pas côté iOS : `MapController` n'est pas modifié par ce lot.
- Les retours haptiques passent par `AppleNavHaptics` (`NavHaptics.swift`) : sélection légère à
  chaque balayage, impact léger au retour.

### Chiffres par arrêt

- Quand une étape reste à venir, la barre basse prend les chiffres de l'arrêt suivant, nommé sous
  eux (`nav-next-stop`), avec la distance et l'heure d'arrivée (`nav-stop-figures`). La ligne
  `nav_bar_trip` garde le trajet entier et son heure d'arrivée juste en dessous. Sans étape, la
  barre reste celle du trajet entier.
- Ces valeurs viennent de l'état R-1 `NavUiState.nextStop*` et `stopsAhead`, lus sans modification.
  Aucun calcul local ne fabrique une heure d'arrivée.

### Grands textes

- Aux tailles d'accessibilité, l'instruction est limitée à deux lignes en `subheadline`, la
  distance est réduite au besoin (`minimumScaleFactor`), les icônes passent de 36 à 26 points et les
  rembourrages de 16 à 12 points. Les voies et les écussons grandissent d'au plus 1,5 fois.
- `NavBannerUITests.testBannerAtAccessibilityXXXL` mesure la carte de manœuvre à AX XXXL et exige
  au plus 36 % de la hauteur de l'écran. Le compromis est la perte d'une ligne d'instruction
  au-delà de deux lignes : le texte complet reste dans la feuille des étapes.

## Preuves

- `core-common:jvmTest` : `ParkingLotTurnTest` (virage dans le parking, refus, absence de tuiles).
- `ios-shared:jvmTest` : `NavArrivalTest` (étape annoncée puis conduite qui continue, une seule
  session, arrivée finale, proposition de parking selon mode et position).
- `VelaUITests/NavArrivalUITests` : trajet avec une étape sur le rejeu Market Street, captures
  `nav-waypoint.png` et `nav-arrival.png`, proposition de parking enregistrée, `Done`, une seule Live
  Activity sur tout le trajet.
- `VelaUITests/NavUITests` et `NavRobustnessUITests` restent les preuves de la conduite simple et de
  pause, tunnel et cycle de vie.
- `ios-shared:jvmTest` : `NavStoreTest.maneuverCarriesLanesRefAndCurrentRoad` prouve le passage des
  voies, du `ref`, du `laneHint` et de la route actuelle ; `bannerPreviewWalksStepsAndRestoresLiveGuidance`
  prouve le balayage et le retour sans changer la manœuvre en direct.
- `VelaUITests/NavBannerUITests` : captures `nav-banner-lanes-shield-stop.png`,
  `nav-banner-preview.png`, `nav-banner-live-restored.png`, `nav-banner-ax.png`,
  `nav-banner-shield-fr.png` et `nav-banner-shield-gb.png`. Le scénario active
  `-VelaNavBannerFixture YES` pour garantir voies et écussons, car une route de démonstration réelle
  ne les porte pas toujours ; le test JVM prouve le même chemin avec les données partagées.
- La prévisualisation par balayage, les chiffres par arrêt et les écussons n'ont pas encore de passe
  iPhone en conduite réelle.

## Cycle de vie, alertes seules et notifications

Le lot NAV-LIFE ferme L168-L169, L171, L208-L209 et L210-L211. Il ne touche ni `MapScreen` ni
`MapController` : tout vit dans `NavStore`, `NavChrome`, `NavModel`, `NavNotifications.swift` et
`NavLifecycle.swift`.

### Reprise après un appel, une suspension ou une relance

- Un appel téléphonique, un écran verrouillé et un passage en arrière-plan ne changent pas la
  session : `NavLifecyclePolicy` coupe seulement la phrase en cours, réarme la session audio au
  retour et rattache la caméra si elle suivait. Aucune instruction n'est répétée par ce chemin, et
  la Live Activity reste unique.
- Une conduite interrompue par un processus tué est écrite dans un magasin séparé, avec les clés
  d'Android : `lat`, `lng`, `label`, `mode`, `at`, plus `origin_lat` et `origin_lng`. Le magasin
  s'appelle `vela_nav_resume`, comme la préférence Android.
- Au lancement, `NavStore.start()` lit ce magasin dès que Swift lui a passé les magasins de
  plateforme (`attachPreferences`). Un enregistrement de moins d'une heure est replanifié depuis le
  premier point frais, comme `resumeNav` sur Android : la partie déjà parcourue pendant l'absence
  n'est pas redessinée, et l'ETA, l'étape courante et les distances restantes viennent du nouveau
  calcul. Le point enregistré sert de repli quand aucun point n'arrive en huit secondes.
- La conduite reprend d'elle-même, car l'écran de reprise Android n'a pas d'hôte iOS : `NavChrome`
  n'est monté que quand `nav.active` est vrai. Un échec garde l'enregistrement et le cycle suivant
  de premier plan retente. `End` et l'arrivée effacent l'enregistrement.
- L'horodatage est rafraîchi toutes les cinq minutes pendant la conduite, donc la fenêtre d'une
  heure mesure le temps depuis l'interruption, pas depuis le départ. L'écriture passe par `commit`
  pour survivre à une tuée immédiate.
- La pause n'est pas persistée : une conduite reprise redémarre en marche. Les étapes intermédiaires
  ne sont pas enregistrées non plus ; la destination, son libellé, le mode et la dernière position
  le sont. C'est la limite actuelle, à traiter avec `NAV-FREEDRIVE` pour les étapes.

### Alertes seules

- Le bouton haut-parleur du bandeau suit les trois états Android : `On`, `Alerts only`, `Off`. Il
  appelle `NavStore.cycleVoiceMode()`; l'icône devient un haut-parleur, une cloche ou un haut-parleur
  barré, et son libellé d'accessibilité suit l'état.
- Les deux clés sont celles d'Android dans `vela_settings` : `spoken_directions` (faux quand la voix
  est coupée) et `spoken_alerts_only` (vrai seulement en Alerts only). Elles sont relues au
  lancement, donc le mode survit à une relance.
- En Alerts only, la voix de conduite est coupée et les alertes vitesse, caméra, radar de plaques
  et pont jouent un court carillon avec le retour haptique. Rien n'est prononcé. En Off, tout est
  silencieux, carillon compris, comme sur Android.
- Aucune ligne de réglages iOS n'écrit encore ces clés : le bandeau est le seul chemin. `SET-VOICE`
  ajoutera la ligne correspondante sans changer le magasin.

### Notifications locales et pont de retour

- À l'entrée en arrière-plan d'une conduite active et non en pause, `NavNotificationController`
  poste une notification locale unique : destination, minutes restantes et prochaine instruction.
  L'identifiant est `vela.nav.background`. Le retour au premier plan et la fin de conduite la
  retirent.
- La permission est demandée au premier départ, pas au lancement de la carte. Les scénarios UI
  déterministes ne voient pas la demande système sauf `NavAlertsUITests` avec
  `-VelaNavNotificationTest YES`.
- Le tap passe par le délégué `UNUserNotificationCenter` : la conduite reste la même, la caméra se
  rattache et recentre. Si le processus avait été tué, le tap ouvre l'app et la reprise persistée
  fait le reste.
- Limites iOS, sans serveur push : la notification est postée une fois à la transition, pas mise à
  jour en continu. Une app suspendue par le système ou tuée par la personne ne calcule plus rien
  et ne poste plus rien. La Live Activity reste la surface vivante tant que le processus vit. Une
  permission refusée laisse la conduite fonctionner sans notification, et aucun mode silencieux ne
  prétend le contraire. Le texte de la notification est en anglais pour l'instant ; `I18N-TRANS`
  le reprendra.
- La mini-carte d'image dans l'image reste ➖ : iOS n'offre pas de Picture in Picture MapKit pour
  une conduite, et la simuler avec une seconde vue de carte serait un faux. La Live Activity et la
  notification couvrent la surface visible.

### Ponts mobiles

- `OverpassNavAlertProvider` demande NDW (`planningsfeed_brugopeningen`) seulement quand la ligne
  entre aux Pays-Bas, projette les ponts sur le trajet avec le corridor de 30 m d'Android et remplit
  `NavRouteData.bridges`. Hors des Pays-Bas, aucune requête n'est faite.
- `NavAlerts` applique `BridgeAlerts.due` avec l'heure murale et annonce une fois par pont et par
  route : pont ouvert maintenant, ou ouverture prévue autour de l'heure d'arrivée estimée. La carte
  emploie `nav_bridge_open_ahead` ou `nav_bridge_opening_ahead` avec l'heure formatée, et l'icône
  `water.waves`.
- La préférence `bridge_openings` est lue et écrite par `NavStore`, vraie par défaut. Aucune ligne
  de réglages iOS ne l'expose encore.
- Limite : le flux NDW est demandé une fois par route, alors qu'Android le rafraîchit pendant la
  conduite. Un pont dont l'ouverture est publiée après le départ peut donc manquer. Les scénarios
  UI roulent à San Francisco et ne peuvent pas prouver un pont néerlandais ; le test JVM couvre le
  déclenchement.

### Preuves

- `ios-shared:jvmTest` : `NavStoreTest.voiceModePersistsUnderAndroidKeys` (cycle des trois états et
  relecture par un second processus), `alertCueFollowsTheThreeWayVoiceMode`,
  `resumeRecordRestoresTheDriveAndEndClearsIt` (destination, libellé, ETA, une seule session, `End`
  efface) et `staleResumeRecordIsDropped`.
- `ios-shared:jvmTest` : `NavAlertsTest.bridgeOnTheRouteIsAnnouncedOnce`.
- `VelaUITests/NavLifecycleUITests` : suspension en arrière-plan avec captures
  `nav-life-before-background.png` et `nav-life-background.png` (même session, étape non régressée,
  ETA restante, pas d'instruction répétée), puis relance avec `nav-life-resume.png` (`resumed=1`,
  ETA et instruction présentes).
- `VelaUITests/NavAlertsUITests` : `testAlertsOnlySilencesGuidanceAndKeepsAlerts` (captures
  `nav-alerts-only.png` et `nav-alerts-cycle.png`) et `testBackgroundNotificationAndTapBridge`
  (capture `nav-alert-bridge.png`). Le pont de notification passe par le même gestionnaire que le
  délégué système ; le scénario ne dépend pas d'un tap sur une bannière du SpringBoard.
- Une passe iPhone reste nécessaire pour un vrai appel entrant, une vraie bannière de notification
  et un pont néerlandais. Le simulateur ne compose pas d'appel et le runner ne roule pas aux
  Pays-Bas.

## NAV-FREEDRIVE: conduite libre et arrêt ajouté en route

La conduite libre est l'équivalent iOS du mode conduite d'Android (FEATURES L30-L34) : la carte
sans destination, avec ce qu'un conducteur regarde. Elle ne remplace ni la navigation guidée de
NAV-BANNER ni les règles de NAV-LIFE ; elle partage leur session, leur voix et leurs réglages.

### Entrées et habillage

- Une manette dans la pile de boutons de la carte (`free-drive-open`) démarre la conduite libre.
  La feuille d'itinéraire, en mode voiture, offre aussi « Drive without a destination »
  (`route-free-drive`), ce qui quitte l'itinéraire planifié sans le démarrer.
- `FreeDriveChrome` dessine la barre du haut : la vitesse réelle et le panneau de limite, puis les
  boutons carte simple, voix, recentrer et sortie (`free-simple-map`, `free-voice`, `free-locate`,
  `free-exit`). Le bas porte le panneau de la rue courante (écusson et nom, `free-road`) et
  l'attribution OpenStreetMap.
- La caméra suit le cap en vue inclinée, comme en navigation. Un panoramique la détache ; recentrer
  la rattache. L'écran ne s'éteint pas pendant la conduite libre.
- Aucune session n'est créée : pas de Live Activity, pas de notification d'arrière-plan, pas de
  bilan de trajet. Aucun enregistrement de reprise n'est écrit, et une reprise guidée en attente
  n'est pas démarrée sous la conduite libre. La voix, elle, suit les mêmes trois états qu'une
  navigation guidée et persiste sous les clés Android.

### D'où viennent la vitesse et la limite

- La vitesse vient du flux GPS, la même valeur que la session guidée publie dans `speedMps`.
- La limite vient d'OpenStreetMap, jamais d'une estimation. `FreeDriveRoads` interroge Overpass
  autour du point courant (60 m) pour les `way["highway"]["maxspeed"]` et les autres `way["highway"]`,
  et prend la voie carrossable la plus proche à moins de 20 m. La limite est lue par le même
  analyseur qu'Android (`OsmMaxspeed`), avec ses règles de `maxspeed`, `maxspeed:forward` /
  `:backward`, mph et `maxspeed:conditional` appliqué à l'heure murale.
- La voie la plus proche porte aussi son nom et son `ref`, affichés dans le panneau de la rue.
- La requête repart après 120 m parcourus, ou 30 m si 12 secondes ont passé. Entre deux requêtes,
  une limite connue reste affichée jusqu'à 80 m du point où elle a été lue ; au-delà, le panneau
  disparaît. Une voie sans `maxspeed` laisse le panneau vide, jamais une valeur inventée.
- Le Debug des scénarios UI répond à cette requête avec une voie nommée et limitée ; les tests JVM
  couvrent l'analyse, la voie non carrossable, la voie hors du rayon et la limite absente.

### La carte simple

- Le bouton `free-simple-map` passe la carte en carte simple : plus de lieux, plus de transit, plus
  de routes peintes, plus de prix de carburant, plus de ponts, plus de feux ni de circulation.
  Les caméras, l'itinéraire éventuel et les alertes restent. L'état vit en mémoire pour la
  conduite en cours.
- La carte simple passe par une copie de `MapLayerData` ; en quittant la conduite libre, la carte
  reprend exactement la feuille de couches de l'utilisateur, sans écrire de préférence.

### Ajouter un arrêt pendant la conduite

- `NavChrome` gagne une action « Add stop » (`nav-add-stop`) visible pendant une navigation guidée.
  Elle ouvre `NavStopOverlay`, un panneau posé sur la conduite (sans feuille modale, donc sans
  interrompre la caméra ni la Live Activity), qui réutilise la recherche de la carte.
- Le choix part à la session commune par `NavStore.addStop(...)` : l'arrêt devient le dernier du
  plan et la session recalcule depuis la position courante. `NavStore` publie alors
  `stopsRecalculating` (indicateur « Rerouting », identifiant `nav-stop-recalc`) et l'efface quand
  la nouvelle route arrive, ou au bout de 20 secondes. La même session, la même Live Activity et la
  même route continuent : rien n'est relancé.
- La nouvelle route traverse l'arrêt, donc `nav-next-stop`, `nav-stop-eta` et `nav-stop-figures`
  reprennent avec la nouvelle valeur, comme pour un arrêt prévu dès le départ. Les voies, les
  écussons, l'aperçu de manœuvre et le budget de 36 pour cent de NAV-BANNER ne changent pas :
  aucun identifiant n'a été renommé.

### Tests

- `ios-shared:jvmTest` : `FreeDriveRoadsTest` (nom, `ref`, limite mph, voie non carrossable, hors
  rayon, limite absente, requête) et `NavStoreTest.freeDriveShowsTheRoadLimitAndKeepsTheVoiceMode`,
  `freeDriveSurvivesAForegroundWithoutStartingThePersistedDrive`,
  `addingAStopDuringADriveShowsRecalculationThenFreshStopEta`.
- `VelaUITests/FreeDriveUITests` : la vitesse réelle, le panneau de limite, le nom de rue, la carte
  simple et le retour à l'habillage guidé ; captures `free-drive-speed-limit.png` et
  `free-drive-simple-map.png`.
- `VelaUITests/NavStopsUITests` : l'ajout d'un arrêt par la feuille, l'indicateur de recalcul, l'ETA
  de l'arrêt rafraîchie, une seule session ; capture `nav-stop-added.png`.
- Les scénarios de NAV-BANNER et NAV-LIFE restent inchangés et sont rejoués dans la même passe.

### Limites connues

- La limite de la conduite libre dépend d'Overpass, en ligne. Sans réseau, le panneau reste vide ;
  l'overlay hors ligne de limites d'Android n'est pas porté ici.
- La conduite libre ne lance pas les alertes de caméras ni de vitesse excessive : elles restent
  celles de la navigation guidée (NAV-LIFE).
- La barre de recherche est masquée en conduite libre, comme le mode conduite d'Android ; l'ajout
  d'un arrêt passe par le bouton de la navigation guidée.
- Le panneau d'arrêt emploie la recherche en ligne de la carte : sans réseau, il ne propose rien.

## NAV-RENDER : congestion, Road ahead et voies sur la carte

NAV-RENDER dessine la route de conduite elle-même, pas seulement le bandeau. Tout vient de la
route commune : `Route.trafficSpans` pour la congestion, `Route.maneuvers` pour les deux flèches et
`Maneuver.lanes` pour les voies. Aucun niveau de trafic ni aucune flèche n'est fabriqué par l'UI.

### Route parcourue et congestion

- Le trait est coupé au point parcouru (`NavState.traveledM`) et à chaque borne de
  `TrafficSpan` : la partie derrière la voiture est grise, la partie restante prend la couleur du
  niveau Google (1 orange, 2 rouge, 3 rouge sombre) ou le bleu du flux libre. Une portion grise
  reste grise même si un span la recouvre encore, puisqu'elle est déjà derrière la voiture.
- La logique pure vit dans `core-common/.../nav/RouteRender.kt`. Elle fusionne deux morceaux
  adjacents de même niveau, garde les deux extrémités exactement sur la polyligne et prend le
  niveau le plus grave quand deux spans se chevauchent.
- Le trait a un liseré de 10 points sous une ligne de 7 points, constant de z16 à z19. Les
  marques peintes de ROAD-MARKINGS sont insérées au-dessus de ce groupe, donc lignes de voie,
  bandes vélo et flèches de sens unique restent visibles sur le tracé. Le liseré ne les couvre pas.
- `NavModel` ne renvoie la géométrie à la carte que lorsque le point parcouru a bougé de 8 m, que
  l'étape, l'aperçu ou l'approche des voies change. Une conduite ne re-tesselle donc pas la route
  à chaque point GPS.

### Road ahead

- Deux flèches sont posées aux points des manoeuvres : la prochaine (`next`) et la suivante
  (`then`). L'index de départ est `stepIndex`, celui que lit le bandeau. La première flèche porte
  donc toujours le même `ManeuverType` que l'icône du bandeau, via `StepsSheet.symbol`, jamais un
  symbole voisin. Une manoeuvre `DEPART` est ignorée, un point déjà posé n'est pas répété.
- Pendant un aperçu par balayage, les flèches partent de l'étape prévisualisée ; le bandeau et la
  carte parlent alors de la même manoeuvre.
- Les glyphes sont des images dessinées au chargement du style (cercle bleu, flèche blanche) :
  aucun sprite distant, donc un style hors ligne les affiche aussi. L'image est orientée selon le
  cap d'approche de la manoeuvre.

### Voies sur la route

- Quand la manoeuvre porte des voies, une flèche par voie est posée en travers de l'approche, voie
  de gauche en premier, à 3,2 m d'écart. Les voies utiles sont bleues et claires, les autres
  grises, comme les cellules du bandeau.
- La ligne n'apparaît qu'à l'approche, avec la même règle que le bandeau (`max(800 m, vitesse x
  30 s)`), est toujours visible pendant un aperçu, et disparaît quand la manoeuvre est passée
  puisque la manoeuvre courante change.
- Une route sans données de voies n'affiche rien : `laneHint` ne fabrique pas de flèches.

### Ordre de dessin et appuis

- De bas en haut : carte et routes de base, liseré et pièces de navigation, rasters de trafic,
  caméras et marques peintes, puis les flèches et voies de navigation, puis les libellés. Les
  rasters et les caméras gardent donc leur place actuelle, les marques peintes restent au-dessus
  du liseré, et les glyphes de navigation restent lisibles au-dessus des marques.
- Tous les identifiants sont déclarés dans `RouteLayers.layerIdentifiers` et enregistrés dans
  `MapTapRegistry`. Les lignes de navigation gardent le comportement existant de sélection de
  route ; les deux couches de symboles sont `.none`, l'appui passe à la ligne située dessous.
- La conduite libre ne dessine jamais ce groupe : il est effacé à l'entrée en conduite libre, à la
  fin du guidage et à l'arrivée avec `Done`, tandis que les caméras et alertes restent en place.

### Tests

- JVM `core-common:jvmTest` : `RouteRenderTest` sur le gris coupé au point parcouru, un span qui
  commence derrière la voiture, les spans qui se chevauchent, la sélection des deux flèches à
  partir du bandeau, le saut de `DEPART`, le doublon de point, la limite de deux et la porte des
  voies (`800 m` ou vitesse x 30 s) avec l'ordre gauche à droite des glyphes.
- UI `VelaUITests/NavRenderUITests.testCongestionGreyAndRoadAhead` : captures `nav-congestion.png`,
  `nav-road-ahead.png` et `nav-lanes-map.png`, lignes `nav_route_segments=<n>`, `nav_congestion=1`,
  `nav_road_ahead=<n>`. Le scénario active `-VelaNavRenderFixture YES`, car la route de
  démonstration ne porte pas toujours du trafic ni des voies, et garde les types d'icône du
  bandeau pour prouver l'accord carte et carte de manoeuvre.
- Les quatre scénarios `NavBannerUITests` sont rejoués dans la même passe ; aucun identifiant du
  bandeau n'a changé.

### Limites

- La congestion vient de Google Directions. Une route OSRM sans spans reste bleue, sans fausse
  bande orange.
- Les voies dépendent des données du routeur ; beaucoup de routes Google n'en portent pas et la
  carte reste alors sans rangée de voies.
- Aucune passe iPhone en conduite réelle n'a encore validé le rendu sur un vrai trajet.

### Passe Mac

Run `nav-render-20261029-033244-31859` : build simulateur, 602 tests JVM et 501 tests Kotlin
simulateur sans échec, 182 tests unitaires iOS sans échec. Les cinq scénarios UI passent :
`NavRenderUITests.testCongestionGreyAndRoadAhead` (12,9 s) et les quatre `NavBannerUITests`
(grands textes 19,6 s, France 14,2 s, voies et arrêt 20,2 s, Royaume-Uni 12,2 s). Lignes de
rapport : `nav_route_segments=3`, `nav_congestion=1`, `nav_road_ahead=2`, `nav_lanes_map=4`, et
les lignes NAV-BANNER inchangées (`nav_banner_lanes=4`, `nav_banner_preview=2`,
`nav_banner_restored=1`). Captures : `nav-congestion.png` (gris derrière la voiture, rouge sur le
bouchon, bleu au-delà), `nav-road-ahead.png` (virage à droite puis à gauche, comme le bandeau) et
`nav-lanes-map.png` (quatre voies à l'approche).

## NAV-CAMERA : caméra de conduite et vue d'ensemble

NAV-CAMERA ferme L124-L125, L126-L129 et L162. La caméra impérative reste dans
`MapController.swift` ; `NavModel` lui passe la position, la vitesse, la distance et le point de la
prochaine manœuvre, et `NavChrome` n'ajoute qu'un bouton. Aucune couche n'est dessinée et aucun
identifiant de NAV-RENDER ou de NAV-BANNER ne change.

### La voiture dans le tiers bas

- Le cadrage vient de `contentInset` : l'écart entre l'insertion haute et l'insertion basse vaut
  0,45 fois la hauteur de la carte, donc la voiture se pose à 72,5 pour cent de l'écran. Le réglage
  « Keep the car in the lower third » remet ce pad à zéro et la voiture au centre.
- Le cap suit la géométrie de la route dessinée, pas seulement le cap GPS : `NavMapRender` livre
  les morceaux dans l'ordre du trajet, `MapController` les concatène et prend le cap du segment le
  plus proche de la voiture. Le cap GPS ne sert que si aucune ligne n'est encore disponible.
- Le zoom de vitesse reprend les valeurs d'Android : 18,5 au repos, 15,8 à 30 m/s (108 km/h), en
  ligne droite entre les deux. Les 250 derniers mètres resserrent en plus le zoom de 0,35 niveau.
- L'inclinaison demandée est de 55 degrés, plafonnée par MapLibre à 60. Elle s'aplatit linéairement
  entre z12,5 (0 degré) et z15 (55 degrés), comme `navTiltCap` sur Android.
- Le cadrage de la manœuvre reprend `NavFraming` : le point de la prochaine manœuvre est projeté à
  72 points sous le bord bas du bandeau, avec la correction de perspective de l'inclinaison
  (`turnZoomFlattening`). La caméra tourne vers la manœuvre de 90 degrés au plus, pondérés par
  l'écart entre le zoom de vitesse et le zoom de manœuvre. Le zoom ne descend pas sous le plancher
  choisi.

### Réglages de caméra

- `zoom_to_turn`, la clé Android, active ou coupe le cadrage de la manœuvre. Il est faux par
  défaut, comme sur Android, donc la caméra de conduite reste au zoom de vitesse tant qu'on ne
  l'active pas.
- `zoom_to_turn_floor`, également la clé Android, garde les trois planchers d'Android : Town z12,
  Region z10, Far z8. La valeur est écrite en `Float` pour rester lisible par le magasin Android.
- `nav_camera_tilt` et `nav_camera_lower_third` sont deux clés iOS : Android applique ces deux
  comportements sans réglage. Elles vivent dans la même suite `vela_settings` et s'appliquent à la
  conduite en cours par notification, sans relancer la session.

### Vue d'ensemble et retour

- Le bouton `nav-overview` de la barre basse, ou un appui à deux doigts sur la carte, cadre toute
  la route restante, à plat et au nord, avec la marge du bandeau et de la barre basse. Le même
  bouton, un appui simple sur la carte ou le passage de la prochaine manœuvre rendent la caméra de
  conduite.
- Le retour ne fabrique pas de nouvelle caméra : `MapController` garde le dernier point, la
  dernière vitesse, le dernier cap routier et la dernière manœuvre, puis rejoue exactement le
  cadrage de conduite. La ligne de débogage `camzoom` revient donc à sa valeur d'avant l'overview.
- Pendant l'overview, `setNavigationFollowing(true)` est ignoré : une publication de la session ne
  peut pas rallumer la poursuite sous la route cadrée.

### Ne pas contrarier le conducteur

- Un panoramique manuel détache la caméra et appelle toujours `NavStore.panned()`, donc
  l'identifiant `nav-recenter` existant apparaît. Cinq secondes après le dernier geste, `NavModel`
  peut reprendre la caméra, sauf si la conduite est en pause ou si une étape est prévisualisée.
  Recentrer reste le chemin immédiat et efface aussi l'overview.
- La conduite libre et le guidage en transport gardent leur propre caméra : la conduite libre
  partage seulement `beginNavigation` et `endNavigation`, et le transport ne passe jamais par
  `navigationCamera`.

### Preuves

- `VelaUITests/NavCameraUITests.testThirdOfScreenZoomAndOverview` : la voiture à 72 pour cent au
  moins, une caméra inclinée et zoomée, puis l'overview et le retour au même zoom. Captures
  `nav-camera-tilt.png`, `nav-camera-overview.png` et `nav-camera-third.png`. Lignes
  `nav_camera_third=1`, `nav_camera_zoom=<z>` et `nav_camera_overview=1`.
- Les scénarios `NavBannerUITests` sont rejoués dans la même passe ; aucun identifiant du bandeau
  ni de la barre basse n'a changé.

### Limites

- Aucune passe iPhone en conduite réelle ne valide encore le cadrage sur une route qui tourne, ni
  la reprise automatique après un panoramique. Le runner ne roule que sur le trajet de
  démonstration de San Francisco.
- Le cadrage de la manœuvre est faux par défaut, comme sur Android. Il n'est donc pas dessiné dans
  la capture de référence ; le calcul reste couvert par le code commun et à vérifier à la main avec
  le réglage activé.
- Le cap routier suit la ligne restante : après un recalcul, le premier point publié peut précéder
  la voiture de quelques mètres, et la caméra reprend le nouveau tracé au point suivant.

### Passe Mac

Run `nav-camera-20261029-110241-9372` : build simulateur, 188 tests unitaires iOS et 5 scénarios UI
sans échec. `NavCameraUITests.testThirdOfScreenZoomAndOverview` passe en 45,7 s, avec les quatre
`NavBannerUITests` rejoués dans la même passe. Lignes de rapport : `nav_camera_third=1`,
`nav_camera_zoom=16.8`, `nav_camera_overview=1`, et les lignes NAV-BANNER inchangées. Captures :
`nav-camera-third.png` (voiture à 76 pour cent, cap routier, zoom de conduite),
`nav-camera-overview.png` (route restante entière, à plat et au nord) et `nav-camera-tilt.png`
(caméra inclinée avant l'overview).

## Recherche pendant la conduite (DRIVE-SEARCH)

État : branche `ios/drive-search`. Le chrome de conduite gagne une entrée de recherche propre,
sans quitter le guidage. Aucun fichier `MapScreen.swift` ni `MapController.swift` n'est modifié :
`NavChrome` monte lui-même le champ et le bouton de voix, et lit le modèle de recherche déjà
possédé par la carte par le registre faible `SearchActions`.

### Le champ et le bandeau

- Une loupe de 44 points (`drive-search-open`) et un microphone de 44 points (`drive-search-mic`)
  sont posés dans la rangée au-dessus de la barre basse, à côté de « Add stop ». Ils restent des
  cibles fixes quand le texte est agrandi.
- La loupe ouvre `DriveSearchOverlay`, une carte posée au-dessus du bandeau, jamais une feuille.
  Le voile est léger : la carte, la caméra, l'étape en cours et la Live Activity continuent
  derrière. La croix (`drive-search-close`) et un appui hors de la carte ramènent au guidage sans
  toucher à la session.
- Le champ ne prend jamais le focus tout seul. Il n'y a ni `.focused` ni remplissage automatique :
  seul un appui du conducteur ouvre le clavier. Le microphone, lui aussi, ne s'ouvre que sur son
  bouton ; le bouton de recherche ne l'arme pas.
- `NavChrome` ignore la zone clavier en bas (`ignoresSafeArea(.keyboard, edges: .bottom)`), donc le
  clavier ne remonte ni le bandeau ni la barre d'arrêt. La liste de résultats est plafonnée à 240
  points et défile, pour rester au-dessus du clavier.
- À AX3, la pastille de rue courante quitte la rangée et les deux entrées gardent leurs 44 points.
  Le bandeau conserve son budget d'un tiers d'écran ; seul le panneau de recherche grandit.

### Ajouter un arrêt ou changer la destination

- Les commandes passent par le même analyseur que la carte et la dictée (`SearchCommands`).
  Maison, Travail, l'appel, la recherche le long de la route et une recherche ordinaire suivent le
  chemin habituel.
- Pendant une conduite, `directions to X` n'exécute rien tout de suite : le panneau affiche X avec
  deux choix, « Add stop » (`drive-search-add-stop`) et « Change destination »
  (`drive-search-replace`), plus Annuler. Choisir un arrêt cherche X puis appelle
  `NavStore.addStop`, comme la feuille d'arrêt existante. La session, la Live Activity et la caméra
  ne sont pas relancées ; le bandeau repasse en « Rerouting » puis reprend la nouvelle étape.
- Choisir de changer la destination reprend la phrase d'origine et le chemin d'itinéraire normal :
  le choix s'ouvre sur le nouveau lieu et la conduite en cours continue jusqu'au départ de ce
  nouvel itinéraire. Rien n'est remplacé en silence.

### Voix

- Le microphone du chrome ouvre `DriveDictation`, les mêmes moteurs locaux que VO-2 (sherpa-onnx
  installé, sinon la reconnaissance Apple sur l'appareil), avec la même session audio et le même
  arrêt par silence. La phrase reconnue remplit le champ et passe par le même analyseur et la même
  question ajouter ou remplacer. Le dialogue vocal de la carte n'est pas réutilisé : son modèle ne
  rend pas le texte reconnu à l'appelant. Un lot `Voice/` pourra exposer ce texte et supprimer la
  petite duplication.

### Tests

- `VelaUITests/DriveSearchUITests.testSearchAndAddStopDuringDrive` ouvre le champ, vérifie que
  `directions to coffee` propose les deux choix, puis tape `search coffee`, choisit le premier des
  quatre résultats et vérifie que `stopadds` augmente sans nouvelle session, sans perte de Live
  Activity et sans perte du bandeau. La commande le long de la route garde sa couverture
  SRCH-ALONG et passe par le même `submit` depuis ce champ. Lignes de rapport :
  `drive_search_open=1`, `drive_search_directions_choice=1`, `drive_search_cmd=search`,
  `drive_search_added=1`, `drive_search_session_starts=<n>`. Le trajet du scénario va de San
  Francisco à Oakland : le rejeu de l'hôte suit Market Street et la route reste ouverte pendant
  qu'une recherche lente revient, donc l'arrêt est ajouté sur une conduite encore vivante.
  Captures : `drive-search.png`, `drive-search-results.png` et `drive-search-stop.png`.
- `NavBannerUITests` reste inchangé et rejoué dans la même passe : la rangée gagne deux boutons,
  mais aucun identifiant existant ne bouge.

### Limites

- La liste de conduite garde quatre résultats au plus. Un besoin de liste longue reste la
  recherche de la carte, hors conduite.
- Le détour est calculé en Swift sur la ligne publiée par `NavStore.line()`, avec la même formule
  que `SearchCommandCorridor` : deux fois la distance perpendiculaire, et rien derrière la voiture.
  Il n'y a pas d'heure d'arrivée par résultat.
- La dictée de conduite duplique le choix de moteur de VO-2. Aucun fichier `Voice/` n'est modifié
  par ce lot.
