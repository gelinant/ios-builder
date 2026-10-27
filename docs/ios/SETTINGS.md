# Réglages de contenu et de données sur iOS (SET-CONTENT)

État : branche `ios/set-content`. Ce document décrit ce que font réellement les réglages de contenu
de la fiche lieu, les deux drapeaux Android, le cache photo et la purge des trajets enregistrés. La
référence produit reste `FEATURES.md` ; `PARITY.md` garde le tableau de validation.

## Ordre de l'écran

L'écran garde les sections existantes et les place ainsi :

1. Apparence : langue, unités, horloge.
2. Confidentialité : interrupteur Google, télémétrie, session Google, page de confidentialité,
   export de diagnostics.
3. Data and content.
4. Recorded trips.
5. Voix.

Le choix Google est donc dans les deux premiers écrans du formulaire. `LocalizationUITests` et
`PrivacyUITests` continuent de le trouver, et `SettingsUITests.testContentAndData` vérifie qu'il
demande au plus deux balayages.

## Contenu des fiches lieu

Les valeurs sont écrites par le Kotlin `SettingsStore` dans `vela_settings`, avec les clés
d'Android quand elles existent. `ContentPolicy` porte les valeurs vers `PlaceStore` avant la
première requête.

| Réglage | Clé | Effet vérifié |
|---|---|---|
| Place content : Full place data | `place_content=full` | comportement normal : détails, avis, photos |
| Place content : Tiles only | `place_content=tiles` | la fiche garde la ligne de recherche (nom, adresse, point) et n'envoie aucune requête lieu |
| Show reviews | `show_reviews` | off : aucun flux d'avis ni page cachée pour les avis |
| Load photos | `load_photos` | off : aucune page photo ni téléchargement d'image |
| Load photos only on Wi-Fi | `photos_wifi_only` | `ImageLoader` refuse une nouvelle image sur un chemin `isExpensive` |
| Photo quality | `photo_quality` | high 1200x900, standard 600x450, low 320x240 |
| Photo cache size | `photo_cache_mb` | budget mémoire de 50 à 400 Mo |
| Load all photos and reviews | `place_full_load` | relève le plafond de la page d'avis à 50 |
| Wait for popular times | `details_retry` | off : un seul essai de détails par lieu |
| Hide adult categories | `hide_adult` | pilote `CategoryFilter` à la source de recherche et de POI |
| Hide website and external links | `hide_external_links` | retire le lien Site web de la fiche |

Limites honnêtes :

- « Tiles only » ne change pas la recherche : elle peut encore demander Google pour la liste de
  résultats. Le réglage couvre l'ouverture d'une fiche lieu.
- « Hide website and external links » ne masque pas encore Street View, Book, Reserve ni Order.
- « Load photos only on Wi-Fi » utilise `NWPathMonitor`. Au tout premier instant du lancement, le
  chemin n'est pas encore connu et le téléchargement est autorisé par prudence.
- La qualité photo change la taille demandée à Google, pas un recadrage local.

## Drapeaux Android

Les noms Android restent visibles dans les libellés :

- `LowDataMode` (`low_data_mode`) : appliqué par `SettingsStore.start()` à
  `app.vela.core.data.LowDataMode` avant que `MapSession` ne construise ses facettes et avant la
  première requête. `PlaceStore` saute les photos et `ImageLoader` refuse les nouvelles images.
- `LowRamMode` (`low_ram_mode`) : appliqué au même moment à `app.vela.core.data.LowRamMode`. Sur
  iOS, il n'y a pas de détection automatique comme `ActivityManager.isLowRamDevice` ; le réglage
  est donc explicite et off par défaut.

`IosGoogle.applyFlags` ne remet plus `LowDataMode` à zéro : `SettingsStore` est le seul écrivain
avant la première requête.

## Cache photo

`ImageLoader` garde les images en mémoire, avec un coût en octets. Le budget est un `NSCache`
`totalCostLimit` de 50, 100, 200 ou 400 Mo. La ligne « Photo cache » du réglage affiche les octets
utilisés et le budget ; « Clear photo cache » vide le cache immédiatement.

Le compteur d'octets est incrémenté à chaque insertion. Quand le système évince une image de lui-
même, le compteur peut surestimer le contenu jusqu'au prochain `Clear`. Il n'y a pas de cache disque
de photos dans ce lot.

## Trajets enregistrés

La section Recorded trips affiche le nombre de fichiers et leur taille réelle, lue par
`TripsStore.totalBytes()`. « Delete all recorded trips » demande confirmation, puis
`TripsStore.deleteAll()` supprime les trajets complets et les enregistrements partiels. Le
réglage « Redact places in exports » écrit `diag_redact` et fait démarrer le partage d'un trajet au
rayon de 800 m au lieu de 400 m.

`TripsStore.deleteAll()` et `totalBytes()` sont couverts par
`TripsStoreTest.settingsPurgeReportsTheSizeAndRemovesEveryTrip`.

## Preuves

Linux :

```
./gradlew --no-daemon -Pvela.iosOnly=true :core-common:jvmTest :ios-shared:jvmTest \
  :ios-shared:compileKotlinIosSimulatorArm64
```

Tests JVM ajoutés :

- `SettingsStoreTest.contentPolicyPersistsAndReachesTheHoldersBeforeStart` ;
- `SettingsStoreTest.contentKeysMatchAndroidAndClampTheCache` ;
- `PlaceStoreTest.tilesOnlyKeepsTheSearchRowAndAsksGoogleNothing` ;
- `PlaceStoreTest.reviewsAndPhotosOffSkipTheirGoogleLoads` ;
- `PlaceStoreTest.lowDataSkipsPhotosButStillLoadsDetails` ;
- `PlaceStoreTest.noWaitForPopularTimesMeansOneDetailsRequest` ;
- `TripsStoreTest.settingsPurgeReportsTheSizeAndRemovesEveryTrip`.

Mac : le 2026-10-27, `scripts/ios/ci-compile.sh` a rendu `simulator build: ok` sur le build
`set-content-manual` après une première erreur de compilation corrigée (accesseur manquant de la
politique de liens externes). Le scénario simulateur est préparé mais n'a pas été lancé dans ce lot,
faute de budget de lancements Mac.

Simulateur : `VELA_ONLY_UI=SettingsUITests` doit exécuter `SettingsUITests.testContentAndData`, qui
vérifie l'accès au choix Google, les deux drapeaux, Wi-Fi only, le contenu « tiles », la qualité,
le budget, la purge du cache, le masquage des liens externes et la confirmation de purge des
trajets. `LocalizationUITests` reste le garde de la langue, des unités et du choix Google.

## Reste à faire

- Traduire les nouveaux libellés « Data and content », « Photo quality », « Low data mode » et les
  autres dans le catalogue : ils sont en anglais dans ce lot.
- Faire une passe iPhone sur une vraie fiche lieu avec Wi-Fi only et low data.
- Masquer Street View et les boutons Book, Reserve et Order quand les liens externes sont cachés.
- Décider si `reviews_on_tap` et `photos_on_tap` méritent un bouton dans la fiche ; les clés sont
  déjà lues par `SettingsStore` mais l'interface ne les expose pas.
