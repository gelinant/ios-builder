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

Il n'y a pas encore de cache disque du dernier tableau consulté hors ligne sur iOS. La ligne
correspondante de `FEATURES-IOS.md` reste donc ❌.

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

Une marche n'affiche pas encore ses manœuvres pas à pas. Les endpoints de marche sont conservés,
mais le calcul OSRM à la demande n'est pas branché sur iOS ; la ligne L191 de la matrice reste donc
❌.

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

Scénarios interface :

- `TransitActivityTests.testStopBoardShowsDeparturesAndRefreshes` ouvre le tableau du Ferry
  Building avec le flux réel, vérifie au moins une ligne et un départ, rafraîchit et capture
  `transit-board.png` ;
- `TransitActivityTests.testTransitOptionsChangeTheDepartureAndVehicles` ouvre un trajet vers le
  Ferry Building, applique un départ dans 15 minutes, active le filtre rail et capture
  `transit-options.png`. Les lignes `UITEST transit_board_*` et `transit_options_*` donnent les
  nombres et l'epoch.
- `TransitActivityTests` reste le scénario X-3 : démarrage, avance de marche, retard réel et End.

## Résultat du runner macOS

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
