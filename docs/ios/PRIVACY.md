# Confidentialité sur iOS (PR-1, SET-PRIVACY)

État : branche `ios/set-privacy`. Ce document décrit ce que font réellement les réglages de
confidentialité sur iOS, leurs limites et les preuves automatisées. La référence produit reste
`PRIVACY.md` à la racine du dépôt ; ce fichier ne cite aucune donnée personnelle.

## Consentement au premier lancement

Une feuille plein écran reprend la question d'Android : utiliser Google ou non, avec deux cartes
qui disent ce que chaque choix apporte et ce qui part chez Google, puis un bouton « Choisir ce pour
quoi Google est utilisé » et « Continuer ». Elle ne peut pas être fermée par balayage.

Les réponses sont enregistrées dans les clés d'Android :

- `welcome_done` : la question a reçu une réponse. C'est la clé `Onboarding.welcomeDone`
  d'Android ;
- `ios_google_disabled` : le choix « Utiliser Vela sans Google », la clé que le réglage et
  `OfflineStore` écrivent déjà.

Tant que `welcome_done` est absent, le client HTTP refuse tout hôte Google sur le téléphone et
compte le refus. La règle pure est `PrivacyConsent.googleAllowed(welcomeDone, noGoogle)` et un
test JVM la couvre. La page personnalisée propose les interrupteurs qui existent vraiment sur iOS :
recherche au toucher, avis, photos, chargement complet d'une fiche, popular times. Android y ajoute
les caméras de plaques : iOS n'a pas cette fonction, donc la feuille ne la propose pas.

En Debug, une réponse absente compte comme répondue sauf avec `-VelaFirstRunConsent YES`, pour que
les autres scénarios UI d'un simulateur neuf ne restent pas bloqués derrière la feuille. En
Release, une installation neuve affiche toujours la question. Une mise à jour depuis une version
sans clé la pose une fois.

Limite : la carte derrière la feuille est construite et utilise le style Liberty, sans requête
Google ; les tuiles Google que MapLibre irait chercher lui-même ne passent pas par le client HTTP,
mais aucune n'est demandée avant que l'utilisateur ait répondu.

## Session Google

Sur iOS, une session Google est l'ensemble suivant, tous deux en mémoire :

- le pot de cookies du client HTTP (`CookieJar`, amorcé avec les seuls cookies de consentement
  `SOCS` et `CONSENT`) ;
- le magasin de données non persistant de la WebView cachée (`WKWebsiteDataStore.nonPersistent`),
  avec ses cookies, son cache et son stockage de site.

La page Confidentialité reprend les trois choix d'Android : chaque semaine (par défaut), chaque
jour, à chaque lancement. « Démarrer une nouvelle session maintenant » vide les deux magasins puis
réamorce les cookies de consentement. Aucun lieu enregistré, aucune liste, aucune région
téléchargée n'est touché.

Limite réelle : comme les deux magasins sont en mémoire, iOS repart déjà d'une session neuve à
chaque lancement. Le choix hebdomadaire ou quotidien ne change donc rien entre deux lancements ;
il compte pour un processus qui reste ouvert plusieurs jours, et l'horodatage affiché est celui du
lancement courant. Un test unitaire couvre les périodes et l'échéance (`PrivacyPolicy`).

## Utiliser Vela sans Google

Le réglage écrit `ios_google_disabled` dans la suite de réglages partagée. Le client HTTP
(`URLSessionVelaHttp`) refuse toute requête vers un hôte Google lorsque le réglage est actif ou
lorsque la question de premier lancement n'a pas de réponse : la requête ne quitte pas le
téléphone et le compteur l'enregistre comme bloquée. C'est le filet de sécurité pour les chemins
qui pourraient encore demander Google, notamment le repli Google du routeur hybride quand OSRM ne
répond pas.

Hôtes reconnus : `google.com` et ses domaines pays, `googleapis.com`, `gstatic.com`,
`googleusercontent.com`, les hôtes publicitaires et `doubleclick.net`. Un domaine qui imite
`google` n'est pas compté.

Deux exceptions explicites, chacune avec son interrupteur :

