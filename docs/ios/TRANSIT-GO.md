# Guidage transport GO (TRANSIT-GO)

Ce lot ajoute un écran de guidage pas à pas inspiré du GO de Citymapper, avec les assets et les
textes de Vela. Il ne remplace ni la carte de guidage compacte, ni la Live Activity X-3, ni l'écran
de trajet T-3. Il répond à une seule question pendant un trajet : quelle est l'action maintenant,
et quand faut-il descendre.

## Ce que l'écran montre

La moitié haute est une seule action, en grand :

- « Walk 4 min to République » avant la montée ;
- « Take M2 towards Nation » à l'arrêt, avec la pastille de ligne dans sa couleur ;
- « Get off at Belleville in 2 stops », puis « Get off at Belleville at the next stop », puis
  « Get off now at Belleville » ;
- « Walk 2 min to the destination » à la fin ;
- « You have arrived at Belleville » après la dernière jambe.

Le compte à rebours occupe la même carte : « departing in 2 min », « now », « arrival time passed »
ou « No time ». Il est recalculé chaque seconde depuis l'epoch cible et l'horloge de l'appareil.
Aucun minuteur ne demande un nouvel horaire au flux. La carte porte aussi l'état de l'heure,
« Live », « Scheduled » ou « No time », toujours en toutes lettres.

Sous cette carte, un bandeau de descente apparaît quand la machine déclenche l'invite. Il porte le
texte, l'icône et la mention du mode d'heure. Il ne repose jamais sur la couleur seule.

La partie basse de la course montre les arrêts restants, l'arrêt passé, l'arrêt courant, le prochain
arrêt et la descente. Quand le flux fournit deux heures estimées voisines, un marqueur « Estimated »
situe la position entre les deux arrêts, avec une barre de progression orange. Sans ces deux
heures, aucun marqueur n'est dessiné. Un toucher de la rail ou du bouton « See line » ouvre la liste
des arrêts et de leurs heures. La feuille de ligne du lot TRANSIT-LINEVIEW peut remplacer cette
liste locale par le hook `onOpenLine`.

Les quatre commandes du bas reprennent la forme de Citymapper : « Next departures », « Leave later »,
« Whole trip » et « End ». Chacune fait au moins 44 pt, porte un libellé VoiceOver avec la ligne et
la direction, et garde un état lisible sans couleur. « Leave later » propose plus 5, 15 ou 30 minutes
et repasse par `RouteStore.setTime`, donc par le même planificateur que le reste de l'application.
Il ne réécrit pas l'itinéraire affiché avant qu'une nouvelle option soit choisie.

## Machine à étapes

`TransitGoMachine`, dans `TransitGoState.kt`, possède la séquence et rien d'autre. Elle part de la
première jambe de l'itinéraire sélectionné : marche, attente de la course, course, marche de
correspondance, course suivante, marche finale, arrivée. Les quatre valeurs rendues sont `walk`,
`ride`, `transfer` et `done`. Une attente avant la première course compte comme `walk` pour la
personne qui marche encore ; une attente entre deux courses compte comme `transfer`.

La session partagée peut pousser sa progression avec `sync(legIndex:passedStops:boarded:arrived:)`.
La machine ne recule jamais : un index de jambe ou un arrêt plus petit est ignoré. Sans session,
les commandes manuelles restent disponibles : « I'm on board » passe de l'attente à la course,
« Skip this step » avance d'une étape et « Next stop (preview) » n'existe qu'en Debug. Un trajet
sans heure, sans arrêt intermédiaire ou sans position reste donc utilisable.

La machine ne calcule ni itinéraire ni heure. `TransitGoPlanBuilder` traduit seulement les champs
déjà présents dans `TransitItinerary` : ligne, couleur, direction, arrêts, heures imprimées,
retard et nombre d'arrêts. Une heure imprimée est ancrée au jour de l'itinéraire dans le fuseau de
l'appareil ; une heure illisible reste zéro. Aucun arrêt et aucune heure ne sont inventés.

