# Calques du monde : hôte partagé (WLD-1)

État au 2026-10-28, branche `ios/wld-1`, depuis `ios/main`. Ce document décrit l'hôte commun des
six calques du monde. Aucun calque métier n'est livré ici : `aviation`, `maritime`, `energy`,
`notam`, `satellite` et `wiki` restent désactivés et marqués « not installed » tant que leur lot
n'a pas remplacé son fichier.

## Fichiers

| Fichier | Rôle |
|---|---|
| `iosApp/Vela/Map/Layers/WorldLayers.swift` | protocole `WorldLayer`, `WorldLayersHub`, notification de recentrage |
| `iosApp/Vela/Map/Layers/WorldLayerSection.swift` | section générique de la feuille de couches |
| `iosApp/Vela/Map/Layers/AviationLayer.swift` | squelette A-1 |
| `iosApp/Vela/Map/Layers/MaritimeLayer.swift` | squelette A-2 |
| `iosApp/Vela/Map/Layers/EnergyLayer.swift` | squelette A-3 |
| `iosApp/Vela/Map/Layers/NotamLayer.swift` | squelette A-4 |
| `iosApp/Vela/Map/Layers/SatelliteLayer.swift` | squelette G-3 |
| `iosApp/Vela/Map/Layers/WikiLayer.swift` | squelette W-1 |
| `iosApp/Vela/Platform/KeychainSecrets.swift` | stockage des clés dans le Keychain |
| `ios-shared/src/commonMain/kotlin/app/vela/ios/world/WorldLayerState.kt` | catalogue, fenêtres de fraîcheur, états |
| `ios-shared/src/commonMain/kotlin/app/vela/ios/world/WorldLayerSettings.kt` | interrupteurs persistés, horodatages, présence de clé |

## Socket d'un futur calque

Un lot de calque ne modifie ni `WorldLayers.swift` ni `WorldLayerSection.swift`. Il remplace
uniquement son propre fichier :

1. garder `id` égal à l'identifiant du catalogue (`aviation`, `maritime`, ...) ;
2. renseigner `title` et `source` (nom lisible, sans URL) ;
3. implémenter `refresh(viewport:)` : une requête au plus par appel, retour
   `WorldLayerRefresh(updatedAtMs:rows:)`, ou `nil` en cas d'échec sans effacer les données déjà
   reçues ;
4. implémenter `apply(style:offline:)` : ajouter les sources MapLibre en mémoire, ne rien dessiner
   hors ligne si la source est distante ;
5. passer `installed` à `true` seulement quand les deux appels produisent réellement des données.

L'hôte appelle `refresh` et `apply` uniquement pour un calque installé et allumé, et seulement
lorsque la caméra bouge. Il n'y a ni minuterie, ni lien d'affichage, ni travail quand la feuille est
fermée. `WorldLayerSection` lit les états au moment où la feuille apparaît, après un changement
d'interrupteur ou après un rafraîchissement.

Une ligne de résultat qui porte une coordonnée appelle `WorldLayers.focus(latitude:longitude:)`.
`MapController` écoute cette notification et recentre la carte ; c'est le seul point d'entrée ajouté
au contrôleur.

## Interrupteurs et clés

Les interrupteurs sont coupés par défaut et vivent dans le magasin `vela_world`, sous les clés
stables suivantes :

| Calque | Interrupteur | Horodatage | Compte Keychain |
|---|---|---|---|
| aviation | `world_layer_aviation_on` | `world_layer_aviation_updated_at` | `world_layer_aviation_key` |
| maritime | `world_layer_maritime_on` | `world_layer_maritime_updated_at` | `world_layer_maritime_key` |
| energy | `world_layer_energy_on` | `world_layer_energy_updated_at` | `world_layer_energy_key` |
| notam | `world_layer_notam_on` | `world_layer_notam_updated_at` | `world_layer_notam_key` |
| satellite | `world_layer_satellite_on` | `world_layer_satellite_updated_at` | `world_layer_satellite_key` |
| wiki | `world_layer_wiki_on` | `world_layer_wiki_updated_at` | `world_layer_wiki_key` |

Les clés ne passent jamais par `UserDefaults`, `vela_settings`, `calibration.json` ni un journal.
`KeychainSecrets` écrit sous le service `app.vela.ios.world`, avec l'accessibilité
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. La feuille n'affiche que « Key saved » ou
« No key saved » et un champ sécurisé pour remplacer la valeur. Le Kotlin ne lit jamais la valeur :
`WorldSecretStore.has` répond seulement par un booléen.

## Fraîcheur et états

Chaque calque déclare sa fenêtre. Une donnée plus vieille que sa fenêtre passe à « late » et perd
toute prétention au direct.

| Calque | Fenêtre | Clé requise | Raison |
|---|---|---|---|
| aviation | 60 s | non | cache de 10 s et quota 429 côté A-1 |
| maritime | 5 min | non | cache Digitraffic de A-2 |
| energy | 30 min | non | péremption NESO de A-3 ; les clés Electricity Maps et Radar restent facultatives |
| notam | 15 min | oui | accès FAA NMS sur demande |
| satellite | 2 h | non | cache TLE de G-3 |
| wiki | 24 h | non | cache Wikivoyage de W-1 |

