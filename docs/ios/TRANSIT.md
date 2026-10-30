# Transports en commun iOS (T-1)

Ce document couvre les tableaux de départs, les options de recherche de trajets et le détail d'un
itinéraire. Le guidage pas à pas et sa Live Activity restent décrits dans
[TRANSIT-ACTIVITY.md](TRANSIT-ACTIVITY.md). La source est Transitous, seul planificateur transport
d'iOS, avec ses arrêts, ses horaires GTFS et GTFS-Realtime.

## Tableau de départs d'un arrêt

Un toucher d'arrêt ouvre une feuille avec les prochains départs. Deux entrées existent :

- une icône d'arrêt Transitous, dessinée à partir de z15 et fusionnée par nom et proximité comme
  sur Android (`Transitous.stopsInBox`, `mergeDirectionalPairs`) ; le tableau interroge son
  identifiant d'arrêt et celui de sa station parente (`Transitous.boardFor`) ;
- un libellé d'arrêt du fond de carte ou une fiche lieu dont la catégorie est un arrêt, résolu par
  proximité (`Transitous.board`) ; un arrêt nommé par un carrefour suit le même chemin.

Chaque ligne affiche la pastille de couleur de l'agence, son numéro, sa direction et ses départs.
Un départ porte « Live » seulement quand le flux Transitous a marqué le passage en temps réel ;
sinon il affiche « Scheduled » et son heure théorique. Le compte à rebours est recalculé depuis
l'epoch fourni, sans estimation. Le tableau se rafraîchit toutes les 30 s tant qu'il est ouvert et
le bouton Refresh relance la requête immédiatement. Un échec de rafraîchissement conserve le
dernier tableau et l'indique ; un arrêt sans desserte affiche « No departures found here », jamais
des horaires inventés.

Le dernier tableau réussi de chaque arrêt est conservé sur disque sous `PlatformFiles`, dans
`transit-boards/` (un fichier JSON atomique par arrêt, clé = identifiant Transitous ou coordonnée
arrondie). À l'ouverture, le cache est affiché avant la réponse du flux. Si le flux répond, ses
lignes remplacent le cache et le tableau redevient normal. S'il échoue, les lignes en cache restent
visibles avec « Offline, from HH:MM » et la mention « These departures come from the last saved
board. They are not live. » Aucune pastille Live n'est restaurée : le drapeau temps réel est perdu
à l'écriture, et un départ datant de plus d'une minute est retiré. Un arrêt jamais consulté avec
succès garde « No departures found here », sans horaire inventé.

Les entrées expirent au bout de 6 h et seules les 24 plus récentes sont gardées ; l'élagage a lieu
à chaque écriture. Un rafraîchissement en échec sur un tableau déjà en direct le marque comme
périmé, pas comme hors ligne : les deux états restent distincts.

## Options de recherche

`Transitous.plan` accepte réellement les paramètres suivants, repris par `TransitPlanQuery` :

| Option iOS | Paramètre Transitous | Comportement réel |
|---|---|---|
| Leave now | aucun `time` | Départ maintenant |
| Depart at | `time=<ISO>` | Départ à l'heure choisie |
| Arrive by | `time=<ISO>&arriveBy=true` | Arrivée avant l'heure choisie |
| Bus | `transitModes=BUS` | Filtre véhicule du planificateur |
| Subway | `transitModes=SUBWAY` | Filtre véhicule du planificateur |
| Rail | `transitModes=RAIL` | Filtre véhicule du planificateur |
| Tram | `transitModes=TRAM` | Filtre véhicule du planificateur |
| Fewer transfers | aucun | Tri des itinéraires déjà renvoyés par `TransitOrder.byPreference` |
| Less walking | aucun | Tri des itinéraires déjà renvoyés par `TransitOrder.byPreference` |

Limites exactes, à ne pas dépasser dans l'interface :

- « Last available » n'existe pas dans l'endpoint public. Android le traite comme un arrive-by ;
  iOS ne l'expose pas.
- Le ferry n'a pas de mode dans `Transitous.plan` (`PLAN_MODES` ne contient que BUS, SUBWAY, RAIL
  et TRAM). La feuille d'options ne propose donc pas Ferry et le dit.
- « Fewer transfers » et « Less walking » ne filtrent pas la recherche : ils réordonnent les cinq
  itinéraires renvoyés. Un itinéraire sans correspondance qui n'a pas été renvoyé ne peut pas
  apparaître.
- Aucun `maxTransfers`, aucune vitesse de marche et aucun arrêt intermédiaire ne sont envoyés. Le
  planificateur travaille entre les deux extrémités.
- Changer l'heure relance la requête transport. En voiture, la feuille R-1 affiche une estimation
  typique et ne prétend pas obtenir une prévision de trafic future.

## Détail d'un itinéraire

Le bouton d'étapes du choix d'itinéraire ouvre, en mode transport, une feuille dédiée. Elle montre :

- les heures de départ et d'arrivée, la durée, l'agence et le tarif quand le flux les fournit ;
- chaque marche et chaque trajet, avec la pastille de ligne, la direction, la durée, le nombre
  d'arrêts et le retard fourni ;
- les arrêts de montée et de descente, avec code d'arrêt et heure théorique barrée quand une heure
  réelle diffère ;
- les arrêts intermédiaires renvoyés par le planificateur ;
- les alertes de service quand l'itinéraire ou un trajet en porte.

Le parseur Transitous conserve désormais les alertes d'un itinéraire et de ses trajets. Un flux qui
n'en fournit pas laisse la liste vide. Le tarif reste affiché seulement si le champ existe : Vela ne
le calcule pas.

### Guidage des marches

Chaque jambe de marche est guidée dans la carte de transit, avec la même voix que la conduite
(`VelaNavVoice`, donc le même bouton de mute) et les mêmes règles d'arrivée. Deux sources se
complètent :

- le routeur de marche de l'application (`MapDataSource.directions` en mode WALK) fournit les
  manœuvres nommées « Turn left onto Market Street » ; il est interrogé au démarrage de la jambe et
  remplace le plan initial s'il répond pour cette jambe ;
- sinon, le tracé de la jambe Transitous est simplifié (Douglas-Peucker à 10 m), les changements de
  cap de plus de 20° deviennent des virages à gauche ou à droite, avec distinctions léger, franc et
  demi-tour. Aucun nom de rue n'est inventé : la carte indique « Turn-by-turn from the walk path.
  Street names are unavailable for this leg. » et la ligne de debug porte `walknamed=0` ;
- une jambe sans tracé mais avec ses deux extrémités affiche un plan `straight`, signalé comme tel
  dans `walksource`.

Le bandeau annonce la prochaine manœuvre avec sa distance, la voix dit une fois la formule
lointaine (« In 40 meters, turn right ») puis une fois la formule au virage (« Turn right »).
L'arrivée est annoncée une seule fois. Les positions dont la précision dépasse 100 m sont ignorées ;
un point hors du tracé de plus de 80 m ne reprojette pas la marche. `End` annule la jambe, la
guidance et les requêtes en cours. La Live Activity X-3 n'est ni dupliquée ni recréée par ce
guidage : la session et le contrôleur ActivityKit restent inchangés.

Le bouton Start remet l'itinéraire sélectionné à `TransitSession`, qui possède déjà la progression,
le tracé et la Live Activity X-3. Un nouvel itinéraire démarre une nouvelle session : le contrôleur
ActivityKit termine l'ancienne activité avant d'en demander une autre, et le test de réducteur
`testNewSessionStartsInsteadOfUpdatingTheOldOne` couvre ce cas. Aucune activité en double n'est
créée.

## Vérifications

Sous Linux :

```
source ~/opt/env.sh
flock /tmp/opencode/gradle.lock ./gradlew --no-daemon -Pvela.iosOnly=true \
  :core-common:jvmTest :ios-shared:jvmTest :ios-shared:compileKotlinIosSimulatorArm64
```

Tests JVM ajoutés :

- `TransitBoardStoreTest` : minutes et marque Live, départs passés, tableau remplacé, échec de
  rafraîchissement, boucle de 30 s et fermeture, filtre de catégorie ;
- `TransitOptionsTest` : index des véhicules, modes réellement envoyés, normalisation des trois
  heures et des trois préférences ;
- `RouteStoreTest.transitOptionsReachThePlannerAndReplan` : les options arrivent au planificateur
  et chaque changement relance la recherche ;
- `TransitousPlanTest` : alertes d'itinéraire et de trajet conservées, absence d'alerte sans
  champ.
