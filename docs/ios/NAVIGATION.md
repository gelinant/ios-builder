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
