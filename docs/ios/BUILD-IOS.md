# Construire l'app iOS

L'app iOS vit dans `iosApp/`. Le projet Xcode n'est pas versionné : XcodeGen le génère depuis
`iosApp/project.yml`, avec `iosApp/Vela/Info.plist`. Les deux sont dans `.gitignore`.

## Contenu

| Élément | Valeur |
|---|---|
| Cible | `Vela`, SwiftUI, bundle id `app.vela.ios`, iOS 17.0 minimum, iPhone |
| Carte | MapLibre Native iOS 6.31.0 par Swift Package Manager (`maplibre-gl-native-distribution`, framework dynamique) |
| Style | OpenFreeMap Liberty, `https://tiles.openfreemap.org/styles/liberty` |
| Caméra initiale | San Francisco (fixture), zoom 12 |
| Kotlin | Framework statique `VelaCore` (module `:ios-shared`, exporte `:core-common`), pont Swift SKIE 0.10.15 |
| Tests | `VelaTests`, tests unitaires hébergés dans l'app (style, caméra, crédit, clés de l'`Info.plist`, appels Kotlin, pot à cookies, codes de langue, moteur JS, signature, arguments de lancement, règles des pages cachées) ; `VelaUITests`, scénarios d'interface (lancement, recherche « coffee », fiche lieu, calibration en direct ; réseau requis). Mode d'emploi : `docs/ios/TESTING-IOS.md` |
| Icône | `scripts/ios/make-app-icon.py` la dessine (1024 x 1024, sans alpha) depuis la géométrie de `docs/logo.svg` |

Dossiers de `iosApp/Vela/` :

- `App/` : point d'entrée `@main`, `LaunchOptions` (arguments de test, `docs/ios/TESTING-IOS.md`).
- `Map/` : `MapView` (`UIViewRepresentable` autour de `MLNMapView`), `MapController` (côté
  impératif de la carte), `MapScreen` (bouton de localisation, crédit), `MapDefaults`.
- `Location/` : `LocationPermission` (autorisation « pendant l'utilisation »).
- `Core/` : `VelaCoreCheck`, l'appel Kotlin de contrôle au lancement (voir plus bas) ;
  `CalibrationModel`, miroir SwiftUI de la version de calibration.
- `Platform/` : les coutures en Swift, un fichier par couture (`URLSessionVelaHttp`, `OSLogLog`,
  `SystemClock`, `FileManagerPlatformFiles`, `FoundationTextNormalizer`, `DevicePlatformLocale`,
  `CookieJar`, `JavaScriptCoreJsEngine`, `SecKeySignatureVerifier`), `Vela-Bridging-Header.h`
  (déclare `JSContextGroupSetExecutionTimeLimit`, absent des en-têtes publics du SDK), et
  `AppGraph`, qui construit le `CoreGraph` et les deux coutures JS et signature au lancement et
  les donne à `IosGraph.start`. `KeyValueStores` est en Kotlin (`UserDefaultsKeyValueStores`, `iosMain`) :
  le contrat lève une exception sur une lecture du mauvais type, ce qu'une classe Swift ne peut
  pas faire à travers une interface Kotlin sans `@Throws`. Détail : `SPEC.md` 2.5, « iOS
  implementations ».
- `Search/` : `SearchModel` (miroir SwiftUI du `SearchStore` Kotlin, lu par SKIE), barre de
  recherche, panneau de résultats.
- `Place/` : `PlaceModel` (miroir SwiftUI du `PlaceStore` Kotlin), `PlaceSheet` (la fiche),
  `RemoteImage` (images Google chargées avec les en-têtes d'image de l'identité Safari).
- `Web/` : `HiddenWebView`, la classe de base des pages Google cachées (règles W-2), et
  `ReviewsWebFetcher`, le scrape des avis dessus.
- `Resources/` : catalogue d'assets (icône, couleur d'accent).

Les fonctions à venir prennent chacune leur dossier à côté de `Map/` : `Search/`, `Place/`,
`Nav/`, etc.

Le crédit « © OpenFreeMap © OpenMapTiles © OpenStreetMap contributors » est affiché en bas à
gauche et ouvre `openstreetmap.org/copyright`. Le bouton (i) de MapLibre reste en bas à droite
et liste l'attribution complète du style. Le logo MapLibre est masqué.