- « Ouvrir les liens Google Maps partagés » (clé Android `google_free_resolve_links`, activé par
  défaut) : un lien court `maps.app.goo.gl` ne dit pas où il pointe. Avec ce réglage, une seule
  requête sans cookie va au raccourcisseur, et le client HTTP l'autorise par le tag
  `RequestTags.allowGoogleWhenOff`. Sans ce réglage, le lien court est refusé. Les liens complets
  `google.com/maps` ne demandent rien. Les listes partagées restent indisponibles.
- « Rechercher les lieux touchés sur Google » (clé Android `map_places_google_lookup`, activé par
  défaut) : désactivé, toucher un lieu de la carte garde la ligne Vela et n'envoie rien. Les
  résultats de recherche et les itinéraires continuent d'utiliser Google, comme sur Android.

Preuves :

- test JVM `OfflineSearchStoreTest.offlineOnlySkipsGoogleAndUsesLocalRows` : la recherche ne
  consulte pas Google et rend les lignes de la région installée ;
- test JVM `PrivacyPolicyTest.googleHostsAreRecognizedWithoutLookalikes` et
  `GoogleRequestCounterTest` : le prédicat d'hôte du compteur et du garde est le même ;
- test JVM `ConsentGateTest` : Google est refusé avant la réponse, quel que soit l'interrupteur ;
- test JVM `MapPoiStoreTest.lookupOffKeepsTheVelaRowAndAsksNothing` : aucun appel à la source ;
- scénario UI `PrivacyUITests.testNoGoogleSearchSendsNothingToGoogle` : le compteur Debug
  `greq` et `gblocked` reste à zéro après une recherche ;
- scénario UI `PrivacyUITests.testNoGoogleDirectionsAndTransitSendNothingToGoogle` : un lien
  d'itinéraire long, un calcul voiture puis un calcul transport, avec `greq=0`.

Le compteur ne voit que le client HTTP principal. Le trafic de la WebView cachée ne passe pas par
lui. Avec « Utiliser Vela sans Google », les stores qui ouvrent une page cachée sont déjà fermés ;
les règles de la WebView ne sont pas un garde NoGoogle.

## Requêtes vers Google

La page Confidentialité affiche un compteur alimenté par `app.vela.core.net.GoogleRequestCounter` :

