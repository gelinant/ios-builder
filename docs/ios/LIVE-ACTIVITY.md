# Live Activity de navigation

X-1 ajoute une Live Activity pour les trajets en voiture et à pied. Elle apparaît sur l'écran
verrouillé et sur la Dynamic Island quand l'utilisateur autorise les Live Activities pour Vela. Le
vélo et les transports ne démarrent pas cette activité.

## Contenu et cycle de vie

L'activité affiche la prochaine manœuvre et sa flèche, l'instruction et la rue, la distance avant
la manœuvre, la distance restante, la durée et l'heure d'arrivée, la progression de l'itinéraire et
l'état de recalcul. Aucune coordonnée n'est envoyée à ActivityKit.

- Start demande une activité si `ActivityAuthorizationInfo.areActivitiesEnabled` est vrai. Un refus
  dans les réglages n'empêche pas la navigation dans l'app.
- Un changement de manœuvre, d'instruction, de rue, de mode, d'itinéraire ou d'état de recalcul est
  publié immédiatement. Les autres changements attendent 5 s, sauf si une distance a varié d'au
  moins 25 m depuis la dernière publication.
- À l'arrivée, une carte de fin reste visible 8 s. End et Done terminent aussi l'activité
  immédiatement.
- Au relancement, le contrôleur adopte au plus une activité récente et ferme les doublons. Sans
  reprise de l'état de navigation, une activité adoptée est fermée à son échéance, au plus 60 s
  après sa dernière mise à jour. Les activités déjà plus anciennes sont fermées au lancement.

L'écran verrouillé utilise la couleur d'accent de Vela et des couleurs de premier et second plan
adaptées aux modes clair et sombre. La Dynamic Island possède des présentations étendue, compacte
et minimale.

## Limite d'exécution en arrière-plan

La Live Activity affiche un état. Elle n'exécute ni le GPS ni le moteur de navigation. Les mises à
jour viennent de `NavStore` tant que le processus de Vela fonctionne. La localisation en
arrière-plan et la session audio de navigation restent indispensables écran éteint ou dans une
autre app.

Il n'y a ni jeton de push ni serveur. Après un arrêt forcé de l'app, l'activité ne reçoit plus de
mise à jour et la navigation n'est pas restaurée par ce lot. Il ne faut pas attendre une activité
toujours à jour dans cette situation.

## Structure technique

`iosApp/Shared/NavActivityAttributes.swift` est compilé dans l'app et dans
`NavActivityExtension`, sans paquet supplémentaire. `NavActivityController` est le seul code de
production de l'app qui appelle ActivityKit. `NavModel` lui publie les états de `NavStore`. Le
Widget Extension `app.vela.ios.navactivity`, iOS 17 comme l'app, contient uniquement les vues
SwiftUI et WidgetKit. L'app déclare `NSSupportsLiveActivities=true`.

Aucun entitlement ActivityKit particulier ni App Group n'est ajouté. En sideload, l'outil doit
signer l'app et l'extension avec la même équipe et préserver le préfixe `app.vela.ios`. L'extension
a son propre profil de provisionnement. Une IPA signée seulement à la racine peut s'installer sans
que la Live Activity fonctionne. Les limites habituelles du compte gratuit, notamment le
renouvellement tous les 7 jours, restent applicables. La combinaison de chaque outil de sideload
avec ce profil d'extension doit être validée sur iPhone.

## Vérifications automatiques et limite visuelle

Les tests unitaires couvrent la conversion de l'état, les seuils de publication, le recalcul,
l'arrivée, End et l'adoption des activités périmées. Sur un hôte qui autorise ActivityKit, un test
crée une activité, vérifie son `ContentState` après une mise à jour puis son arrêt. Le scénario
`NavUITests` fait les mêmes vérifications pendant le replay `sf-market`. Si le réglage est désactivé
ou indisponible, les assertions ActivityKit sont signalées et le reste du scénario continue.

XCUITest ne contrôle pas l'écran verrouillé ni la Dynamic Island sur le runner. Les tests
automatiques vérifient donc l'état ActivityKit, pas le rendu visuel. Les captures `nav-*.png`
montrent seulement la navigation dans l'app.

## Tests humains et captures à fournir

Installer l'IPA en vérifiant que l'outil signe aussi `NavActivityExtension.appex`. Dans les
réglages de l'iPhone, autoriser les Live Activities pour Vela et sur l'écran verrouillé.

1. **Conduite, écran verrouillé** : démarrer un itinéraire voiture, verrouiller et se déplacer.
   Vérifier la flèche, la rue, les distances, l'ETA, la progression et les mises à jour avec la voix.
   Prendre une capture de l'écran verrouillé après un changement de manœuvre. Nommer la capture
   `x1-lock-drive.png` pour le compte rendu.
2. **Recalcul** : quitter volontairement l'itinéraire. Vérifier l'indicateur Rerouting puis la
   reprise de la nouvelle instruction et de la progression.
3. **Dynamic Island** : sur un iPhone équipé, rouvrir l'app puis revenir à l'accueil. Vérifier les
   deux côtés compacts, puis maintenir la Dynamic Island pour vérifier la présentation étendue.
   Prendre `x1-island-compact.png` et `x1-island-expanded.png`. Pour voir la présentation minimale,
   afficher en plus la Live Activity d'une autre app et prendre `x1-island-minimal.png`.
4. **Marche et apparences** : répéter Start sur un itinéraire à pied, vérifier le libellé et l'icône
   de marche. Relire l'écran verrouillé en modes clair et sombre.
5. **Arrière-plan** : laisser l'écran éteint plusieurs minutes et ouvrir une autre app. Vérifier que
   le guidage vocal et les distances continuent. Cette étape teste aussi la localisation en
   arrière-plan, pas seulement ActivityKit.
6. **Fin et relance** : vérifier la carte d'arrivée pendant 8 s, puis la disparition avec Done.
   Sur un second trajet, utiliser End et vérifier la disparition immédiate. Forcer ensuite l'arrêt
   de l'app pendant un trajet, constater l'absence de nouvelles mises à jour, la rouvrir et vérifier
   la fermeture de l'activité périmée dans le délai de 60 s.
7. **Refus du réglage** : désactiver les Live Activities pour Vela puis démarrer un trajet. La
   navigation doit rester fonctionnelle sans activité. Réactiver le réglage avant les autres tests.