Trois états seulement :

- `fresh` : calque installé, clé présente si elle est requise, données datées dans la fenêtre ;
- `late` : mêmes conditions, mais données plus vieilles que la fenêtre ;
- `unavailable` : calque non installé, clé requise absente, ou aucune donnée reçue.

## Preuves

- JVM : `WorldLayerSettingsTest` vérifie que les six interrupteurs partent coupés, persistent sous
  les clés stables, que la présence d'une clé ne laisse aucun texte en clair dans le magasin de
  réglages ni dans l'état, que la clé manquante rend le calque indisponible, que les trois états
  suivent la fenêtre propre à chaque calque et que le catalogue garde son ordre.
- Simulateur : `WorldLayersUITests.testWorldLayersStartHidden` ouvre la feuille, vérifie les six
  lignes désactivées avec la valeur « not installed », le champ de clé NOTAM et la capture
  `world-layers.png`, puis inscrit `world_layers=0` et `world_requests=0` au résumé.
- Run Mac `wld-1-20261028-110902-546` : le scénario passe en 59,5 s, avec 434 tests JVM, 338 tests
  Kotlin simulateur et 151 tests Swift sans échec. Le résumé rend `world_layers=0` et
  `world_requests=0` ; la capture montre la section « World layers » avec Aircraft et Ships
  désactivés, leur source, « Data: no data yet » et « Unavailable, not installed ».
- Aucune requête réseau n'est ajoutée par ce lot. Aucun hôte nouveau n'apparaît dans le code, donc
  `Notices.json` ne change pas ; la sonde rend « notices: ok, 26 entries ».

## Limites

- A la livraison de WLD-1, les six entrees etaient desactivees. Au 30 octobre, cinq calques sont
  installes (aviation, maritime, energie, satellites, wiki) et un seul reste indisponible : NOTAM,
  faute d'identifiants FAA.
- L'hôte ne dessine rien tant qu'un lot n'a pas mis `installed` à `true` dans son fichier.
- Aucun test iPhone n'est fait pour ce lot.
- La notification de recentrage ne sert qu'aux lignes déjà reçues ; aucun calque n'en produit ici.

## W-1 : le calque Wikivoyage

`iosApp/Vela/Map/Layers/WikiLayer.swift` remplace le squelette et déclare `installed = true`.
L'hôte WLD-1 n'est pas modifié : la ligne wiki de la feuille des couches devient active, avec les
mêmes clés `world_layer_wiki_on` et `world_layer_wiki_updated_at` et la même fenêtre de 24 h.

- `refresh(viewport:)` interroge une fois `www.wikidata.org` (`wbgetentities`) pour une liste
  curatée de vingt destinations. Chaque élément dont P625 tombe dans le viewport devient une
  ligne `world-row-wiki:<langue>:<titre>`. Un élément sans coordonnée, sans sitelink Wikivoyage ou
  hors du viewport n'entre pas dans le calque. La charge est mise en cache 24 h dans `vela_wiki`,
  donc un déplacement de caméra dans la fenêtre ne refait aucune requête.
- `apply(style:offline:)` ne dessine rien hors ligne et rien tant que `rows` est vide : aucune
  source, aucune couche n'est ajoutée avant la première charge utile. Ensuite, une source en
  mémoire porte un point turquoise et le titre de l'article, en anglais ou dans la langue de
  l'interface quand la sitelink existe.
- Un appui sur une ligne recentre la carte par le chemin WLD-1 existant. Le calque écoute la même
  notification et ouvre la page de l'article dans une feuille `SFSafariViewController`, sans
  modifier `MapController.swift` ni `WorldLayerSection.swift`.
- La liste est curatée parce que l'API Wikidata des deux hôtes autorisés n'offre pas de recherche
  « éléments géolocalisés dans cette boîte avec une page Wikivoyage ». La couverture du calque est
  donc celle de ces vingt villes, pas celle de tout Wikivoyage.

Conséquence pour le test WLD-1 : `WorldLayersUITests.testWorldLayersStartHidden` attend encore
`world_layers=0` et six lignes « not installed ». Avec W-1, le calque wiki est installé et la
ligne compte `world_layers=1`. Ce test appartient à la voie du lot WLD-1 et n'est pas modifié ici ;
il doit accepter un calque installé (wiki) et cinq squelettes.

Preuves Linux : `:core-common:jvmTest` rend 995 tests, `:ios-shared:jvmTest` 441, dont
`WikiStoreTest` pour le filtre du viewport et le cache de 24 h ; `compileKotlinIosSimulatorArm64`
passe. Le run Mac `w1-wiki-20261028-123655-16128` compile le calque, mais le scénario de la fiche
s'arrête sur un identifiant d'accessibilité de la section avant d'atteindre la couche. La capture
`wiki-layer.png` et la ligne `world-row-wiki:` restent à obtenir ; le test de la couche est prêt
dans `PlaceKnowledgeUITests.testWikidataAndWikivoyage`.

