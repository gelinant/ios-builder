# Langage transport de Vela (TRANSIT-LINEVIEW)

Ce document décrit le langage visuel des transports seulement : la fiche d'une ligne, son ruban
d'arrêts, la position estimée des rames et le point d'entrée qui rend le transport cliquable
partout. Le reste de l'application garde son langage. La référence est l'idée de Citymapper, pas
son apparence : Vela reprend la hiérarchie et les gestes, avec ses propres couleurs, ses propres
types et ses propres textes.

Les données restent celles de Transitous. La fiche ne dessine un arrêt que si le flux l'a renvoyé,
ne pose une couleur que si le flux ou le mode la donne, et n'appelle jamais « live » une position
qu'elle a calculée.

## La couleur comme identité

- Une ligne a une seule couleur dans toute l'application. `TransitLineColor.hex` prend le
  `routeColor` du flux quand il est un hexadécimal à six chiffres ; sinon elle prend la couleur du
  mode (`TransitMode.defaultColorHex`), la même que le tableau d'arrêt et l'écran de trajet.
- `colorSource` vaut `feed` ou `mode`, et la fiche l'écrit : « Agency color, from the feed » ou
  « Vela mode colour : the feed sent none for this line ». Une couleur d'agence n'est jamais
  présentée comme celle de Vela, et l'inverse non plus.
- Le texte posé sur la couleur (badge, pastilles de correspondance, capsule de la rame) est noir ou
  blanc selon la luminance de la couleur. Aucun texte blanc sur un jaune d'agence.
- La couleur ne porte jamais un sens seule : « Live », « Scheduled », « Passed », « Canceled »,
  « Next » et le retard sont toujours des mots, pas seulement une teinte.

## La fiche d'une ligne

Une ligne, une direction, un arrêt. L'ordre de lecture répond à la question du voyageur :

1. **En-tête** : badge de la ligne (56 × 42 pt, rayon 10, couleur de la ligne), « Line K » en
   `title2` gras, la direction (« towards Embarcadero Station ») en `subheadline` secondaire, un
   badge « Live » en texte vert avec contour quand le flux a marqué la course en temps réel, puis
   la provenance de la couleur en `caption`.
2. **Sélecteur de direction** : une rangée horizontale de pastilles de 44 pt de haut, une par
   direction que le tableau de l'arrêt renvoie pour cette ligne, dans l'ordre du flux. La direction
   choisie prend la couleur de la ligne ; les autres restent sur `secondarySystemBackground`.
   Changer de direction ne redemande pas le tableau : une seule requête, celle de la course.
3. **Les deux terminus** : le premier et le dernier arrêt de la course, séparés par une flèche.
   Ce sont les extrémités réelles du run, pas une destination devinée depuis le headsign.
4. **Prochains départs** : des cartes de 68 pt de haut minimum, rayon 12, espacement 8. La première
   ligne est le compte à rebours (« 2 min »), calculé depuis le moment où le flux a répondu, pas
   depuis l'horloge du téléphone : une capture et la fiche disent la même chose. Dessous, l'heure,
   puis « Live » ou « Scheduled » en toutes lettres.
5. **Le ruban** : la ligne entière, dans l'ordre du flux.
6. **« See the whole line on the map »** : une seule action, pleine largeur, 48 pt de haut, teintée
   de la couleur de la ligne. Elle publie une requête de géométrie ; elle ne touche aucun fichier de
   carte.

L'espacement suit une échelle de 4, 8, 12, 16 et 20 pt. La fiche est en `pageSheet` plein, avec une
poignée, et se ferme par « Close » ou par le geste système. La taille de texte est plafonnée à AX3
(`.dynamicTypeSize(.xSmall ... .accessibility3)`).

## Le ruban

Le ruban est l'idée Citymapper rendue avec les moyens de Vela : une ligne verticale continue dans la
couleur de la ligne, un point par arrêt, et du texte à droite.

- **Rail** : 6 pt de large, opacité 0,9, continu d'un arrêt à l'autre. Il s'arrête au premier et au
  dernier point du run.
- **Points** : 15 pt pour un arrêt normal ; 13 pt creux (contour 2 pt, fond système) pour un arrêt
  déjà passé ; 22 pt en anneau (fond couleur, centre de 9 pt à la couleur du fond) pour le prochain
  arrêt ; 20 pt plein avec un centre de 7 pt pour un terminus.
