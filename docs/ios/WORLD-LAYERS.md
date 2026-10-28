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
- Aucune requête réseau n'est ajoutée par ce lot. Aucun hôte nouveau n'apparaît dans le code, donc
  `Notices.json` ne change pas.

## Limites

- Les six entrées sont visibles mais désactivées : la feuille ne promet jamais un calque vide.
- L'hôte ne dessine rien tant qu'un lot n'a pas mis `installed` à `true` dans son fichier.
- Aucun test iPhone n'est fait pour ce lot.
- La notification de recentrage ne sert qu'aux lignes déjà reçues ; aucun calque n'en produit ici.