## A-1 : avions depuis adsb.lol

Cette section est ajoutée par le lot A-1. Le reste du document décrit l'hôte WLD-1 et reste
valable : le calque aviation remplace son propre fichier, sans toucher `WorldLayers.swift` ni
`WorldLayerSection.swift`.

### Source et requête

Le calque interroge `https://api.adsb.lol/v2/point/{lat}/{lon}/{radius}`, sous ODbL 1.0, avec
l'attribution « Data from adsb.lol, ODbL 1.0 ». La notice `adsb-lol` couvre l'hôte
`api.adsb.lol` dans `iosApp/Vela/Settings/Notices.json`.

- Le milieu et le rayon viennent de la vue courante. Le rayon est la demi-diagonale de la boîte,
  arrondie et bornée entre 1 et 100 milles marins. L'API accepte jusqu'à 250, le lot n'en demande
  jamais plus de 100.
- Une seule requête par déplacement de caméra, sans minuterie. La couche ne travaille que si son
  interrupteur est allumé, et l'hôte ne l'appelle que dans ce cas.
- La réponse est filtrée sur la boîte visible, puis triée par distance au milieu. Le lot garde les
  300 avions les plus proches. Un avion sans coordonnée est ignoré.
- Chaque avion porte son hexadécimal, son indicatif quand le flux en donne un, sa latitude, sa
  longitude, son altitude, son cap et sa vitesse sol. Un indicatif absent laisse l'hexadécimal en
  majuscules : aucun nom ni numéro de vol n'est fabriqué. Le champ `alt_baro` à `ground` donne
  l'état au sol et pas une altitude de 0 pied. Un cap absent vaut -1 et ne dessine aucune rotation
  inventée.
- Aucune route, aucun aéroport de départ ou d'arrivée et aucune position prédite entre deux
  réponses. Le flux n'en fournit pas et le calque n'en devine pas.

### Dessin et fiche

Le dessin est une `MLNShapeSource` en mémoire, `vela-aircraft-src`, avec une couche symbole
`vela-aircraft` insérée sous les étiquettes. L'icône est un avion blanc dans un disque bleu, créé
par le calque et ajouté au style avec `setImage` : aucun sprite distant n'est requis. Le cap
tourne l'icône dans le repère de la carte, l'indicatif est écrit à côté.

Un toucher sur un avion de la carte, ou sur sa ligne dans la feuille, ouvre une petite fiche avec
l'indicatif, l'altitude, le cap, la vitesse et la ligne d'attribution. La carte est interrogée par
`visibleFeatures(at:styleLayerIdentifiers:)` sur la couche `vela-aircraft`. Aucune ligne de la
feuille ne porte de coordonnée inventée : le recentrage existant de WLD-1 continue de fonctionner.

### Fraîcheur, cache et quota

- Une réponse acceptée est réutilisée pendant 10 secondes. Un déplacement qui reste dans cette
  fenêtre ne dépense pas de requête.
- La fenêtre de fraîcheur du catalogue est de 60 secondes. `snapshot` renvoie les avions seulement
  si la donnée est dans la fenêtre. Passé 60 secondes, la phase devient `late`, la liste d'avions
  est vide et le calque retire les symboles : une position périmée n'est jamais laissée sur la
  carte avec l'air d'être en direct.
- Une réponse HTTP 429 met le calque en phase `quota`, vide les avions et refuse toute requête
  pendant 60 secondes. La feuille affiche une ligne « Quota reached, retry in N s ». Le compteur
  repart après la fenêtre.
- Un échec réseau ou un code autre que 200 garde les données encore fraîches, avec une ligne
  d'état qui nomme l'échec. Sans donnée utilisable, l'état est `unavailable`. Une réponse
  illisible ne remplace pas les données déjà reçues.
- Hors ligne, `apply` ne dessine rien et `refresh` ne fait aucune requête.
- `installed` vaut `true` : `refresh` et `apply` produisent tous les deux des données, et le test
  de la feuille le vérifie.

### Frontière entre fixture et direct

La capture `iosApp/Vela/Resources/world/aviation-fixture.json` est une réponse réelle de
`/v2/point/37.6200/-122.3900/10` prise le 2026-10-28. Le scénario simulateur lance l'application
avec `-VelaAviationFixture YES` et `AviationTestSupport` lit ce fichier dans le bundle. Le chemin
du magasin est le même que pour le direct : filtrage de la vue, plafond de 300, tri, fraîcheur et
lignes. Seule la requête réseau est remplacée.

Le mode fixture est compilé seulement en Debug et ne sert aucune donnée en production. Le rapport
du scénario écrit `aviation_source=fixture` et `aviation_live=0`. En direct, le magasin marque
`live = true` seulement après une réponse 200 encore dans la fenêtre de 60 secondes. Une passe
live sur le Mac reste facultative et n'a pas été faite dans ce lot.

### Preuves

