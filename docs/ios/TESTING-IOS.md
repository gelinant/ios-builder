# Tester l'app iOS sans humain

Ce fichier dit comment l'app iOS se teste seule sur le runner macOS, et comment un lot ajoute un
scénario. Tout passe par `scripts/ios/ci-ipa.sh` (un lancement Mac, voir `docs/ios/HIVE.md` pour
le budget) ; le build lui-même est décrit dans `docs/ios/BUILD-IOS.md`.

## Ce qui tourne à chaque run

| Étape | Contenu | Sortie dans `$OUT` |
|---|---|---|
| Kotlin | `:ios-shared:jvmTest` et `iosSimulatorArm64Test` | `gradle.log.gz`, nombres dans `summary.txt` |
| Tests unitaires Swift | cible `VelaTests`, hébergée dans l'app | `xcodebuild-test.log.gz` ; lignes `SEAM_TEST` recopiées dans le résumé |
| Lancement brut | `simctl launch`, capture après 20 s | `screenshot.png` |
| Scénarios d'interface | toutes les classes de `VelaUITests` | une PNG par capture nommée ; lignes `UITEST clé=valeur` et résultat par test dans le résumé |
| Trajet simulé | `simctl location start` sur un trajet fixture, carte qui suit la position | `route-1.png`, `route-2.png` |
| Journaux | `log show` sur le processus et sur le sous-système `app.vela.ios` (niveaux info et debug gardés) | `app-log.txt`, `velacore-log.txt` |
| IPA | archive appareil sans signature | `Vela-unsigned.ipa` |

Scénarios actuels :

- `LaunchUITests` : la carte sur San Francisco (champ de recherche, bouton de localisation,
  `launch-sf.png`) ; la caméra de départ sur Davis (`launch-davis.png`).
- `SearchUITests` : « coffee » sur San Francisco, au moins 5 lignes, épingles, toucher d'une ligne
  (`search-list.png`, `search-map.png`, `search-centered.png`, `UITEST search_rows=`).
