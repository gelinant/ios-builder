# Ruche iOS : protocole et tableau

Les agents de la ruche lisent ce fichier après `PORTAGE_IOS.md`. Le coordinateur est le seul à
modifier le tableau et à merger dans `ios/main`.

## Tableau

| Lot | État | Branche | Notes |
|---|---|---|---|
| W-1 spike réseau | fait : go | `ios/main` | `docs/ios/spike-scraping-ios.md` §7 |
| P0-1 Mac CI | fait | builder `run` | `scripts/mac-run.sh` |
| F-1 `:core-common` | fait, mergé | `ios/f1-core-common` | jvm consommé par Android ; klibs iOS compilés sous Linux ; Mac vert |
| C-0 carte de migration | fait, mergé | `ios/c0-core-graph` | `docs/ios/CORE-MIGRATION.md` |
| V-1 remontée minimale (recherche) | fait, mergé | `ios/v1-search-core` | 21 fichiers en common ; 76 tests verts sur JVM et simulateur iOS |
| V-2 recherche iOS (M2) | fait, mergé : **M2 validé sur iPhone** | `ios/v2-search-ios` | « coffee » : 60 résultats, liste + épingles ; test UI automatique ; IPA 4,5 Mo sur la branche `ipa` |
| C-1 mécanique (hors V-1) | fait, mergé | `ios/c1-mechanical` | 12 fichiers devenus PURE ; `NavStrings` et `java.time` reportés au déplacement (C-5) |
| F-2 coutures de base | fait, mergé | `ios/f2-seams` | 7 coutures + `CoreGraph`, impl. Android dans `core/platform`, inutilisées pour l'instant |
| F-3a coquille iOS + IPA (Swift seul) | fait, mergé : **M1** | `ios/f3a-ios-shell` | IPA 3,2 Mo ; **iPhone 2026-10-24 : sideload OK, carte, déplacement et zoom OK** , bouton de localisation OK : **M1 validé** |
| P-0 carte de la logique de présentation | fait, mergé | `ios/p0-viewmodel-map` | `docs/ios/PRESENTATION-MAP.md` : `MapSession` unique + facettes, ~4,85 k lignes |
| F-3b `:ios-shared` + VelaCore.framework | fait, mergé | `ios/f3b-ios-shared` | SKIE 0.10.15 OK avec Kotlin 2.4.20 ; IPA 3,7 Mo ; appel Kotlin vérifié au lancement |
| C-4 config | fait, mergé | `ios/c4-config` | `CalibrationStore` en common ; coutures `JsEngine`, `SignatureVerifier` (Swift à écrire) |
| C-3 services ouverts | fait, mergé (partiel) | `ios/c3-open-services` | Photon, Overpass, ShortLinks, PaintedRoads en common ; OSRM/Valhalla attendent C-5, Transitous lot à part |
| C-2 source Google | fait, mergé | `ios/c2-google` | `GoogleMapsSource` en common, routage hybride reste dans `:core` ; snapshot d'en-têtes identique |
| I-0 plateforme iOS + calibration + banc de test | fait, mergé | `ios/i0-ios-platform` | JavaScriptCore + kill switch, signature Security.framework, calibration v27 en direct ; `docs/ios/TESTING-IOS.md` |
| I-3 fiche lieu (M3) | fait, mergé : **M3 sur simulateur** | `ios/i3-place` | détails, horaires, 10 photos, 5 avis (flux qv9Egd), appel/site ; scrape WebView en repli |
| C-8 offline + SQLite | fait, mergé | `ios/c8-offline` | `SqlDb` (Android SQLiteOpenHelper / iOS sqlite-bundled), 3 stores SQLite + PMTiles en common ; 373 tests simulateur |
| C-6 stores | fait, mergé | `ios/c6-stores` | 7 stores + caches en common, compat données Android testée ; SQLite reporté en C-8 |
| C-5 nav | fait, mergé | `ios/c5-nav` | tout `nav/`, NavSession, OSRM/Valhalla, routeur hybride, NavStrings (18 langues, snapshot identique) en common ; 711 tests simulateur |
| C-3b Transitous | fait, mergé | `ios/c3b-transitous` | Transitous, lignes, NDW, carburant UK, OsmMaxspeed en common ; parité avec l'ancien code ; 882 tests simulateur |
| I-4 itinéraires (M4) | fait, mergé : **M4 sur simulateur** | `ios/i4-routes` | alternatives, modes, options, étapes ; build final du merge `m4final-20261025-152820-13098` |
| I-4b finitions itinéraires + hybride + transports | fait, mergé | `ios/i4b-routes-polish` | étapes nommées + voies, 5 itinéraires transport Transitous ; avatars toujours noirs ; identité Chrome à corriger |
| I-5 navigation guidée (M5) | fait, mergé : **M5 sur simulateur** | `ios/i5-nav` | bandeau, distance qui diminue, caméra, 4 phrases vocales ; merge `m5final-20261025-183757-4411` : 9/9 scénarios, nav_end=restored ; IPA publiée |
| I-6 lieux enregistrés | fait, mergé | `ios/i6-saved` | listes, récents, parking, itinéraires enregistrés, imports, partage |
| I-7 régions hors ligne | fait, mergé | `ios/i7-offline` | Monaco : carte locale (0 URL distant) + 30 résultats hors ligne ; téléchargement premier plan |
| I-8 langues + réglages | fait, mergé | `ios/i8-l10n` | 1415 clés, 24 langues, réglages langue/unités/horloge/NoGoogle ; `%ld` vérifié ; FR/DE sur simulateur |
| N-1 carte + recherche | fait, mergé | `ios/n1-map-search` | suggestions après 320 ms, 6 catégories, toucher POI, appui long + géocodage inverse ; 12/12 scénarios |
| P-1 fiche lieu complète | fait, mergé | `ios/p1-place-complete` | galerie 10→20, fallback affluence, Street View, avatars colorés corrigés ; scénario ciblé vert `p1target6-20261026-035815-8092` : 20 photos, balayage, zoom, 5 avatars non noirs ; suite complète en cours |
| X-1 Live Activity conduite/marche | fait, mergé | `ios/x1-live-activity` | ActivityKit + Dynamic Island, 3 mises à jour puis End en test ; vues lock screen à vérifier sur iPhone ; IPA publiée |
| W-2 spike WKWebView | fait, mergé : **go I-3** | `ios/w2-webview-spike` | scripts Android inchangés OK ; WebGL plante le GPU du simulateur ; course d'injection aussi présente sur Android |
| I-8a script de chaînes | fait, mergé | `ios/i8a-strings` | 1415 clés, 24 langues ; à vérifier sur Mac : `%d` vs `%ld`, `area_pick_cells` |

