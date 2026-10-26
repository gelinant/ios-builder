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
  (`search-list.png`, `search-map.png`, `search-centered.png`, `UITEST search_rows=`). Le scénario
  des suggestions tape « coff », attend les lignes d'autocomplétion puis vérifie qu'elles ne
  réapparaissent pas après une sélection (`suggest.png`, `UITEST suggestion_rows=`). Celui des
  catégories lance Coffee depuis sa puce (`category.png`, `UITEST category_rows=`).
- `MapSearchUITests` : cadre le Ferry Building à zoom 18, ouvre puis ferme sa recherche pour
  retirer l'épingle de résultat, touche le POI Liberty au milieu et exige la fiche Google
  (`map-poi.png`, `UITEST map_poi_name=`).
  (`search-list.png`, `search-map.png`, `search-centered.png`, `UITEST search_rows=`).
- `PlaceUITests` : « Davis Food Co-op » sur Davis, toucher du premier résultat, fiche ouverte ;
  galerie paginée, visionneuse avec balayage et zoom, panneau d'avis et
  « More reviews », repli d'affluence journalisé, puis pixels des avatars (`place-top.png`,
  `place-photos.png`, `place-gallery-grid.png`, `place-gallery.png`, `place-reviews.png`,
  `place-reviews-full.png`, `place-avatars.png`, et `place-popular.png` si Google fournit le
  graphique). La marche de catégories n'est pas jouée dans ce scénario CI : la page photo cachée peut
  figer le snapshot d'accessibilité du simulateur (W-2). Elle reste un test manuel sur iPhone,
  signalé par `place_gallery_walk=not-run-on-ci`, et n'est pas comptée comme une réussite. Les lignes
  `UITEST place_gallery_*`, `place_reviews_*`, `place_popular_*` et
  `place_avatars_*` donnent les nombres et l'issue des replis. Le scénario exige une photo, un
  avis et au moins un avatar non noir. Au-delà de cinq avis, il exige la croissance seulement si
  Google répond à la page suivante. Sans affluence, il exige la preuve du repli, pas une donnée
  inventée.
- `SavedUITests` : « coffee », premier résultat, Save puis Saved ; le lieu est présent, une liste
  est créée et le lieu y est ajouté (`place-save.png`, `saved-list.png`). Les récents apparaissent
  après avoir effacé la recherche. Un second lancement dans le même test vérifie la persistance du
  lieu, de la liste et des récents. Lignes `UITEST saved_places=`, `saved_lists=`,
  `saved_lists_after_restart=` et `saved_recents_after_restart=`.
- `DirectionsUITests` : position simulée sur San Francisco, « coffee », premier résultat,
  Directions ; attente des itinéraires en voiture (`directions-drive.png`), passage à la marche
  (`directions-walk.png`), étapes (`directions-steps.png`) ; puis « Ferry Building » pour un
  trajet plus long, une alternative choisie et ses étapes (`directions-far.png`,
  `directions-far-alt.png`, `directions-far-steps.png`), puis le transport en commun et ses
  étapes (`directions-transit.png`, `directions-transit-steps.png`). Lignes `UITEST
  directions_*=` : nombre d'itinéraires, secondes, mètres, étapes, tronçons de trafic,
  itinéraires de transport. Échoue sans itinéraire en voiture ou à pied, avec une seule étape
  pour la voiture vers le Ferry Building, ou sans itinéraire de transport. Le mode est collant
  (`travel_mode`) : le test repart de la voiture.
- `CalibrationUITests` : la ligne de debug `calibration <version>` atteint 27 ou plus en 60 s au
  plus (`calibration.png`, `UITEST calibration_version=`). Le script échoue (`calibration`) sinon.