### Le framework Kotlin VelaCore

`:ios-shared` (cibles `iosArm64`, `iosSimulatorArm64`, et `jvm` pour les tests sous Linux)
dépend de `:core-common` en `api` et produit `VelaCore.framework`, **statique** : il est lié
dans le binaire de l'app, rien à embarquer ni à signer. Il exporte `:core-common`, donc Swift
voit `RoadNameShort` comme `IosGraph`. Point d'entrée : `IosGraph.shared` (`frameworkVersion`,
`shortRoadName(name:)`, `selfCheck()`).

**Intégration choisie : phase de build Xcode.** `project.yml` déclare un `preBuildScripts` qui
lance `iosApp/scripts/build-velacore.sh`, donc
`./gradlew -Pvela.iosOnly=true :ios-shared:embedAndSignAppleFrameworkForXcode` avant la
compilation Swift. Gradle lit `CONFIGURATION`, `SDK_NAME` et `ARCHS` d'Xcode, lie le bon
framework (Debug ou Release, simulateur ou appareil) et le copie dans
`ios-shared/build/xcode-frameworks/$(CONFIGURATION)/$(SDK_NAME)`, où pointe
`FRAMEWORK_SEARCH_PATHS`. `OTHER_LDFLAGS` ajoute `-framework VelaCore -lc++`.
Pourquoi pas une XCFramework construite à part : un humain sur un Mac oublierait de la
reconstruire après un changement Kotlin ; ici, chaque build Xcode est à jour, en CI comme en
local, et Gradle ne refait rien si le Kotlin n'a pas changé.

Réglages qui vont avec : `ENABLE_USER_SCRIPT_SANDBOXING = NO` (Gradle lit et écrit tout le
dépôt ; le plugin Kotlin refuse le sandbox), `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64`
(pas de tranche `iosX64`). La cible `VelaTests` a le même `FRAMEWORK_SEARCH_PATHS` (car
`@testable import Vela` charge les modules que Vela importe) mais ne lie pas VelaCore : les
symboles sont dans l'app qui héberge les tests. Les tests passent par `VelaCoreCheck` et
n'appellent jamais un symbole Kotlin directement.

JDK : le script prend `$JAVA_HOME` s'il contient un `java`, sinon `/usr/libexec/java_home -v
17`. `VELA_GRADLE_FLAGS` ajoute des options à Gradle (la CI y met `--no-daemon`).

**Pont Swift : SKIE**, décision D12 confirmée. SKIE 0.10.15 (Maven Central, 25 septembre
2026) annonce « Support for Kotlin 2.4.20 », et la liste des versions du compilateur dans son
plugin Gradle (`KotlinCompilerVersion`) va de 2.0.0 à 2.4.20. Il est appliqué à
`:ios-shared` seulement. Effets utiles : une fonction `suspend` devient `async throws` en Swift,
un `Flow` une `AsyncSequence`, une classe `sealed` un `enum` exhaustif. Les coutures restent en
style callback (§3.1 du plan) : elles sont implémentées en Swift, SKIE ne sert que dans l'autre
sens. SKIE est compilé pour chaque version de Kotlin : **monter Kotlin oblige à monter SKIE**
(vérifier sa liste avant). Repli si SKIE prend du retard : KMP-NativeCoroutines, ou des API à
callback écrites à la main dans `:ios-shared`. Seul avertissement Gradle ajouté :
`Configuration.setVisible` (SKIE, retiré en Gradle 11).

Au lancement, `MapScreen` appelle `VelaCoreCheck.run()`, qui attend `IosGraph.selfCheck()` et
journalise `Kotlin call ok: VelaCore 0.1.0: West Covell Boulevard -> W Covell Blvd` (sous-système
`app.vela.ios`, catégorie `VelaCore`). En Debug, la même ligne s'affiche en haut à gauche.

Sous Linux (ni link ni Swift) :

```
source ~/opt/env.sh
flock /tmp/opencode/gradle.lock ./gradlew --no-daemon -Pvela.iosOnly=true \
  :ios-shared:jvmTest :ios-shared:compileKotlinIosSimulatorArm64 :ios-shared:compileKotlinIosArm64