## IPA à tester

Toujours la dernière IPA validée par le coordinateur : branche `ipa` du builder,
<https://github.com/gelinant/ios-builder/raw/ipa/Vela-unsigned.ipa> (connecté à GitHub). Le
`README.md` de la branche dit quel build c'est et quoi tester.

## Source SideStore

`https://raw.githubusercontent.com/gelinant/ios-builder/dist/apps.json` : dernière IPA
validée + manifeste. Publication : `scripts/ios/publish-sidestore.sh <ipa> "notes" [capture]`.
Détails : `docs/ios/SIDESTORE.md`.

## Protocole

### Où travailler

- Chaque lot a son worktree : `~/gmaps/wt/<lot>`, sur sa branche `ios/<lot>` créée depuis
  `ios/main`. Ne jamais travailler dans `~/gmaps/vela` (c'est le checkout du coordinateur).
- Les fichiers ignorés nécessaires au build (`local.properties`, `core/libs/*.jar`,
  `app/libs/*.aar`) sont déjà copiés dans le worktree.
- Committer sur sa branche, et la pousser : `git push alt144 ios/<lot>`. Ne jamais pousser
  `ios/main` ni `main`.

### Gradle (machine : 7 Go de RAM)

Un seul Gradle à la fois sur la machine, sinon c'est l'OOM :

```
source ~/opt/env.sh
flock /tmp/opencode/gradle.lock ./gradlew --no-daemon <tâches>
```

Côté iOS Kotlin : `:core-common:compileKotlinIosSimulatorArm64` marche sous Linux. Le Mac pour
le link et les tests simulateur : `scripts/ios/ci-kotlin.sh` (`-Pvela.iosOnly=true`).

Toujours `--no-daemon` (un démon resté vivant garde 3 Go). Viser les tâches utiles, pas un build
complet à chaque fois. `:app:assembleDebug` seulement avant de rendre le lot.

### Mac (budget limité : environ 200 minutes par mois)

```
bash ~/gmaps/ios-builder/scripts/mac-run.sh <worktree> <lot> <script> [args]
```

Le script (dans le worktree, par exemple `scripts/ios/ci-ipa.sh`) tourne sur le runner macOS
depuis la racine du source, avec `$OUT` pour ses sorties. La commande attend la fin et affiche le
statut et la fin du log. Les fichiers de plus de 50 Mo reviennent sur la branche `builds` du
builder. Runner : macOS 26.6, Xcode 26.6, simulateurs iOS 26.5 (iPhone 17), JDK 17 dans
`$JAVA_HOME_17_arm64`, Homebrew présent, XcodeGen absent (à installer par le script).

Règles : tout ce qui se vérifie sous Linux se vérifie sous Linux. Au plus **4 lancements Mac par
lot** sans accord du coordinateur. Grouper les vérifications dans un seul script.

### Écriture

`CLAUDE.md` s'applique : US English dans le code, les commentaires et les commits ; pas de tiret
cadratin ; pas d'attribution IA ; pas de coordonnée hors fixtures (Davis, Sacramento, San
Francisco). Les docs du portage (`PORTAGE_IOS.md`, `docs/ios/`) sont en français.

### Rendre un lot