- `OfflineUITests` : filtre le catalogue sur Monaco, télécharge son paquet de lieux, son archive de
  lieux et son fond de carte, avec le paquet de glyphes commun (62 Mo). Il capture une progression
  partielle (`offline-progress.png`), termine le processus, puis relance Vela et vérifie que le
  plan persistant se rattache (`offline-resume.png`). Les données de reprise fournies par
  `URLSession` sont utilisées quand elles existent. Il attend ensuite l'installation complète
  (`offline-regions.png`),
  active le mode hors ligne, vérifie que le style monté ne contient aucune URL distante et que
  Monaco vient du PMTiles local (`offline-map.png`), puis cherche « Casino de Monte Carlo » sans
  Google (`offline-search.png`). Les lignes `UITEST offline_*` rapportent la progression restaurée,
  les octets de chaque paquet et le nombre de résultats. Sur simulateur, la session reste au premier
  plan : ce scénario ne prouve pas l'exécution en arrière-plan sur iPhone.
- `LocalizationUITests` : lance le français par argument sans changer la langue du simulateur,
  vérifie « Rechercher », « Paramètres », « Langue », « Unités » et l'interrupteur Google
  (`settings-fr.png`), puis vérifie la disposition allemande (`settings-de.png`). Le scénario de
  persistance change langue, unités, horloge et Google, relance l'app et compare la ligne
  `settings-debug`. Les lignes `UITEST l10n_*` rapportent la langue et les libellés vus.

- `NavUITests` : « coffee » sur San Francisco, un résultat le long de Market Street, Directions
  puis Start. Le helper ci-dessous déclenche `sim_route_start sf-market 20 1`. Le test vérifie
  le bandeau, la distance qui diminue, la caméra qui suit, la localisation en arrière-plan et
  l'écran non mis en veille, puis End et la restauration de la carte. Si ActivityKit est autorisé,
  le scénario exige aussi la création de la Live Activity au Start, au moins une mise à jour pendant
  le replay et sa fin avec End ; sinon il rapporte `unsupported_or_disabled` sans masquer un échec
  de navigation. Le délégué `AVSpeechSynthesizer.didStart` prouve la voix sans l'écouter
  (`nav-start.png`, `nav-driving.png`, `nav-end.png`, `UITEST nav_*`). Le texte parlé est
  journalisé en Debug, sans coordonnée. Les tests `LiveActivityTests` couvrent aussi le mapping, le
  throttling, le recalcul, l'arrivée et les activités périmées. Ils vérifient l'état ActivityKit,
  jamais le rendu de l'écran verrouillé ou de la Dynamic Island ; les captures humaines demandées
  sont dans `docs/ios/LIVE-ACTIVITY.md`.
- `NavAlertsUITests` : « Ferry Building » sur San Francisco, Directions puis Start avec
  `-VelaNavAlertsFixture YES`. Un `URLProtocol` de Debug répond aux trois requêtes Overpass à partir
  de la géométrie demandée : une limitation de 80 km/h et des caméras à 250 m, sans fixture de
  coordonnées ni fournisseur factice en production. Le scénario vérifie la pastille de vitesse et de
  limitation, le bandeau de caméra, puis End (`nav-speed.png`, `nav-camera.png`, `UITEST
  nav_speed_limit=`, `nav_camera_groups=`, `nav_alerts_end=`). L'acceptation d'un itinéraire plus
  rapide est couverte par les tests JVM du `NavSession` réel ; le délai de deux minutes ne donne pas
  de capture de trafic déterministe.
- `NavRobustnessUITests` : « coffee » sur San Francisco et le replay `sf-market`, avec
  `-VelaNavRobustnessTest YES`. Le scénario attend que la distance restante diminue, met la
  conduite en pause et vérifie que les chiffres et la caméra se figent (`nav-paused.png`), passe
  l'app en arrière-plan puis la réactive et exige la même session, le même état de pause et une
  seule Live Activity, reprend sans replanifier, puis simule une perte de GPS avec les boutons de
  Debug `nav-test-starve` et `nav-test-gps`. Il exige l'état « no GPS » et l'estimation de tunnel
  (`nav-starved.png`), la reprise automatique au retour des points, puis End et la restauration de
  la carte. Les lignes `UITEST nav_pause=`, `nav_lifecycle=`, `nav_resume=`, `nav_starved=`,
  `nav_reckoning=`, `nav_gps_back=` et `nav_robustness_end=` donnent les preuves. Le scénario ne
  couvre ni un vrai tunnel, ni un appel, ni un changement Bluetooth, ni le verrouillage d'écran sur
  iPhone ; ces quatre points restent des tests humains.