```

`:ios-shared` est aussi inclus dans les builds Android (surcoût de configuration mesuré :
0,5 s sur `help`) ; aucune tâche Android n'en dépend.

## Construire sur un Mac

Prérequis : Xcode 26 ou plus récent, XcodeGen (`brew install xcodegen`), un JDK 17
(`brew install openjdk@17`, ou celui d'Android Studio via `JAVA_HOME`). Le premier build
télécharge Gradle et Kotlin/Native (environ 1 Go dans `~/.gradle` et `~/.konan`).

```
cd iosApp
xcodegen generate
open Vela.xcodeproj
```

Dans Xcode : cible `Vela` > Signing & Capabilities > choisir son équipe (un compte Apple
gratuit suffit pour un iPhone personnel), puis lancer sur le simulateur ou sur l'iPhone
branché. Après chaque modification de `project.yml`, relancer `xcodegen generate`.

En ligne de commande, pour le simulateur :

```
xcodebuild test -project Vela.xcodeproj -scheme Vela \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

## Construire sur la CI

`scripts/ios/ci-ipa.sh` tourne sur le runner macOS du builder (`docs/ios/HIVE.md`) :

```
bash ~/gmaps/ios-builder/scripts/mac-run.sh <worktree> <lot> scripts/ios/ci-ipa.sh
```

Étapes : JDK 17 (`$JAVA_HOME_17_arm64`), Gradle (`--no-daemon -Pvela.iosOnly=true`) qui lie
les deux frameworks VelaCore (Debug simulateur, Release appareil) et lance `:ios-shared:jvmTest`
et `iosSimulatorArm64Test`, puis téléchargement de XcodeGen 2.46.0 (zip des releases GitHub, `brew` en repli),
génération du projet, résolution des paquets, `build-for-testing` puis `test-without-building`
sur le simulateur iPhone 17 (iOS 26.5), installation et lancement de l'app, capture d'écran
après 20 s, lecture de la ligne `Kotlin call ok` dans le journal, `xcodebuild archive` pour `generic/platform=iOS` sans signature
(`CODE_SIGNING_ALLOWED=NO`), puis `Payload/Vela.app` zippé en `Vela-unsigned.ipa`.

Sorties dans `$OUT`, donc sur la branche `results/<tag>/` du builder (`builds/<tag>/` au-delà
de 50 Mo) : `summary.txt`, `screenshot.png`, `Vela-unsigned.ipa`, `app-log.txt` (journal de
l'app dans le simulateur), `velacore-log.txt` (journal du sous-système `app.vela.ios`),
`gradle.log.gz` et un `xcodebuild-<étape>.log.gz` par appel à `xcodebuild`. Le résumé donne aussi la taille des
frameworks VelaCore, celle du binaire de l'app et la présence du code Kotlin dans le binaire
appareil (nom Objective-C `VelaCoreIosGraph`). Un échec des tests, du lancement, de la
capture ou de l'appel Kotlin est noté et le script va quand même jusqu'à
l'IPA ; il sort en erreur à la fin.

Récupérer les fichiers d'un run :

```
cd ~/gmaps/ios-builder && git fetch -q origin results
git show FETCH_HEAD:<tag>/Vela-unsigned.ipa > Vela-unsigned.ipa
```

Durée d'un run : environ 8 minutes, dont 2 à 3 pour démarrer le simulateur.

## Installer sur un iPhone (sideload)

L'IPA n'est pas signée. L'outil de sideload la signe avec l'identifiant Apple de l'utilisateur.
Avec un compte gratuit : signature valable 7 jours, 3 apps au plus, à renouveler. Avec un
compte développeur payant : 1 an.

- **AltStore** (`altstore.io`) : installer AltServer sur un Mac ou un PC, installer AltStore
  sur l'iPhone, puis dans AltStore > My Apps > `+`, choisir `Vela-unsigned.ipa`. AltStore
  renouvelle la signature quand l'iPhone et AltServer sont sur le même Wi-Fi.
- **SideStore** (`sidestore.io`) : comme AltStore, mais renouvelle depuis l'iPhone seul après
  l'installation initiale (fichier d'appairage et VPN local).
- **Sideloadly** (`sideloadly.io`) : sur un Mac ou un PC, brancher l'iPhone, glisser l'IPA,
  saisir l'identifiant Apple, lancer. Pas de renouvellement automatique.