- `TransitWalkGuideTest` : virage déduit des caps sans nom de rue, virage gauche, plan `straight`
  sans tracé, manœuvres nommées du routeur conservées, invites lointaine et proche une seule fois,
  arrivée, projection d'un point hors tracé ;
- `TransitWalkSessionTest` : démarrage sur la marche, correction par le routeur nommé, précision
  de 240 m ignorée, arrivée à l'arrêt, `End` qui efface le guidage ;
- `TransitBoardCacheTest` : écriture et relecture, aucune marque Live restaurée, expiration à 6 h,
  tableau dont tous les départs sont passés, borne de 24 entrées, tableau en cache quand le flux
  échoue, tableau direct remplacé puis marqué périmé, fixture hors ligne.

Scénarios interface :

- `TransitActivityTests.testStopBoardShowsDeparturesAndRefreshes` ouvre le tableau du Ferry
  Building avec le flux réel, vérifie au moins une ligne et un départ, rafraîchit et capture
  `transit-board.png` ;
- `TransitActivityTests.testTransitOptionsChangeTheDepartureAndVehicles` ouvre un trajet vers le
  Ferry Building, applique un départ dans 15 minutes, active le filtre rail et capture
  `transit-options.png`. Les lignes `UITEST transit_board_*` et `transit_options_*` donnent les
  nombres et l'epoch.
- `TransitActivityTests` reste le scénario X-3 : démarrage, avance de marche, retard réel et End.
- `TransitActivityTests.testWalkingLegShowsTurnByTurn` démarre la fixture avec `-VelaTransitWalkTurns`
  (même trajet, tracé de marche coudé), vérifie que le guidage de marche est actif, au moins deux
  instructions, une source connue (`steps`, `path` ou `straight`), puis capture `transit-walk.png`.
  Sur le runner, le routeur de marche a répondu et la source observée était `steps` ; le repli
  géométrique est couvert par `TransitWalkGuideTest` ;
- `TransitActivityTests.testOfflineBoardShowsCachedDepartures` démarre avec
  `-VelaTransitBoardOfflineTest`, qui remplit le cache avec une fixture et n'interroge pas le flux :
  vérifie `offline=1`, `cached=1`, `live=0`, au moins deux départs, la bannière
  `transit-board-offline` et l'absence de texte « Live », puis capture
  `transit-board-offline.png`.

## Lot T-1b : marches et tableaux hors ligne

État au 2026-10-27, avant le run Mac de la branche `ios/t1b-transit-walk` :

- instructions de marche dérivées du tracé, noms de rues quand le routeur de marche répond ;
- voix partagée avec la conduite, mute commun, invites non répétées ;
- cache disque borné du dernier tableau par arrêt, état hors ligne explicite, aucune marque Live
  restaurée ;
- scénarios interface ajoutés, captures `transit-walk.png` et `transit-board-offline.png`.

La fixture `-VelaTransitWalkTurns` et la fixture hors ligne sont réservées aux builds Debug ; elles
ne changent aucun chemin de production.

## Résultat du runner macOS

Run `t1b-transit-walk-20261027-022635-31273`, ciblé sur `TransitActivityTests` : vert. Les 5
scénarios passent, dont `testWalkingLegShowsTurnByTurn` (13 s, `walkcount=2`, `walksource=steps`,
`walknamed=1`, capture `transit-walk.png`) et `testOfflineBoardShowsCachedDepartures` (33 s,
`offline=1`, `cached=1`, `live=0`, 4 départs, capture `transit-board-offline.png`). Côté Kotlin,
205 tests JVM et 184 tests simulateur, aucun échec ; 86 tests Swift, aucun échec.

Run complet `t1b-transit-walk-20261027-030547-21336` : les 5 scénarios transport passent, les tests
Kotlin et Swift aussi, IPA publiée (20 629 052 octets, extension `NavActivityExtension.appex`
présente). Neuf scénarios hors transport échouent (Directions café, trois Localization, MapSearch
POI, trois Quality grands textes, deux Saved), avec des messages de focus clavier, de libellés de
réglages et de feuilles absentes, sans rapport avec les fichiers de ce lot ; ils restent à rejouer
sur `ios/main`.

Run `t1-transit-20261026-184331-24518`, ciblé sur `TransitActivityTests` :

| Vérification | Résultat |
|---|---|
| Kotlin | 124 tests JVM et 103 tests simulateur, aucun échec |
| Tests Swift | 50 tests, aucun échec |
| Live Activity X-3 | verte : marche puis trajet, retard réel, `End`, activité terminée |
| Tableau d'arrêt | vert : 3 lignes, 50 départs, `error=none`, rafraîchissement à 50 départs |
| Options | heure `time=1` appliquée, 8 itinéraires après le changement d'heure, filtre rail appliqué (`train=1`) ; le filtre rail seul a renvoyé zéro itinéraire près du Ferry Building à cette heure, ce qui est une réponse valide du planificateur |
| Captures | `transit-board.png`, `transit-board-refresh.png`, `transit-options.png` |
| IPA | `results/t1-transit-20261026-184331-24518/Vela-unsigned.ipa`, 10 057 107 octets ; extension `NavActivityExtension.appex` présente |
| Statut | rouge sur une seule assertion de test, `trips_after_filters >= 1`, qui supposait à tort qu'un filtre rail ne peut pas vider la liste. L'assertion a été corrigée après le run pour exiger l'état TRANSIT stabilisé et rapporter le nombre, sans fabriquer d'itinéraire. |

Le run n'a pas été rejoué après cette correction, faute de budget Mac. Le prochain run complet doit
confirmer le scénario vert ; les autres preuves ci-dessus restent valables.

## Tests humains sur iPhone

1. Toucher une icône d'arrêt Transitous et un arrêt nommé du fond de carte : vérifier le titre, les
   pastilles, les directions, le compte à rebours et la distinction Live / Scheduled.
2. Laisser la feuille ouverte deux minutes et vérifier le rafraîchissement sans saut visuel. Couper
   le réseau puis rafraîchir : le dernier tableau doit rester avec l'avertissement.
3. Sur un trajet avec correspondance, changer Depart at et Arrive by, activer puis désactiver un
   véhicule, et vérifier qu'aucun trajet n'est présenté comme garanti par le filtre.
4. Ouvrir le détail, vérifier les arrêts, une alerte si le flux en fournit une, puis Start. Vérifier
   la Live Activity et l'absence de seconde activité quand un autre itinéraire est démarré après
   End.
5. Démarrer un trajet dont la première jambe est une marche assez longue : vérifier les virages
   annoncés, le mute (le même que la conduite), l'arrivée à l'arrêt et le passage au trajet.
6. Consulter un tableau d'arrêt avec réseau, fermer la feuille, passer en mode avion, rouvrir le
   même arrêt : le tableau doit revenir avec « Offline, from HH:MM », sans pastille Live. Attendre
   plus de 6 h ou vider les données de l'app pour vérifier que l'entrée a expiré.
7. Mettre l'app en arrière-plan pendant une marche : la voix doit continuer de suivre les invites
   sans doublon au retour, et End doit tout arrêter.

## Lot T-3 : écran de trajet type Citymapper

L'écran de trajet présente l'itinéraire Transitous sélectionné comme une suite de cartes, avec les
prochains départs de la jambe choisie en bandeau. Il s'ouvre depuis la feuille de détail
(« Trip view ») et depuis la carte de guidage pendant une session (« Trip »). `MapScreen.swift` et
`Map/` ne changent pas : les deux boutons vivent dans `TransitDetailSheet` et `TransitGuidanceCard`.

### Bandeau et cartes

Le bandeau interroge le propre `TransitBoardStore` de l'écran (`TransitTripService`) pour l'arrêt de
la jambe choisie : identifier d'arrêt quand il existe, coordonnée sinon. Il ne partage pas la cible
du tableau d'arrêt de la carte, donc ouvrir l'écran ne remplace jamais le tableau qu'un utilisateur
consulte par ailleurs. Il affiche la pastille de la ligne, l'arrêt, les prochains passages, le
compte à rebours et la distinction Live / Scheduled de T-1. Si le flux ne répond pas, le bandeau
le dit ; si le flux ne dessert pas cette ligne, il l'écrit sans fabriquer d'horaire.

Une carte par segment, dans l'ordre de marche :

- marche, avec sa durée, sa distance quand le flux la donne et son arrêt d'arrivée ;
- attente, avec l'heure de départ de la course suivante ;
- trajet, avec la pastille et la couleur Transitous, le mode, la direction, les arrêts de montée et
  de descente avec leur code, les heures de montée et de descente, le nombre d'arrêts et le retard
  fourni ;