## Compte à rebours et honnêteté

Trois états d'heure sont distingués :

- estimate du flux quand l'itinéraire portait un couple réel et théorique et que le réseau est
  présent : l'epoch estimée est affichée, l'étiquette est « Live » ;
- horaire théorique quand le flux n'a pas donné d'estimation, quand le plan est hors ligne ou quand
  il est périmé : l'epoch théorique est affichée, l'étiquette est « Scheduled » ;
- aucune heure quand le flux n'a rien donné : « No time », et l'invite de descente reste muette.

Un plan est périmé au-delà de deux heures depuis son chargement, ou trente minutes après sa
dernière arrivée théorique. Il reste affiché, mais il perd toute étiquette Live, tout marqueur
estimé et toute invite de descente. Le bandeau dit qu'il peut être obsolète. Un plan hors ligne
garde ses étapes et ses horaires, affiche « No network. Showing the last itinerary from HH:MM » et
repasse partout à « Scheduled ». Aucun état ne mélange une heure théorique avec une étiquette Live.

## Invite de descente

Une seule invite est jouée à deux arrêts de la descente, une seule à l'arrêt. La machine les
déclenche sur le nombre d'arrêts restants, jamais sur une minuterie. Chaque invite est un motif
haptique et une phrase :

- deux arrêts avant : deux impulsions courtes et « Get off in two stops at Belleville » ;
- à l'arrêt : une notification de succès et « Get off now at Belleville ».

La voix lit les clés NAV-LIFE au moment de l'invite, dans `NavStore`, sans les posséder :
`spoken_directions` et `spoken_alerts_only`. En mode On, la phrase est prononcée par
`VelaNavVoice`, la même voix que la conduite et la marche. En mode Alerts only, le motif haptique
reste et la phrase est coupée. En mode Off, rien n'est joué, haptique compris. Un itinéraire sans
heure ou périmé ne déclenche aucune invite. Une invite déjà jouée n'est jamais répétée, même si
l'écran se redessine chaque seconde.

## Accessibilité

L'écran plafonne le texte à AX3. L'action reste une seule zone de texte, redimensionnable. Les
arrêts de la rail portent « nom, statut, heure estimée » et sont des boutons. Le bandeau de descente
est combiné en un seul élément qui commence par « Get off cue ». Les quatre commandes du bas et les
commandes manuelles font au moins 44 pt. Les états Live, Scheduled, Estimated, passé, prochain et
descente sont des mots, jamais seulement une couleur.

## Branchement

Le seul point de montage est une ligne dans `TransitGuidanceCard.swift`, à côté de Trip et End :

```swift
TransitGoButton(model: model)
```

`TransitGoButton` présente `TransitGoHostView` en plein écran. L'hôte construit le modèle depuis
`transit.activeTrip` ou, en Debug, depuis l'itinéraire de fixture, puis relie les quatre commandes
aux surfaces existantes : `TransitBoardSheet` pour les prochains départs, `RouteStore.setTime` pour
« Leave later », `TransitTripScreen` pour le trajet entier et `TransitSession.end` pour End. Il
n'édite ni `MapScreen.swift` ni `TransitModel.swift`.

Hooks facultatifs, dans cet ordre de priorité :

- `onOpenLine` : passer la feuille de ligne de TRANSIT-LINEVIEW. Sans ce hook, la feuille locale
  liste les arrêts de la course et leurs heures.
- `onNextDepartures` : remplacer l'ouverture du tableau T-1 par la surface de départs du lot de
  lignes. Sans ce hook, l'hôte ouvre `TransitBoardSheet` sur l'arrêt de montée.
- `onLeaveLater` : brancher un autre calcul de départ. Sans ce hook, l'hôte appelle
  `transit.setTimeMode(1, epochSec:)`.
- `onWholeTrip` : ouvrir une autre vue de trajet. Sans ce hook, l'hôte ouvre `TransitTripScreen`.
- `vehicleHint` : position du lot TRANSIT-INTERP. L'hôte peut le remplir ainsi, sans que ce lot
  dépende du type de l'autre :

