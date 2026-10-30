# Réglages de contenu et de données sur iOS (SET-CONTENT)

État : branche `ios/set-content`. Ce document décrit ce que font réellement les réglages de contenu
de la fiche lieu, les deux drapeaux Android, le cache photo et la purge des trajets enregistrés. La
référence produit reste `FEATURES.md` ; `PARITY.md` garde le tableau de validation.

## Liste convergée (SETTINGS-CONVERGE)

La feuille Réglages n'est plus un formulaire unique. C'est une liste courte de huit lignes, sur le
modèle de Google Maps : chaque ligne affiche sa valeur actuelle à droite et ouvre la page qui
possède ses contrôles. L'écran tient sur une hauteur d'iPhone sans défilement.

| Ligne | Valeur à droite | Page ouverte |
|---|---|---|
| Utiliser Vela sans Google (Confidentialité) | interrupteur Google | Confidentialité |
| Apparence | thème, langue et unités | Apparence, langue, unités, horloge |
| Navigation | unité de vitesse | Caméra de conduite, gestes, vélo |
| Voix | mode On, Alertes seules ou Off | Voix et recherche vocale |
| Données et contenu | Full place data ou Tiles only | Contenu des fiches, cache photo, boutons rapides |
| Voyages enregistrés | nombre de trajets | Trajets et exports |
| Hors ligne | nombre de régions installées | Feuille Hors ligne existante |
| À propos | version | Hub de recherche, aide, notices |

Le commutateur Google reste sur la première ligne, visible sans défilement. Son libellé ouvre la
page Confidentialité ; l'interrupteur lui-même bascule le choix en un seul tap. `LocalizationUITests`
garde cette promesse.

Chaque page reprend les identifiants et les assertions de l'ancien formulaire. `SettingsIndex`
pointe toujours vers l'ancre réelle : le hub d'À propos ouvre maintenant la sous-page qui possède
la ligne, puis fait défiler cette page jusqu'au contrôle. Les ancres `settings-language`,
`settings-units`, `settings-clock`, `settings-telemetry`, `settings-session-mode`,
`settings-place-content`, `settings-trips-delete` et les autres n'ont pas changé.

La ligne Hors ligne ouvre la feuille `OfflineSheet` existante. Le tracé de zone a besoin de la
fenêtre cartographique vivante : `MapScreen` doit fournir cette fermeture, comme le note le
commentaire de `SettingsScreen`.

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

## À propos, aide et notices (SET-ABOUT)

État : branche `ios/set-about`, depuis `ios/main` après les merges de SET-CONTENT et SET-PRIVACY.

La feuille Réglages garde son formulaire unique. Une section À propos, en dernier après Voix,
ouvre `AboutScreen` avec un seul champ de recherche. Ce champ couvre quatre familles :

- les lignes de réglages de l'écran, indexées par `SettingsIndex` avec leur ancre SwiftUI ;
- les sujets d'aide de `HelpCatalog` ;
- les notices et attributions de `Notices.json` ;
- les entrées de support : version, installateur, diagnostics, don, projet et notices.

Un résultat de réglage ferme la feuille et fait défiler le formulaire jusqu'au contrôle réel par
son `.id`. Les autres résultats ouvrent une page ou défilent vers le bloc Support. Les ancres sont
posées sur les lignes existantes ; la section Voix n'a qu'une ancre, `settings-voice`, parce que
son contenu appartient à un autre lot.

### Sujets d'aide

Les réponses décrivent le comportement réel du code, limites comprises.

| Sujet | Ce qu'il répond |
|---|---|
| Carte vide | tuiles OpenFreeMap absentes, région téléchargée hors couverture, glyphes et sprites distants, question Google du premier lancement |
| Pas de trafic en direct | raster Google, absence hors ligne, tuiles directes de MapLibre quand Google est coupé, temps OSRM et Valhalla sans congestion |
| Fiche sans avis ni photos | pages Google sans compte, session limitée, « Tiles only », avis et photos coupés, NoGoogle, Street View séparé |
| Régions hors ligne | paquet de lieux, archive de lieux, PMTiles, glyphes partagés, reprise en arrière-plan, absence de graphe de routage sur iOS |
| Sources de recherche | Google et Photon, Photon seul sans Google, lignes installées, élargissement à 40 km pour une adresse |
| Téléchargement d'une voix | Piper et sherpa-onnx sur l'appareil, repli AVSpeech, dictionnaire de noms de lieux, recherche vocale distincte |
| Données envoyées à Google | IP, requête, zone ou extrémités, cookie de session, deux exceptions NoGoogle, compteur partiel |
| Signaler un problème | export de diagnostics, version et build, trajets enregistrés, dépôt GitHub |

Le contenu est en anglais dans ce lot. Le traduire demande les 24 catalogues et n'est pas fait ici.