Sur l'iPhone, la première fois : Réglages > Général > VPN et gestion de l'appareil > faire
confiance au profil développeur. Depuis iOS 16, activer aussi le mode développeur
(Réglages > Confidentialité et sécurité > Mode développeur), puis redémarrer.

## Résultat M1

Runs `f3a-ios-shell-20261024-205143-16009` et `f3a-ios-shell-20261024-210010-22344`
(Xcode 26.6, macOS 26.6), mêmes résultats :

| Étape | Résultat |
|---|---|
| Build simulateur | OK, 19 s (paquet MapLibre résolu en 17 s) |
| Tests unitaires | 4 tests, 0 échec |
| Lancement simulateur iPhone 17, iOS 26.5 | L'app tourne encore après 20 s |
| Capture | Carte Liberty sur San Francisco, tuiles chargées, bouton de localisation et crédit visibles |
| Archive sans signature | OK, 24 s |
| IPA | `Vela-unsigned.ipa`, 3,2 Mo (binaire MapLibre : 7,8 Mo décompressé), arm64, version 0.1.0, sur `results/<tag>/` |

Reste à faire par un humain, sur un iPhone : installer l'IPA par sideload, vérifier que la
carte s'affiche, que le bouton de localisation demande l'autorisation puis montre la position,
et que le refus mène à l'alerte qui ouvre les Réglages.

## Résultat F-3b (VelaCore lié)

Run `f3b-ios-shared-20261024-214906-13406` (Xcode 26.6, JDK 17.0.20.1), premier essai, tout vert :

| Étape | Résultat |
|---|---|
| Gradle avant Xcode (2 links + tests Kotlin), runner sans cache | 178 s ; `jvmTest` 2/2, `iosSimulatorArm64Test` 2/2 |
| Phase Xcode `embedAndSign` (frameworks déjà liés) | 32 s en simulateur, 61 s à l'archive (surtout la configuration Gradle) |
| `VelaCore.framework` | Debug simulateur 44 Mo (bibliothèque statique 45,2 Mo) ; Release appareil 6,0 Mo (5,7 Mo) ; module Swift SKIE présent |
| Tests unitaires | 6 tests, 0 échec (dont les 2 appels Kotlin) |
| Appel Kotlin au lancement | `Kotlin call ok: VelaCore 0.1.0: West Covell Boulevard -> W Covell Blvd`, libellé visible sur la capture |
| Archive appareil | OK, 86 s ; binaire arm64 1,9 Mo, contient `VelaCoreIosGraph` |
| IPA | 3,7 Mo (3,2 Mo en F-3a) |

## Résultat V-2 (M2 : recherche Google)

Runs `v2-search-ios-20261024-225803-24241` et `v2-search-ios-20261024-232044-20241` (Xcode 26.6, simulateur iPhone 17, iOS 26.5, IP de
datacenter) :

| Étape | Résultat |
|---|---|
| Kotlin | `jvmTest` 30/30, `iosSimulatorArm64Test` 28/28 |
| Tests unitaires Swift | 9 tests, 0 échec |
| Test d'interface `SearchUITests` | « coffee » sur la caméra de départ (San Francisco) : **60 lignes** (3 pages de 20), épingles sur la carte, un toucher amène la carte sur le lieu et ouvre la bulle |
| Captures | `search-list.png`, `search-map.png`, `search-centered.png` |
| Réponse brute enregistrée | `search-coffee-sf.txt.gz` (242 Ko, 32 Ko compressée), devenue la fixture de `RecordedSearchReplyTest` (20 lieux) |
| IPA | 4,5 Mo (3,7 Mo en F-3b) |

Ce que V-2 a appris :

- `scripts/ios/ci-ipa.sh` lance les tests unitaires seuls (`-only-testing:VelaTests`), puis,
  simulateur démarré, `simctl privacy grant location`, `simctl location set 37.7749,-122.4194`
  et le test d'interface seul. Le test écrit ses captures dans `$SHOT_DIR`, transmis par
  `TEST_RUNNER_SHOT_DIR` ; en repli, `xcresulttool export attachments`. Le nombre de lignes
  sort dans le journal (`SEARCH_ROWS=`).