```swift
let hint = vehicleModel.vehicles
    .first { $0.label == go.state?.line }
    .map {
        TransitGoVehicleHint(
            line: $0.label,
            fraction: $0.fraction,
            fromStop: $0.fromStopName,
            toStop: $0.nextStopName)
    }
```

`TransitGoVehicleHint` est une structure locale, donc ce lot compile sans le fichier de l'autre.
Le marqueur reste toujours « Estimated », que la position vienne du véhicule interpolé ou des
heures estimées de deux arrêts voisins.

Pour réutiliser les lignes du lot TRANSIT-LINEVIEW sans le hook, `TransitGoState` expose déjà
`line`, `colorHex`, `textColorHex`, `direction` et `stops` ; la rail et la pastille lisent ces
champs. Aucune couleur d'agence n'est recalculée par GO.

`TransitGoTestBootstrap.m` et `TransitGoTestSupport.swift` sont une couture de test Debug. Le
constructeur ObjC ne fait rien sans l'argument `-VelaTransitGoTest` ; il présente l'écran au-dessus
de l'application pour `TransitGoUITests`, car `MapScreen.swift` appartient à un autre lot.

## Tests

Tests Kotlin, `TransitGoStateTest` :

- marche, attente, montée, course, descente, correspondance et arrivée, avec les quatre valeurs
  rendues ;
- deux courses consécutives donnent `transfer` et « Skip this step » avance ;
- invite à deux arrêts puis à l'arrêt, une seule fois chacune, texte compris ;
- course sans heure : « No time », aucune invite, commandes manuelles toujours possibles ;
- hors ligne : compte à rebours théorique, aucune étiquette Live, aucun marqueur estimé ;
- plan périmé : étapes conservées, plus aucune prétention au direct, aucune invite ;
- position estimée seulement entre deux heures estimées voisines ;
- compte à rebours qui avance avec l'horloge, sans nouveau plan ;
- progression de session qui ne recule jamais ;
- construction depuis `TransitPreview.sf` avec arrêts, couleur et heures, et depuis un itinéraire
  muet sans heure inventée.

Scénario interface, `TransitGoUITests.testGoModeCuesAndRail` : la course et sa rail, l'invite à
l'arrêt, le passage à `transfer` puis `done`, et le mode dégradé. Captures `transit-go-ride.png`,
`transit-go-getoff.png` et `transit-go-degraded.png`. Lignes de rapport `go_step`, `go_estimated`
et `go_cue`.

Vérification Linux, en avant-plan :

```
source ~/opt/env.sh
flock /tmp/opencode/gradle.lock ./gradlew --no-daemon -Pvela.iosOnly=true \
  :core-common:jvmTest :ios-shared:jvmTest :ios-shared:compileKotlinIosSimulatorArm64
```

## Résultat du runner macOS

Run `transit-go-20261028-230148-11678`, ciblé sur `TransitGoUITests`, en avant-plan :

| Vérification | Résultat |
|---|---|
| Compilation simulateur | verte |
| Kotlin | 550 tests JVM et 454 tests simulateur, aucun échec |
| Tests Swift | 172 tests, aucun échec |
| Scénario GO | vert en 36 s : `go_step=ride`, `go_estimated=1`, `go_cue=none` sur la course, puis `go_cue=stop` à l'arrêt, `go_step=transfer`, `go_step=done` |
| Mode dégradé | vert : `go_estimated=0`, `go_cue=none`, bannière hors ligne |
| Captures | `transit-go-ride.png`, `transit-go-getoff.png`, `transit-go-degraded.png` |
| Statut | ok |

Le run a aussi servi à réparer deux artefacts de la fusion SAV-MARK sur `ios/main` : la couche
`MapSavedMarkers.swift` vide et l'initialisation de `savedStore` dans `MapController`. Ces deux
correctifs viennent de `ios/main` courant, fusionné dans cette branche ; ils ne changent pas le
guidage GO.