### Notices et attributions

`iosApp/Vela/Settings/Notices.json` contient 26 entrées : l'application, sept bibliothèques et
dix-huit sources de données. La page `NoticesScreen` les groupe en Vela, bibliothèques liées,
puis données et services. Chaque ligne montre le titre, le régime de réutilisation, une note
courte et un lien.

`scripts/ios/check_notices.py` refuse une dépendance ou un hôte non couvert :

- paquets Swift lus dans le bloc `packages:` de `iosApp/project.yml` ;
- xcframeworks du dossier `Vendor` cités par ce fichier ;
- bibliothèques Gradle tierces lues dans `core-common` et `ios-shared`, résolues par
  `gradle/libs.versions.toml` ;
- hôtes extraits des sources et des styles, chaque hôte devant appartenir à une notice ou à la
  liste courte des adresses du projet.

Le script est appelé par `scripts/ios/ci-ipa.sh` à l'étape Notices, donc un run Mac échoue avant
la compilation si la couverture manque. `scripts/ios/test_notices.py` vérifie l'arbre réel, les
analyseurs et deux cas de manque, un paquet Swift ajouté et un hôte inconnu.

Limites trouvées :

- Transitous ne publie pas de régime unique pour ses données : chaque flux GTFS garde le sien et
  la notice renvoie à `transitous.org/sources` au lieu d'inventer un régime global ;
- Esri et Google sont sous leurs termes de service, pas sous un régime libre ;
- les voix Piper portent chacune leur fiche de modèle, la notice le dit et ne choisit pas à leur
  place ;
- les autres bibliothèques transitives internes à MapLibre et sherpa-onnx ne sont pas énumérées
  une par une, seules les distributions liées le sont ;
- Overture n'apparaît pas : iOS ne consomme pas ce paquet de lieux, contrairement à Android ;
- aucun lien de don n'est inventé : la ligne Support Vela utilise `VelaLinks.donate()`, déjà
  documenté par `README.md` et par les défauts de `:core-common`.

### Support

Le bloc Support affiche `CFBundleShortVersionString` et `CFBundleVersion`, avec un bouton pour
copier la ligne. iOS ne dit pas à une application qui l'a installée : TestFlight, SideStore et
Xcode se ressemblent depuis l'intérieur de Vela. La ligne affiche donc « Not available on iOS » et
explique ce manque, sans annoncer un installeur qu'elle ne peut pas connaître.

« Export diagnostics » appelle `DiagnosticsExport.fileURL()`, la même source que le bouton de la
page Confidentialité (DG-1). Elle produit le fichier texte expurgé et ouvre la feuille de partage
iOS. Le texte de la page précise que les journaux Kotlin de recherche, d'itinéraire et d'analyse
n'y sont pas.

### Preuves

Linux :

```
python3 scripts/ios/check_notices.py
python3 scripts/ios/test_notices.py
./gradlew --no-daemon -Pvela.iosOnly=true :core-common:jvmTest :ios-shared:jvmTest \
  :ios-shared:compileKotlinIosSimulatorArm64
```

Mac : `scripts/ios/ci-ipa.sh` exécute l'étape Notices puis `SettingsAboutUITests`. Le scénario
`testHubSearchAboutNoticesSupport` ouvre Réglages, cherche « live traffic », ouvre le sujet,
cherche « photo quality » et vérifie que le formulaire atteint le contrôle, cherche « maplibre »
et vérifie BSD-2-Clause, cherche « diagnostics » et vérifie les deux entrées, puis contrôle la
version, l'installeur inconnu et treize notices nommées. Captures : `settings-about-search.png`,
`settings-about-support.png`, `settings-about-notices.png`.

Le 2026-10-27, le run `set-about-20261027-231040-17502` a compilé l'application, exécuté les 131
tests Swift et joué le scénario jusqu'au bloc Support : recherche « live traffic », ouverture du
sujet, saut vers « photo quality », notice MapLibre, recherche « diagnostics », version
`Vela 0.1.202610272311 (build 1793142706)`, installateur inconnu et bouton d'export. Le scénario
s'est arrêté avant la page Notices parce que le champ de recherche était hors écran après le
défilement vers Support. Le test remonte maintenant en haut de la feuille avant de chercher
« notices », et la capture des notices attend un nouveau run. Captures obtenues :
`settings-about-search.png` et `settings-about-support.png`.

Le même run a échoué à l'étape Gradle sur deux tests hors lot après le merge de NAV-BANNER :
`NavStoreTest.trafficOfferIsMirroredAndAcceptanceAdoptsTheCandidate` et
`NoGooglePhotonSourceTest.noGoogleSearchAsksPhotonOnlyAndMergesInstalledRows`. La commande Linux
demandée était verte avant ce merge.

### Reste et risques