- `PlaceUITests` : « coffee » sur San Francisco, toucher du premier résultat, fiche ouverte ;
  attente des détails puis des avis (le flux `qv9Egd` d'abord, la page cachée ensuite), défilement
  (`place-top.png`, `place-photos.png`, `place-reviews.png`, `place-reviews-2.png`, `UITEST
  place_photos=`, `place_reviews=`, `place_reviews_from=`, `place_popular_hours=`). Échoue sans
  photo ou sans avis.
- `DirectionsUITests` : position simulée sur San Francisco, « coffee », premier résultat,
  Directions ; attente des itinéraires en voiture (`directions-drive.png`), passage à la marche
  (`directions-walk.png`), étapes (`directions-steps.png`) ; puis « Ferry Building » pour un
  trajet plus long, une alternative choisie et ses étapes (`directions-far.png`,
  `directions-far-alt.png`, `directions-far-steps.png`). Lignes `UITEST directions_*=` :
  nombre d'itinéraires, secondes, mètres, étapes, tronçons de trafic. Échoue sans itinéraire en
  voiture ou à pied. Le mode est collant (`travel_mode`) : le test repart de la voiture.
- `CalibrationUITests` : la ligne de debug `calibration <version>` atteint 27 ou plus en 60 s au
  plus (`calibration.png`, `UITEST calibration_version=`). Le script échoue (`calibration`) sinon.

## Arguments de lancement

Lus par `iosApp/Vela/App/LaunchOptions.swift`, sous la forme `-Nom valeur` (la même chose que
`simctl launch <udid> app.vela.ios -Nom valeur`) :

| Argument | Effet |
|---|---|
| `-VelaStartCamera sf` | Caméra de départ : `sf`, `davis`, `sacramento`, ou `lat,lng[,zoom]`. Défaut : San Francisco, zoom 12 |
| `-VelaDeterministic YES` | Aucune animation UIKit ni de caméra, pour des captures stables |
| `-VelaFollowUser YES` | Suit la position au lancement si l'autorisation est déjà donnée (trajets simulés) |

Un argument illisible ou hors bornes retombe sur le défaut.

## Éléments de debug

En Debug seulement, la carte affiche en haut à gauche des lignes d'état lisibles par
XCUITest par leur identifiant d'accessibilité :

| Identifiant | Texte |
|---|---|
| `velacore-debug` | `VelaCore 0.1.0: West Covell Boulevard -> W Covell Blvd` (l'appel Kotlin de contrôle) |
| `calibration-debug` | `calibration <version>` : 0 avant le démarrage de la session, puis la version en cache ou compilée, puis celle du rafraîchissement |
| `route-debug` | Quand le choix d'itinéraire est ouvert : `routes=<n> active=<i> mode=DRIVE\|WALK\|BICYCLE\|TRANSIT loading=0\|1 seconds=<s> meters=<m> steps=<n> traffic=<tronçons> center=0\|1 error=0\|1` |
| `place-debug` | Sous le nom, dans la fiche lieu : `photos=<n> reviews=<n> from=feed\|page\|cache\|none details=loading\|done reviewsLoading=0\|1 popular=<heures> hours=<lignes> phone=0\|1` |

Un lot qui a besoin d'observer un état sans le deviner sur une capture ajoute une ligne de ce
genre dans `MapScreen` (bloc `#if DEBUG`), jamais de coordonnée ni de texte tapé.

## Ajouter un scénario

1. Un fichier `iosApp/VelaUITests/<Fonction>UITests.swift`, une classe qui hérite de
   `VelaUITestCase`.
2. `launch(camera:deterministic:followUser:arguments:)` lance l'app et attend la carte ;
   `shot("nom")` enregistre `nom.png` (dans `$OUT`, et en pièce jointe du résultat) ;
   `waitUntil(secondes) { condition }` attend sans `sleep` fixe ; `debugText("id")` lit une
   ligne de debug ; `report("clé", valeur)` écrit une ligne `UITEST clé=valeur` que le résumé
   reprend.
3. Rien à changer dans `ci-ipa.sh` : toutes les classes de `VelaUITests` tournent, chacune a sa
   ligne `ui Classe.test: passed|failed` dans le résumé, et toutes les PNG sont recopiées. Seul
   ajout éventuel : un nom de capture dans la ligne `ui screenshots` du script.
4. XcodeGen prend tout fichier du dossier ; pas de `project.yml` à toucher.

Exemple :

```swift
final class PlaceUITests: VelaUITestCase {
    func testPlaceSheetOpens() {
        let app = launch(camera: "davis")
        // ...
        shot("place-sheet")
        report("place_rows", 3)
    }
}
```

## Position simulée et trajets

`scripts/ios/sim-helpers.sh`, chargé par `ci-ipa.sh`, prend l'UDID du simulateur en premier
argument :

| Fonction | Rôle |
|---|---|
| `sim_location_grant <udid> <bundle>` | Autorisation de localisation sans la fenêtre système |
| `sim_location_set <udid> sf` | Position fixe : un nom de fixture ou `lat,lng` |
| `sim_route_start <udid> sf-market 20 1` | Rejoue un trajet : `xcrun simctl location start --speed=20 --interval=1` sur les points du trajet ; rend la main tout de suite |
| `sim_location_clear <udid>` | Arrête le trajet, efface la position |
| `sim_shot <udid> <fichier>` | Capture de l'écran du simulateur |
| `sim_log_persist <udid>` | Garde les lignes info et debug de `app.vela.ios` dans le journal du simulateur |
| `sim_collect_logs <udid> <dossier> [minutes]` | Écrit `app-log.txt` et `velacore-log.txt` |

Trajets fixtures (`sim_route_points`) : `sf-market` (Market Street, de Van Ness au Ferry
Building, environ 2,6 km) et `davis-covell` (West Covell Boulevard vers l'est puis F Street vers
le sud, environ 3 km). Un trajet nouveau reste dans les zones fixtures (San Francisco, Davis,
Sacramento).

Pour un futur test de navigation : `sim_location_grant`, `sim_route_start` dans le script, puis
le test d'interface lancé avec `followUser: true` ; ou, depuis un test, le trajet démarré avant
`xcodebuild test-without-building` par le script. XCUITest ne pilote pas la position lui-même.

## Pièges connus

- Les lignes `info` du `Log` Kotlin ne sont pas gardées par défaut dans le journal du
  simulateur : `sim_log_persist` doit passer avant le premier lancement de l'app (le script le
  fait juste après le démarrage du simulateur, avant les tests unitaires).
- Les tests unitaires lancent déjà l'app hôte : la calibration y est récupérée et mise en cache.
  Le scénario de calibration peut donc la lire depuis le cache vérifié ; `velacore-log.txt` dit
  laquelle (`calibration at startup` puis `calibration after refresh`).
- Le runner sort par une IP de datacenter ; un échec réseau de Google n'y est pas concluant
  (`docs/ios/spike-scraping-ios.md`).
- WebGL fait planter le GPU du simulateur (W-2) : pas de scénario WKWebView avec WebGL.
  `HiddenWebView` refuse WebGL dans le simulateur seulement (`#if targetEnvironment(simulator)`) ;
  sur un iPhone, la carte WebGL de la page cachée tourne.
- Les avis ne partent que quand leur section arrive à l'écran (contenu paresseux, comme Android) :
  un scénario qui veut des avis doit faire défiler la fiche.