Les premiers essais de la branche se sont arrêtés sur ces artefacts de base avant d'atteindre le
code GO. Les essais suivants ont corrigé les types Int32 du pont Swift, le déclenchement trop
précoce de l'invite au démarrage du scénario, puis la disposition des quatre commandes. Le dernier
run est vert.

## Limites et risques

- L'epoch d'un arrêt vient de son heure imprimée, ancrée au jour de l'itinéraire dans le fuseau de
  l'appareil. Un trajet qui traverse un fuseau peut décaler une heure de quelques heures ; Vela ne
  prétend alors pas à une estimation live, mais l'horaire affiché reste celui du flux.
- Transitous ne fournit pas de position de véhicule. Le marqueur estimé est une interpolation entre
  deux heures du flux, ou la position du lot TRANSIT-INTERP quand il est monté. Il n'est jamais
  présenté comme une mesure.
- La feuille de ligne locale ne montre que les arrêts de la course choisie. La ligne entière demande
  le hook `onOpenLine` du lot TRANSIT-LINEVIEW.
- Le plan n'est pas persisté sur disque. « No network » conserve l'itinéraire de la session en
  cours, pas celui d'un lancement précédent ; ce dernier cas reste couvert par le cache de T-1.
- Aucune passe iPhone réelle n'a encore mesuré les deux motifs haptiques en poche, ni la voix GO en
  mode Alerts only sur un vrai appel entrant.

## Tests humains sur iPhone

1. Démarrer un trajet avec marche, course et marche finale, ouvrir GO et vérifier l'action unique,
   la pastille, le compte à rebours et la rail.
2. Toucher « I'm on board » sans bouger : l'écran doit passer à la course, puis les arrêts doivent
   avancer avec la position réelle ou avec « Next stop (preview) » en Debug.
3. À deux arrêts de la descente, vérifier une seule phrase et un seul motif haptique, puis la
   seconde invite à l'arrêt. Rejouer en Alerts only puis en Off.
4. Couper le réseau : vérifier « No network », « Scheduled » partout, aucun marqueur estimé et
   aucune invite inventée. Attendre plus de deux heures ou avancer l'horloge pour vérifier le
   bandeau périmé.
5. Avec VoiceOver et un texte jusqu'à AX3, parcourir l'action, la rail, l'invite et les quatre
   commandes du bas ; vérifier les cibles de 44 pt et les libellés avec ligne et direction.
6. Toucher « Next departures », puis « Leave later » plus 15, puis « Whole trip » et « End » :
   vérifier que chaque surface reste la même session et que End termine la Live Activity.

## Lot TRANSIT-POLISH

État au 2026-10-30, run `transit-polish-20261030-020844-7527`.

Le bouton Trip de la carte de guidage, GO et End ne se disputent plus la même rangée à AX3. À une
taille d'accessibilité, la carte place les trois commandes sous la ligne et la direction, en icônes,
avec une cible de 44 pt et le libellé VoiceOver complet. GO lui-même n'est pas modifié : il garde
son action unique, sa rail et ses quatre commandes du bas.

Les scénarios GO existants restent verts. Voir `TRANSIT.md` pour l'ancre du départ différé, la
fermeture épinglée du détail et la preuve du run.

Limite restante : « Leave later » dans GO part encore de l'heure de l'itinéraire sélectionné et non
du tableau de l'arrêt. Une ancre par arrêt dans GO reste ouverte.

## Lot GO-ANCHOR

État au 2026-10-30, run `go-anchor-20261030-094425-10342` (branche `ios/go-anchor`).

### « Leave later » ancré sur le tableau de l'arrêt

Le « Leave later » de GO suit maintenant la même règle que l'écran de trajet. La requête part de
l'heure que le tableau de l'arrêt donne pour cette ligne et cette direction, au nom de l'arrêt de
montée de la course courante. Elle ne part plus de l'heure de l'itinéraire sélectionné.

