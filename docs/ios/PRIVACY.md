# Confidentialité sur iOS (PR-1)

État : branche `ios/pr1-privacy`. Ce document décrit ce que font réellement les réglages de
confidentialité sur iOS, leurs limites et les preuves automatisées. La référence produit reste
`PRIVACY.md` à la racine du dépôt ; ce fichier ne cite aucune donnée personnelle.

## Session Google

Sur iOS, une session Google est l'ensemble suivant, tous deux en mémoire :

- le pot de cookies du client HTTP (`CookieJar`, un par processus, amorcé avec les seuls cookies
  de consentement `SOCS` et `CONSENT`) ;
- le magasin de données non persistant de la WebView cachée (`WKWebsiteDataStore.nonPersistent`),
  avec ses cookies, son cache et son stockage de site.

`Settings > Confidentialité > Google session` reprend les trois choix d'Android : chaque semaine
(par défaut), chaque jour, à chaque lancement. « Démarrer une nouvelle session maintenant » vide
les deux magasins puis réamorce les cookies de consentement. Aucun lieu enregistré, aucune liste,
aucune région téléchargée n'est touché : ces données vivent dans d'autres magasins SQLite et
fichiers.

Limite réelle : comme les deux magasins sont en mémoire, iOS repart déjà d'une session neuve à
chaque lancement. Le choix hebdomadaire ou quotidien ne change donc rien entre deux lancements ;
il compte pour un processus qui reste ouvert plusieurs jours, et l'horodatage affiché est celui du
lancement courant. Le bouton manuel vide bien les deux magasins de la session en cours. Un test unitaire couvre les
périodes et l'échéance (`PrivacyPolicy`), et un scénario UI change le mode, démarre une session
et vérifie l'horodatage.

La marque « vue limitée » de `GoogleStanding` reste en mémoire pour la même raison : un nouveau
lancement est une nouvelle session, donc une nouvelle évaluation.

## Utiliser Vela sans Google

Le réglage existant écrit `ios_google_disabled` dans la suite de réglages partagée. En plus des
gardes déjà présentes dans les stores Kotlin (recherche hors ligne, fiche lieu, POI de carte,
Street View, listes), le client HTTP (`URLSessionVelaHttp`) refuse maintenant toute requête vers
un hôte Google lorsque le réglage est actif : la requête ne quitte pas le téléphone et le compteur
Debug l'enregistre comme bloquée. C'est le filet de sécurité pour les chemins qui pourraient
encore demander Google, notamment le repli Google du routeur hybride quand OSRM ne répond pas.

Hôtes reconnus : `google.com` et ses domaines pays, `googleapis.com`, `gstatic.com`,
`googleusercontent.com`, les hôtes publicitaires et `doubleclick.net`. Un domaine qui imite
`google` n'est pas compté.

Preuves :

- test JVM `OfflineSearchStoreTest.offlineOnlySkipsGoogleAndUsesLocalRows` : la recherche ne
  consulte pas Google et rend les lignes de la région installée ;
- test JVM `PrivacyPolicyTest.googleHostsAreRecognizedWithoutLookalikes` : le prédicat du compteur
  et du garde est le même ;
- scénario UI `PrivacyUITests.testNoGoogleSearchSendsNothingToGoogle` : le compteur Debug
  `greq` et `gblocked` reste à zéro après une recherche ;
- scénario UI `PrivacyUITests.testNoGoogleDirectionsAndTransitSendNothingToGoogle` : un lien
  d'itinéraire long, un calcul voiture puis un calcul transport, avec `greq=0`. Le compteur
  `gblocked` est rapporté : s'il est supérieur à zéro, un chemin a tenté Google et a été refusé,
  ce qui reste sans envoi mais signale une fuite de code à corriger.

Le compteur ne voit que le client HTTP principal. Le trafic de la WebView cachée ne passe pas par
lui. Avec « Utiliser Vela sans Google », les stores qui ouvrent une page cachée sont déjà fermés ;
les règles de la WebView ne sont pas un garde NoGoogle.

## Bloquer la télémétrie des pages Google

Le réglage `settings_block_google_telemetry` est off par défaut. Quand il est actif, une
`WKContentRuleList` séparée est ajoutée à la WebView cachée. Elle bloque :

- `play.google.com/log` ;
- les chemins `/gen_204` ;
- les hôtes `ogads-pa.*`.

La liste est compilée une fois avec la liste de blocage existante, puis seule celle qui est
sélectionnée est ajoutée à la configuration. Un changement s'applique à la prochaine page cachée,
pas à une page déjà chargée.

Couverture réelle : la liste de base de `HiddenWebView` bloquait déjà `/gen_204`,
`play.google.com/log` et `/log?` en permanence, comme `BlockedHosts` sur Android. L'apport du
réglage est donc `ogads-pa.*` et la possibilité de nommer l'ensemble ; désactiver le réglage ne
réactive pas les deux autres. Les requêtes principales de recherche, de fiche, de photos et
d'itinéraires ne passent jamais par cette liste et ne sont jamais bloquées par elle. Un test
unitaire vérifie les trois filtres, leur JSON et leur compilation par WebKit.

## Export de diagnostics

Le bouton `Exporter la session de débogage` écrit un fichier texte et ouvre le partage iOS
(`UIActivityViewController`). Le fichier contient :

- la version de l'app et son numéro de build ;
- la version de calibration ;
- les réglages de confidentialité (`no_google`, mode de rotation, télémétrie, compteurs de
  requêtes Google) ;
- au plus 200 lignes des catégories OSLog `Web`, `Calibration` et `Privacy`.

Chaque ligne est expurgée : les URL perdent tout sauf leur hôte, les paires de coordonnées et les
longues suites de chiffres deviennent `<coordinates>` ou `<number>`, et le texte entre guillemets
est remplacé. Aucun nom de lieu, aucune requête tapée et aucune position ne doit sortir. Les
autres catégories de journal, notamment la navigation, ne sont pas exportées parce qu'elles
peuvent contenir des noms de rues.

Limite : `DiagLog` et son `DiagSink` Android ne sont pas branchés sur iOS. Les sources partagées
reçoivent `DiagSink.NONE`, donc l'export ne contient pas les miettes Kotlin d'Android (recherche,
parsing, itinéraires). Il faudrait construire un `DiagSink` Swift et l'injecter dans `IosGraph`
pour les obtenir.

## Reste et risques

- Le repli Google du routeur hybride n'est pas retiré à la source ; il est refusé par le client
  HTTP. Sans OSRM, un itinéraire peut donc échouer au lieu d'utiliser un autre routeur ouvert.
- La recherche sans Google en ligne ne consulte pas Photon sur iOS : elle se limite aux régions
  installées, alors que `PRIVACY.md` décrit Photon pour chaque recherche sans Google. C'est un
  écart préexistant de `SearchStore`, hors de ce lot.
- Les compteurs de requêtes Google ne couvrent ni les tuiles de la carte, ni la WebView cachée.
- La rotation hebdomadaire n'a pas d'effet observable entre deux lancements sur iOS, pour la
  raison expliquée plus haut.
- Aucun test sur iPhone réel n'a été fait pour ce lot.
