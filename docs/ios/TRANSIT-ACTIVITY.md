# Live Activity de transport en commun

X-3 ajoute un guidage de transport à partir de l'itinéraire Transitous sélectionné dans le choix
d'itinéraires. Le bouton « Start transit » ferme le choix, conserve le tracé et ouvre une carte
compacte dans Vela avec une Live Activity. « End » termine la session, enlève le tracé et ferme
l'activité. À l'arrivée, la carte de fin reste visible dans l'app et ActivityKit programme la
disparition de sa présentation.

## Contenu et progression

La session conserve les marches et les trajets dans leur ordre. Pour chaque trajet, elle expose la
ligne, ses couleurs, la direction, les arrêts de montée et de descente, le nombre d'arrêts et les
horaires. La carte et la Live Activity indiquent la marche vers le prochain point de montée ou la
destination, puis la montée, le prochain arrêt et la descente. Les changements de position font
avancer les marches et les arrêts détaillés. Le bouton « Next leg (preview) » existe seulement en
Debug pour rejouer la progression sans déplacement. Les seuils et les règles exactes sont dans
`SPEC.md`, section « iOS Live Activity ».

Les horaires de service et les estimations temps réel restent distincts. Sans couple d'horaires
réel et théorique fourni par Transitous, seule l'heure planifiée est affichée. Une estimation porte
le libellé « Live » et peut conserver l'heure planifiée barrée. Le badge de retard ou d'avance
n'apparaît que si Transitous fournit ce couple et son écart. Vela ne calcule pas un retard à partir
de l'horloge du téléphone et n'invente pas de rafraîchissement temps réel.

L'activité affiche l'écran verrouillé et les présentations étendue, compacte et minimale de la
Dynamic Island. Elle comprend la pastille colorée de ligne, la direction, l'action suivante, les
arrêts restants, les heures de montée et de descente et l'arrivée globale. Les changements
sémantiques sont publiés immédiatement ; les autres changements sont limités comme X-1. Aucune
coordonnée n'entre dans l'état ActivityKit.

## Previous et Next

L'écran verrouillé et la Dynamic Island étendue portent deux boutons ronds de 44 pt, Previous et
Next, de part et d'autre de l'action. Ils suivent la même séquence que GO, décrite dans
`TRANSIT-GO.md` : un Previous manuel tient l'étape contre la position GPS jusqu'à ce qu'elle dépasse
l'étape quittée, ou jusqu'à Next. Chaque bouton porte le titre de l'étape visée,
`previousStepTitle` ou `nextStepTitle` dans `ContentState`, et son libellé VoiceOver le lit, par
exemple « Next step: Board K at Metro Van Ness Station ». Un titre absent désactive le bouton : pas
de Previous à la première étape, pas de Next à l'arrivée. La carte d'arrivée n'a aucun bouton.

Chaque bouton est un `Button(intent:)` sur `TransitStepIntent`, une `LiveActivityIntent` de
`iosApp/Shared/`, donc compilée dans l'app et dans l'extension. iOS exécute `perform()` dans le
processus de Vela. L'app installe au lancement `TransitStepRouter.handler`, qui appelle
`TransitStepCommands.run`. Ce routeur fait d'abord bouger GO s'il est ouvert, puis
`TransitSession.previousStep()` ou `nextStep()`. Le nouvel état de session repasse par
`TransitModel` et `TransitActivityController`, comme toute autre étape, donc l'activité et GO
restent alignés. Dans GO, Previous et Next prennent le même chemin dans l'autre sens.

L'intent porte l'identifiant de session de l'activité. Un bouton d'une activité plus ancienne ne
peut pas faire bouger un nouveau trajet. Si Vela a été tué, iOS relance le processus en arrière-plan
pour l'intent ; la session n'est pas restaurée, donc l'intent ne trouve aucune session et ferme
l'activité touchée, qui ne pourrait plus être mise à jour. Previous après l'arrivée relance une
nouvelle activité, car la carte d'arrivée a déjà terminé la précédente.

## Exécution en arrière-plan

ActivityKit affiche un état. Il ne demande pas de position et ne fait avancer aucune étape par
lui-même. Seuls les boutons Previous et Next réveillent Vela, le temps d'un pas. Les mises à jour
ont lieu pendant que l'app est active, ou pendant qu'une session de transport explicitement démarrée
reçoit légitimement des positions avec la localisation en
arrière-plan. Cette autorisation est retirée à l'arrivée et à « End ». Vela ne laisse pas la
localisation en arrière-plan active uniquement pour conserver une carte ou une Live Activity.

Il n'y a ni jeton de push, ni serveur, ni minuterie de rafraîchissement des retards. Si iOS suspend
le processus et qu'aucune position n'est délivrée, l'état ne change pas. Après un arrêt forcé de
Vela, il n'y a plus aucune mise à jour. La session n'est pas restaurée au prochain lancement ; une
activité récente orpheline est nettoyée selon la même échéance que X-1. Le compromis privilégie
ainsi la batterie et une exécution en arrière-plan liée au trajet réel, sans promettre un suivi
minute par minute dans une app tuée.