GO ouvre ce tableau pour l'arrêt de montée à l'ouverture de l'écran, sans présenter la feuille :
seul son état est lu. Le bouton « Next departures » ouvre la même surface. La règle est portée par
`TransitGoAnchorSelector`, pur et testé en JVM. Elle ne retient un départ que si l'arrêt, la ligne,
la direction et l'heure imprimée correspondent à la course affichée. Un départ d'une autre ligne,
d'une autre course ou d'un autre arrêt ne peut donc pas servir d'ancre.

Quand le tableau n'a aucune heure pour cette course à cet arrêt, GO replie sur maintenant plus les
minutes demandées. La source est alors `now` et un bandeau le dit dans l'interface, avec la clé
`transit_go_board_has_no_time_for_this_stop` et sa traduction française. Le bandeau porte
l'identifiant `transit-go-anchor-notice`. Aucun repli n'est présenté comme une heure du tableau.
La ligne de debug `transit-go-debug` porte `go_anchor=board`, `go_anchor=now` ou `go_anchor=none`,
et `go_fallback_notice=1` seulement quand le repli est affiché.

Le reste de GO est inchangé : machine à étapes, compte à rebours, invite de descente, rail et
disposition AX3. La requête part toujours par `RouteStore.setTime` et l'itinéraire affiché garde ses
propres heures jusqu'à ce qu'une nouvelle option soit choisie.

### Preuve du repli

`TransitGoStateTest` couvre les deux chemins de `TransitGoAnchorSelector` :

- un départ du tableau qui correspond à l'arrêt, à la ligne, à la direction et à l'heure imprimée
  donne `board`, avec l'epoch du tableau plus les minutes ;
- un tableau vide, une autre ligne, une autre course ou un autre arrêt donnent `now`, avec l'epoch
  de l'horloge plus les minutes.

`TransitGoUITests.testLeaveLaterAnchorsOnTheBoardOrSaysItCannot` joue les deux scénarios de la
couture Debug. Le scénario `anchor` répond avec le départ de la course de la fixture : le rapport
donne `go_anchor=board` et `go_fallback_notice=0`, et aucune notice n'est visible. Le scénario
`fallback` répond avec un tableau vide pour le même arrêt : le rapport donne `go_anchor=now` et
`go_fallback_notice=1`, et le bandeau affiche la raison. Captures `transit-go-anchor.png` et
`transit-go-fallback.png`.

### Vérifications

Linux, en avant-plan : `:core-common:jvmTest`, `:ios-shared:jvmTest` et
`:ios-shared:compileKotlinIosSimulatorArm64` verts.

Run macOS `go-anchor-20261030-094425-10342`, ciblé sur `TransitGoUITests` et
`TransitCitymapperUITests` :

| Vérification | Résultat |
|---|---|
| Compilation simulateur | verte |
| Tests Kotlin | 662 tests JVM et 551 tests simulateur, aucun échec |
| Tests Swift | 188 tests, aucun échec |
| Citymapper | 5 scénarios verts |
| GO | 2 scénarios verts, dont `testLeaveLaterAnchorsOnTheBoardOrSaysItCannot` en 17 s |
| Ancrage | `go_anchor=board`, `go_fallback_notice=0`, puis `go_anchor=now`, `go_fallback_notice=1` |
| Captures | `transit-go-anchor.png`, `transit-go-fallback.png` |
| Statut | ok |

### Limites et risques

- L'ancre dépend de la réponse du tableau au moment de la demande. Si le tableau n'a pas encore
  répondu, GO replie sur maintenant plus N et le dit ; il ne garde pas la demande en attente.
- Le tableau est ouvert par GO à l'ouverture de l'écran puis fermé s'il l'a ouvert lui-même. Un
  tableau déjà ouvert sur un autre arrêt est remplacé par celui de l'arrêt de montée.
- La correspondance se fait sur l'heure imprimée et la direction, comme l'écran de trajet. Un flux
  qui changerait le libellé de direction entre deux réponses ferait replier sur maintenant plus N.