- JVM : `AviationStoreTest` sur la fixture capturée : indicatif et altitude, avion au sol, cap
  absent, avion hors vue refusé, plafond de 300, cache de 10 secondes, 429 sans requête pendant
  60 secondes, péremption à 60 secondes et échec HTTP qui conserve une donnée encore fraîche.
- Simulateur : `AviationLayerUITests.testAircraftAroundView` avec la caméra
  `37.6200,-122.3900,13`. Le scénario allume Aircraft, déplace la carte, capture `aviation.png`,
  rouvre la feuille, touche une ligne d'avion et capture `aviation-detail.png`.
- Run Mac `a1-adsb-20261028-122341-29296` : le scénario passe en 87,2 secondes, avec 440 tests JVM,
  344 tests Kotlin simulateur et 151 tests Swift sans échec. Le résumé rend
  `aviation_count=19`, `aviation_source=fixture` et `aviation_live=0`. La capture
  `aviation-detail.png` montre la fiche OPS15 (« On ground », 0 kt), la ligne d'attribution et les
  trois valeurs de rapport ; la feuille montre Aircraft frais avec ses lignes OPS15 et OPS44.
  Dans `aviation.png`, le bandeau de débogage de l'application couvre la moitié haute de la carte
  et masque une partie des symboles ; la preuve du nombre vient de la liste et de la fiche.

### Limites

- adsb.lol est un service communautaire sans SLA ni quota garanti. La couverture est inégale
  au-dessus des océans et en Afrique, et une réponse vide n'est pas une preuve d'absence d'avion.
- Aucun flux militaire officiel n'est employé et aucun avion n'est mis en avant selon son type.
- ODbL 1.0 : le lot ne livre aucune base dérivée, seulement un affichage temporaire avec
  attribution.
- Les positions ne sont ni interpolées ni prédites. Deux requêtes successives peuvent montrer un
  saut, et la fenêtre de 60 secondes décide seule de l'arrêt du dessin.
- Un toucher sur la carte peut manquer un petit symbole ; la ligne correspondante dans la feuille
  reste le chemin déterministe vers la fiche.
- Aucune passe iPhone n'a été faite pour ce lot.
## A-2 : navires AIS et liste UKMTO

État au 2026-10-28, branche `ios/a2-marine`, depuis `ios/main` au commit `66e3ca7e`.

### Ce que le calque dessine et ce qu'il refuse de dessiner

`MaritimeLayer` est installé : `installed = true`, car `refresh` et `apply` produisent réellement
des données. La ligne « Ships » de la feuille s'allume donc, contrairement aux cinq autres calques.
Le calque ne dessine pas les avis UKMTO sur la carte : la liste UKMTO est une liste de liens dans
la feuille, sans point et sans zone.

- **Navires Digitraffic.** `https://meri.digitraffic.fi/api/ais/v1/locations` donne les positions
  autour de la vue ; `https://meri.digitraffic.fi/api/ais/v1/vessels` donne le nom et le type AIS,
  gardés six heures en mémoire. Les deux requêtes portent l'en-tête `Digitraffic-User` exigé par le
  service et acceptent une réponse gzip. Chaque navire affiche son nom ou son MMSI, son type, sa
  vitesse, son cap et son MMSI. Un navire sans position, sans MMSI ou avec une coordonnée hors
  bornes est écarté.
- **Déduplication.** Une position venue des deux sources pour le même MMSI est fusionnée : la plus
  récente gagne. À horodatage égal, Digitraffic reste. Le résultat est trié par distance au milieu
  de la vue et plafonné à 500 navires.
- **Cache.** Une réponse est gardée cinq minutes tant que le milieu de la vue reste dans la boîte
  demandée. AISHub reçoit donc au plus une requête par cinq minutes, sous sa limite d'une par
  minute.
- **Finlande seulement.** Digitraffic ne couvre que les eaux finlandaises. Hors de cette boîte,
  aucune requête Digitraffic n'est envoyée et la ligne de couverture le dit. Sans clé AISHub, la
  ligne « AISHub: key required » est toujours visible : le calque ne montre jamais une mer vide
  silencieuse. Un échec total sans données antérieures rend `refresh` nul, et la feuille affiche
  « Unavailable, no data yet », jamais « aucun navire ».
- **AISHub.** Le service répond en XML même quand le JSON est demandé, et les deux formes sont
  lues. Une clé refusée produit « AISHub: key rejected » et Digitraffic reste affiché. La clé est
  un compte du Keychain, `world_layer_maritime_key`, sous le service `app.vela.ios.world`.
  `MaritimeLayer` est le seul endroit qui relit la valeur, uniquement pendant un rafraîchissement
  du calque allumé. Le Kotlin ne la reçoit que pour construire l'URL, ne l'écrit ni dans un journal,
  ni dans un réglage, ni dans une ligne de résultat. `WorldLayerSettings` continue de ne connaître
  que sa présence.