## Arguments de lancement

Lus par `iosApp/Vela/App/LaunchOptions.swift`, sous la forme `-Nom valeur` (la même chose que
`simctl launch <udid> app.vela.ios -Nom valeur`) :

| Argument | Effet |
|---|---|
| `-VelaStartCamera sf` | Caméra de départ : `sf`, `davis`, `sacramento`, ou `lat,lng[,zoom]`. Défaut : San Francisco, zoom 12 |
| `-VelaDeterministic YES` | Aucune animation UIKit ni de caméra, pour des captures stables |
| `-VelaFollowUser YES` | Suit la position au lancement si l'autorisation est déjà donnée (trajets simulés) |
| `-VelaOfflineTest YES` | En Debug, affiche dans la feuille Offline les boutons qui bloquent le réseau après les téléchargements et suspendent un transfert pour le scénario de relance |
| `-VelaLanguage fr` | Langue intégrée à Vela pour ce lancement, sans la persister ni changer le simulateur |
| `-VelaResetSettings YES` | En Debug, efface les suites `vela_settings` et `vela_units` avant leur première lecture |
| `-VelaNavAlertsFixture YES` | En Debug, réponses Overpass déterministes dérivées de la route pour les alertes de navigation |
| `-VelaNavRobustnessTest YES` | En Debug, affiche les boutons `nav-test-starve` et `nav-test-gps`, qui coupent puis rétablissent la livraison des points à Vela sans arrêter le replay `simctl` |

Un argument illisible ou hors bornes retombe sur le défaut.

## Éléments de debug

En Debug seulement, la carte affiche en haut à gauche des lignes d'état lisibles par
XCUITest par leur identifiant d'accessibilité :