- Le contenu d'aide, des notices et du support est en anglais ; l'index de recherche porte sur
  les libellés anglais même quand le formulaire est traduit.
- Le défilement vers une ligne dépend de `ScrollViewReader` dans un `Form` ; un écran très court
  peut poser l'ancre trop haut ou trop bas, jamais hors de la ligne.
- La recherche ne connaît que les lignes listées dans `SettingsIndex`. Une ligne ajoutée à
  l'écran sans y être ajoutée reste invisible pour le hub.
- L'export de diagnostics ne couvre pas les journaux Kotlin, comme le documente déjà PRIVACY.md.
- Aucun test sur iPhone réel n'a été fait pour ce lot.

## Voix (SET-VOICE)

La section Voix de `SettingsScreen.swift` monte `VoiceSettingsSection(model:)`, qui reste après les
trajets et avant À propos. Elle porte le mode On, Alerts only, Off des clés partagées NAV-LIFE, la
langue des directions distincte de celle des menus, l'état de la voix qui parle, le repli sur la
voix iPhone, les téléchargements avec taille et progression, la bibliothèque Piper, le volume, la
vitesse et la recherche vocale VO-2.

Le modèle `SettingsModel` garde la clé Android `directions_language` dans la suite
`app.vela.ios.vela_settings` et applique le choix à `NavStringsRegistry` après chaque changement de
langue de l'application. Les règles pures, la priorité du choix et les replis sont dans
`DirectionsLanguage` et `VoiceInstallRules` sous `:ios-shared`, testés par
`DirectionsLanguageTest` et `VoiceInstallRulesTest`.

La section énonce les limites iOS : la voix système ne peut pas être nivelée ni amplifiée, une
langue sans voix neuronale installée parle avec elle, et aucun moteur TTS tiers ne peut être choisi.
Les détails et les preuves sont dans `docs/ios/VOICE.md`.

## Apparence et chrome de navigation (SET-APPEARANCE)

État : branche `ios/set-appearance`, depuis `ios/main` après SET-CONTENT, SET-PRIVACY, SET-VOICE
et SET-ABOUT. La feuille Réglages garde son formulaire unique. La section Apparence ajoute une
seule ligne, « Theme and navigation chrome », qui ouvre `AppearanceScreen`. Les lignes langue,
unités et horloge restent en tête, puis viennent Confidentialité, Bike, Data and content,
Recorded trips, Voix et À propos, dans cet ordre. Le choix Google reste donc dans les deux
premiers écrans et `SettingsUITests` le vérifie encore.

### Thème de l'app et carte séparés

`AppearanceSettings` est un seul détenteur observable, dans `iosApp/Vela/Settings/`. Il écrit les
clés d'Android quand elles existent et publie `VelaAppearanceChanged` après chaque changement.

| Réglage | Clé | Valeurs | Effet |
|---|---|---|---|
| App theme | `theme_mode` | `SYSTEM`, `LIGHT`, `DARK` | `overrideUserInterfaceStyle` sur chaque fenêtre active, réappliqué à l'activation d'une scène |
| Map look | `map_look` | `vela`, `bright`, `positron`, `fiord`, `black` | style local rechargé par `MapController` via `MapStyleSettings.save` |
| Map light or dark | `map_appearance` | `system`, `light`, `dark` | variante Vela claire ou sombre, indépendante du thème de l'app |

Les deux choix sont indépendants : une app sombre peut garder une carte claire. `theme_mode` est
lu en majuscules Android et en minuscules pour une suite écrite par un ancien build iOS. iOS
n'offre pas AMOLED ni « Day and night » : le premier n'a pas d'équivalent sur un écran iOS, le
second demande le calcul solaire d'Android et n'est pas dans ce lot.

### Chrome de navigation

Les réglages sont lus par `NavChrome` et `FreeDriveChrome`, pas seulement affichés.

| Réglage | Clé | Valeurs | Consommateur |
|---|---|---|---|
| Navigation icon size | `puck_size` | `normal`, `large`, `xl` | taille de l'icône de manœuvre et de la pastille véhicule |
| Navigation label size | `nav_label_size` | `system`, `large`, `xl` | multiplicateur de la taille Dynamic Type du texte de manœuvre |
| Show speed and speed limit | `speed_display` | booléen | masque la pastille vitesse, en conduite guidée comme en conduite libre |
| Speed unit | `speed_unit` | `auto`, `metric`, `imperial` | chiffres et unité de la pastille, `auto` suivant les unités de l'app |
| Vehicle icon | `puck_shape` | `arrow`, `car`, `ufo`, `ship`, `duck` | pastille dessinée à côté de la vitesse, avec le symbole SF correspondant |
| Navigation detail | `nav_detail` | `full`, `compact`, `minimal` | `full` garde le nom de rue et la prochaine instruction, `compact` cache le nom de rue, `minimal` garde la carte de manœuvre et les alertes |