Le dernier message de l'agent au coordinateur contient :

1. Branche et dernier commit poussé.
2. Fait / reste.
3. Commandes de vérification lancées et leur résultat (Linux et Mac).
4. Tests iPhone à faire par l'humain.
5. Risques découverts, fichiers hors périmètre qui devraient changer.

| N-2 navigation alertes et trafic | fait, mergé | `ios/n2-nav-alerts` | vitesse/limitations, Overpass, offres plus rapides ; preuves UI encore à rejouer |
| O-2 téléchargements hors ligne arrière-plan | fait, mergé | `ios/o2-offline-background` | background URLSession, reprise après relance, noms de rues PMTiles locaux ; dernier scénario UI à rejouer |
| X-2 App Intents + Spotlight | fait, mergé | `ios/x2-intents-spotlight` | Maison/Travail/parking/recherche, liens `vela://` et spotlight |
| Q-1 matrice de parité et qualité | fait, mergé | `ios/q1-parity-quality` | 204 lignes : 2 ✅, 12 🟡, 84 ⚠️, 87 ❌, 19 ➖ ; `FEATURES-IOS.md`, `QUALITY.md` |

| X-3 Live Activity transports | fait, mergé | `ios/x3-transit-activity` | TransitSession, ligne/direction/descente, ActivityKit partagée avec X-1 ; test fixture vert ; limites sans push documentées |

| V1 intégration | **suite complète verte** `fullmerge5-20261026-064718-24926` | `ios/main` | 27 scénarios UI + 6 perf, 45 tests Swift, 92 tests Kotlin simulateur ; IPA et source SideStore publiées |

| Q-2 accessibilité | fait, mergé | `ios/q2-accessibility` | RTL hébreu, cibles 44 pt, labels VoiceOver, grands textes et paysage ; corrections de harnais à rejouer |
| I-2b recherche adresses et déduplication | fait, mergé | `ios/i2b-search-addresses` | Photon + Google + adresses installées, élargissement 40 km, dédup 0 doublon ; 26 résultats, 14 avec l'adresse tapée |
| L-1 lieux enregistrés finitions | fait, mergé | `ios/l1-saved-polish` | raccourcis Maison/Travail sur la carte, ligne enregistrée dans le choix d'itinéraire, partage de liste, Takeout avec accès sécurisé |
| R-1 options d'itinéraires | fait, mergé | `ios/r1-route-options` | origine (position/carte/lieu/favori), 10 arrêts, départ/arrivée à une heure ; arrêts pendant le guidage hors lot |

| S-0 stabilisation récents + Spotlight | fait, mergé (cherry-pick) | `ios/stabil-saved` | écriture synchronisée des préférences ; test Spotlight vérifie l'émission réelle des requêtes, le démon du simulateur pouvant ne pas répondre |
| T-1 transports : départs, options | fait, mergé | `ios/t1-transit` | tableau d'arrêt (3 lignes, 50 départs), filtres véhicule, départ/arrivée à une heure, détail avec alertes ; ferry non supporté par Transitous |
| I-1b couches et styles de carte | fait, mergé | `ios/i1b-map-layers` | panneau de couches, POI par catégorie, densité, marques peintes, caméras, contrôles, carburant UK, ponts NL ; trafic/satellite Google affichés indisponibles |

| DL-1 liens entrants | fait, mergé | `ios/dl1-incoming-links` | liens Google Maps place/dir/cid, short links, geo: ; arrêts intermédiaires refusés explicitement |
| N-3 navigation robuste | fait, mergé | `ios/n3-nav-robustness` | tunnel et perte GPS (dead-reckoning Android), pause/reprise, cycle de vie, correction de la voix injectée |

## Matrice

Le tableau de parité vit dans `docs/ios/FEATURES-IOS.md` (204 lignes, synthèse générée par
`scripts/ios/parity_check.py`). État au dernier rafraîchissement : 2 validées iPhone, 20 testées
simulateur, 94 partielles, 69 absentes, 19 sans équivalent iOS.

| VO-1 voix neurales | fait, mergé | `ios/vo1-neural-voice` | Piper/sherpa-onnx, 56 856 échantillons réels, repli AVSpeech ; run ciblé vert `vo1-fix3-20261026-235926-7079` |
| SV-1 Street View interactif | fait, mergé | `ios/sv1-street-view` | panoramas SceneKit sans WebView, voisins, nord, zoom, cache ; run ciblé vert `sv1-fix-20261026-220653-7405` |

| M-1 vue 3D + relief ombré | planifié, fin de pipeline | - | bâtiments extrudés, pitch, ciel, hillshade terrarium |
| M-2 écran Relief (terrain) | planifié | - | GL JS `setTerrain`, écran séparé |
| G-1 spike globe natif | planifié | - | pré-release `ios-v2026.10.19-globe`, `MLN_WITH_GLOBE` |
| G-2 globe intégré | planifié | - | natif si G-1 conclut, sinon écran GL JS |
