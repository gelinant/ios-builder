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

## Preuves

- `core-common:jvmTest` : `ParkingLotTurnTest` (virage dans le parking, refus, absence de tuiles).
- `ios-shared:jvmTest` : `NavArrivalTest` (étape annoncée puis conduite qui continue, une seule
  session, arrivée finale, proposition de parking selon mode et position).
- `VelaUITests/NavArrivalUITests` : trajet avec une étape sur le rejeu Market Street, captures
  `nav-waypoint.png` et `nav-arrival.png`, proposition de parking enregistrée, `Done`, une seule Live
  Activity sur tout le trajet.
- `VelaUITests/NavUITests` et `NavRobustnessUITests` restent les preuves de la conduite simple et de
  pause, tunnel et cycle de vie.