- **Arrêts passés** : le contenu de la rangée passe à 55 % d'opacité, le mot « Passed » reste
  lisible, l'heure reste affichée. Un arrêt passé ne disparaît pas : le voyageur doit pouvoir lire
  d'où vient la rame.
- **Colonne d'heure** : 62 pt de large, alignée à droite, chiffres à chasse fixe. L'heure prévue
  barrée apparaît sous l'heure réelle quand le flux a déplacé l'appel, avec « 1 min late » en ambre
  ou rouge selon la bande (vert sous 2 minutes, ambre de 2 à 5, rouge au-delà). L'écart vient de
  deux heures du flux, jamais d'une estimation.
- **Correspondances** : les autres lignes du tableau de l'arrêt ouvert, une pastille de 20 pt par
  ligne, dans sa propre couleur, suivie du mot « Transfer ». Le ruban ne demande pas un tableau par
  arrêt : les correspondances connues sont celles de l'arrêt d'où la fiche a été ouverte.
- **Position estimée** : une capsule de 44 × 18 pt dans la couleur de la ligne, avec un pictogramme
  de rame, insérée entre les deux arrêts qui encadrent l'heure actuelle. Sa hauteur dans la rangée
  suit la fraction du trajet déjà parcourue. Le texte dit « Estimated position », puis « About 25 %
  of the way to Metro Van Ness Station, 2 min ». La fiche écrit « Estimated, not GPS » au-dessus du
  ruban et rappelle en pied de page que Transitous ne publie aucune position de véhicule.

Le ruban est une vue, pas une carte : il ne dépend pas de MapLibre et fonctionne hors ligne dès que
la séquence est en mémoire.

## Mouvement

- L'insertion du marqueur estimé et le changement de direction utilisent l'animation standard de
  SwiftUI (0,2 s, `easeInOut`), sans animation des données elles-mêmes.
- Aucun minuteur, aucune animation en boucle : une requête par action de l'utilisateur. Le
  rafraîchissement est un bouton.
- En mode déterministe (`-VelaDeterministic YES`), les captures ne dépendent d'aucune animation.

## Accessibilité

- Toute la fiche plafonne le texte à AX3. Les cibles font au moins 44 pt (boutons, pastilles de
  direction, action carte).
- VoiceOver lit **un arrêt par élément** : nom, heure, « Passed » ou « Next stop », « Canceled »,
  retard en mots, puis « Transfer to line L, line M ». L'identifiant `transit-line-stop` est posé sur
  chaque rangée.
- VoiceOver lit **le véhicule comme un élément distinct** : « Estimated vehicle position, not GPS.
  About 25 % of the way to Metro Van Ness Station, 2 min », identifiant `transit-line-vehicle`.
- Le badge annonce « Line K, agency colour » ou « Line K, Vela mode colour ».
- Les départs annoncent le compte à rebours, l'heure et « live » ou « scheduled ».
- Aucune information ne passe par la couleur seule. Les états sont des mots.

## Ce que le flux donne, et ce qu'il ne donne pas

Donné par Transitous et affiché tel quel :

- la séquence complète d'une course (`/api/v1/trip`) : arrêts, heures prévues, heures théoriques,
  retards arrêt par arrêt, arrêts annulés, géométrie du tracé quand elle existe ;
- le tableau de l'arrêt (`/api/v1/stoptimes`) : lignes, directions, couleurs d'agence, départs,
  marque temps réel, identifiant de course ;
- le `routeColor` de la ligne.

Absent du flux, donc absent de l'écran :

- aucune position GPS de véhicule, aucun identifiant de véhicule : le marqueur est une
  interpolation entre deux heures du flux, et il le dit ;
- aucune séquence quand la course n'a pas d'identifiant ou quand `/api/v1/trip` ne répond pas : la
  fiche écrit « Transitous did not send this run's stop sequence » et n'affiche que les départs
  reçus, sans inventer d'arrêt intermédiaire ;
- les correspondances des autres arrêts du ruban ne sont pas demandées : seule la ligne ouverte est
  interrogée, pour rester dans le budget de 720 requêtes par 24 h ;
- aucune couleur inventée : sans `routeColor`, la couleur du mode est affichée et nommée comme telle.

## Les accroches : rendre le transport cliquable partout

