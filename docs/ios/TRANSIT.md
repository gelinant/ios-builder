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
