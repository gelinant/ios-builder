# Widgets de l'écran d'accueil (X-4)

État : 29 octobre 2026, branche `ios/x4-widgets2`, depuis `ios/main`. Ce document décrit les deux
widgets livrés, le contrat de l'App Group, ce qu'ils affichent quand la donnée est vieille ou
absente, et ce qui reste à vérifier sur un vrai iPhone.

## 1. Les deux widgets

Le lot ne livre pas un tableau de bord. Deux blocs seulement, choisis parce que l'app possède déjà
la donnée et parce que le widget peut la montrer sans mentir.

### 1.1 Voiture garée (`VelaParking`)

- Source : `SavedState.parking` du `SavedStore` Kotlin, soit une latitude, une longitude et
  l'instant où le spot a été enregistré. `SavedStore` ne garde ni rue ni adresse : le widget
  n'en invente pas.
- Contenu : depuis combien de temps la voiture est garée, puis une distance à vol d'oiseau
  seulement si l'app a écrit une position récente dans l'App Group. La distance est calculée sur
  place à partir de cette position, elle n'est jamais une durée de trajet ni un itinéraire.
- L'âge de la position est affiché à côté de la distance. Au-delà de 15 minutes, le widget ne
  dessine aucune distance et affiche `map_parking_no_fix` (« Waiting for a location fix »).
- Lien : `vela://parking`, qui ouvre la fiche de la voiture garée. Le libellé est
  `map_parking_find` (« Find my car »).

### 1.2 Prochains départs (`VelaDepartures`)

- Source : `TransitBoardState` du `TransitBoardStore` Kotlin, c'est-à-dire le dernier arrêt dont
  l'utilisateur a ouvert le tableau des départs dans Vela. Ce n'est pas une épingle : l'app n'a pas
  d'action « épingler un arrêt », et le widget ne prétend pas en avoir une. La documentation dit
  « dernier arrêt ouvert ».
- Contenu : le nom de l'arrêt, au plus trois lignes pour la taille moyenne, une seule pour la
  petite, et le prochain départ de chaque ligne. Les heures viennent du flux Transitous via l'app.
  Le widget n'interroge jamais Transitous.
- Chaque départ porte sa marque `place_transit_live` (« Live ») ou `place_transit_scheduled`
  (« Scheduled »), comme la feuille de l'app. Rien n'est estimé quand le flux ne marque pas un
  passage en direct.
- Lien : `vela://board`, intercepté dans `VelaApp` par `WidgetDeepLink`. La route rouvre l'arrêt
  enregistré avec `session.board.open` et la feuille des départs de `MapScreen` suit l'état Kotlin,
  sans ajouter de cas dans `MapScreen`. Le libellé est `transit_refresh` (« Refresh »).

Les deux widgets acceptent les tailles `systemSmall` et `systemMedium`. Ils utilisent les jetons de
`iosApp/Vela/Design/DesignTokens.swift` pour les espacements, les rayons, les couleurs et les rôles
typographiques, et le catalogue `Localizable.xcstrings` par `VelaL10n`.

## 2. App Group et snapshot

Identifiant : **`group.app.vela.ios`**, déclaré dans `iosApp/Vela/Vela.entitlements` et
`iosApp/VelaWidgets/VelaWidgets.entitlements`.

L'app écrit un seul objet JSON sous la clé `widget.snapshot.v1` dans les `UserDefaults` du groupe.
Le modèle est `WidgetSnapshot`, compilé dans les deux cibles depuis
`iosApp/VelaWidgets/WidgetSnapshot.swift` :

| Champ | Contenu | Écrit par |
|---|---|---|
| `parking` | latitude, longitude, `savedAt` | `SavedStore` |
| `board` | arrêt, coordonnées, `fetchedAt`, `offline`, `refreshFailed`, jusqu'à trois lignes et trois départs par ligne | `TransitBoardStore` |
| `location` | dernière position déjà reçue par l'app, avec `fixedAt` | `CoreLocationPipeline.lastKnownFix(maxAge: 15 min)` |
| `writtenAt` | instant d'écriture du snapshot | `WidgetStatePublisher` |