Un seul point d'entrée :

```swift
TransitLineLink.shared.open(line: "K", direction: "Embarcadero Station", stop: transitLineStop)
```

Il présente la fiche lui-même, depuis le contrôleur visible, donc aucune vue hôte n'ajoute de
`.sheet`. `TransitLineStopRef` porte l'identifiant Transitous quand la surface l'a, sinon seulement
le nom et la coordonnée, et le tableau est alors résolu par proximité. Ce lot ne pose pas les
accroches : chacune appartient au fichier d'un autre lot.

| Surface | Fichier et ligne | Appel d'une ligne |
|---|---|---|
| Rangée de ligne d'un tableau d'arrêt | `iosApp/Vela/Transit/TransitBoardSheet.swift:184` | `TransitLineLink.shared.open(line: line.label ?? modeLabel(line.mode), direction: line.headsign, stop: TransitLineStopRef(stopId: model.boardStopId, name: model.boardName, latitude: model.boardLat, longitude: model.boardLng))` |
| Jambe d'un détail d'itinéraire | `iosApp/Vela/Transit/TransitDetailSheet.swift:213` | `TransitLineLink.shared.open(line: leg.line ?? "", direction: leg.headsign, stop: TransitLineStopRef(stopId: leg.board?.stopId, name: leg.board?.name ?? "", latitude: leg.board?.location?.lat ?? 0, longitude: leg.board?.location?.lng ?? 0))` |
| Carte de segment d'un trajet | `iosApp/Vela/Transit/TransitTripScreen.swift:277` | `TransitLineLink.shared.open(line: segment.lineLabel ?? "", direction: segment.direction, stop: TransitLineStopRef(stopId: nil, name: segment.boardName ?? "", latitude: segment.boardLat ?? 0, longitude: segment.boardLng ?? 0))` |
| Rangée de lignes à proximité | `iosApp/Vela/Transit/TransitTripScreen.swift:659` | `TransitLineLink.shared.open(line: line.label ?? modeLabel(line.mode), direction: line.headsign, stop: TransitLineStopRef(stopId: nil, name: model.nearbyStop, latitude: originPoint.lat, longitude: originPoint.lng))` |
| Résultat de recherche | `iosApp/Vela/Search/SearchViews.swift:423` | `TransitLineLink.shared.open(line: row.name, direction: nil, stop: TransitLineStopRef(stopId: nil, name: row.name, latitude: row.latitude, longitude: row.longitude))` |

Conditions et prérequis, pour que l'accroche soit honnête :

- **Tableau d'arrêt** : `StopBoardLine` ne porte ni l'identifiant d'arrêt ni la coordonnée. Le lot du
  tableau doit publier `boardStopId`, `boardLat` et `boardLng` depuis `TransitBoardStore` (la cible
  les possède déjà). La rangée devient cliquable avec `.contentShape(Rectangle())` et
  `.onTapGesture` juste avant `.accessibilityIdentifier("transit-board-line")`.
- **Détail d'itinéraire** : `TransitDetailStop` ne porte pas `stopId` ni `location`, alors que
  `TransitStopTime` les fournit déjà. Le lot du détail ajoute ces deux champs, puis l'appel ci-dessus
  se pose sur la carte de jambe, après `.accessibilityIdentifier("transit-detail-leg")`.
- **Carte de segment** : la carte sélectionne déjà le segment au toucher (ligne 277). L'appel se
  place dans le même geste, sous la garde `segment.isRide && segment.hasBoardPoint`. Comme
  `TripSegment` n'a pas d'identifiant d'arrêt, la fiche résout le tableau par la coordonnée de
  montée.
- **Lignes à proximité** : aucune condition, `originPoint` et `model.nearbyStop` existent déjà dans
  l'écran. L'appel se pose après `nearbyRow(line, now: now)`.
- **Résultat de recherche** : aucun résultat de recherche ne porte aujourd'hui un nom de ligne ou un
  identifiant d'arrêt. L'appel ci-dessus est celui d'une rangée de ligne le jour où la recherche en
  renvoie une. Un résultat d'arrêt passe déjà par le tableau d'arrêt, donc par la première accroche.

### L'accroche carte

« See the whole line on the map » publie une requête, sans modifier la carte :

