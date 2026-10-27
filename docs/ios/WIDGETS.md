# Widgets d'écran d'accueil

X-4 ajoute trois widgets Vela sur l'écran d'accueil : raccourcis Maison et Travail, voiture
garée, et prochains départs du dernier arrêt ouvert dans l'app. Ils lisent un instantané écrit par
l'app dans un App Group. L'extension ne fait aucune requête réseau et n'appelle ni Google ni
Transitous.

## Contenu

| Widget | Familles | Contenu | Toucher |
|---|---|---|---|
| `VelaShortcuts` | petit, moyen | nom et adresse de Maison et Travail | `vela://navigate/home` ou `vela://navigate/work`, la route existante qui résout le raccourci dans `SavedStore` |
| `VelaParking` | petit, moyen | « Parked car », coordonnées et ancienneté calculée à l'affichage | `vela://parking`, la route existante de la voiture garée |
| `VelaDepartures` | petit, moyen | nom de l'arrêt, ligne, direction, minutes, mention Live ou Sched., heure de dernière mise à jour | `vela://board`, nouvelle route du routeur unique qui rouvre l'arrêt épinglé |

L'heure de mise à jour est celle que Transitous a renvoyée à l'app, pas l'heure de rafraîchissement
du widget. Au-delà de 20 minutes, ou si le dernier rafraîchissement a échoué, le pied du widget
affiche « not refreshed » en orange. Aucun horaire n'est inventé : une ligne sans départ à venir
disparaît, un arrêt sans départ garde son nom et propose de rouvrir l'arrêt.

Le widget des départs montre le **dernier arrêt ouvert** dans Vela. Ouvrir un tableau d'arrêt dans
l'app l'épingle. Il n'y a pas encore d'écran de choix explicite ni de bouton pour retirer
l'épingle.

## Données partagées

`iosApp/Shared` reste réservé aux attributs ActivityKit. Le payload des widgets vit dans
`iosApp/Widgets/WidgetSnapshot.swift`, compilé à la fois dans l'app, dans l'extension
`app.vela.ios.widgets` et dans les tests unitaires. Il contient :

- les raccourcis Maison et Travail (nom, adresse, type) ;
- le parking (latitude, longitude, date d'enregistrement) ;
- l'arrêt épinglé (nom, coordonnées, heure du feed, échec de rafraîchissement, lignes et départs
  en epoch) ;
- l'heure d'écriture.

L'app écrit ce JSON dans `UserDefaults(suiteName: "group.app.vela.ios")`, clé
`widget.snapshot.v1`, via `WidgetSnapshotStore`, puis appelle
`WidgetCenter.shared.reloadAllTimelines()` seulement si le contenu a changé. `WidgetStatePublisher`
observe directement les `StateFlow` Kotlin `SavedStore` et `TransitBoardStore` depuis `AppGraph`,
donc aucun écran SwiftUI n'a besoin d'être ouvert. Au lancement, le payload existant est restauré
avant la première émission, ce qui garde l'arrêt épinglé après une relance.

## Provisionnement et sideload

L'app et l'extension déclarent toutes deux l'App Group `group.app.vela.ios` dans leurs fichiers
`.entitlements`. Sur iPhone, l'outil de sideload doit signer **l'app et l'extension** avec des
profils qui contiennent cet App Group. Une IPA signée à la racine seulement, ou un compte gratuit
sans capacité App Groups, installe l'app mais les widgets restent vides : l'extension ne partage
alors aucun conteneur avec l'app. Aucun repli par fichier n'est possible, l'extension étant
sandboxée dans son propre conteneur. Ce point doit être vérifié avec chaque outil de sideload.

L'archive produite par `scripts/ios/ci-ipa.sh` est non signée : elle prouve la présence et le
point d'extension, pas la validité du profil.

## Actualisation et limites

- WidgetKit choisit quand reconstruire les timelines. Le fournisseur demande une reconstruction
  après 15 minutes et fournit une entrée par minute pour que les comptes à rebours restent
  justes. Rien ne garantit une actualisation à l'heure prévue.
- Les départs sont rafraîchis par Transitous seulement quand le tableau d'arrêt est ouvert dans
  l'app (toutes les 30 s) ou rouvert plus tard. Il n'y a ni push, ni tâche de fond, ni requête
  réseau dans l'extension. Un widget peut donc afficher un tableau plus ancien que la réalité ;
  l'heure de mise à jour et l'avertissement de péremption le disent.
- Le stationnement ne stocke qu'un point et une date. Le widget affiche les coordonnées, pas une
  adresse que l'app n'a jamais enregistrée.
- Les libellés des widgets sont en anglais. Le catalogue de chaînes de l'app n'est pas encore
  compilé dans l'extension.
- iOS 17 minimum, comme l'app. Aucune Live Activity n'est créée par les widgets.

## Vérifications

`VelaTests/WidgetTests.swift` couvre la construction de l'instantané (raccourcis, âge du parking,
lignes et départs retenus, péremption, heure de mise à jour), l'aller-retour JSON dans l'App Group,
le rejet d'un payload illisible et la route `vela://board`. XCUITest ne peut pas ajouter ni
toucher un widget d'écran d'accueil ; il n'y a donc pas de scénario d'interface pour ces vues.

`scripts/ios/ci-ipa.sh` vérifie en plus que `PlugIns/WidgetsExtension.appex` est présent dans
l'archive et dans l'IPA, que son bundle id et son point d'extension sont corrects et qu'il n'est
pas signé dans l'archive non signée.

Capturer un vrai rendu de widget sur le runner n'est pas possible : `simctl` n'ajoute pas de
widget à l'écran d'accueil et XCUITest ne voit pas SpringBoard. Les aperçus SwiftUI et le rendu
sur iPhone restent à contrôler à la main.

## Tests humains

1. Installer une IPA dont l'app et `WidgetsExtension.appex` portent l'App Group, puis ouvrir Vela
   une fois.
2. Ajouter les trois widgets depuis la galerie. Vérifier Maison et Travail avec leurs adresses,
   puis toucher chacun : Vela doit ouvrir l'itinéraire correspondant.
3. Enregistrer un stationnement, ouvrir le widget et vérifier les coordonnées et l'ancienneté.
   Toucher le widget doit ouvrir la voiture garée. Supprimer le parking et vérifier l'état vide.
4. Ouvrir un arrêt à forte fréquence, vérifier ligne, direction, minutes et mentions Live/Sched.,
   puis laisser le téléphone verrouillé 20 minutes : le pied doit signaler l'absence de
   rafraîchissement. Toucher le widget doit rouvrir le même arrêt. Captures `x4-widgets.png`,
   `x4-parking.png`, `x4-departures.png`.
5. Vérifier les tailles petite et moyenne, les modes clair et sombre, puis un redémarrage de
   l'iPhone : le dernier arrêt doit rester épinglé.