| Identifiant | Texte |
|---|---|
| `velacore-debug` | `VelaCore 0.1.0: West Covell Boulevard -> W Covell Blvd` (l'appel Kotlin de contrôle) |
| `calibration-debug` | `calibration <version>` : 0 avant le démarrage de la session, puis la version en cache ou compilée, puis celle du rafraîchissement |
| `route-debug` | Quand le choix d'itinéraire est ouvert : `routes=<n> active=<i> mode=DRIVE\|WALK\|BICYCLE\|TRANSIT loading=0\|1 seconds=<s> meters=<m> steps=<n> traffic=<tronçons> transit=<itinéraires> legs=<étapes> center=0\|1 error=0\|1` |
| `place-debug` | Sous le nom, dans la fiche lieu : `photos=<n> reviews=<n> from=feed\|page\|cache\|none details=loading\|done reviewsLoading=0\|1 popular=<heures> fallback=none\|loading\|empty\|details\|popular\|unavailable walk=0\|1 moreReviews=0\|1 avatarLoaded=<n> avatarColor=<n> hours=<lignes> phone=0\|1` |
| `place-gallery-debug` | Dans la galerie : `count=<n> filtered=<n> loading=0\|1 walk=0\|1 categories=<n>` |
| `place-reviews-debug` | Dans le panneau : `count=<n> more=0\|1 loading=0\|1 initialLoading=0\|1 from=<source> avatarLoaded=<n> avatarColor=<n>` |
| `offline-debug` | `regions=<n> installed=<n> pack=<octets> places=<octets> map=<octets> glyphs=<octets> total=<octets> rev=<n>` |
| `offline-download-debug` | Dans la feuille avec `-VelaOfflineTest YES` : `downloading=<id\|-> stage=<pièce\|-> pct=<n> pieces=<terminées>/<total> error=<clé\|->` |
| `offline-map-debug` | Quand un fond local est monté : `archive=<fichier> remote=<n>`, où `remote` compte les URL HTTP(S) restant dans le style JSON |
| `search-debug` | `offline=0\|1 results=<n> suggestions=<n>` : 1 quand la réponse vient uniquement des données installées |
| `settings-debug` | Dans l'écran Settings : `language=<code\|system> units=<mode> clock=<mode> google=0\|1` |
| `nav-debug` | `nav=0\|1 active=0\|1 starting=0\|1 left=<m> eta=<s> follow=0\|1 camera=<n> voice=<n> idle=0\|1 background=0\|1 offroute=0\|1 activity=0\|1 actenabled=0\|1 actrequests=<n> actupdates=<n> actended=<n> acterror=0\|1 limit=<km/h> speeding=0\|1 alertgroups=<n> offer=0\|1 delay=<s> paused=0\|1 starved=0\|1 reckoning=0\|1 bg=0\|1 interruptions=<n> routechanges=<n> accuracy=<m> suppressed=<n>` |
| `nav-voice-debug` | `spoken=<n>` puis `text=<dernière phrase>` après le premier rappel du délégué vocal |

Dans `nav-debug`, `paused` suit la pause, `starved` l'absence de point de guidage utilisable depuis
10 s, `reckoning` l'estimation le long de la route, `bg` l'état arrière-plan, `interruptions` et
`routechanges` les événements audio vus, `accuracy` le rayon du dernier point en mètres et
`suppressed` les points ignorés par le bouton de perte de GPS.

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
| `sim_route_arm <udid> sf-market 20 1` | Arme le replay sur `nav replay: start` dans le journal, puis restaure la position fixe sur `nav replay: end` ; définit `SIM_ROUTE_ARM_PID` |
| `sim_route_disarm <pid>` | Tue le surveillant et les deux côtés de son pipeline de journal |
| `sim_location_clear <udid>` | Arrête le trajet, efface la position |
| `sim_shot <udid> <fichier>` | Capture de l'écran du simulateur |
| `sim_log_persist <udid>` | Garde les lignes info et debug de `app.vela.ios` dans le journal du simulateur |
| `sim_collect_logs <udid> <dossier> [minutes]` | Écrit `app-log.txt` et `velacore-log.txt` |

Trajets fixtures (`sim_route_points`) : `sf-market` (Market Street, de Van Ness au Ferry
Building, environ 2,6 km) et `davis-covell` (West Covell Boulevard vers l'est puis F Street vers
le sud, environ 3 km). Un trajet nouveau reste dans les zones fixtures (San Francisco, Davis,
Sacramento).

La cible XCUITest iOS ne peut pas lancer `simctl` avec `Process`. Avant les scénarios,
`ci-ipa.sh` appelle donc `sim_route_arm`. Le surveillant écoute le journal unifié :
`NavModel` écrit `nav replay: start` au début de la conduite, ce qui déclenche
`sim_route_start sf-market 20 1`, puis `nav replay: end`, ce qui restaure la position fixe de San
Francisco pour les scénarios suivants. `sim_route_disarm` arrête le surveillant à la fin des tests.

## Preuve hors ligne sans coupe-réseau du simulateur

`simctl` n'a pas de mode avion et le runner n'a pas `sudo`. Le scénario télécharge donc d'abord,
puis `OfflineTestSupport` enregistre un `URLProtocol` qui fait échouer toute nouvelle requête
HTTP(S) sans toucher aux URL `file://`. `OfflineStore` passe aussi en mode local forcé, ce qui
empêche la recherche Google et reste effectif si `NWPathMonitor` signale encore un chemin satisfait.
MapLibre ne dépend pas de ce protocole pour la preuve : le test lit le style généré et exige
`remote=0`, donc ni tuile, glyphe, sprite ni style OpenFreeMap ou Google à demander. Le PMTiles, le
style, les glyphes et le sprite sont alors tous locaux. Cette méthode ne prétend pas couper le
réseau du système entier ; elle prouve que les chemins utilisés par la carte et la recherche n'en
ont pas besoin.

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