```swift
.onReceive(NotificationCenter.default.publisher(for: .velaTransitLineMapRequest)) { note in
    guard let request = note.object as? TransitLineMapRequest else { return }
    // request.shape, request.colorHex, request.stops, request.vehicle (estimé), request.live
}
```

`TransitLineMapRequest` porte le tracé du flux quand la course en a un (`shapeSource == "feed"`),
sinon la chaîne des arrêts (`shapeSource == "stops"`, et la fiche le dit). `vehicle` est le point
interpolé, à ne pas présenter comme une position GPS. Le propriétaire de la carte branche cette
notification dans `MapController` ou `MapScreen`.

## Ce que Vela ne copie pas

- Aucun élément de Citymapper : ni logo, ni icônes, ni captures, ni polices, ni couleurs de marque.
- Aucun texte de Citymapper : les libellés sont ceux de Vela, en anglais dans le code et traduits
  comme le reste de l'application.
- Aucune disposition copiée au pixel : la hiérarchie (couleur d'abord, départs ensuite, ruban
  complet, direction en haut) est une idée de lecture, pas un calque.
- Aucun service ou compte Citymapper : la source reste Transitous, ouverte et sans clé.
- Aucune position de rame empruntée à un autre fournisseur : Vela n'affiche que son interpolation et
  l'annonce comme telle.

## Vérifications

Sous Linux, la commande de T-1 :

```
source ~/opt/env.sh
flock /tmp/opencode/gradle.lock ./gradlew --no-daemon -Pvela.iosOnly=true \
  :core-common:jvmTest :ios-shared:jvmTest :ios-shared:compileKotlinIosSimulatorArm64
```

Tests JVM ajoutés :

- `TransitLineClientTest` (`core-common`) : séquence complète depuis une réponse `/api/v1/trip`,
  heures prévues et théoriques, couleur, mode, temps réel, course à moins de deux arrêts refusée,
  couleur à six chiffres seulement ;
- `TransitLineRouteTest` (`ios-shared`) : ordre et heures du flux, retard arrêt par arrêt,
  correspondances de l'arrêt ouvert seulement, interpolation entre deux appels (quart du trajet à
  14:00:30), avant le départ, après le terminus, course sans heure, couleur du flux contre couleur
  de mode, géométrie du flux contre chaîne d'arrêts, ouverture du magasin, course sans identifiant,
  ligne absente du tableau, changement de direction sans nouvelle requête de tableau, budget
  épuisé, fermeture.

Scénario interface `TransitLineViewUITests.testLineRibbonAndColours` sur la fixture
`-VelaTransitLineFixture` (tableau et course K enregistrés le 2026-10-28 à Metro Van Ness Station) :
20 arrêts, couleur `437c93` du flux, 2 directions, au moins un départ, marqueur estimé présent et
annoncé, arrêts passés et prochain arrêt en mots, correspondances, action carte, captures
`transit-line.png` et `transit-line-ribbon.png`, lignes `line_stops=20`, `line_color=437c93`,
`line_estimated=1`.

La fixture est réservée aux builds Debug. Elle n'ajoute aucun chemin de production : le seul point
d'entrée de test est `TransitLineLink.startFixtureIfRequested()`, appelé sous `#if DEBUG` depuis
`VelaApp.init`.

## Tests humains sur iPhone

1. Depuis un tableau d'arrêt, toucher une ligne : la fiche s'ouvre sur la ligne, la direction et
   l'arrêt touchés. Vérifier la couleur, la provenance annoncée et les deux terminus.
2. Changer de direction : les départs et le ruban changent, le tableau n'est pas redemandé, et une
   direction sans séquence affiche le message au lieu d'arrêts inventés.
3. Faire défiler le ruban : les arrêts passés sont atténués avec le mot « Passed », le prochain est
   en anneau, les terminus sont pleins, la rame estimée est entre deux arrêts avec son texte.
4. Toucher « See the whole line on the map » : la ligne est envoyée à la carte une fois l'accroche
   branchée ; sans elle, la fiche dit seulement que la requête est partie.
5. Passer en mode avion puis rafraîchir : la fiche ne fabrique ni heure ni arrêt, et l'état d'échec
   est écrit.
6. Avec VoiceOver et un texte jusqu'à AX3, parcourir la fiche : chaque arrêt et le véhicule sont des
   éléments distincts, les états sont en mots, les cibles font 44 pt.
