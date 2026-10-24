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
| Tests | `VelaTests`, tests unitaires hébergés dans l'app (style, caméra, crédit, clés de l'`Info.plist`) |
| Icône | `scripts/ios/make-app-icon.py` la dessine (1024 x 1024, sans alpha) depuis la géométrie de `docs/logo.svg` |

Dossiers de `iosApp/Vela/` :

- `App/` : point d'entrée `@main`.
- `Map/` : `MapView` (`UIViewRepresentable` autour de `MLNMapView`), `MapController` (côté
  impératif de la carte), `MapScreen` (bouton de localisation, crédit), `MapDefaults`.
- `Location/` : `LocationPermission` (autorisation « pendant l'utilisation »).
- `Resources/` : catalogue d'assets (icône, couleur d'accent).

Les fonctions à venir prennent chacune leur dossier à côté de `Map/` : `Search/`, `Place/`,
`Nav/`, etc.

Le crédit « © OpenFreeMap © OpenMapTiles © OpenStreetMap contributors » est affiché en bas à
gauche et ouvre `openstreetmap.org/copyright`. Le bouton (i) de MapLibre reste en bas à droite
et liste l'attribution complète du style. Le logo MapLibre est masqué.

### Point d'accroche F-3b

Le framework Kotlin `VelaCore` (module `:ios-shared`) n'existe pas encore. Il se branchera dans
`iosApp/project.yml`, à l'endroit marqué `F-3b hook` dans les dépendances de la cible `Vela` :
un `preBuildScripts` qui lance `./gradlew :ios-shared:embedAndSignAppleFrameworkForXcode` et la
dépendance au framework produit. `scripts/ios/ci-ipa.sh` devra alors installer le JDK 17
(`$JAVA_HOME_17_arm64` sur le runner) avant `xcodebuild`.

## Construire sur un Mac

Prérequis : Xcode 26 ou plus récent, XcodeGen (`brew install xcodegen`).

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

Étapes : téléchargement de XcodeGen 2.46.0 (zip des releases GitHub, `brew` en repli),
génération du projet, résolution des paquets, `build-for-testing` puis `test-without-building`
sur le simulateur iPhone 17 (iOS 26.5), installation et lancement de l'app, capture d'écran
après 20 s, `xcodebuild archive` pour `generic/platform=iOS` sans signature
(`CODE_SIGNING_ALLOWED=NO`), puis `Payload/Vela.app` zippé en `Vela-unsigned.ipa`.

Sorties dans `$OUT`, donc sur la branche `results/<tag>/` du builder (`builds/<tag>/` au-delà
de 50 Mo) : `summary.txt`, `screenshot.png`, `Vela-unsigned.ipa`, `app-log.txt` (journal de
l'app dans le simulateur) et un `xcodebuild-<étape>.log.gz` par appel à `xcodebuild`. Un
échec des tests, du lancement ou de la capture est noté et le script va quand même jusqu'à
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

Run `f3a-ios-shell-20261024-205143-16009` (Xcode 26.6, macOS 26.6) :

| Étape | Résultat |
|---|---|
| Build simulateur | OK, 19 s (paquet MapLibre résolu en 17 s) |
| Tests unitaires | 4 tests, 0 échec |
| Lancement simulateur iPhone 17, iOS 26.5 | L'app tourne encore après 20 s |
| Capture | Carte Liberty sur San Francisco, tuiles chargées, bouton de localisation et crédit visibles |
| Archive sans signature | OK, 24 s |
| IPA | `Vela-unsigned.ipa`, 3,2 Mo (binaire MapLibre : 7,8 Mo décompressé), arm64, sur `results/<tag>/` |

Reste à faire par un humain, sur un iPhone : installer l'IPA par sideload, vérifier que la
carte s'affiche, que le bouton de localisation demande l'autorisation puis montre la position,
et que le refus mène à l'alerte qui ouvre les Réglages.