## Structure technique

`TransitSession` est une facette de `MapSession` dans `:ios-shared`. `TransitModel` relie son état à
Core Location, à la carte et à `TransitActivityController`. Les tests JVM couvrent la progression,
les marches, les arrêts restants, la séparation entre heures planifiées et estimées, l'arrivée et
« End ».

La présentation transport rejoint le `WidgetBundle` de `NavActivityExtension.appex`. Les deux
configurations ActivityKit restent indépendantes et le comportement X-1 est inchangé. Ce partage
évite une seconde extension et un second profil de provisionnement en sideload. L'app et
l'extension doivent néanmoins être signées avec la même équipe et le préfixe `app.vela.ios`, comme
pour X-1.

## Vérifications automatiques

Les tests Swift couvrent la conversion de l'état, les changements sémantiques, la limitation des
mises à jour, l'arrivée, le nettoyage des activités périmées et le cycle ActivityKit réel quand le
réglage l'autorise. `TransitActivityTests` côté interface démarre l'itinéraire Transitous K
enregistré sur San Francisco, avance de la marche au trajet avec le hook Debug, vérifie le retard
réel du fixture et « End ». `TransitStepTests` vérifie que l'intent transmet sa commande et sa
session, que Next et Previous changent le `ContentState` publié aussitôt, qu'un intent sans session
correspondante ne fait rien et que l'arrivée n'a aucun bouton. `TransitGoUITests` vérifie qu'un pas
dans GO fait suivre la session et, si l'hôte le permet, l'activité. Les captures sont `transit-activity-start.png` et
`transit-activity-next.png`. Elles montrent la carte dans l'app, pas l'écran verrouillé ni la
Dynamic Island.

L'archive est aussi contrôlée pour la présence de `NavActivityExtension.appex` dans l'IPA et pour
l'absence de signature.

## Résultat du runner macOS

Run `x3-transit-activity-20261026-010530-6408`, source `016f3a85` :

| Vérification | Résultat |
|---|---|
| Kotlin | 106 tests JVM et 85 tests simulateur, aucun échec |
| Tests Swift | 42 tests, aucun échec ; le test ActivityKit réel crée, met à jour et termine une activité transport |
| Scénario X-3 | Réussite en 15,5 s ; marche puis trajet, retard de 4 min conservé, deux mises à jour et « End » |
| Captures | `transit-activity-start.png` et `transit-activity-next.png`, heure d'arrivée 9:39 AM dans le fuseau de l'arrêt |
| IPA | `results/x3-transit-activity-20261026-010530-6408/Vela-unsigned.ipa`, 9 726 625 octets |
| Extension | `PlugIns/NavActivityExtension.appex` présente, exécutable de 220 888 octets, symboles transport présents, aucune signature |

Le run reste rouge sur trois scénarios déjà documentés avant X-3 : la visionneuse de
`PlaceUITests`, puis les deux contrôles AX5 paysage de recherche et de choix d'itinéraire décrits
dans `QUALITY.md`. Les 23 autres scénarios, dont navigation, hors ligne, lieux enregistrés et X-3,
passent. Les tests visuels de l'écran verrouillé et de la Dynamic Island restent humains.

## Tests humains sur iPhone

Installer en vérifiant que l'outil de sideload signe aussi l'extension. Autoriser les Live
Activities pour Vela et sur l'écran verrouillé.

1. Démarrer « Start transit » sur un itinéraire avec marche, correspondance et descente. Vérifier
   dans l'app la ligne, la direction, l'action, les arrêts et les deux sortes d'horaires.
2. Verrouiller l'écran pendant la marche puis pendant le trajet. Vérifier les mises à jour au
   changement d'arrêt et l'absence de badge quand le flux ne fournit pas de temps réel. Prendre
   `x3-lock-transit.png`.
3. Sur un iPhone équipé, vérifier les présentations compacte, étendue et minimale de la Dynamic
   Island. Prendre `x3-island-compact.png`, `x3-island-expanded.png` et
   `x3-island-minimal.png`.
4. Laisser l'écran éteint puis ouvrir une autre app pendant le trajet. Vérifier que les positions
   continuent sans session audio de navigation, puis que « End » ou l'arrivée arrête aussi la
   localisation en arrière-plan.
5. Forcer l'arrêt de Vela et constater l'absence de nouvelles mises à jour. Rouvrir Vela et vérifier
   le nettoyage de l'activité orpheline.
6. Toucher Previous et Next sur l'écran verrouillé et dans la Dynamic Island étendue, app en
   arrière-plan puis après un arrêt forcé. Vérifier l'étape dans l'app à la réouverture, puis la
   fermeture de l'activité orpheline après un arrêt forcé.
7. Désactiver les Live Activities pour Vela. Le guidage dans l'app doit continuer sans activité.
8. Terminer une session par « End », puis une autre par l'arrivée. Vérifier la disparition du tracé,
   le retour à la carte et la carte de fin avant sa disparition programmée.
