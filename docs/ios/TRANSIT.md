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