Règles d'écriture :

- `WidgetStatePublisher` (dans `iosApp/Vela/App/`) observe `session.saved.state` et
  `session.board.state`. Il démarre depuis `AppGraph.session`, sans qu'un écran soit ouvert.
- Il ne réécrit pas le snapshot quand seul `writtenAt` change : `sameContent` compare `parking`,
  `board` et `location`.
- Il appelle `WidgetCenter.reloadTimelines` pour les deux `kind` seulement après une écriture
  réelle.
- Il ne fait aucune requête réseau et ne demande jamais une nouvelle position. `lastKnownFix` lit
  uniquement le dernier point que Core Location a déjà livré à l'app.
- Si l'App Group n'est pas provisionné, `WidgetSnapshotStore.shared` est `nil`, l'app journalise
  l'erreur et les widgets restent dans leur état vide.

La lecture est tolérante : un décodage impossible, une clé absente ou un groupe absent donnent un
widget vide, jamais une donnée de la veille présentée comme fraîche.

## 3. Donnée vieille ou absente

### Départs

- Un tableau est **périmé** quand `fetchedAt` manque, quand `refreshFailed` est vrai, quand
  `offline` est vrai, ou quand `fetchedAt` a plus de **20 minutes**. Le seuil est
  `WidgetBoard.staleAfter`.
- L'heure du flux est toujours affichée avec `transit_updated` (« Updated 09:41 »). Quand le
  tableau est périmé, cette ligne passe en couleur d'alerte et l'âge relatif est ajouté à côté.
- Si `refreshFailed` ou `offline` est vrai, la ligne
  `transit_the_last_board_is_shown_refresh` (« The last board is shown. Refresh failed. »)
  apparaît au-dessus de l'heure. Un tableau mis en cache n'est jamais marqué « Live ».
- Sans `fetchedAt`, la ligne devient `transit_the_board_did_not_answer_for`.
- Sans aucun départ à venir, le widget affiche `transit_no_departures_found_here` et
  `transit_transitous_may_not_cover_this_stop`, sans remplir la liste.
- Sans arrêt enregistré, il affiche son état vide et ne propose pas de lien.

### Voiture garée

- L'âge est toujours affiché, y compris quand la voiture est garée depuis plusieurs jours : c'est
  une information vraie, pas une donnée périmée.
- La distance n'apparaît que si `location` a moins de 15 minutes. Sa ligne montre aussi l'âge de
  la position. Une position plus vieille est ignorée, même si l'app la possède encore.
- Sans voiture garée, le widget affiche `settings_parking_history_empty` et aucun lien.

### Ce que le widget ne promet pas

- Aucune actualisation en arrière-plan : le widget ne télécharge rien. `VelaWidgetProvider` produit
  des entrées de timeline pour les 20 prochaines minutes afin que les comptes à rebours restent
  justes sans réveiller l'extension, puis WidgetKit peut reconstruire la timeline. Si WidgetKit ne
  le fait pas, le dernier rendu reste affiché et porte l'heure du flux, donc son âge reste lisible.
- Aucune position live : le widget ne démarre pas Core Location.
- Aucune distance vers un lieu enregistré : ce lot ne publie pas la liste des lieux enregistrés.
  La voiture garée est le seul bloc qui porte une distance.

## 4. Liens profonds

| Bloc | URL | Effet |
|---|---|---|
| Voiture garée | `vela://parking` | route existante, ouvre la fiche de la voiture |
| Départs | `vela://board` | interceptée dans `VelaApp`, rouvre le dernier arrêt |

`WidgetDeepLink.open` ne reconnaît que `vela://board` avec un chemin vide ou `/`. Toute autre URL
repasse par `VelaDeepLinkCenter`, donc les routes existantes ne changent pas. Sans snapshot
d'arrêt, la route n'est pas consommée et l'app suit son traitement d'URL inconnue.