- Noms Swift des symboles Kotlin : `VelaCore.Clock` et `VelaCore.Cancellable` qualifiés (le
  `Clock` de la bibliothèque standard, le `Cancellable` de Combine). Une lambda Kotlin qui rend
  `Unit` devient en Swift une closure qui rend `Void`. Les énumérations Kotlin se comparent
  par `==` (`level == .debug`), ce qui marche avec ou sans le pont SKIE.
- Sur iOS 26, un texte `.secondary` et un `Divider` dans un `ScrollView` posé sur un fond
  `.regularMaterial` sortaient invisibles (adresse et nombre d'avis absents de la première
  capture) : le panneau a un fond opaque et des couleurs `UIColor` explicites.
- Pas encore là : élargissement à 40 km pour une adresse (`AddressQuery` est dans `:core`),
  passe « près de moi », autres succursales, transformations JS, chaînes traduites.

## Calibration en direct (I-0)

L'app iOS récupère et vérifie `calibration.json` comme Android : `IosCalibration`
(`:ios-shared`) fait tourner le `CalibrationStore` commun au démarrage de la session (cache
vérifié dans `Application Support`, puis un rafraîchissement : lien poussé, URL brute compilée,
miroir poussé, copie du site), et la recherche lit cette calibration et ses transformations JS
au lieu des valeurs compilées. Le journal (catégorie `Calibration`) donne la version au
démarrage et après le rafraîchissement ; en Debug, la ligne `calibration <version>` s'affiche
sous la ligne VelaCore.

`JavaScriptCoreJsEngine` utilise `JSContextGroupSetExecutionTimeLimit`, une fonction exportée
par JavaScriptCore mais déclarée dans un en-tête privé : sans importance pour un sideload, mais
une soumission App Store pourrait la refuser (API privée). Repli dans ce cas : pas de limite
(JavaScriptCore public n'en a pas) et transformations JS désactivées sur iOS.

Run `i0-ios-platform-20261025-000020-15244` (Xcode 26.6, simulateur iPhone 17, iOS 26.5) :

| Étape | Résultat |
|---|---|
| Kotlin | `jvmTest` 36/36 (dont 5 pour `IosCalibrationTest`, sur les vrais `calibration.json` et `.sig`), `iosSimulatorArm64Test` 28/28 |
| Tests unitaires Swift | 14 tests, 0 échec ; `while(true)` tué en 0,52 s pour une limite de 0,5 s, l'appel suivant marche ; vrai `calibration.json` vérifié, octet modifié refusé |
| Calibration en direct | journal : `version 1` au premier lancement, `version 27` après le rafraîchissement (3 s), puis 27 dès le démarrage depuis le cache |
| Scénarios d'interface | 4/4 : lancement San Francisco et Davis, « coffee » 60 lignes, calibration 27 |
| Trajet simulé | `sf-market` à 20 m/s : le point bleu avance et la carte le suit |
| IPA | 4,6 Mo (4,5 Mo en V-2) |

## Résultat I-3 (M3 : fiche lieu)

Run `i3-place-20261025-005924-9696` (Xcode 26.6, simulateur iPhone 17, iOS 26.5, IP de
datacenter), tout vert. Le premier run (`i3-place-20261025-004900-21706`) s'était arrêté sur une
erreur de compilation dans le test d'interface seul.

| Étape | Résultat |
|---|---|
| Kotlin | `jvmTest` 46/46, `iosSimulatorArm64Test` 31/31 |
| Tests unitaires Swift | 17 tests, 0 échec (dont la liste de règles `BlockedHosts` compilée par WebKit) |
| Recherche (source commune `GoogleMapsSource`, identité Safari) | « coffee » : 60 lignes |
| `PlaceUITests` | Doppio Coffee & Brunch : note 4,8 (534), « Coffee shop », « Open · Closes 8 PM », 7 lignes d'horaires, adresse, téléphone, site ; **10 photos** (`hspqX`), **5 avis** par le flux `qv9Egd` (vue limitée signalée), pas d'affluence |
| Captures | `place-top.png`, `place-photos.png`, `place-reviews.png`, `place-reviews-2.png` |
| IPA | 5,4 Mo (4,6 Mo en I-0) |

Le flux d'avis a répondu : le scrape en page cachée (`ReviewsWebFetcher`) n'a pas tourné dans ce
run. Il est couvert par les tests JVM (`PlaceStoreTest`) et se force avec la calibration
`iosNativeReviewFeed` à 0.
