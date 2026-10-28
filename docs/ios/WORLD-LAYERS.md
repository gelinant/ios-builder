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

- Les six entrées sont visibles mais désactivées : la feuille ne promet jamais un calque vide.
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
