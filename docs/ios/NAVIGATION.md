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