- par jour et par but (`search`, `photos`, `directions`, `session`, etc., les noms d'Android) ;
- par serveur Google, pour que le chiffre soit vérifiable hôte par hôte ;
- les refus du jour, quand Google est coupé ou la question encore ouverte ;
- « Aujourd'hui : N. Ces 7 derniers jours : environ M par jour. »

Le compteur est enregistré dans la suite de réglages sous `google_request_counter` (chaîne JSON,
quatorze jours). Il est relu au lancement (`PrivacyRequestCounter.start()`) et réécrit au plus une
fois par seconde, plus une écriture immédiate quand l'app passe en arrière-plan ou quand la page
s'ouvre. Il survit donc à une relance, ce que `GoogleRequestCounterTest` et le scénario UI
`testRequestCounterAndClearHistory` vérifient.

« Effacer le compteur » vide uniquement le compteur. Les lieux enregistrés, les listes, les
recherches récentes et les trajets ne sont pas touchés. Le test UI le vérifie en relisant un lieu
enregistré après l'effacement.

Limites honnêtes : les tuiles de la carte (trafic, satellite) sont chargées par MapLibre et ne
passent pas par ce client ; les pages de la WebView cachée non plus. Le chiffre est donc un
plancher, pas un total, et la page le dit.

## Effacer l'historique

« Effacer l'historique » sur la page Confidentialité supprime en une action les recherches
récentes, les lieux récents, l'historique de stationnement et tous les trajets enregistrés
(`SavedStore.clearRecents()`, `SavedStore.clearParkingHistory()`, `TripsStore.deleteAll()`). Les
lieux enregistrés, les listes, Maison et Travail, les réglages et les régions téléchargées restent.
La confirmation reprend le texte d'Android. Le bouton de la page Équipements pour supprimer les
trajets reste en place.

Limite : il n'y a pas d'historique de lieux consultés distinct sur iOS, donc rien de plus à
effacer. Les régions téléchargées se suppriment depuis Hors ligne, les lieux depuis Enregistrés.

## Bloquer la télémétrie des pages Google

Le réglage `block_google_telemetry` est off par défaut. Quand il est actif, une
`WKContentRuleList` séparée est ajoutée à la WebView cachée. Elle bloque :

- `play.google.com/log` ;
- les chemins `/gen_204` ;
- les hôtes `ogads-pa.*`.

La liste est compilée une fois avec la liste de blocage existante, puis seule celle qui est
sélectionnée est ajoutée à la configuration. Un changement s'applique à la prochaine page cachée,
pas à une page déjà chargée. La liste de base de `HiddenWebView` bloquait déjà `/gen_204`,
`play.google.com/log` et `/log?` en permanence ; l'apport du réglage est `ogads-pa.*` et la
possibilité de nommer l'ensemble.

## Export de diagnostics

Le bouton « Exporter la session de débogage » écrit un fichier texte et ouvre le partage iOS
(`UIActivityViewController`). Le fichier contient la version de l'app et son numéro de build, la
version de calibration, les réglages de confidentialité (réponse au premier lancement, NoGoogle,
rotation, télémétrie, recherche au toucher, liens courts, compteurs du jour et de la semaine) et au
plus 200 lignes des catégories OSLog `Web`, `Calibration` et `Privacy`, expurgées comme avant.

Limite : `DiagLog` et son `DiagSink` Android ne sont pas branchés sur iOS, donc l'export ne contient
pas les miettes Kotlin d'Android (recherche, parsing, itinéraires).

## Preuves automatisées de ce lot

- `core-common:jvmTest` : `GoogleRequestCounterTest` (comptage par hôte et par but, restauration
  après relance, fusion et purge des vieux jours, effacement) ;
- `ios-shared:jvmTest` : `ConsentGateTest` (refus avant consentement, interrupteurs) et
  `MapPoiStoreTest.lookupOffKeepsTheVelaRowAndAsksNothing` ;
- `VelaTests/PrivacyTests` : `testConsentGateBlocksGoogleBeforeTheAnswer`,
  `testTheCounterCountsPerHostAndSurvivesRelaunch`, plus les tests de rotation, télémétrie et
  expurgation ;
- `VelaUITests/PrivacyUITests` : `testConsentAndFullPrivacyPage` (feuille de premier lancement,
  personnalisation, page complète) et `testRequestCounterAndClearHistory` (compteur non nul après
  une recherche, conservé après relance, effacé sans perdre un lieu enregistré, historique effacé).
  Captures : `privacy-consent.png`, `privacy-page.png`, `privacy-counter.png`,
  `privacy-counter-cleared.png`, `privacy-history-cleared.png`.

## Reste et risques

- Le repli Google du routeur hybride n'est pas retiré à la source ; il est refusé par le client
  HTTP. Sans OSRM, un itinéraire peut donc échouer au lieu d'utiliser un autre routeur ouvert.
- La recherche sans Google en ligne ne consulte pas Photon sur iOS : elle se limite aux régions
  installées, alors que `PRIVACY.md` décrit Photon pour chaque recherche sans Google.
- Les compteurs ne couvrent ni les tuiles de la carte, ni la WebView cachée.
- Les couches Google « trafic » et « satellite » restent sélectionnables quand Google est coupé :
  MapLibre chargerait alors leurs tuiles directement, hors du client HTTP et donc hors du garde.
  La copie du consentement le dit ; le correctif est de passer `offline || noGoogle` au plan de
  `MapRasterLayers` depuis `MapController`, fichier d'un autre lot.
- La rotation hebdomadaire n'a pas d'effet observable entre deux lancements sur iOS.
- La feuille de consentement s'appuie sur `MapScreen` pour la carte derrière : le style par défaut
  ne demande rien à Google, mais le test ne prouve pas l'absence de toute autre requête native
  avant la réponse.
- Aucun test sur iPhone réel n'a été fait pour ce lot.