- correspondance, quand une marche sépare deux trajets.

Les heures théoriques restent barrées quand une heure réelle les remplace, et le retard s'écrit
« 4 min late ». « Live » et « Scheduled » sont toujours du texte, jamais une couleur seule.

### Heure d'un segment

Un toucher de carte sélectionne le segment et ouvre trois actions :

- « Leave later » : +5, +15 ou +30 minutes. L'heure d'ancrage est le passage que le flux liste pour
  cette ligne à cet arrêt, reconnu par son heure affichée ; à défaut, le premier segment s'ancre sur
  le départ de l'itinéraire. Un segment intermédiaire sans correspondance dans le tableau est refusé
  explicitement, jamais approximé ;
- « Arrive by » : Transitous n'a pas de contrainte d'arrivée par arrêt (`/api/v1/plan` ne connaît
  que le départ et l'arrivée aux deux extrémités). Seul le dernier segment l'accepte, ancré sur
  l'arrivée de l'itinéraire. Les autres segments expliquent cette limite ;
- « Skip this one » : voir plus bas.

Le calcul produit une `TransitPlanQuery` (départ à une heure ou arrivée avant une heure) envoyée par
`RouteStore.setTime`, donc par `Transitous.plan`, le même planificateur et le même modèle que la
feuille de détail. La réponse s'affiche comme un nouvel ensemble d'options avec ses heures, sa durée
et ses lignes ; l'itinéraire au-dessus garde ses propres heures. Choisir une option appelle
`RouteStore.select`, donc la feuille de détail et l'écran de trajet montrent ensuite le même
itinéraire. Une réponse vide laisse l'itinéraire en place et le dit.

### Un seul contrôle d'heure (TIME-1)

Le même composant, `TimeChoiceBar`, est présent dans six surfaces : la feuille d'itinéraire, les
options transport, l'écran de trajet, le tableau d'arrêt, le détail d'un trajet et le choix d'un
itinéraire enregistré. Il propose les trois modes (Maintenant, Partir à, Arriver avant), un
sélecteur de date et d'heure, « +15 min » et « Apply time ». Chaque surface garde ses identifiants
d'accessibilité et ajoute un identifiant stable `time-choice` sur le conteneur.

La règle de temps est celle de `TimeChoice` dans `:ios-shared` : le mode 0 n'envoie aucun `time`,
le mode 1 envoie `time`, le mode 2 envoie `time` et `arriveBy`. Une heure passée est ramenée au
prochain créneau de cinq minutes, jamais envoyée telle quelle. Le libellé « Leave now », « Depart
at 9:05 AM » ou « Arrive by 9:00 AM » vient de la même fonction Kotlin, donc des six surfaces.

Sous les boutons, une ligne nomme la requête : le mode, l'heure choisie, le fuseau de l'appareil et,
après « Apply », la minute d'envoi. Une réponse ancienne ne peut donc pas passer pour une réponse
fraîche. Chaque application relance la requête de sa surface : un nouveau `plan` pour
l'itinéraire, les options, le trajet et le détail, la même reprise pour l'itinéraire enregistré,
et une nouvelle demande du tableau pour l'arrêt. Un trajet en voiture garde sa limite connue : le
routeur ouvert n'a pas de champ de départ, la feuille écrit donc « Estimate only, no live departure
forecast » et ne relance pas la requête.

Le fuseau et l'heure d'été sont ceux de l'appareil : « Arrive by 09:00 » demain est converti par le
calendrier local, y compris au changement d'heure. Un trajet qui traverse un fuseau garde les heures
imprimées par le flux, sans conversion ; l'écran de trajet et le détail le disent et nomment le
fuseau qu'utilise le contrôle.

Le scénario rouge `TransitCitymapper.testSegmentTimeChangeShowsANewOptionSet` venait de la position
du libellé de requête : il était rendu sous les quatre cartes de segment, dans une feuille courte,
et trois glissements ne l'atteignaient pas. Le contrôle et le nouvel ensemble d'options sont
maintenant en haut de l'écran, avant les cartes, et l'écran ramène ce bloc en haut après chaque
changement d'heure. Le scénario lit donc `transit-trip-options-query` sans défiler et exige qu'il
contienne « Depart at ». Le scénario d'interface `TransitTimeUITests.testTimeEverywhere` produit
`time-route.png`, `time-transit.png`, `time-segment.png` et `time-board.png`.

#### Résultat du runner macOS (TIME-1)

Tag `time-1-20261029-135605-1203`, run ciblé
`VELA_ONLY_UI=TransitTimeUITests,TransitCitymapperUITests` avec `VELA_SKIP_ARCHIVE=1`. La compilation
Kotlin, le framework et le build simulateur passent. Cinq scénarios sur six sont verts :

- `TransitCitymapper.testSegmentTimeChangeShowsANewOptionSet` : vert, 53,4 s. Le libellé
  `transit_trip_shift_query=Depart` et `transit_trip_option_rows=2` sont lus sans défilement, et
  `transit-trip-shift.png` est produit ;
- `TransitTimeUITests.testTimeEverywhere` : vert, 135,3 s, avec `time-board.png`, `time-route.png`,
  `time-segment.png` et `time-transit.png`. Les lignes publiées sont
  `time_board_query=Depart_at_2:55_PM_·_GMT_·_asked_2:38_PM`,
  `time_route_query=Depart_at_2:55_PM_·_GMT_·_asked_2:39_PM`,
  `time_segment_query=Depart_at_2:55_PM_from_Metro_Van_Ness_Station_·_fixture,_display_only`,
  `time_trip_query=Depart_at_3:10_PM_·_GMT_·_asked_2:38_PM`,
  `time_transit_query=Depart_at_3:10_PM_·_GMT_·_asked_2:40_PM` et `time_surfaces=4` ;
- `testTripScreenShowsSegmentCardsAndNextDepartures`, `testNearbyLinesTabListsTheStopsLines` et
  `testSkipLetsTheRunPassAndAdvancesTheHeader` restent verts.

`testLiveTripScreenWhenTheFeedAnswers` reste rouge, 103,4 s : sur l'itinéraire vivant, le bouton
« Trip view » de la feuille de détail est à `y=880,3`, sous la fenêtre, et XCUITest ne peut pas le
faire défiler. Le premier run (`time-1-20261029-133150-9112`) montrait le même cadre. La cause est
la hauteur idéale de la feuille : le `ScrollView` du détail ajoutait tout son contenu à la hauteur
du `VStack`, et le contrôle d'heure ajouté dans ce contenu a poussé la rangée d'actions fixe sous le
bord. Le correctif place le `ScrollView` dans un `GeometryReader` pour qu'il prenne la hauteur
proposée au lieu de l'imposer. Il est arrivé après le dernier run autorisé et n'est donc pas rejoué
sur le runner ; il reste à vérifier au prochain run de la classe.

### Laisser passer une course

« Skip this one » lit le prochain passage de la même ligne dans le bandeau, avance le bandeau à ce
passage et demande de nouvelles options ancrées sur son heure. L'itinéraire reste affiché avec toutes
ses cartes ; la carte de la course laissée passer est marquée « passed » dans son libellé
d'accessibilité. Si le flux ne liste aucun passage suivant, l'écran le dit au lieu d'inventer une
heure.

### Progression en direct

Quand `TransitSession` conduit l'itinéraire, l'écran affiche la progression de la session partagée,
la jambe courante et sa ligne. Cette progression vient des positions de la session, pas d'une
estimation d'horaire : sans session active, aucun indicateur n'est affiché.

### Lignes à proximité

L'onglet « Lines nearby » interroge le même `TransitBoardStore` sur l'arrêt d'origine de
l'itinéraire et liste chaque ligne du flux avec ses prochains passages, sa direction, sa couleur et
sa marque Live / Scheduled. Une ligne absente du flux n'apparaît pas ; un arrêt sans desserte affiche
un message vide. L'origine vient de la première coordonnée de l'itinéraire. Utiliser la position de
l'utilisateur quand elle est plus proche demanderait un accès à la position déjà filtrée de la
carte : ce n'est pas fait, l'onglet s'en tient à l'origine du trajet.

### Perturbations

Les alertes de l'itinéraire Transitous s'affichent sous « Reported by the operator », avec le texte
du flux. Un itinéraire sans alerte n'affiche aucune section.

### Accessibilité

Les cartes, les lignes voisines et les départs ont un libellé VoiceOver complet (mode, ligne,
direction, arrêts, heures, Live ou Scheduled, retard, nombre d'arrêts), les boutons font au moins
44 pt et l'écran plafonne la taille du texte à AX3. Les états Live, Scheduled, retard et « passed »
portent tous du texte.

### Limites Transitous, sans invention

- aucun paramètre d'heure par arrêt : « Leave later » sur un arrêt intermédiaire n'agit que si son
  passage figure dans le tableau ; « Arrive by » ne contraint que la destination ;
- aucun paramètre de saut de course : « Skip this one » avance le bandeau et repropose un départ à
  l'heure du passage suivant, sans réécrire l'itinéraire ;
- pas de position de véhicule ni de retard par ligne dans cet écran : seuls les champs du flux sont
  affichés ;
- pas de ferry dans le planificateur, comme pour T-1 ;
- le bandeau et l'onglet exigent les coordonnées de l'arrêt ; sans elles, l'écran l'explique.

### Vérifications

Sous Linux, la commande de T-1 reste la même et passe : 310 tests JVM pour `:ios-shared` (dont 14
nouveaux) et 950 pour `:core-common`, aucun échec, plus la compilation du simulateur iOS.

Tests JVM ajoutés, `TransitTripTest` :

- cartes marche, attente, trajet et correspondance, avec l'ordre et les champs du flux ;
- bandeau de la ligne choisie, direction préférée, heures triées, marque Live conservée, absence de
  ligne inventée quand le flux est muet ;
- ancrage de « Leave later » sur le passage du tableau, repli sur le départ de l'itinéraire pour le
  premier segment, refus d'un segment intermédiaire sans passage ;
- « Arrive by » limité au dernier segment, mode et heure de la requête ;
- « Skip this one » vers le passage suivant, tableau avancé, refus sans course suivante ;
- lignes à proximité avec leurs passages, lignes passées retirées, flux nul sans invention ;
- options d'un nouvel ensemble dans l'ordre du planificateur.

Scénarios interface, `TransitCitymapperUITests` :

- `testTripScreenShowsSegmentCardsAndNextDepartures` : cartes, bandeau, marques Live et Scheduled,
  capture `transit-trip.png` ;
- `testSegmentTimeChangeShowsANewOptionSet` : sélection de la course K, « Leave later » +15, nouvel
  ensemble d'options, itinéraire inchangé, capture `transit-trip-shift.png` ;
- `testSkipLetsTheRunPassAndAdvancesTheHeader` : bandeau avancé d'un passage, itinéraire conservé,
  capture `transit-trip-skip.png` ;
- `testNearbyLinesTabListsTheStopsLines` : onglet des lignes voisines, capture
  `transit-trip-nearby.png` ;
- `testLiveTripScreenWhenTheFeedAnswers` : recherche réelle du Ferry Building, capturé
  `transit-trip-live.png` quand le planificateur répond.

Les quatre premiers scénarios tournent sur la fixture `-VelaTransitFixture` : aucune requête
Transitous n'est nécessaire et l'ensemble d'options de la fixture est explicitement en lecture seule
(« display only »), donc il ne peut pas remplacer l'itinéraire par des heures de fixture. Le dernier
scénario est le seul en direct ; il est ignoré, pas échoué, si le planificateur ne renvoie aucun
trajet.

### Tests humains sur iPhone

1. Ouvrir un trajet avec correspondance, vérifier le bandeau, les cartes, les pastilles et la
   distinction Live / Scheduled.
2. Sélectionner une course, « Leave later » +15, vérifier que de nouvelles options apparaissent avec
   leurs heures et que l'itinéraire au-dessus n'a pas changé ; en choisir une et vérifier que la
   feuille de détail montre le même trajet.
3. Sélectionner le dernier segment, « Arrive by », vérifier la contrainte d'arrivée ; sélectionner un
   segment intermédiaire et vérifier le refus expliqué.
4. « Skip this one » sur une course : le bandeau passe au passage suivant, l'itinéraire reste, les
   nouvelles options arrivent.
5. Onglet « Lines nearby » : vérifier les lignes et les heures, puis couper le réseau et vérifier le
   message hors ligne ou vide.
6. Avec Règles > Texte en très grand jusqu'à AX3 et VoiceOver, parcourir cartes, bandeau et onglet ;
   vérifier les libellés et les cibles de 44 pt.

### Résultat du runner macOS (T-3)

Run `t3-transit-20261027-221854-1833`, ciblé sur `TransitCitymapperUITests` :

| Vérification | Résultat |
|---|---|
| Compilation simulateur | verte après trois corrections de pont Swift (coordonnées Kotlin optionnelles, ombrage de `header` dans le saut) |
| Kotlin | 310 tests JVM et 262 tests simulateur, aucun échec |
| Tests Swift | 124 tests, aucun échec |
| Écran et bandeau | données vertes (4 segments, 1 course, 4 prochains départs, fixture=1), mais l'assertion « Scheduled » cherchait ce mot dans les cartes alors que la seule course de la fixture est Live ; le test lit maintenant aussi les libellés du bandeau. Correctif non rejoué |
| Lignes à proximité | vert : 3 lignes, 3 rangées, capture `transit-trip-nearby.png` |
| Laisser passer | vert : bandeau 4 puis 3, itinéraire conservé, 2 options, capture `transit-trip-skip.png` |
| Changement d'heure | requête et options produites (`shift=1`, 2 options), mais l'assertion sur le libellé de la requête a échoué : la section des nouvelles options était hors de l'écran et n'était pas encore défilée. Le test défile maintenant avant de lire la section ; ce correctif de test n'a pas été rejoué faute de budget Mac |
| Écran et décalage, captures | `transit-trip.png` et `transit-trip-shift.png` manquantes pour la même raison ; la capture est prise avant les assertions au prochain run |
| Scénario en direct | ignoré : le planificateur n'a pas renvoyé de trajet pendant ce run ciblé, donc il n'a pas été compté comme échec |

Trois lancements Mac ont été consommés en corrections de pont Swift avant ce run vert de compilation. Le prochain run doit confirmer les deux scénarios corrigés et produire les deux captures manquantes. Deux scénarios sur cinq étaient verts à ce run (lignes à proximité et laisser passer), deux rouges sur des assertions de test, un ignoré faute de trajet en direct.

## Lot T-2, première partie : atteignabilité, lignes et alternatives

Cette partie livre les données et l'écran transport de T-2. Le branchement carte est préparé mais
pas posé : `MapController.swift`, `MapScreen.swift` et les autres fichiers de `Map/` appartiennent à
d'autres lots. Les deux fichiers `TransitLinesLayer.swift` et `TransitReachOverlay.swift` sont neufs
et n'appellent rien tant que la carte ne les branche pas.

### Ce que l'API renvoie réellement

L'ancien plan citait `/api/v6/one-to-all` et `/api/v6/map/trips`. Ces chemins n'existent pas sur
l'instance publique : les réponses capturées le 2026-10-28 viennent de `/api/v1/one-to-all` et de
`/api/v1/map/trips`. Les formes réelles diffèrent aussi de l'ancien plan :

- `one-to-all` accepte `one=lat,lng`, `maxTravelTime` en minutes, `time` et `arriveBy`. La réponse a
  un objet `one` (nom, coordonnée, heure) et un tableau `all` ; chaque entrée porte `place` (nom,
  `stopId`, latitude, longitude, fuseau, `arrival`, `vertexType`, `modes`), `duration` en minutes et
  `k`, le nombre de correspondances. Une capture de 10 minutes autour du Ferry Building contient 323
  entrées, dont beaucoup de quais du même arrêt. Aucun polygone n'est renvoyé.
- `map/trips` renvoie un tableau de tronçons, pas un objet. Un tronçon porte `trips` (au moins
  `tripId` et `routeShortName`), `mode`, parfois `routeColor` (hexadécimal sans dièse, par exemple
  `73d700`), `from` et `to` avec leur nom et leur coordonnée, `departure`, `arrival`,
  `scheduledDeparture`, `scheduledArrival`, `realTime` et `polyline`. La précision de la polyligne
  est celle demandée par `precision` (4 à 6), pas un champ de la réponse. Une capture de cinq
  minutes dans le milieu de Berlin donne 44 tronçons, 33 groupes ligne et direction, 19 couleurs
  d'agence et 9 tronçons marqués temps réel.
- Aucune position de véhicule, aucun identifiant de véhicule et aucune prévision de retard par
  véhicule ne figurent dans ces réponses. Vela n'en invente pas.
- `plan` accepte `via=<stopId>` et rien d'autre : une coordonnée `via=lat,lng` répond 404
  (`unknown feed id`). Une recherche Ostkreuz vers Hauptbahnhof avec `via` sur Alexanderplatz
  renvoie bien trois itinéraires qui passent par cet arrêt. L'identifiant est donc résolu d'abord
  par nom avec `map/stops`, puis envoyé tel quel.

### Atteignabilité

`Transitous.oneToAll` transforme la réponse en arrêts atteignables avec leur temps de trajet et
leur nombre de correspondances. `TransitReach` en construit une zone : les arrêts dans le budget,
puis une enveloppe convexe de leurs points. La carte reçoit cette enveloppe et les points ; elle ne
reçoit pas de polygone officiel, car l'API n'en fournit pas. L'enveloppe peut donc couvrir un bloc
ou une baie entre deux arrêts que le service n'a pas atteints. L'écran écrit « A hull drawn around
the stops Transitous reached, not an official isochrone polygon. »

Le budget est plafonné entre 5 et 60 minutes. L'écran propose 10, 20, 30 et 45 minutes et ne lance
la requête qu'au toucher de « Show reachable area ». Une seule requête à la fois, pas de boucle, et
une réponse identique (même point arrondi au dix-millième, même budget) est servie depuis le cache
pendant cinq minutes.

### Lignes, couleurs et retards

`Transitous.mapTrips` plafonne à 800 tronçons, ne garde que les modes bus, tram, métro, train et
ferry, et regroupe par `routeShortName` et destination `to.name`. Une ligne garde sa `routeColor`
quand elle existe ; sinon `TransitLiveLines` prend la couleur du mode, et l'écran dit « Vela mode
color ». La couleur d'agence n'est jamais présentée comme une couleur Vela.

Le retard d'une ligne est la médiane des écarts des tronçons qui portent à la fois une heure
prévue, une heure réelle et `realTime`. Sans ces deux heures, le retard reste nul et l'écran écrit
« No delay data » : aucune couleur n'est posée sur une absence. Les bandes sont vert sous 2 minutes,
ambre de 2 à 5, rouge au-delà de 5 ; un passage en avance est jugé sur sa distance à l'horaire, pas
sur son signe. Le badge « Live » n'apparaît que si `realTime` vaut vrai pour la ligne.

### Alternatives dans un trajet

Deux chemins, tous les deux affichés comme un nouvel ensemble d'options au-dessus du trajet qui
garde ses propres heures :

- par arrêt intermédiaire : `TransitAlternatives` propose les arrêts intermédiaires de la course
  choisie ; l'identifiant porté par le trajet est utilisé s'il existe, sinon le nom est résolu par
  `map/stops` autour de la coordonnée de l'arrêt, puis `planVia` envoie `via` ;
- par départ décalé : `TransitTrip.shift` de T-3 est réutilisé tel quel, donc les actions « Leave
  later » et « Arrive by » gardent le même calcul et la même feuille de détail.

Choisir une option via adopte l'itinéraire dans l'écran de trajet et dans la feuille de détail. La
feuille d'itinéraire de T-3 passe par `RouteStore`, qui n'a pas de champ `via` ; quand l'option est
déjà dans la liste du magasin, `RouteStore.select` est appelé, sinon les deux surfaces adoptent le
même objet et une recherche ultérieure le remplace. Aucune option n'est construite sans heure
départ ni heure d'arrivée renvoyées par le planificateur.

### Politique de 720 requêtes et comportement de l'application

La page publique de Transitous demande de coordonner tout usage de plus de 720 requêtes par 24 h
pour `/plan`, `/one-to-all` et `/one-to-many`. Vela compte ses propres appels dans
`TransitRequestBudget`, partagé par ces trois usages :

- une action utilisateur, une requête ; aucun minuteur et aucune boucle de rafraîchissement ;
- cache de cinq minutes pour l'atteignabilité, deux minutes pour les lignes, et fenêtre de
  `map/trips` plafonnée à dix minutes ;
- à 720 appels dans la fenêtre, le magasin refuse la requête et l'écran écrit que Vela a atteint sa
  part quotidienne ; il ne redemande rien avant la fin de la fenêtre ;
- sur un 429, la dernière réponse reste affichée avec la mention « Transitous asked Vela to slow
  down », aucun nouvel essai automatique, et les autres panneaux partagent un recul de 30 minutes ;
- une réponse absente ou invalide laisse la dernière réponse en place, sans horaire fabriqué.

### Branchement carte, une ligne

Les deux fichiers neufs n'ont besoin que d'un appel dans `MapController.styleDidLoad(_:)`, après
`routes.apply(to: style)` :

```swift
TransitOverlays.apply(to: style)
```

Puis, quand les deux états arrivent du service partagé :

```swift
TransitOverlays.set(lines: liveLines, reach: area, on: mapView.style)
```

`TransitOverlays.set` dessine une source et une couche par couleur de ligne, et l'enveloppe avec ses
points. Aucun autre fichier de carte n'est modifié par ce lot ; tant que l'appel n'est pas posé, la
carte ne montre ni lignes ni zone, et l'écran « Transit live » reste la seule preuve visuelle.

### Vérifications

Sous Linux, la commande de T-1 reste la même et passe : les tests `:core-common:jvmTest` et
`:ios-shared:jvmTest`, plus `:ios-shared:compileKotlinIosSimulatorArm64`.

Tests JVM ajoutés, tous hors réseau :

- `TransitousOneToAllTest` : 149 arrêts de la capture de Berlin, temps dans le budget, tri, absence
  d'horaire inventé, bornes 5 et 60 minutes de l'URL, réponse changée refusée ;
- `TransitousMapTripsTest` : 33 groupes ligne et direction sur 44 tronçons, couleur `#73d700`
  conservée, couleur absente laissée nulle, retard de 3 minutes, retard nul d'un passage à l'heure,
  absence de retard sans `realTime`, plafond de tronçons, URL ;
- `TransitousViaTest` : arrêt résolu par nom dans `map/stops`, nom inconnu refusé, `via` encodé
  comme identifiant d'arrêt, plan capturé passant par Alexanderplatz avec son `stopId` conservé ;
- `TransitReachTest` : enveloppe convexe, points alignés refusés, filtrage par budget, cache de cinq
  minutes, une requête par action, budget quotidien, 429 qui garde la dernière zone ;
- `TransitDelayTest` : bandes 2 et 5 minutes, couleur de mode quand `routeColor` manque, badge Live
  seulement sur `realTime`, compteurs de l'état, cache de deux minutes, fenêtre plafonnée, 429 ;
- `TransitAlternativesTest` : arrêts intermédiaires, extrémités et heure de la requête, options
  seulement depuis la réponse, départ décalé T-3, index de sélection, `via` envoyé comme `stopId`,
  résolution par nom avant le plan, trajet sans extrémités refusé.

Scénarios interface, `TransitAdvancedUITests`, sur la fixture `-VelaTransitFixture` et
`-VelaTransitAdvancedFixture` :

- `testIsochroneAndColoredLines` : 14 arrêts atteignables et une enveloppe d'au moins trois
  sommets depuis la capture de San Francisco, huit lignes dont cinq couleurs d'agence depuis la
  capture de Berlin, captures `transit-isochrone.png` et `transit-lines.png` ;
- `testLiveTripBadgeOnlyWhenRealTime` : cinq lignes marquées temps réel sur huit, une ligne
  `Scheduled` sans badge Live, capture `transit-live.png` ;
- `testLineDelayColors` : au moins une ligne verte, une ambre et une rouge, retard écrit en toutes
  lettres, capture `transit-delay.png` ;
- `testViaAlternativeInsideTrip` : course K, « Via », un arrêt intermédiaire, un ensemble d'options
  marqué « display only », capture `transit-via.png`.

Les fixtures complètes sont les réponses capturées de `TransitFixtures` dans `core-common`, à côté
des tests. Les valeurs de l'interface sont un extrait documenté de deux captures du 2026-10-28
(`one-to-all` à San Francisco, `map/trips` à Berlin) ; aucun délai, aucune couleur et aucun drapeau
temps réel n'y est inventé. Les tests JVM et les scénarios interface tournent donc sur fixture, pas
sur le flux. Une passe réelle reste à faire sur iPhone.

### Résultat du runner macOS (T-2)

Deux runs ciblés sur `TransitAdvancedUITests`, tous deux en avant-plan.

Run `t2-transit-20261028-110926-13839` : compilation simulateur verte, Kotlin vert, trois scénarios
sur quatre verts. `transit-isochrone.png`, `transit-lines.png`, `transit-live.png` et
`transit-delay.png` sont produits avec 14 arrêts atteignables, une enveloppe de 6 sommets, 8 lignes
dont 5 couleurs d'agence, 5 lignes temps réel sur 8 et 2 lignes vertes, 2 ambre, 1 rouge. Le
scénario via échoue sur la recherche du contrôle d'arrêt intermédiaire : le bouton portait
`.accessibilityElement(children: .ignore)` et n'était plus publié comme bouton. Le run n’a pas rapporté le nombre d’arrêts avant l’échec ; le correctif retire cette agrégation et interroge tout descendant.

Run `t2-transit-20261028-115354-27621` : les trois mêmes scénarios verts, et le scénario via va
jusqu'au bout des données, avec `viacand=3` et `via=2` dans la ligne de debug. Il échoue sur la seule
recherche du texte de requête : l'identifiant posé sur le conteneur de la section via repliait le
libellé dans un élément combiné, le même défaut que T-3 avait rencontré sur ses options. Le
correctif retire l'identifiant du conteneur et prend la capture avant l'assertion ; il n'a pas été
rejoué, faute de budget Mac. `transit-via.png` manque donc encore.

Après ces deux runs, les tests Kotlin locaux comptent 1008 cas JVM pour `:core-common` (aucun
échec) et 451 pour `:ios-shared` (aucun échec), plus la compilation du simulateur iOS. Le prochain
run Mac doit confirmer `transit-via.png` et le libellé de la requête via.

### Tests humains sur iPhone

1. Depuis un trajet, ouvrir « Live map », choisir 20 minutes et toucher « Show reachable area » :
   vérifier les arrêts, leur temps, l'enveloppe et la mention qu'elle n'est pas officielle.
2. Toucher « Live lines » : vérifier la couleur d'agence, la couleur de mode annoncée comme telle,
   les badges Live et Scheduled, et les trois bandes de retard.
3. Couper le réseau puis relancer une des deux actions : la dernière réponse doit rester, avec la
   mention d'échec, sans nouvel essai automatique.
4. Sélectionner une course, « Via », choisir un arrêt intermédiaire, puis une option : vérifier que
   l'écran de trajet et la feuille de détail montrent le même itinéraire.
5. Avec VoiceOver et un texte jusqu'à AX3, parcourir les deux onglets : chaque ligne doit dire sa
   direction, Live ou Scheduled, et son retard en mots.

## Modes et itinéraire complet (TRANSIT-MODES)

Signalé sur l'iPhone : la feuille d'un itinéraire ne montrait pas les modes de transport et semblait
s'arrêter au premier trajet avant la correspondance. La reproduction sur une vraie réponse
Transitous (Paris, Hôtel de Ville vers La Défense, deux courses avec correspondance à Charles de
Gaulle - Étoile) donne cinq jambes dans l'ordre : marche, Métro 1 (RATP), marche de correspondance,
RER A (RER), marche finale. Le parseur les rendait déjà toutes les cinq, avec leur mode brut :
`WALK`, `SUBWAY`, `WALK`, `REGIONAL_RAIL`, `WALK`. Le défaut était donc à l'affichage, pas dans les
données :

- la feuille de détail n'affichait jamais le mode : son titre était « towards <direction> », ou
  « Ride » sans direction, et la pastille ne portait que le numéro de ligne. Les modes `TRAM`,
  `BUS`, `SUBWAY` et `TRAIN` étaient donc invisibles sur les deux trajets ;
- les arrêts intermédiaires du premier trajet étaient tous dépliés. Avec neuf arrêts sous le Métro
  1, la première course occupait à elle seule la feuille limitée à 62 % de l'écran, et la
  correspondance, le RER et la marche finale restaient sous le pli sans vue d'ensemble ;
- aucune ligne ne disait le point de correspondance ni le temps d'attente entre l'arrivée et le
  départ suivant.

La table des modes est maintenant centrale (`TransitLegMode`, Swift) : `WALK` marche, `BUS` bus,
`TROLLEYBUS` bus, `COACH` car, `TRAM` tram, `SUBWAY`/`METRO` métro, `RAIL` et ses variantes
(`REGIONAL_RAIL`, `HIGHSPEED_RAIL`, `LONG_DISTANCE`, `NIGHT_RAIL`) rail, `FERRY` ferry,
`CABLE_CAR`/`AERIAL_LIFT`/`GONDOLA` téléphérique, `FUNICULAR` funiculaire. Un mode absent ou
`GENERIC` affiche « Transit » et n'invente aucun véhicule. Le titre lit la ligne et l'agence du
planificateur : « Bus 38 », « M2 », « Tram K », « RER B », « Coach 15 ». Chaque carte de jambe
montre le glyphe du mode, ce titre lisible, puis le nom du mode et l'agence quand elle ajoute une
information (« Metro · RATP »).

Le planificateur envoie désormais, par jambe, son nom de mode brut, l'agence de la jambe et ses
deux horloges. Ces champs sont additifs (`TransitStep.modeName`, `agencyName`, `departEpochSec`,
`arriveEpochSec`) : `plan`, `board` et `stopTimes` gardent leur signature et leur sortie, et un
champ absent reste nul. La feuille de détail ajoute une bande « Whole trip » avec la séquence
complète (« Walk · M1 · Walk · RER A · Walk »), replie les arrêts intermédiaires derrière un bouton
« N intermediate stops », et insère une ligne de correspondance au point de changement avec les
minutes d'attente calculées sur les horloges du flux : trois minutes entre l'arrivée du Métro 1 et
le départ du RER A dans la fixture. Quand le flux ne donne pas les heures, la ligne dit seulement
le point de correspondance, sans estimation.

L'écran de trajet T-3 garde ses cartes par segment, la distinction Live/Scheduled et les couleurs
de retard. Ses cartes de course lisent le même mode et la même agence, la carte d'attente affiche
« N min wait », et ses ensembles d'options montrent la séquence de glyphes du trajet entier, pas
seulement les lignes. La feuille de détail et l'écran de trajet lisent le même itinéraire : aucune
requête Google ou Transitous supplémentaire n'est faite.

### Fixture et tests

La réponse réelle est versionnée deux fois, à l'identique : `iosApp/Vela/Transit/Fixtures/paris-transfer-plan.json`
pour le bundle de l'application (scénario Debug) et `core-common/src/jvmTest/resources/transitous/plan-paris-transfer.json`
pour le test JVM. Elle ne sert qu'aux tests et au scénario `-VelaTransitTransfer`.

- `TransitousParisTransferTest` (JVM) : cinq jambes dans l'ordre, noms de mode bruts, agences RATP
  et RER, marche de correspondance de 2 minutes, attente de 3 minutes entre l'arrivée du métro et
  le départ du RER ;
- `TransitTripModesTest` (ios-shared) : les cartes T-3 gardent le mode et l'agence, la carte
  d'attente porte ses minutes, la marche de correspondance garde sa carte ;
- `TransitModeTests` (XCTest) : table des modes (bus, métro, tram, rail RER, car, ferry,
  téléphérique, funiculaire, générique), titres, glyphes distincts, ordre des cinq jambes et
  attente de transfert ;
- `TransitModesUITests.testAllLegsAndModes` : scénario `-VelaTransitFixture -VelaTransitTransfer`,
  captures `transit-modes.png` et `transit-transfer.png`, lignes `transit_legs=5`,
  `transit_modes=walk,metro,walk,rail,walk`, `transit_transfer=1`.

Le bouton « Legs » qui ouvre la feuille de détail dans ce scénario n'existe qu'en Debug et seulement
sous `-VelaTransitFixture` : en production la feuille reste ouverte par le choix d'itinéraire.

### Reste à faire

- La passe réelle sur iPhone avec une vraie recherche à correspondance (Paris ou Lyon) reste à
  faire : la fixture prouve l'affichage, pas la couverture réseau.
- Le choix d'itinéraire (Routes/) garde ses pastilles existantes : il affiche déjà toutes les
  jambes par ses glyphes de mode, mais son libellé de course n'est pas encore passé à
  `TransitLegMode`. Le faire dans un lot Routes/ éviterait un conflit d'écriture.
- VoiceOver annonce le titre et le nom du mode de chaque carte ; une revue avec un lecteur d'écran
  réel sur la nouvelle ligne de correspondance reste à faire.

### Résultat du runner macOS (TRANSIT-MODES)

Run `transit-modes-20261028-184626-17169`, avant-plan, `VELA_ONLY_UI=TransitModesUITests,TransitCitymapperUITests`
et `VELA_SKIP_ARCHIVE=1` : compilation simulateur verte, `VelaTests` 156 cas et 0 échec,
`TransitCitymapperUITests` 5 scénarios verts, `TransitModesUITests.testAllLegsAndModes` vert en
19 s. Le résumé publie `transit_legs=5`, `transit_modes=walk,metro,walk,rail,walk`,
`transit_transfer=1`. Les captures `transit-modes.png` et `transit-transfer.png` sont sur la
branche `results`, sous ce tag.

Deux échecs utiles ont précédé ce run. Le premier venait de `transit-detail-open` absent : fermer
le choix d'itinéraire publiait un état qui remettait `detail` à zéro, alors que la fixture venait
de le remplir. Le second venait des identifiants de mode à zéro : un identifiant posé sur le
conteneur de la carte de jambe republiait tous ses enfants sous cet identifiant et masquait
`transit-detail-mode`. Les deux correctifs sont dans `TransitModel` et `TransitDetailSheet`.

## Lot TRANSIT-INTERP : véhicules estimés entre deux arrêts

Ce lot dessine la position estimée de chaque véhicule en service quand le flux porte des heures
réelles. Il ne change pas la limite posée par T-2 : Transitous ne publie aucune position GPS, aucun
identifiant de véhicule et aucune prévision par véhicule. Le point affiché est calculé par Vela à
partir des heures réelles et de la polyligne du tronçon, et il est présenté partout comme une
estimation, jamais comme une mesure.

### Données conservées

`Transitous.mapTrips` regroupait les tronçons par ligne et destination et perdait les heures de
chaque tronçon. Le parseur garde maintenant, en plus, une liste `runs` de tronçons entiers :
identifiant de course, ligne, mode, couleur d'agence, arrêt de départ et arrêt suivant avec leurs
coordonnées, heures prévues et réelles de départ et d'arrivée, drapeau `realTime` et polyligne.
`MapTripsReply.runs` est un champ additif ; `MapTripLine` et les champs existants ne changent pas.
`Transitous.parseMapTripRuns` expose le même résultat aux tests.

### Formule d'interpolation

Pour un tronçon marqué `realTime` et muni d'une heure de départ réelle :

- la durée est `arrivée réelle - départ réel` ; si l'arrivée réelle manque, Vela prend l'arrivée
  prévue décalée du retard observé au départ ;
- la fraction est `(maintenant - départ) / durée`, bornée à `[0, 1]` ;
- la position est le point à cette fraction de la longueur cumulée de la polyligne, entre le
  sommet le plus proche de l'arrêt de départ et le sommet le plus proche de l'arrêt suivant. Les
  sommets dessinés avant ou après la paire d'arrêts sont donc ignorés, et une polyligne tracée
  dans l'autre sens est parcourue depuis le départ ;
- le cap du glyphe est le relèvement entre le point et un point légèrement plus loin sur la même
  chaîne.

Un tronçon sans `realTime`, sans heure de départ, sans arrivée exploitable ou dont la durée est
nulle ne produit aucun marqueur. Avant le départ et après l'arrivée, aucun marqueur n'est produit :
le véhicule est alors sur un autre tronçon de la même course. Si deux tronçons de la même course
se chevauchent, le départ le plus récent gagne.

### Limites

- la vitesse est supposée constante entre les deux arrêts ; une course arrêtée à un feu avance donc
  dans le dessin alors que le véhicule réel est immobile ;
- la polyligne vient du flux et peut être simplifiée ; le point est aussi précis que ce tracé ;
- une heure réelle manquante, un arrêt sans heure ou un `realTime` faux retire le marqueur au lieu
  d'inventer une position depuis l'horaire théorique ;
- le flux ne donne pas de nom de course ni de véhicule : la direction affichée est l'arrêt suivant
  du tronçon ;
- la couverture temps réel reste inégale, et la fenêtre `map/trips` est plafonnée à dix minutes
  comme pour T-2.

### Lissage sans requête supplémentaire

Le panneau allume un minuteur de 20 secondes seulement quand l'interrupteur « Show vehicles » est
actif. Chaque battement recalcule les points depuis les tronçons déjà en mémoire et l'horloge ;
aucune requête ne part de ce battement. Une nouvelle requête `map/trips` n'est possible qu'après
la fenêtre de quatre minutes du magasin, soit 360 appels par jour pour une vue laissée ouverte,
sous la limite de 720. Le minuteur s'arrête quand le calque est coupé ou quand l'application passe
en arrière-plan. La couche carte reçoit les nouveaux points au même rythme et les redessine.

### Branchement carte

`TransitLinesLayer.apply(to:)` installe la couche des véhicules sur la même passe de style, au-dessus
des couches `vela-transit-line` et sous les libellés. Ce fichier ne change que par cet appel
documenté. Les données arrivent par :

```swift
TransitVehicleOverlays.set(models: vehicleModel.vehicles, on: mapView.style)
```

appelé quand le modèle publie de nouveaux points. `MapController.styleDidLoad` n'a rien de plus à
poser que l'appel `TransitOverlays.apply(to: style)` déjà prévu par T-2. La couche est une couche
symbole en mémoire, avec un disque coloré et un chevron orienté par le cap ; elle ne fait aucune
requête et reste donc utilisable dans une région téléchargée.

### Vérifications

Sous Linux, la commande de T-1 reste la même et passe : `:core-common:jvmTest`,
`:ios-shared:jvmTest` et `:ios-shared:compileKotlinIosSimulatorArm64`.

Tests JVM ajoutés :

- `TransitVehiclesTest` : milieu de tronçon, avant le départ, après l'arrivée, absence de
  `realTime`, arrêt sans heure, arrivée réelle absente remplacée par l'arrivée prévue décalée,
  saut de sommets de polyligne, polyligne inversée, chaîne dégénérée, une seule position par course
  courante, extrémités sur les deux arrêts ;
- `TransitousMapRunsTest` : un tronçon conservé par tronçon accepté, heures et couleur de la course
  S7 en temps réel, tronçon théorique gardé avec son drapeau faux, plafond appliqué, réponse
  invalide sans tronçon.

Scénario interface `TransitVehiclesUITests.testInterpolatedVehicles` sur la fixture
`-VelaTransitVehicleFixture` : l'onglet « Vehicles » du panneau temps réel, l'interrupteur, quatre
véhicules estimés, `vehicles_count`, `vehicles_estimated=1`, `vehicles_live_times`, et la capture
`transit-vehicles.png`. Chaque rangée porte « estimated from live times, not GPS » dans son libellé
VoiceOver.

### Tests humains sur iPhone

1. Ouvrir « Live map », puis l'onglet « Vehicles » et activer « Show vehicles » sur une zone avec
   du temps réel : vérifier la pastille de ligne, la direction, l'arrêt suivant et le mot
   « Estimated ».
2. Laisser le panneau ouvert deux minutes : les points doivent avancer sans nouvelle requête, et le
   compteur de requêtes du journal de débogage ne doit pas bouger à chaque battement.
3. Couper le calque, puis passer l'application en arrière-plan : aucune requête ne doit partir.
4. Avec VoiceOver, parcourir les rangées : chacune doit dire la ligne, la direction, l'arrêt
   suivant et « estimated from live times, not GPS ».
5. Couper le réseau : la dernière estimation doit rester, avec la mention d'échec, et aucun point
   ne doit être fabriqué depuis l'horaire théorique.

### Réparation de fusion rencontrée pendant la vérification

Le merge SAV-MARK de `ios/main` avait laissé trois trous qui empêchaient toute compilation Swift,
y compris celle de ce lot : `MapSavedMarkers.swift` était vide alors que `MapController` instanciait
`SavedMarkerLayer` et `SavedShapeLayer`, `SavedStore` n'exposait plus `mapPins()` et `mapShapes()`
au niveau du magasin, et l'initialisation de `MapController` lisait `savedStore` avant de l'avoir
posé. Ce lot restaure le contenu de `MapSavedMarkers.swift` déjà écrit sur la branche map-tap,
ajoute les deux passages de `SavedStore` vers `SavedState` et déplace une ligne d'initialisation.
Ces changements ne touchent pas l'interpolation et doivent se résoudre sans conflit dans le merge
SAV-MARK.

### Résultat du runner macOS (TRANSIT-INTERP)

Run `transit-interp-20261028-214039-2108`, en avant-plan : notices vertes, Gradle vert en 646 s,
525 tests JVM pour `core-common` et 429 tests simulateur pour `ios-shared`, 151 tests unitaires
iOS sans échec, puis le scénario interface vert en 46,5 s. Il rapporte `vehicles_count=4`,
`vehicles_estimated=1` et `vehicles_live_times=4`, et produit `transit-vehicles.png` : l'onglet
« Vehicles » montre les quatre lignes S7, U2, M4 et 100, la mention « Estimated » sur chaque
rangée, le texte « estimated from live times, not GPS » et la légende sur l'absence de GPS.

La couche carte elle-même n'est pas vérifiable par XCTest sans le branchement de `MapController` ;
les tests Kotlin possèdent la géométrie, et la capture prouve les données et le libellé. Une passe
réelle sur iPhone reste à faire pour voir les pastilles se déplacer sur la carte.

## Lot TRANSIT-WIRE : ce qui est maintenant branché

Ce lot ne livre aucun écran neuf. Il pose les appels qui relient les quatre lots précédents :
l'accroche de ligne sur cinq surfaces, le dessin d'une ligne entière en couleur sur la carte,
l'interpolation des véhicules sur la même passe de style et le bouton GO dans la carte de guidage.

### Carte

`MapController.styleDidLoad` appelle `TransitOverlays.apply(to: style)` juste après
`routes.apply(to: style)`, puis `TransitVehicleOverlays.apply(to: style)`. Une seule passe par objet
de style est retenue par `ObjectIdentifier`, donc un rechargement de style réinstalle les couches une
fois, et une nouvelle passe ne les empile pas. Les deux couches restent sous les libellés de la
carte, comme `TransitLinesLayer` les insère déjà : la carte est sous les panneaux SwiftUI et les
couches ne prennent aucun toucher.

`MapController` écoute la notification `.velaTransitLineMapRequest` publiée par la fiche de ligne.
Le tracé du flux est dessiné quand il a au moins deux points, sinon la chaîne d'arrêts, avec la
couleur déjà résolue par la fiche. C'est la première fois que « See the whole line on the map »
change la carte.

Deux méthodes sont la couture posée pour les modèles du panneau temps réel :
`showTransitLive(_:reach:)` appelle `TransitOverlays.set(lines:reach:on:)` et
`showTransitVehicles(_:)` appelle `TransitVehicleOverlays.set(models:on:)`. Elles acceptent un style
absent et gardent les descripteurs pour la passe suivante.

### Accroches de ligne

- **Tableau d'arrêt** : la carte d'une ligne et ses départs ouvrent la fiche par
  `TransitLineLink.shared.open(line:direction:stop:)`. `TransitBoardState` porte le nom et la
  coordonnée de l'arrêt mais pas son identifiant Transitous : la fiche résout donc le tableau par
  proximité, ce que `TransitLineStopRef` documente déjà. Aucune valeur n'est inventée.
- **Détail d'itinéraire** : un bouton par jambe roulée, `transit-detail-line`, ouvre la ligne à
  l'arrêt de montée. L'identifiant et la coordonnée viennent de la jambe du planificateur, lue par
  l'index de la jambe ; une jambe sans l'un ni l'autre n'ouvre rien.
- **Carte de segment d'un trajet** : un bouton `transit-trip-line-link` par course, avec la
  coordonnée de montée du segment. Il est séparé du geste de sélection pour que « Leave later »,
  « Arrive by » et « Skip this one » gardent exactement le comportement de T-3.
- **Lignes à proximité** : une rangée ouvre la même fiche à l'origine du trajet.
- **Recherche** : aucun `SearchRow` ne porte de nom de ligne ni d'identifiant d'arrêt. Les résultats
  d'arrêt et de ligne de la recherche unifiée ouvrent déjà le tableau, dont les rangées sont la
  première accroche : la recherche atteint donc la fiche par le tableau, comme le prévoyait
  `TRANSIT-DESIGN.md`.

### GO

`TransitGuidanceCard` monte `TransitGoButton(model:)` entre « Trip » et « End ». Le bouton présente
l'écran GO et ses quatre commandes sur l'itinéraire déjà sélectionné.

### Ce qui reste à brancher

- `TransitGoButton` n'a pas de paramètre `vehicleHint` : l'écran GO accepte l'estimation du calque
  véhicules, mais le bouton ne peut pas la transmettre. Il manque un paramètre au bouton et un
  modèle de véhicules partagé par la carte et la fiche.
- Le panneau temps réel crée ses modèles dans ses propres vues. `showTransitLive` et
  `showTransitVehicles` existent, mais `TransitLiveModel` et `TransitVehicleModel` ne les appellent
  pas encore : une ligne d'appel dans chaque `apply` du modèle reste à poser. Tant qu'elle manque, la
  carte ne dessine pas les lignes du panneau ni ses véhicules ; seule la ligne demandée par la fiche
  est dessinée.
- `TransitBoardState` n'expose pas l'identifiant de l'arrêt : le tableau est résolu par proximité.
  Publier `boardStopId`, `boardLat` et `boardLng` dans `TransitModel` supprimerait cette résolution.
- Aucun registre de toucher n'existe dans `MapController` : `handleTap` interroge une liste fixe
  d'identifiants (`poi_*`, `RouteLayers.altLayer`). Les couches de transport sont additives et ne
  sont jamais interrogées, donc MAP-TAP n'est pas modifié ; il n'y a pas de point d'enregistrement
  à utiliser.

### Vérifications

Sous Linux, la commande de T-1 passe : `:core-common:jvmTest`, `:ios-shared:jvmTest` et
`:ios-shared:compileKotlinIosSimulatorArm64`.

Scénario interface `TransitWiredUITests.testTapTransitEverywhereAndSeeTheLine`, sur les fixtures
uniquement : tableau hors ligne à Ferry Building, fiche de ligne K enregistrée, trajet de San
Francisco et véhicules de Berlin. Il ouvre une ligne du tableau, un de ses départs, le bouton de
ligne d'un segment, une ligne voisine et GO, puis l'onglet Vehicles. Captures
`transit-wired-line.png`, `transit-wired-go.png` et `transit-wired-vehicles.png`, lignes
`wired_line=1`, `wired_go=1`, `wired_vehicles=<n>`.

### Résultat du runner macOS

Run `transit-wire-20261028-234454-7929`, en avant-plan, ciblé sur `TransitWiredUITests`,
`TransitCitymapperUITests` et `TransitLineViewUITests`.

| Vérification | Résultat |
|---|---|
| Compilation simulateur | verte, 172 tests unitaires iOS sans échec |
| Kotlin | 589 tests JVM pour `core-common` et 488 tests simulateur pour `ios-shared`, aucun échec |
| `TransitLineViewUITests` | vert, `transit-line.png` et `transit-line-ribbon.png` produits |
| `TransitCitymapperUITests` | quatre scénarios de fixture verts, dont `transit-trip.png` et `transit-trip-nearby.png` |
| `TransitCitymapperUITests` en direct | rouge sur le bouton « Trip view » du détail, hors écran à `y=875` dans ce run réseau ; le scénario ne touche aucune accroche de ce lot |
| `TransitWiredUITests` | rouge sur `app.otherElements["transit-board"]` : l'identifiant est porté par un `ScrollView`, pas par un `Other`. Le tableau était bien ouvert et chargé derrière la fiche de ligne |

Le scénario corrigé lit le tableau par `descendants(matching: .any)`. Le run de confirmation
`transit-wire-20261029-002131-24451` a été demandé, puis aucun `STATUS` n'a été publié pendant plus
de deux heures alors que la file ne contenait plus de demande : il est perdu, et les captures
`transit-wired-*.png` et les lignes `wired_*` restent à produire au prochain run vert.

### Tests humains sur iPhone

1. Depuis un tableau d'arrêt réel, toucher une ligne puis un départ : la fiche s'ouvre sur la ligne,
   la direction et l'arrêt touchés ; la fermer ramène au tableau.
2. Dans le détail d'un itinéraire, toucher le bouton de ligne d'une jambe roulée : la fiche s'ouvre
   sur l'arrêt de montée du planificateur.
3. Dans l'écran de trajet, toucher « Open line K » sur une course, puis une ligne de l'onglet voisin.
   Vérifier que la sélection de segment et « Leave later » n'ont pas changé.
4. Toucher « See the whole line on the map » dans la fiche : la ligne apparaît sur la carte dans sa
   couleur, au-dessus des tracés de route et sous les libellés. Toucher la carte ensuite : MAP-TAP
   ouvre toujours le même objet sous le doigt.
5. Toucher GO dans la carte de guidage : l'écran s'ouvre sur l'action courante, puis « Close » rend
   la carte et la session intactes.
6. Avec VoiceOver, parcourir une rangée de tableau et une jambe : l'action « Open the line » est
   annoncée, les cibles font 44 pt.
