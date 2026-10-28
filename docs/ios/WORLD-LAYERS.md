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
- Run Mac : à compléter.

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
