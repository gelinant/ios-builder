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

## Exécution en arrière-plan

ActivityKit affiche un état. Il ne réveille pas Vela, ne demande pas de position et ne fait avancer
aucune étape. Les mises à jour ont lieu pendant que l'app est active, ou pendant qu'une session de
transport explicitement démarrée reçoit légitimement des positions avec la localisation en
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
réel du fixture et « End ». Les captures sont `transit-activity-start.png` et
`transit-activity-next.png`. Elles montrent la carte dans l'app, pas l'écran verrouillé ni la
Dynamic Island.

L'archive est aussi contrôlée pour la présence de `NavActivityExtension.appex` dans l'IPA et pour
l'absence de signature. Les résultats du run final sont consignés dans `PARITY.md`.

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
6. Désactiver les Live Activities pour Vela. Le guidage dans l'app doit continuer sans activité.
7. Terminer une session par « End », puis une autre par l'arrivée. Vérifier la disparition du tracé,
   le retour à la carte et la carte de fin avant sa disparition programmée.