`puck_shape` garde le nom de clé Android, mais iOS ne remplace pas le point bleu de localisation
de MapLibre : le choix dessine la pastille du chrome. Aucune couche de carte n'est ajoutée et
aucune requête n'est faite. Les cinq symboles sont `location.north.fill`, `car.fill`,
`airplane`, `sailboat.fill` et `bird.fill`, faute d'assets de marque.

### Dynamic Type et taille de police

Le système reste la seule source de la taille du texte. `nav_label_size` multiplie une valeur
`@ScaledMetric(relativeTo:)`, donc la taille système et le pas de l'app s'additionnent. Aucun
`.dynamicTypeSize` fixe n'est posé sur un texte de contenu, aucun `minimumScaleFactor` n'est
ajouté. Le pas de l'app ne touche que le chrome de navigation ; les fiches, Réglages et À propos
suivent uniquement Dynamic Type. C'est la seule façon de tenir L312-L313 sans lutter contre le
réglage système.

### Contraste

`Design.Palette` donne les composantes sRGB et `Design.Contrast` calcule la luminance relative et
le rapport WCAG. La puce de mode d'itinéraire sélectionnée utilise désormais
`Design.Colors.routeChipFill` et `routeChipLabel`, alias de `accentFill` et `onAccent`.

| Paire | Avant | Après |
|---|---:|---:|
| Blanc sur teal de marque `#149387` | 3,78:1, insuffisant pour du texte de 13 points | inchangé, réservé aux icônes, sélections et texte large |
| Blanc sur `accentFill` clair `#0B5D55` | non utilisé par la puce | 7,75:1 |
| Noir sur `accentFill` sombre `#4FB3A6` | non utilisé par la puce | 8,33:1 |
| Ambre `#F2A65A` sur blanc | 2,02:1, décoratif | inchangé, l'étoile n'est jamais seule |

`AppearanceTests` recalcule ces quatre valeurs et échoue si une constante dérive. La paire
problématique nommée par `DESIGN.md` est donc fermée pour la puce de mode.

### Preuves

Linux : le lot ne touche aucun fichier Kotlin, la commande JVM n'est pas nécessaire. La
compilation Swift et les tests unitaires passent par le run Mac.

Mac : `bash ~/gmaps/ios-builder/scripts/mac-run.sh ... set-appearance scripts/ios/ci-ipa.sh
VELA_ONLY_UI=AppearanceUITests,LocalizationUITests VELA_SKIP_ARCHIVE=1`.

`AppearanceUITests.testThemesSpeedAndVehicle` ouvre Réglages, vérifie que le choix Google demande
au plus deux balayages, ouvre la page Apparence, choisit le thème sombre, le style Bright et la
carte sombre, puis Large, Largest labels, mph, UFO et Compact. Il contrôle la ligne
`appearance-debug`, la pastille d'aperçu, puis ouvre la conduite libre et exige `free-vehicle-icon`
avec le libellé UFO et `free-speed-unit` avec mph. Captures : `appearance-theme.png`,
`appearance-dark.png`, `appearance-chrome.png`, plus `appearance-chrome-drive.png` pour la preuve
dans le vrai chrome.

`AppearanceTests` couvre le contraste et la persistance des clés `puck_size` et `puck_shape`.
`LocalizationUITests` reste le garde de la langue, des unités et du choix Google.

Résultat Mac du 2026-10-29, run `set-appearance-20261029-032551-4729` : compilation simulateur
verte, 4 scénarios exécutés. Les trois scénarios `LocalizationUITests` passent, dont la
persistance après relance. `AppearanceUITests` atteint la page, applique le thème sombre et la
carte Bright puis sombre, et produit `appearance-dark.png` et `appearance-theme.png`. Il s'arrête
ensuite sur l'interrupteur « Show speed and speed limit » : le tap XCUITest sur le Switch n'a pas
changé la valeur lue par la ligne de débogage. Le réglage est devenu un menu On/Off dans la page
et le scénario choisit ses deux valeurs comme les autres menus. Ce correctif n'a pas de second
run Mac : le budget du lot était d'un run et d'un rerun, tous deux consommés.

### Limites

- Le point de localisation de la carte reste celui de MapLibre ; la forme choisie est une pastille
  du chrome. Remplacer le point demanderait une vue d'annotation dans `MapView` ou `MapController`
  hors du périmètre de ce lot.
- AMOLED et le thème solaire jour/nuit d'Android ne sont pas offerts.
- `nav_detail` ne réduit jamais les alertes de sécurité ni la carte de manœuvre.
- Les libellés de la page Apparence sont en anglais ; les traduire demande les 24 catalogues.
- Aucun test sur iPhone réel n'a été fait pour ce lot.
