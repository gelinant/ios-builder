# Fiche de bas d'écran + barre de trajet en cours (TRANSIT-FICHE-BARRE)

Lot de refonte de la présentation transport en commun : toute l'UI transit (board, détail, GO)
pop en fiche de bas d'écran, et un trajet GO en cours reste dans une barre permanente pour
pouvoir faire autre chose (recherche, navigation) pendant le trajet.

## Comportement actuel (avant ce lot)

Chaque surface transit a sa propre présentation :

| Surface | Fichier | Présentation actuelle |
|---|---|---|
| Board (prochains départs) | `TransitBoardSheet` | `.sheet` depuis `MapScreen` quand `transit.boardOpen` |
| Détail (ficitifs) | `TransitDetailSheet` | `.sheet` `.presentationDetents([.large])` depuis la carte de guidage, ou panneau inline dans `MapScreen.bottomPanel` |
| Trajet | `TransitTripScreen` | `.fullScreenCover` depuis la carte de guidage et le board |
| **GO** | `TransitGoScreen` via `TransitGoHostView` | **`.fullScreenCover`** depuis `TransitGoButton` (carte de guidage) et depuis le bouton primaire de `TransitTripScreen` |

Pendant un trajet actif (`transit.active`), `MapScreen.mapRoot` remplace tout le
browserChrome (recherche) par la carte de guidage `TransitGuidanceCard`. GO prend tout
l'écran en plein, et le fermer ramène à la carte de guidage : impossible de chercher ou de
naviguer pendant le trajet.

La machine du trajet vit dans la session Kotlin (`TransitSession`), pas dans l'écran GO.
Fermer GO ne stoppe pas le trajet : `TransitGoScreen.onDisappear` ne fait que couper le
minuteur de l'écran ; la session continue (Live Activity comprise), comme le prouve la carte
de guidage qui revient avec `active=1` après un Close.

## Choix de design : fiche + barre

### 1. GO devient une fiche de bas d'écran

`TransitGoButton` et le bouton primaire de `TransitTripScreen` présentent `TransitGoHostView`
avec `.sheet` + `.presentationDetents([.large])` + `.presentationDragIndicator(.visible)` au
lieu de `.fullScreenCover`. Le contenu de GO est inchangé ; la fiche se ferme par le bouton
Close ou par un swipe vers le bas, et le trajet continue.

### 2. Barre permanente de trajet en cours

Nouveau `TransitGoBar` (Transit/TransitGoBar.swift), monté dans `MapScreen.mapRoot` :

- visible quand `transit.active` ET que GO a été engagé (`transit.goEngaged`) : la carte de
  guidage pleine est remplacée par cette barre compacte, et le browserChrome (recherche,
  actions) redevient disponible ; la barre est montée dans le bas du browserChrome, au-dessus
  du footer (échelle, attribution) et sous les feuilles de résultats ;
- la barre montre la ligne, la direction, l'action courante, la progression, l'arrivée et le
  nombre d'arrêts restants, depuis le même `transit.content` que la carte de guidage ;
- les trois actions de la carte de guidage restent : Trip (`transit-trip-open`), GO
  (`transit-go-open`, rouvre la fiche) et End (`transit-end`, stoppe la session et le trajet) ;
- un tap sur la barre rouvre la fiche GO.

`goEngaged` est posé quand GO s'ouvre (`TransitModel.engageGo()`), et remis à zéro quand la
session se termine (`apply` voit `state.active == false`, ou `stop()`).

### Pourquoi

- board, détail et GO partagent la même grammaire de fiche de bas d'écran : un seul geste
  mental (glisser vers le bas pour fermer) ;
- fermer GO ne tue plus la visibilité du trajet : la barre permanente remplace la carte pleine
  et libère la recherche, objectif explicite du lot ;
- aucune donnée n'est dupliquée : la barre lit la même ContentState que la carte de guidage et
  que la Live Activity, donc aucun des trois ne peut dériver d'un plan différent.

## Identifiants

Barre : conteneur `transit-go-bar` ; actions inchangées `transit-trip-open`, `transit-go-open`,
`transit-end` (la carte de guidage n'est plus montée quand la barre l'est, aucun doublon).

## Tests

- `TransitWiredUITests` : après fermeture de GO, la surface est la barre (`transit-go-bar`)
  et non plus la carte (`transit-card`) — lignes 135 et 160 mises à jour ; capture
  `transit-go-bar.png` ajoutée.
- `JourneyUITests` : après fermeture de GO, End se touche sur la barre (`transit-end`) et
  ramène au browserChrome. Inchangé.
- Tous les scénarios qui ne touchent pas GO (board, détail, trajet, AX3) restent sur la carte
  de guidage : aucun changement pour eux.

## Risques et limites

- La barre et la carte de guidage sont mutuellement exclusives ; le basculement se fait au
  premier GO engagé de la session.
- À une taille d'accessibilité, les trois actions passent en icônes sur une rangée qui peut
  se replier, comme la carte de guidage.
- La fiche GO garde sa propre carte : deux contextes WebGL coexistent toujours pendant GO.