- **UKMTO.** La liste vient du JSON public que le site UKMTO charge lui-même
  (`https://sccd.royalnavy.mod.uk/api/ukmto/all`). Le titre est le numéro et le type
  (« UKMTO #154 Attack »), la date est celle de l'incident en UTC, le lien pointe vers
  `https://www.ukmto.org/recent-incidents#<sitecoreId>`. Le texte de l'avis, le lieu et les
  coordonnées ne sont pas lus. Vingt entrées au plus, les plus récentes d'abord. L'en-tête de la
  liste dit « link list only » et « Not a live advisory feed ». Aucune zone n'est dessinée.
- **Navigation.** Chaque ligne de couverture AIS porte « Not for navigation ». La source affichée
  est « Digitraffic AIS, CC BY 4.0; AISHub with a member key ».

### Hôte et rafraîchissement

WLD-1 ne rafraîchit un calque que lorsque la caméra bouge. Activer « Ships » ne déclenche donc pas
de requête : il faut déplacer la carte une fois. L'hôte applique le style avant de lancer
`refresh` ; `MaritimeLayer` réapplique le style à la fin du rafraîchissement pour que la première
réponse atteigne la carte sans second déplacement. Un changement de style ou de carte hors ligne
repeint au déplacement suivant. Les lignes de navire portent une coordonnée et ramènent la carte au
toucher. Les lignes UKMTO n'en portent pas : l'hôte les laisse en lecture seule, avec le lien
visible dans le détail.

### Preuves

- JVM : `MaritimeStoreTest` couvre le GeoJSON Digitraffic, les métadonnées de navires, le XML et le
  JSON AISHub, le refus de clé, la déduplication par MMSI dans les deux sens, la chute d'un navire
  sans position, le plafond de 500, le cache de cinq minutes, la sortie de la boîte en cache et
  l'absence de clé. `UkmtoStoreTest` couvre le titre, la date et le lien seulement, l'ordre du plus
  récent au plus ancien, le silence sur le texte d'avis, le cache de dix minutes et l'échec sans
  liste. Les deux fichiers passent sous
  `flock /tmp/opencode/gradle.lock ./gradlew --no-daemon -Pvela.iosOnly=true :core-common:jvmTest
  :ios-shared:jvmTest :ios-shared:compileKotlinIosSimulatorArm64`.
- Simulateur : `MaritimeUITests.testShipsAndUkmtoList` part de Helsinki avec
  `-VelaMaritimeFixture`, allume « Ships », déplace la carte, vérifie le nom, le type, la vitesse,
  le cap et le MMSI d'un navire, la mention Finlande seulement et « Not for navigation », puis
  l'en-tête UKMTO et un lien. Captures `maritime.png`, `maritime-detail.png` et `ukmto.png` ; lignes
  `maritime_count>0` et `ukmto_mode=link_only`. Aucune requête réseau n'est faite par ce scénario.
- Run Mac `a2-marine-20261028-124040-18722` : `MaritimeUITests.testShipsAndUkmtoList` passe en
  105,8 s, avec 455 tests JVM, 359 tests Kotlin simulateur et 151 tests Swift sans échec. Le résumé
  rend `maritime_count=3` et `ukmto_mode=link_only`. Le run est vert après un premier échec de
  compilation Swift (`try` manquant sur l'appel SKIE), corrigé avant le rerun unique. Les captures
  `maritime.png`, `maritime-detail.png` et `ukmto.png` sont publiées ; `maritime.png` montre la
  liste UKMTO complète sous les navires.
- `python3 scripts/ios/check_notices.py` rend « notices: ok, 29 entries » avec les notices
  `digitraffic-ais`, `aishub` et `ukmto`.

### Limites

- Digitraffic ne couvre que la Finlande. AISHub ne fonctionne qu'avec la clé personnelle d'un
  membre qui alimente une station, et ses conditions interdisent de republier les données brutes.
- Les données AIS ne servent pas à la navigation. Elles peuvent être incomplètes, en retard ou
  absentes, et la vie privée des navires n'est pas garantie par les sources.
- UKMTO est sous Crown copyright sans conditions de réemploi ouvertes. Seuls le titre, la date
  et le lien sont affichés ; le texte des avis n'est pas recopié et aucune zone n'est dessinée.
- La liste UKMTO dépend d'un point d'entrée public non documenté du site UKMTO. S'il change, le
  calque affiche « UKMTO: link list unavailable » et ne fabrique aucun avis.
- Aucun test iPhone n'est fait pour ce lot.
- La capture `ukmto.png` du run a été prise alors que l'en-tête UKMTO existait hors écran. Le test
  corrigé exige maintenant une ligne visible, mais ce correctif de défilement n'a pas été rejoué sur
  le Mac, faute de budget de run. `maritime.png` montre la liste complète et le scénario vérifie les
  libellés de l'en-tête et d'un lien.
## A-3 : intensité carbone et Cloudflare Radar

État au 2026-10-28, branche `ios/a3-energy`, depuis `ios/main`. Le calque `energy` est installé :
`EnergyLayer.installed` vaut `true`, donc la ligne WLD-1 n'est plus désactivée. Le fichier
`WorldLayers.swift` et la section générique ne changent pas.

### Sources et états

| Source | Accès | Fenêtre | État sans clé |
|---|---|---|---|
| NESO Carbon Intensity | sans clé, CC BY 4.0 | 30 min | dessine toujours les 14 zones britanniques |
| Electricity Maps | clé utilisateur, conditions du service | 30 min | « Electricity Maps: key required » |
| Cloudflare Radar | jeton utilisateur, CC BY-NC 4.0 | 30 min | « Cloudflare Radar: token missing » |

`https://api.carbonintensity.org.uk/regional` renvoie les 14 zones DNO et des agrégats. Les
agrégats 15 à 18 sont ignorés, ainsi que toute zone sans point central connu. Les formes de
`iosApp/Vela/Resources/world/neso-regions.json` sont simplifiées depuis les limites DNO publiées
par NESO ; les points centraux sont des centroïdes approximatifs et ne sont pas des points officiels. La
couleur suit l'indice NESO : très faible, faible, modéré, élevé, très élevé, inconnu.

Electricity Maps n'a pas de palier gratuit anonyme. Sans clé, le calque ne fait aucune requête
Electricity Maps et affiche une ligne « key required » : une carte vide ne doit jamais se lire
comme « zéro carbone ». Avec une clé, la requête v3 porte le jeton dans l'en-tête `auth-token`.

Cloudflare Radar interroge les annotations de pannes sur sept jours et le classement des attaques
de couche 3. Le jeton part dans `Authorization: Bearer`. Radar ne voit que le trafic qui traverse
Cloudflare : chaque ligne et la section le disent. Les pannes sont des annotations par pays ; un
marqueur n'est dessiné que si un point central de pays approximatif existe, et il indique un pays, jamais
le site de la panne. Les attaques sont des couples origine et destination, sans coordonnée propre.

### Clés et confidentialité

Les comptes Keychain sont `world_layer_energy_key` pour le jeton Radar et
`world_layer_energy_maps_key` pour la clé Electricity Maps, dans le service
`app.vela.ios.world`. Le champ générique de WLD-1 ne s'affiche pas pour `energy`, parce que le
calque carbon est sans clé. Une alerte unique, au premier affichage du calque dans un build réel,
propose donc les deux valeurs dans des champs sécurisés et les écrit avec `KeychainSecrets`. Le
texte de l'alerte ne répète jamais une valeur.

Aucune clé n'entre dans `vela_world`, `vela_settings`, `UserDefaults`, une ligne de débogage, une
ligne de liste ou une capture. Seule la présence est lue par `WorldLayerSettings` et par la ligne
`energy-debug`. Les tests Kotlin vérifient que l'instantané, l'état et la ligne de débogage ne
contiennent pas le jeton. Aucune valeur n'est écrite dans le journal.

### Comportement

- `EnergyLayer.refresh` fait au plus une requête NESO, une requête Electricity Maps seulement
  avec une clé, puis deux requêtes Radar seulement avec un jeton. Une panne conserve les données
  précédentes et les laisse vieillir.
- Les données de plus de 30 minutes ne sont plus dessinées ; le panneau les marque « Late ».
- Hors ligne, `apply` ne dessine rien, comme pour les autres calques distants.
- La ligne `energy-debug`, présente seulement en Debug, porte
  `energy_source=neso radar_state=fresh|key_required energy_regions=14 electricity_maps=ok|key_required|no_data`.
  Elle ne contient aucune clé.
- Les traps de l'API sont traduits en états : jeton absent, jeton refusé ou réseau, aucune donnée.

### Preuves

- `EnergyStoreTest` : les 14 zones britanniques et le rejet des agrégats, l'horodatage sans
  secondes de NESO, la péremption à 30 min, l'absence de clé Electricity Maps sans requête et
  l'état `key_required`, la clé envoyée dans `auth-token` mais absente de l'instantané.
- `RadarStoreTest` : jeton absent sans requête, pannes et attaques datées, péremption à 30 min,
  flux vide mais frais, retrait du jeton qui efface les événements, absence de jeton dans l'état,
  la ligne de débogage et le magasin de réglages.
- `EnergyRadarUITests.testCarbonAndRadar` : captures `energy.png`, `radar.png` et
  `energy-key-required.png`, lignes `energy_source=neso` et `radar_state=fresh` puis
  `radar_state=key_required`. Les réponses viennent de fixtures Debug, sans réseau ni vrai jeton.
- Run Mac `a3-energy-20261028-134410-18809` : la compilation simulateur passe, 151 tests Swift, 445 tests JVM et 349 tests Kotlin simulateur passent sans échec. `EnergyRadarUITests.testCarbonAndRadar` passe en 286,2 s. Le résumé rend `energy_source=neso`, `radar_state=fresh` et `radar_state=key_required` ; les captures `energy.png`, `radar.png` et `energy-key-required.png` sont publiées.

### Limites

- Sans clé, le calque ne couvre que la Grande-Bretagne. Ailleurs, il ne dessine pas de zones et
  ne prétend pas connaître le mix local.
- Electricity Maps dépend des conditions du service et d'une clé personnelle.
- Radar est sous CC BY-NC 4.0 : les données ne conviennent pas à un usage commercial.
- Radar ne voit que le trafic Cloudflare ; une absence d'événement n'est pas un « tout va bien »
  pour Internet.
- Les points centraux de pays et les formes de zones sont approximatifs. Ils servent à situer une
  annotation, pas à délimiter une frontière.
- Le champ de clé de WLD-1 reste réservé aux calques qui exigent une clé. A-3 ajoute une alerte
  dédiée ; une future section de réglages pourra la remplacer sans toucher au contrat du calque.
- Aucune passe iPhone humaine n'est faite pour ce lot. La passe live NESO reste une vérification
  manuelle facultative.

## A-4 : NOTAM, accès FAA non obtenu, aucune couche

État au 2026-10-30, branche `ios/a4-notam`, depuis `ios/main`. Le lot A-4 est **abandonné** :
l'API NOTAM de la FAA n'est pas accessible à un client tiers sans identifiants délivrés par la FAA.
Aucune couche NOTAM n'est installée, aucun hôte n'est appelé et aucune notice n'est ajoutée.

### Verdict d'accès

| Question | Réponse établie le 2026-10-30 |
|---|---|
| Point d'entrée | Le service visé est le NOTAM Management Service (NMS). Le portail `nms.aim.faa.gov` décrit l'API de distribution NMS. Les chemins exacts, la base et le document OpenAPI ne sont pas publiés sans identifiants. |
| Modèle d'authentification | OAuth2 `client_credentials` avec un `client_id` et un `client_secret` délivrés par la FAA. Un tiers public décrit aussi un jeton OAuth2 et un appel `/v1/notams` en GeoJSON, mais la documentation officielle ne publie ni la base de production ni le contrat. |
| Délivrance | Sur demande par courriel, pas en self-serve. La FAA demande d'écrire à `7-AWA-NAIMES@faa.gov` depuis la page NMS et sa FAQ, et à `NOTAMS@faa.gov` depuis le portail NMS. Le compteur officiel du portail indique 261 utilisateurs API onboardés au 2026-04-18, ce qui confirme un accès accordé au cas par cas. |
| Attribution exigée par le lot | « FAA NOTAM data, U.S. Government work, not for operational use ». Les œuvres du gouvernement américain ne sont pas protégées par le droit d'auteur aux États-Unis (17 U.S.C. §105), mais l'avertissement « not for operational use » reste obligatoire dans l'application. |
| Scraping de NOTAM Search | Interdit par le lot. `notams.aim.faa.gov/notamSearch/` affiche lui-même un avertissement : site informatif, à utiliser avec d'autres sources, et non source unique pour satisfaire 14 CFR 91.103. |

Sources publiques consultées le 2026-10-30 :

- `https://www.faa.gov/about/initiatives/notam` : page officielle NMS, section « Get API Access and
  Documentation », demande d'accès à `7-AWA-NAIMES@faa.gov`.
- `https://www.faa.gov/about/initiatives/notam/faqs` : FAQ officielle, dernière mise à jour le
  2026-08-25, question « How can I access or report any issues with the new NMS-API distribution
  interface? », réponse par courriel à `7-AWA-NAIMES@faa.gov`.
- `https://nms.aim.faa.gov/` : portail officiel NMS, compteur « NMS API Onboarded Users » à 261 au
  2026-04-18, bouton « Request API Access » vers `NOTAMS@faa.gov`.
- `https://notams.aim.faa.gov/notamSearch/` : avertissement d'usage informatif de NOTAM Search.
- `https://apis.io/apis/faa/faa-notam-api/` : profil tiers, appel non authentifié en 401 le
  2026-07-28, identifiants `client_id` et `client_secret` délivrés par `api.faa.gov`.
- `https://github.com/DimaD16/faa-nms-api` et
  `https://docs.rs/crate/aerocontext-nms/0.4.4/source/README.md` : clients tiers indépendants,
  OAuth2 `client_credentials`, identifiants demandés par courriel à `NOTAMS@faa.gov`, base et
  chemins fournis avec les identifiants. Ces deux sources corroborent le modèle mais ne remplacent
  pas la documentation officielle.

Conclusion : sans identifiants FAA, le lot ne peut ni obtenir un jeton, ni connaître les chemins et
le contrat de réponse, ni vérifier le GeoJSON et les types N, R et C. Aucun contournement par
l'interface web n'est fait et aucune réponse n'est fabriquée.

### Ce qui est livré à la place

`iosApp/Vela/Map/Layers/NotamLayer.swift` reste un squelette honnête :

- `installed` vaut `false` et `refresh` renvoie `nil`, donc l'hôte ne fait aucune requête et
  n'appelle jamais `apply` pour ce calque ;
- la ligne NOTAM de la feuille des couches reste désactivée, affiche « Not installed in this build »
  et « Unavailable, key required » ;
- la ligne de source dit « FAA NOTAM data, U.S. Government work, not for operational use; FAA
  credentials required » : l'utilisateur voit l'attribution, la raison et l'avertissement, sans
  promesse de couche ;
- le champ Keychain générique `world-key-field-notam` reste visible, car le catalogue marque
  `notam` comme exigeant une clé. Le calque ne lit jamais cette valeur ;
- aucun texte, aucun point et aucune zone ne sont dessinés. Un NOTAM textuel sans géométrie ne
  produit jamais de zone inventée, même dans le futur code.

Le champ Keychain à une seule valeur ne suffit pas au modèle réel : NMS demande un couple
`client_id` et `client_secret`, et l'accès est délivré à un client, pas à un utilisateur qui
collerait une clé personnelle. Le lot ne prétend donc pas que ce champ ouvre l'accès. Une
intégration autorisée devra ajouter deux comptes Keychain distincts, ou un stockage dédié, sans
jamais écrire le secret dans `vela_world`, `vela_settings`, `UserDefaults`, un journal ou une
ligne de résultat.

Aucun littéral d'hôte FAA n'est ajouté dans `iosApp/Vela` ni dans `ios-shared`, donc
`Notices.json` ne change pas. La notice `faa-notam` ne sera ajoutée que le jour où un hôte FAA sera
réellement appelé.

### Preuves

- Linux, le 2026-10-30 : `:core-common:jvmTest`, `:ios-shared:jvmTest` et
  `:ios-shared:compileKotlinIosSimulatorArm64` passent en 2 min 02 s. Aucun fichier Kotlin n'est
  ajouté, puisque le lot s'arrête avant une couche.
- `NotamUITests.testNotamDisabledStateAndCredentialPrompt` ouvre la feuille des couches, vérifie
  que `world-layer-notam` est désactivée avec la valeur « not installed », que la mention
  « FAA credentials required » et « not for operational use » est visible, que le champ
  `world-key-field-notam` existe, qu'un toucher ne change pas l'état et qu'aucune requête de calque
  n'est faite. Captures `notam-disabled.png` et `notam-credentials.png`.
- Run Mac `a4-notam-20261030-012657-24873` : `STATUS: ok`, 654 tests JVM, 544 tests Kotlin
  simulateur et 188 tests Swift sans échec ; le scénario NOTAM passe en 53,1 s. Le résumé rend
  `notam_installed=0`, `notam_credentials=required`, `notam_count=0`, `notam_geometry=0` et
  `notam_operational=0`. Les captures sont publiées sur la branche `results` du dépôt
  `ios-builder`.
- Un premier run, `a4-notam-20261030-010312-14286`, a exécuté `NotamUITests` avec succès mais a
  échoué sur `WorldLayersUITests.testWorldLayersStartHidden`, ligne 30 : ce scénario WLD-1 exige
  encore que `aviation` ne soit pas installé, alors que A-1 l'a installé sur `ios/main`. Le fichier
  n'appartient pas à A-4 et n'est pas modifié ici. Le second run a donc été limité à
  `NotamUITests` pour obtenir un tag vert propre au lot ; la dette de `WorldLayersUITests` reste
  ouverte pour WLD-1.
- `python3 scripts/ios/check_notices.py` rend « notices: ok, 39 entries ». Aucune notice
  `faa-notam` n'est ajoutée, car aucun hôte FAA n'est appelé et aucun littéral d'hôte n'entre dans
  le code.
- Les lignes d'acceptation `notam_count>0`, `notam_geometry=1` et le scénario
  `testNotamTextAndZone` ne s'appliquent pas, faute de couche.

### Ce qu'une intégration autorisée demanderait

1. Un courriel accepté par la FAA, avec un `client_id` et un `client_secret`, la base de production,
   l'URL du jeton et le document OpenAPI ou un accès à l'environnement de test.
2. Une revue de la conservation des identifiants : deux comptes Keychain, jeton OAuth2 en mémoire
   seulement, aucune valeur dans les réglages, les journaux ou les captures.
3. Un `NotamSource` qui demande un jeton, interroge `/v1/notams` en GeoJSON avec un filtre par
   aéroport ou par rayon et une date d'expiration, et ne lit que les types N, R et C.
4. Un `NotamStore` qui garde le texte brut, l'identifiant, la date d'expiration et la géométrie
   seulement quand le GeoJSON en porte. Une entrée sans géométrie reste textuelle, sans zone.
5. L'attribution exacte « FAA NOTAM data, U.S. Government work, not for operational use » visible
   sur la carte et dans chaque fiche, plus la notice `faa-notam`.
6. `NotamStoreTest` sur des fixtures avec et sans géométrie, les types N, R et C, l'expiration et le
   texte brut, puis `NotamUITests.testNotamTextAndZone` avec `notam-map.png`, `notam-text.png`,
   `notam-no-geometry.png` et les lignes `notam_count>0`, `notam_geometry=1|0`,
   `notam_operational=0`.
7. Une passe live manuelle avec les identifiants, aux États-Unis seulement, sans scraping de NOTAM
   Search et sans promesse de sécurité opérationnelle.