## 5. Construire sans l'extension

La cible `Vela` ne référence aucun symbole de l'extension. Le seul fichier partagé est
`WidgetSnapshot.swift`, compilé dans les deux cibles. Pour produire une app sans widget :

1. retirer `- target: VelaWidgets` des dépendances de `Vela` dans `iosApp/project.yml` ;
2. retirer la cible `VelaWidgets` du même fichier ;
3. relancer `xcodegen generate`.

`WidgetStatePublisher` continue de compiler, `WidgetKit` étant un framework système. Sans App
Group provisionné, il journalise l'indisponibilité et n'écrit rien. Un build de l'app seule reste
donc valide, même si les widgets ne sont alors pas installés.

## 6. Preuves

Mac, un seul run GitHub : tag `x4-widgets2-20261029-190659-18916`, statut `ok`. La commande est
celle du lot, avec `VELA_ONLY_UI=LaunchUITests` et `VELA_SKIP_ARCHIVE=1`. Le journal de build
montre `** TEST BUILD SUCCEEDED **`, la compilation de la cible `VelaWidgets`, la copie de
`VelaWidgets.appex` dans `Vela.app/PlugIns` et `ValidateEmbeddedBinary` réussi. Les 188 tests
unitaires et les deux scénarios `LaunchUITests` passent. Le run ne peut pas installer un widget sur
l'écran d'accueil : XCUITest ne pilote pas le SpringBoard. Il ne vérifie donc pas le rendu, et
l'archive complète n'est pas produite avec `VELA_SKIP_ARCHIVE=1`.

## 7. Ce qui reste à faire à la main

- Ajouter les deux widgets depuis la galerie sur un iPhone et vérifier les tailles petite et
  moyenne, en clair et en sombre, avec une grande taille de texte.
- Vérifier qu'un départ réel s'affiche après avoir ouvert un arrêt dans Vela, puis que le widget
  passe en état périmé après 20 minutes sans nouvelle ouverture.
- Garer une voiture, fermer Vela, vérifier l'âge et la distance ; puis attendre plus de 15 minutes
  et vérifier que la distance disparaît.
- Vérifier `vela://parking` et `vela://board` depuis le widget, app fermée puis app ouverte.
- Vérifier le provisionnement de `group.app.vela.ios` sur un profil de signature réel : un profil
  sans ce groupe laisse les widgets vides, ce qui est l'état prévu mais doit être constaté.
- Traduire les libellés réutilisés dans les 24 langues est déjà fait par le catalogue Android ;
  vérifier visuellement l'allemand, l'arabe (RTL) et le japonais.

## 8. Risques connus

- **Dernier arrêt, pas épingle** : le nom du widget et ce document disent « dernier arrêt ouvert ».
  Un utilisateur qui ouvre un autre arrêt change le widget sans l'avoir demandé. Une vraie épingle
  demande une action dans la feuille des départs et une clé persistée, hors de ce lot.
- **Distance à vol d'oiseau** : elle ne suit pas les rues. Le libellé « Distance » et l'âge de la
  position la rendent honnête, mais un utilisateur peut la lire comme un trajet.
- **App Group** : sans profil de signature qui inclut `group.app.vela.ios`, les widgets restent
  vides. C'est documenté et silencieux pour l'utilisateur, avec une erreur dans le journal de
  l'app.
- **Timeline** : WidgetKit reste seul juge du moment où il reconstruit une timeline. Les comptes à
  rebours peuvent se figer ; l'heure absolue du flux et son âge restent affichés.
- **Embarquement** : le run Mac de ce lot saute l'archive (`VELA_SKIP_ARCHIVE=1`). L'extension est
  compilée et embarquée dans l'app de simulateur, mais la présence dans l'IPA et la signature d'un
  profil réel restent à constater sur un run d'archive complet.
