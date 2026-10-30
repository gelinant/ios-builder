# Vela → iOS : plan de portage (v2)

> Chaque agent lit ce fichier en entier, puis `CLAUDE.md` (Rules, Traps, "What Vela never
> does", Location hygiene), puis ne traite **que** son lot.
>
> Mesures prises sur `main` au commit `090d1e1` (oct. 2026), avec les commandes du §1. Ce plan
> remplace le plan initial et la v1 de ce fichier. Les écarts sont résumés au §2.

**État au 30 octobre 2026** : la phase 8 est livrée sauf T-2 partiel et A-4 abandonné. Le détail
des lots, des merges et des preuves est dans
[docs/ios/BACKLOG.md](docs/ios/BACKLOG.md), section « État au 30 octobre ».

---

## 0. Le plan en dix lignes

1. **Go/no-go d'abord** : Google répond-il à une app iOS ? Un script Swift (`tools/ios-spike.swift`)
   le dit en une heure sur un Mac. Rien d'autre ne démarre avant.
2. **Ne pas convertir `:core` en KMP.** On crée à côté un module **`:core-common`** (KMP : `jvm`,
   `iosArm64`, `iosSimulatorArm64`). `:core` reste une Android library, avec les mêmes plugins et
   les mêmes tâches Gradle, et dépend de `:core-common`. Les fichiers y migrent un par un, des
   feuilles vers la racine.
3. **UI iOS en SwiftUI** (décision validée), carte MapLibre iOS native.
4. **Le code spécifique iOS est écrit en Swift**, derrière des interfaces Kotlin en style callback.
   `iosMain` reste presque vide : les agents Linux compilent et testent tout le Kotlin, le Mac ne
   juge que le Swift.
5. **Identité réseau iOS = Safari**, cohérente avec la pile TLS d'Apple. Pas de Chrome sur iOS :
   il n'existe pas de Cronet iOS récent.
6. **Sur iOS, la couche WebView est plus simple qu'Android** : WKWebView n'ajoute pas
   `X-Requested-With`, donc `WebProxy`, `WebStreamProxy` et l'interception disparaissent. Il
   reste : charger, injecter le JS existant, recevoir le résultat.
7. **Une tranche verticale tôt** : la première IPA affiche une carte, la deuxième cherche sur
   Google. Ensuite seulement, on élargit.
8. **La logique d'orchestration** (`MapViewModel`, 10,7 k lignes, presque sans Android) n'est pas
   recopiée en Swift. Elle est extraite par fonction dans un module KMP **`:ios-shared`**
   (stores Search, Place, Route, Nav) que SwiftUI observe.
9. **V1 = recherche, fiche lieu, itinéraires, navigation guidée avec voix, lieux enregistrés,
   régions hors ligne (carte + recherche).** Hors V1 : CarPlay, routage hors ligne OsmAnd,
   dictée, voix neurales, Street View, D-pad.
10. **Distribution** : IPA non signée produite par la CI macOS, signée par AltStore, SideStore ou
    Sideloadly.

---

## 1. Mesures (ce qui est vrai dans le repo)

### 1.1 `:core` (`core/src/main/java`)

| Mesure | Valeur | Commande ou méthode |
|---|---|---|
| Fichiers `.kt` | 172 (31,9 k lignes) | `find … -name '*.kt'` |
| Sans import `android`, `androidx`, `java`, `javax`, `okhttp3`, `org.mozilla`, `dagger`, `net.osmand` | **106** | grep des lignes `import` |
| … dont qui appellent quand même une API JVM en nom qualifié (`Math.toRadians`, `java.time`, `java.text.Normalizer`, `java.util.Locale`, `String.format`, `Thread`) | ~45 | grep des usages |
| Vraiment portables tels quels | **~60** | différence |
| Fichiers qui importent `android.*` | 23 | |
| Fichiers avec `javax.inject` / `dagger` | 22 | |
| Fichiers qui importent `okhttp3` | 21, dont 13 qui font des appels (`GoogleMapsDataSource` : 11) | surface réelle : `OkHttpClient`, `Request`, `toRequestBody`, `CookieJar` |
| `synchronized` | 58 occurrences | |
| `String.format` / `.format(` | 28 occurrences | |
| Stores SQLite (`SQLiteOpenHelper`) | **3** : `OfflinePoiStore`, `OfflineAddressStore`, `OfflinePacks` | |
| Stores `SharedPreferences` | **7** : `ParkingStore`, `PlaceListStore`, `PlaceShortcutStore`, `RecentPlaceStore`, `RecentSearchStore`, `SavedPlaceStore`, `SavedRouteStore` | |
| Tests (`core/src/test`) | 169 fichiers, dont 153 sans import Android/OkHttp/Rhino/OsmAnd/`File`/`org.json` | |

Gros paquets : `data/` 83 fichiers (16,5 k lignes), `nav/` 25 (4,8 k), `util/` 12, `model/` 12.

### 1.2 `:app` (`app/src/main/java`)

| Paquet | Fichiers | Lignes | Sort sur iOS |
|---|---|---|---|
| `ui/` | 161 | 58,9 k | Réécrit en SwiftUI. Dont `ui/map/VelaMapView.kt` 11 k, `MapViewModel.kt` 10,7 k (3 imports Android), `MapScreen.kt` 7,3 k, `NavController.kt` 1,6 k |
| `offline/` | 23 | 3,4 k | Parties pures vers `:core-common`, le reste en Swift |
| `web/` | 18 | 3,4 k | Réécrit en Swift (WKWebView), JS partagé |
| `car/` | 20 | 3,4 k | Hors V1 (CarPlay) |
| `voice/` | 8 | 1,6 k | `AVSpeechSynthesizer` en V1 |
| `update/` | 4 | 0,4 k | Abandonné (lien vers les releases) |
| `service/`, `streetview/`, `diag/`, `data/`, … | 24 | 3,1 k | Au cas par cas |

### 1.3 Faits techniques qui orientent les choix

- **AGP 9.4.1 et Kotlin 2.4.20.** Depuis AGP 9, `com.android.library` n'est plus compatible avec
  le plugin `kotlin-multiplatform` dans le même module. Convertir `:core` en place oblige à passer
  au plugin `com.android.kotlin.multiplatform.library`. Ce plugin n'a qu'une variante : les tâches
  `:core:testDebugUnitTest` changent de nom, et cette commande est citée dans `CLAUDE.md`, la CI et
  les procédures de calibration. C'est pour ça que D1 crée un module à côté.
- **Cronet** porte toutes les requêtes vers les hôtes Google sur Android (`GoogleTransport.hook`,
  SPEC « Transport »), pour que l'empreinte TLS/HTTP2 soit celle de Chrome. Le bucket
  `storage.googleapis.com/chromium-cronet/ios/` ne publie plus rien d'utile après la version 108
  environ. **Sur iOS, on ne peut pas être Chrome au niveau TLS.**
- **WebView Android** : les 5 fetchers + `ReviewsPanel` font tous `loadUrl` → `onPageFinished` →
  `evaluateJavascript` + un pont `addJavascriptInterface`. `shouldInterceptRequest` sert à
  trois choses : le proxy Cronet (retirer `X-Requested-With`), le blocage de télémétrie et
  `BlockedHosts`. Sur iOS, la première n'a pas lieu d'être, les deux autres se font avec
  `WKContentRuleList`.
- **JS sandbox** : Rhino avec un kill switch de 2 s. JavaScriptCore n'a pas d'API publique de
  limite de temps, mais `JSContextGroupSetExecutionTimeLimit` existe (en-tête privé, symbole
  exporté). Hors App Store, on peut l'utiliser.
- **Artefacts non versionnés** : `core/libs/*.jar` (OsmAnd), l'AAR Cronet et l'AAR sherpa-onnx
  viennent de releases (`obf-runtime`, `cronet-runtime`, …). Un agent qui veut compiler `:core` ou
  `:app` doit les récupérer comme le fait `ci.yml`. `:core-common` n'en a pas besoin.
- **ROADMAP.md L560** : « iOS. Not started. `:core` is plain Kotlin and would move to Kotlin
  Multiplatform. MapLibre and sherpa-onnx have iOS builds. The interface would be rewritten. »

---

## 2. Écarts avec les plans précédents

| Sujet | Plan initial | v1 de ce fichier | v2 (ce fichier) | Pourquoi |
|---|---|---|---|---|
| Fichiers core purs | 107 | 116 | 106 par imports, ~60 vraiment | §1.1 |
| Stores SQLite | 3 | 10 | 3 SQLite + 7 SharedPreferences | §1.1 |
| `web/`, `car/` | 18, non compté | 19, 23 | 18, 20 | comptage |
| Structure KMP | `:core` converti en place | idem | **nouveau `:core-common`**, `:core` intact | AGP 9 (§1.3), merges upstream |
| Déplacement | `git mv` de tout `src/main` vers `androidMain` | idem | aucun déplacement de masse ; un fichier ne bouge que pour aller dans `commonMain` | chaque merge upstream hebdo devient un conflit sinon |
| HTTP | Ktor partout | Ktor | interface `VelaHttp` ; Android = le client OkHttp existant (Cronet inclus) ; iOS = `URLSession` en Swift | Android reste identique à l'octet ; pas de nouvelle dépendance |
| Code iOS des coutures | `actual` Kotlin/Native | idem | **Swift**, injecté dans le graphe Kotlin | délégués Apple plus simples en Swift ; Linux compile tout le Kotlin |
| Identité Google | inchangée | inchangée | **Safari** sur iOS | cohérence UA/TLS (§1.3) |
| Couche web | `WKURLSchemeHandler` à explorer | idem | inutile : pas de proxy à faire | §1.3 |
| Logique UI | Compose partagé | réécrite en Swift (non dit) | extraite dans `:ios-shared` | ne pas recopier 10 k lignes de Kotlin en Swift |
| Ordre | fondations → coutures → core → app | spike → idem | spike → squelette + 1re IPA → tranche « recherche » → élargissement | une IPA utile tôt ; les risques sortent tôt |
| Sync upstream | rebase hebdo | idem | **merge** hebdo de `origin/main` + `git rerere` | une branche longue rebasée chaque semaine re-résout les mêmes conflits |

---

## 3. Décisions

| # | Décision | Choix | Statut |
|---|---|---|---|
| D0 | Ordre | Spike réseau (W-1, fait : go) et spike WebView (W-2) avant toute migration | validé |
| D1 | Partage | Module **`:core-common`** (KMP `jvm` + `iosArm64` + `iosSimulatorArm64`). `:core` (Android library) en dépend. À vérifier en premier dans F-1 : Android consomme bien la variante `jvm`. Sinon, ajouter `androidTarget` via `com.android.kotlin.multiplatform.library` dans `:core-common` seulement. | **validé** (F-1 : `:core` résout `jvmRuntimeElements`) |
| D2 | UI iOS | **SwiftUI**, carte MapLibre iOS (SPM) | validé |
| D3 | DI | `:core-common` : construction manuelle (`CoreGraph`). Hilt reste dans `:core`/`:app` : un `@Module` fournit les classes déplacées. On enlève `@Inject` d'une classe au moment où elle passe en common, pas avant. | proposé |
| D4 | HTTP | Interface `VelaHttp` en common. Android : enveloppe du `OkHttpClient` partagé (le hook Cronet ne bouge pas). iOS : `URLSession` en Swift, cookies partagés avec `WKHTTPCookieStore`. | proposé |
| D5 | Stockage | `KeyValueStore` (Android : `SharedPreferences` existantes ; iOS : `UserDefaults` d'une suite dédiée). `SqlDb` (Android : le code existant ; iOS : `androidx.sqlite:sqlite-bundled` en `iosMain`). Fichiers : `PlatformFiles` (iOS : `Application Support`, exclu de la sauvegarde, et `Caches`). | proposé |
| D6 | JS | `JsEngine` : Rhino sur Android, JavaScriptCore sur iOS avec `JSContextGroupSetExecutionTimeLimit` (2 s). Test `while(true)` obligatoire sur les deux. | proposé |
| D7 | Routage hors ligne | Hors V1. `ObfRouteEngine` reste dans `:core`. iOS = OSRM, Valhalla, Google. | validé |
| D8 | CarPlay | Hors V1 (entitlement navigation à demander à Apple, incompatible avec le sideload gratuit). | validé |
| D9 | Distribution | IPA non signée en artefact CI. Compte Apple gratuit : resignature tous les 7 jours, 3 apps max. Compte payant : 1 an. Pas d'App Store. | validé |
| D10 | Upstream | Proposer upstream **seulement** l'extraction `:core-common` (neutre pour Android), en petites PR par paquet, après une Discussion. L'app iOS reste dans le fork. | proposé |
| D11 | Identité iOS | **Safari macOS** pour le HTTP (W-1 du 2026-10-24 : les trois identités passent, la forme mobile est plus légère). Les templates `pb` restent ceux de `calibration.json` upstream. L'identité iOS vient d'un **second fichier signé** du fork, `calibration-ios.json` (clé du fork, épinglée à côté de celle d'upstream), qui ne surcharge que `userAgent`, les en-têtes et les dials iOS. | proposé |
| D12 | Outillage iOS | Projet Xcode généré par **XcodeGen** (`iosApp/project.yml` versionné, `.xcodeproj` ignoré) : un agent Linux peut l'éditer. Framework Kotlin intégré par `embedAndSignAppleFrameworkForXcode`. Pont Swift : **SKIE** (Flow → `AsyncSequence`, sealed → enum), à vérifier contre Kotlin 2.4.20 ; repli KMP-NativeCoroutines. | proposé |
| D13 | CI macOS | `gelinant/ios-builder` sur GitHub Actions `macos-latest` (§4). Plus tard, éventuellement, un runner Forgejo sur un Mac. | en place |
| D14 | Carte 3D | **MapLibre d'abord** : bâtiments extrudés (la couche `building-3d` est déjà dans le style embarqué), inclinaison et relief ombré (DEM terrarium AWS + `hillshade`, comme Android). Le terrain déformé et l'atmosphère passent par un renderer custom greffé sur MapLibre, après la phase 8 (D16). | validé |
| D15 | Globe | **Deux étapes.** G-1 : spike sur la pré-release native `ios-v2026.10.19-globe` (construite avec `MLN_WITH_GLOBE`) produite par notre CI en xcframework. Sinon, repli : écran « Globe » séparé en MapLibre GL JS dans une WKWebView, en lecture seule. Mapbox et Cesium sont écartés (licence propriétaire, clé API). | validé : natif retenu par `GLOBE-SPIKE.md` |
| D16 | Terrain 3D après la phase 8 | Renderer custom Metal ajouté à MapLibre (voie a du spike `TERRAIN-SPIKE.md`) : terrain drapé, atmosphère, arbres en volume, mer et météo. Périmètre, ordre et effort dans `ROADMAP-3D.md`. Il démarre après la phase 8 et ne bloque aucun lot de parité. | validé (29 octobre) |
| D17 | Langage visuel | Google Maps comme langage d'interaction (carte plein écran, pilule de recherche, feuille par paliers, accent unique), sans reprendre assets, couleurs ni textes Google. Jetons et règles dans `DESIGN.md` et `DESIGN-AUDIT.md`. | validé (29 octobre) |
| D18 | Écrans transports | Langage Citymapper pour les transports : écran de trajet, cartes de segment, prochains départs, heure modifiable et guidance GO. Règles dans `TRANSIT-DESIGN.md`. | validé (29 octobre) |
| D19 | Globe intégré | Le globe natif de G-1 est adopté pour G-2, avec plafond de zoom arrière, fond hors globe, revalidation à chaque release et essai PMTiles. Le repli GL JS n'est plus le chemin prévu. | validé (29 octobre), livré par `9702956a` |
| D20 | Sources en lien seulement | Atlas Obscura et Gastro Obscura ne deviennent ni calques ni données stockées : une action ouvre leur site dans `SFSafariViewController`, sans lire, copier ni conserver un titre, un texte ou une photo. Le verdict et les conditions sont dans `BACKLOG-PHASE8.md` section 3.6. | validé (29 octobre), livré par `f0b42b73` |
| D21 | Widgets | X-4 livre deux widgets WidgetKit, parking et prochains départs, sur l'App Group `group.app.vela.ios`. Ils lisent un instantané local et ne promettent pas de temps réel sans push ; CarPlay reste hors V1. | validé (29 octobre), livré par `a5e6c942` |
| D22 | Renderer 3D natif différé | Le renderer Metal custom (terrain drapé, atmosphère, arbres, mer, météo) reste après la phase 8. M-1 garde le relief ombré natif et M-2 le terrain GL JS dans un écran séparé; aucun lot de parité ne dépend du renderer. | confirmé (30 octobre) |

### 3.1 Forme des coutures (D4 à D6)

Les interfaces sont en style callback, pour qu'une classe Swift puisse les implémenter sans
toucher aux coroutines. Le common les enveloppe en `suspend` avec `suspendCancellableCoroutine`.

```kotlin
// :core-common, commonMain, package app.vela.core.platform
interface VelaHttp {
    fun execute(request: HttpRequest, callback: (HttpResponse?, Throwable?) -> Unit): Cancellable
}
data class HttpRequest(val method: String, val url: String, val headers: List<Pair<String, String>>,
                       val body: ByteArray?, val tag: RequestTag) // tag : AgedSession, purpose…
```

Liste fermée : `VelaHttp`, `KeyValueStore`, `SqlDb`, `PlatformFiles`, `JsEngine`,
`SignatureVerifier` (ECDSA P-256 ; iOS : `SecKeyVerifySignature`), `Unzip`, `TextNormalizer`
(remplace `java.text.Normalizer`), `PlatformLocale`, `Log`, `Clock`, `LocationSource`,
`HeadingSource`, `SpeechSynth`, `UnicodeScripts` (`Character.UnicodeScript`, 68 usages), `Sha256`, `Haptics` (`XmlPull` est finalement un parseur pur dans `util/`). Chacune est décrite dans `SPEC.md`, section « Platform seams »,
dans le commit qui la crée.

Remplacements mécaniques sans couture : `Math.*` → `kotlin.math` (+ `toRadians` maison dans
`util/`), `synchronized` → `kotlinx.atomicfu.locks.synchronized` (moniteur JVM sur Android, donc
même comportement), `java.time` → `kotlinx-datetime`, `BigInteger(hex, 16)` → `toULong(16)`,
`String.format` → formateurs dans `util/Fmt.kt` testés contre la sortie JVM, `@Volatile` →
`kotlin.concurrent.Volatile`.

### 3.2 Modules après le portage

```
:core-common   KMP (jvm, iosArm64, iosSimulatorArm64). Modèles, parseurs Google, nav, i18n,
               calibration, stores sur coutures, offline pur. Aucune dépendance plateforme.
:core          Android library (inchangé de forme). Implémentations Android des coutures,
               Hilt, OsmAnd, Cronet hook, ce qui ne peut pas partir.
:app           Android (inchangé de forme).
:ios-shared    KMP (iosArm64, iosSimulatorArm64, jvm pour les tests). CoreGraph iOS, stores de
               présentation, exporte :core-common. Produit VelaCore.framework.
iosApp/        SwiftUI + implémentations Swift des coutures + MapLibre + WKWebView.
```

---

## 4. Environnement

- **Linux (agents)** : JDK 17, Android SDK (`source ~/opt/env.sh`). Compile et teste
  `:core-common:jvmTest`, `:ios-shared:jvmTest`, `:core`, `:app`. Compile aussi les klibs iOS
  (`compileKotlinIosSimulatorArm64`, par défaut en Kotlin 2.4.20). Le link, les tests simulateur et
  le Swift sont Mac seulement : `scripts/ios/ci-kotlin.sh` avec `-Pvela.iosOnly=true` (pas de SDK
  Android sur le Mac). Pour `:core`/`:app`, récupérer les jars et AAR comme `ci.yml`.
- **Mac (CI), en place : `github.com/gelinant/ios-builder`** (privé, accès SSH). Sa branche
  `main` ne contient que les workflows du builder, jamais les workflows d'upstream (sinon leurs
  `schedule` et `push` tourneraient). Le source y est poussé sur une branche `src/<nom>`.
  Un build se déclenche en poussant sur `main` du builder un fichier `requests/<job>` qui nomme
  la ref source. Le workflow écrit ses sorties (logs, rapport, IPA) sur la branche orpheline
  `results` avec le `GITHUB_TOKEN` : un agent les lit avec `git fetch`, sans API ni jeton.
  Budget : un repo privé en offre gratuite a ~200 minutes macOS réelles par mois (2 000 minutes
  facturées ×10). Ne pas lancer de build macOS pour rien ; tout ce qui se vérifie sous Linux se
  vérifie sous Linux. Repo public = minutes illimitées.
  Le runner Forgejo auto-hébergé reste l'option long terme si un Mac est disponible.
- **Contenu des jobs macOS** : Xcode récent, JDK 17. Workflow :
  `:ios-shared:linkDebugFrameworkIosSimulatorArm64`, `iosSimulatorArm64Test`, `xcodegen`,
  `xcodebuild build` (simulateur), puis sur `ios/main` et les tags : `xcodebuild archive
  CODE_SIGNING_ALLOWED=NO` → `Payload/Vela.app` → `Vela-<version>-unsigned.ipa` en artefact.
  Cache Gradle, `~/.konan`, DerivedData, SPM.
- **iPhone (humain)** : tout ce qui touche GPS, arrière-plan, audio, conduite. Chaque PR liste les
  tests à faire. « Ça marche dans le simulateur » ne vaut pas test.
- **Règles du repo** : `CLAUDE.md` s'applique. Docs dans le même commit. Pas de backend, pas de
  clé Google, pas d'attribution IA, pas de tiret cadratin, pas de coordonnée hors fixtures
  (Davis/Sacramento, San Francisco). Installer les hooks : `bash scripts/install-hooks.sh`.

---

## 5. Phases et lots

Tailles : **S** < 1 session, **M** 1 à 3, **L** > 3. Chaque lot : branche `ios/<lot>` depuis
`ios/main`, une PR.

> **État au 29 octobre 2026** : 58 lots mergés, 1 partiel (`T-2`) et 13 ouverts. La matrice donne
> 2 lignes ✅, 66 🟡, 76 ⚠️, 41 ❌ et 19 ➖ sur 204. Le détail, les voies de fichiers et les trois
> prochains lots sont dans [docs/ios/BACKLOG.md](docs/ios/BACKLOG.md), section « État au
> 29 octobre ».

### Phase 0 : faisabilité (humain + 1 agent)

| Lot | Taille | Contenu | Fini quand |
|---|---|---|---|
| **P0-1** Mac CI | S | `gelinant/ios-builder` : workflows `spike` et (plus tard) `ipa`, sortie sur la branche `results`. | Un job `macos` écrit son rapport sur `results`. |
| **W-1** Spike réseau (**fait : go**, `docs/ios/spike-scraping-ios.md` §7) | S | `swift tools/ios-spike.swift` via le builder. Attention : un runner GitHub sort par une IP de datacenter Azure, que Google traite plus durement qu'une IP résidentielle. Un succès y est un bon signe ; un échec n'est pas concluant et se rejoue depuis un vrai Mac ou iPhone sur IP résidentielle et mobile. Procédure et grille : `docs/ios/spike-scraping-ios.md`. | Ligne de décision remplie (identité retenue pour D11). |
| **W-2** Spike WKWebView | M | Mini app SwiftUI jetable (`tools/ios-spike-web/`) : WKWebView hors écran, UA Safari, charge une fiche lieu, injecte le script d'extraction de `WebReviewsFetcher` (copié tel quel, pont `VelaBridge` émulé par un `WKUserScript` qui renvoie vers `webkit.messageHandlers`), compte les avis reçus. Même chose pour `WebPopularTimesFetcher`. | Nombre d'avis et horaires obtenus, temps de chargement, comportement avec `.desktop` vs `.mobile`. |
| **W-3** Spike carte | S | Même app : MapLibre iOS via SPM, style OpenFreeMap Liberty, une couche GeoJSON de 2 000 points, un fichier `.pmtiles` local. Mesure du défilement (Instruments, 60/120 Hz). | Captures + chiffres. |

**Porte M0** (franchie : W-1 et W-2 go) : si W-1 ne passe avec aucune identité, on s'arrête. Si W-2 échoue, les avis complets
sortent de V1 (il reste les 5 à 20 de `listentitiesreviews`).

### Phase 1 : squelette et première IPA (séquentiel, 1 agent)

| Lot | Taille | Contenu | Fini quand |
|---|---|---|---|
| **F-1** `:core-common` | M | Module KMP vide + `settings.gradle.kts` + catalog (plugin multiplatform, atomicfu, kotlinx-datetime, serialization, coroutines). `:core` y ajoute `api(project(":core-common"))`. Déplacer **un seul** fichier sans dépendance pour prouver la chaîne (fait : `util/RoadNameShort.kt`). | `:core:testDebugUnitTest :app:assembleDebug` vert, `:core-common:jvmTest` vert, link iOS vert sur le Mac. |
| **F-2** Coutures de base | M | `platform/` : `Log`, `Clock`, `KeyValueStore`, `PlatformFiles`, `VelaHttp`, `TextNormalizer`, `PlatformLocale` + implémentations Android dans `:core` qui enveloppent l'existant + `CoreGraph`. Section « Platform seams » dans `SPEC.md`. | Rien ne change à l'exécution Android. |
| **F-3** Coquille iOS | M | `:ios-shared` (framework `VelaCore`), `iosApp/project.yml`, app SwiftUI avec une carte MapLibre plein écran, implémentations Swift de `Log`, `Clock`, `PlatformFiles`, `KeyValueStore`. `Info.plist` : `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`, `UIBackgroundModes` (`location`, `audio`), bundle id `app.vela.ios`. CI : IPA en artefact. | **M1 : une IPA installée sur un iPhone affiche la carte.** |

### Phase 2 : tranche verticale « recherche » (1 à 2 agents)

| Lot | Taille | Contenu | Fini quand |
|---|---|---|---|
| **V-1** Remontée minimale | L | La clôture V-1 de `docs/ios/CORE-MIGRATION.md` (22 fichiers : `model/`, `SearchParser`, `GoogleResponse`, `SearchPb`, `DirectionsPb`, `RequestShape`, `BrowserViewport`, `Jitter`, `Calibration`, `MapDataSource`, `VelaConfig`, `VelaLinks`…), avec ses remplacements mécaniques et deux coupures : `Calibration` ne dépend plus de `VelaPiper` (constante `DEFAULT_VOICE_ID`), `SearchParser` reçoit la langue en paramètre au lieu de `Locale.getDefault()`. Tests correspondants vers `commonTest` (conversion JUnit vers `kotlin.test` : message en dernier). | Tests verts sur JVM et simulateur. |
| **V-2** Recherche iOS | M | `VelaHttp` en Swift (`URLSession`, cookies pré-semés comme `InMemoryCookieJar`), identité D11 en dur pour l'instant, `GoogleSession` (warm-up) et la recherche en common, `SearchStore` dans `:ios-shared`, barre de recherche + liste + épingles. | **M2 : l'IPA cherche « coffee » et affiche les résultats sur la carte.** |

> **Référence de découpage : `docs/ios/CORE-MIGRATION.md`** (généré par `scripts/ios/core_deps.py`,
> régénérable). Il donne la classe de chaque fichier (56 PURE, 56 MECHANICAL, 53 SEAM, 7 STAYS),
> l'ordre de déplacement par vagues, les 2 cycles et la clôture exacte de V-1 (22 fichiers). En cas
> d'écart entre ce document et les tables ci-dessous, il fait foi. Avant de démarrer un lot :
> `python3 scripts/ios/core_deps.py --file <chemin>` pour chaque fichier visé.

### Phase 3 : remontée du core (parallèle, 4 à 6 agents, après V-1)

Règle : un fichier ne part en common que si tout ce qu'il importe y est déjà. Chaque lot commence
par le graphe d'imports de son périmètre et l'ordre de déplacement.

| Lot | Taille | Périmètre | Points d'attention |
|---|---|---|---|
| **C-1** Mécanique | M | Remplacements du §3.1 et de `CORE-MIGRATION.md` (Charsets, URLEncoder, TimeUnit, `Dispatchers.IO`, `Thread.sleep`, `NavStrings` sans `Locale`…) sur les fichiers encore dans `:core` hors clôture V-1, sans les déplacer. `@Synchronized` vers atomicfu obligatoire (il ne verrouille rien sur iOS). Ne pas toucher aux `"%.5f".format(x)` qui fabriquent des identifiants stockés. | Lot préalable aux autres, à découper par paquet. Aucun changement de sortie (`String.format` : tests d'égalité contre la JVM). |
| **C-2** Source Google | L | `GoogleMapsDataSource`, `GoogleSession`, `BrowserHeaders`, reste de `data/google/` et `parse/` | `BrowserHeaders` devient « fabrique d'en-têtes par identité ». Le tag `AgedSession` passe dans `HttpRequest.tag`. Aucune requête Android ne doit changer : test qui compare les en-têtes générés avant/après. |
| **C-3** Services ouverts | M | `ValhallaRouter`, `RouteGeometry` (OSRM), `PhotonGeocoder`, Nominatim, `Overpass*`, `Transitous`, `NdwBridgeOpenings`, `ShortLinks`, `FuelGbStore`, `PaintedRoads` | Purement HTTP + JSON. |
| **C-4** Config | M | `Calibration`, `CalibrationStore`, `JsSandbox` (→ `JsEngine`), `BundleSignature` (→ `SignatureVerifier`), `VelaLinks` | Test avec les vrais `calibration.json` et `.sig`. Ajout de l'overlay `calibration-ios.json` (D11) : côté iOS seulement. |
| **C-5** Nav | L | `nav/` (25 fichiers), `replay/`, `location/SpeedKalman`, `DemoTrace` ; `NavSession` derrière `LocationSource`/`HeadingSource` | Les tests de replay tournent sur `jvmTest` **et** `iosSimulatorArm64Test`. `StepAudit` reste la référence. |
| **C-6** Stores | M | 7 stores `SharedPreferences` → `KeyValueStore` ; 3 stores SQLite → `SqlDb` ; `PlaceCache`, `StreetViewCache`, `TransitLineCache`, `OfflineRoot` → `PlatformFiles` | Clés et schémas inchangés : une installation Android existante relit tout. |
| **C-7** Voix (texte) | M | `SpeechText`, `SpokenScript` (sans `android.icu`), `PiperCatalog`, `VoiceGuide` (logique) derrière `SpeechSynth` | La phrase dite doit être identique : tests de snapshot sur les 25 langues. |
| **C-8** Offline pur | L | Depuis `app/offline/` : `PmtilesReader`, `PmtilesCompact`, `PmtilesPatch`, `RegionCatalog`, `RegionPolys`, `PlacesArchiveSearch`, `OfflineRank` → `:core-common` | Touche `:app` : diff minimal, imports seulement. |

Sortie de phase : la liste de ce qui reste dans `:core`, chaque fichier avec sa raison.

### Phase 4 : fonctions iOS (parallèle, 4 à 6 agents)

> **Référence : `docs/ios/PRESENTATION-MAP.md`.** Un seul `MapSession` (un `MapState` partagé) dont
> les stores sont des facettes, pas des stores indépendants : 44 champs de `MapUiState` sont écrits
> par trois fonctions ou plus. Les stores rendent des clés de chaînes et des nombres, jamais du
> texte formaté. Constructeurs inertes, démarrage par `start()`. Ne jamais copier un `Route`.
> À chaque merge upstream : `python3 scripts/ios/vm_map.py --check` (dérive des fonctions portées).

Chaque lot ajoute un store dans `:ios-shared` (logique extraite de `MapViewModel`/`NavController`,
avec ses tests JVM) et les vues SwiftUI. Si une logique peut servir à Android, elle va dans
`:core-common`, mais `MapViewModel` n'est pas modifié dans le fork.

| Lot | Taille | Contenu | Dépend de |
|---|---|---|---|
| **I-1** Carte | L | Style, POI Vela (données du repo), clusters, tracé d'itinéraire, puck, caméra de nav. Porter les règles de `CLAUDE.md` « The map » et « Frame rate » qui s'appliquent à MapLibre iOS. | F-3, W-3 |
| **I-2** Recherche complète | M | Autocomplétion (`suggest`), catégories, Photon pour les numéros, récents | V-2, C-2, C-6 |
| **I-3** Fiche lieu (règles : `docs/ios/spike-webview-ios.md`) | L | Détails, horaires, affluence, photos (`hspqX`), avis : `HiddenWebView` en Swift (une classe de base, comme sur Android), scripts JS **déplacés** de `app/web` vers `:core-common` (`app.vela.core.web`) pour une seule source. `WKContentRuleList` pour `BlockedHosts` et la télémétrie. `SessionRotation`, `GoogleStanding`. | W-2, C-2 |
| **I-4** Itinéraires | L | Voiture, marche, vélo, transport (page Google en WKWebView + Transitous), choix d'itinéraire, `HybridRoute` | C-2, C-3, I-1 |
| **I-5** Navigation | L | `NavEngine` piloté par `CLLocationManager` (Swift) ; arrière-plan (`allowsBackgroundLocationUpdates`), `isIdleTimerDisabled`, `AVSpeechSynthesizer` avec `AVAudioSession` `.voicePrompt` + `.duckOthers`, recalcul, alertes radars/caméras. Live Activity en option. | C-5, C-7, I-4 |
| **I-6** Lieux enregistrés | M | Listes, favoris, raccourcis, parking, import Takeout, partage (`ShortLinks`) | C-6 |
| **I-7** Hors ligne | L | Catalogue de régions, téléchargement en arrière-plan (`URLSession` background), PMTiles servies à MapLibre (`pmtiles://file://…`), paquets de lieux, recherche hors ligne | C-8, I-1 |
| **I-8** Réglages et langues | M | Réglages V1 ; script `scripts/ios/strings_to_xcstrings.py` qui génère le String Catalog depuis les `values*/strings.xml` (25 dossiers), uniquement les clés utilisées par iOS | F-3 |

### Phase 4b : V1 stabilisée (3 à 5 agents + humain)

Référence détaillée : `docs/ios/PARITY.md`. Objectif : un remplacement quotidien crédible, avant la
parité exhaustive. Lots :

- **N-1** carte et recherche : ouverture des POI au toucher, suggestions pendant la frappe,
  catégories, fusion en ligne/hors ligne et déduplication.
- **P-1** fiche lieu complète : galerie et catégories, panneau de tous les avis, affluence et scrape
  de repli vérifiés sur device, avatars.
- **N-2** navigation durcie : alertes radars et limitations, trafic et détours, arrêts, reprise
  après interruption, Bluetooth, conduite réelle.
- **O-2** hors ligne : téléchargements `URLSession` en arrière-plan, reprise, deltas et petit zoom
  monde, noms de rues depuis les fonds locaux.
- **Q-1** qualité : matrice `FEATURES.md`, accessibilité, grands textes, paysage, mémoire, batterie,
  GPU de la page cachée, tests iPhone.

Sortie : toutes les fonctions V1 de `PARITY.md` sont ✅ ou ont une limite documentée et acceptée.

### Phase 5b : fonctions spécifiques iOS (2 à 4 agents)

Après la V1 stabilisée, dans cet ordre :

1. **X-1 Live Activity conduite et marche** (2 à 4 jours) : ActivityKit, Dynamic Island, prochaine
   manœuvre, distance et ETA. `NSSupportsLiveActivities` dans l'Info.plist. L'activité affiche
   l'état de `NavStore`, elle ne remplace pas la localisation en arrière-plan.
2. **X-2 App Intents et Spotlight** (3 à 5 jours) : itinéraire Maison/Travail, parking, recherche,
   lieux enregistrés et récents indexés.
3. **X-3 Live Activity transports** (4 à 7 jours) : ligne, direction, descente, heures et retard.
   Sans backend de push, pas de promesse de mise à jour minute par minute app tuée : les limites
   doivent être visibles dans l'interface et la doc.
4. **X-4 Widgets puis CarPlay** : widgets livrés, limités par leur timeline ; CarPlay nécessite
   l'entitlement navigation d'Apple et reste hors V1.

### Phase 6 : parité Android (long terme)

Par blocs de `FEATURES.md`, chacun avec sa preuve : couches de carte et alertes, Street View,
navigation avancée et trajets, hors ligne avancé et routage `.obf` (nouvelle implémentation iOS),
voix neurales et dictée, réglages/confidentialité/diagnostics, CarPlay. Cible 90 à 95 % avant de
traiter les derniers cas spécifiques. Voir `docs/ios/PARITY.md`.

### Phase 7 : carte 3D, relief et globe (fin de pipeline, après la parité)

Livrée au 30 octobre : M-1 (`c3292ec2`), M-2 (`77bba6cb`), G-1 (`ae82a2d9`) et G-2
(`9702956a`). Le tableau garde le périmètre du plan. Aucun de ces lots ne devait fragiliser la
carte actuelle : ils s'ajoutent derrière des interrupteurs ou un écran séparé.

| Lot | Taille | Contenu | Fini quand |
|---|---|---|---|
| **M-1** Vue 3D | M | `building-3d` déjà présente dans `liberty-roboto.json` (`fill-extrusion` sur `render_height`) : l'activer selon l'inclinaison, avec la lumière du style comme Android (`B3D_TILT_ON` 20°, fondu). Inclinaison plafonnée à 60°, interrupteur dans la feuille de couches. Pas de couche `sky` : MapLibre Native ne la rend pas. Relief ombré : source `raster-dem` terrarium AWS (`elevation-tiles-prod`, sans clé) + `MLNHillshadeStyleLayer`, insérée sous les routes, plafonnée à z16, désactivée par défaut, exclue du style hors ligne. | Bâtiments visibles en perspective à z16+, relief ombré activable, aucun URL distant en hors ligne, captures et mesure fps/chauffe sur iPhone |
| **M-2** Écran Relief | L | Si le relief ombré ne suffit pas : écran séparé en MapLibre GL JS (WKWebView) avec `setTerrain`, DEM plus fin, déplacement synchronisé avec la carte. Lecture seule ou avec les mêmes POI. | Relief déformé visible, gestes fluides, retour instantané à la carte native, hors ligne explicitement non couvert |
| **G-1** Spike globe | M | Construire `ios-v2026.10.19-globe` (ou le tag stable suivant) avec `MLN_WITH_GLOBE` en xcframework reproductible dans `scripts/ios/`, l'intégrer à un projet jetable, style Liberty avec `"projection": {"type": "globe"}`, zoom arrière depuis z3 vers la planète. Mesurer taille (+208 Kio annoncés), fps, gestes et limites de caméra. | Verdict documenté : natif retenu ou repli GL JS |
| **G-2** Globe intégré | L | Livré par `9702956a` : xcframework globe intégré à l'app, bascule Mercator/globe, pins et itinéraires sur le globe, PMTiles hors ligne vérifié. L'atmosphère n'est pas rendue par ce build ; elle reste une PR amont séparée. | Globe utilisable depuis la carte, retour Mercator sans perte d'état, tests simulateur et passe iPhone |

Limites à documenter d'avance : Terrain3D n'est pas dans MapLibre Native (prototype non mergé,
financement recherché), donc **pas de relief déformé dans la carte principale** ; les ombres portées
et l'occlusion par les montagnes ne sont pas au programme ; l'atmosphère du globe est une PR
séparée ; un globe natif est une pré-release, donc à revalider à chaque montée de version.

### Phase 8 : transports avancés, couches du monde et savoir ouvert (fond de pile)

Après M-1, M-2, G-1 et G-2. Chaque lot est indépendant et se coupe par un interrupteur ; aucun ne
doit dégrader la carte ni les transports actuels. Les sources commerciales ou à clé sont marquées,
et une source sans clé libre est toujours préférée. État au 30 octobre : A-1, A-2, A-3, G-3, W-1,
TIME-1, AO-1 et AO-2 sont livrés, A-4 est abandonné, T-2 est partiel (lignes, couleurs, retards,
courses et trafic livrés, zone atteignable et `via` à finir).

#### 8a. Transports : Transitous complet et présentation type Citymapper

| Lot | Taille | Contenu | Fini quand |
|---|---|---|---|
| **T-2** Transitous complet | L | Arrêts atteignables par `/api/v6/one-to-all` avec leur enveloppe, sans polygone officiel ; lignes et couleurs de toutes les lignes sur la carte ; courses en service avec leur tracé et leurs horaires, sans position GPS de véhicule, que Transitous n'expose pas ; retards par ligne avec couleur (vert/ambre/rouge) ; **alternatives à l'intérieur d'un trajet** calculées en rejouant `plan` avec un arrêt `via` ou un départ décalé ; heure modifiable partout (départ, arrivée, étape). | Arrêts atteignables affichés, lignes et retards réels quand le flux les donne, alternatives proposées avec leur heure, aucune donnée inventée |
| **T-3** Écran transports type Citymapper | L | Écran dédié par trajet : bandeau des prochaines départs, segments en cartes (marche, attente, ligne, correspondance), **heure de chaque segment modifiable** (partir plus tard, arriver à), horaires en direct et prévus distincts, alertes perturbations, bouton « laisser passer celui-ci », progression en direct, et un onglet « lignes à proximité ». Réutilise `TransitBoardStore`, `TransitSession` et `Transitous.plan`. | On peut changer l'heure d'un segment et voir les départs recalculés, en direct si le flux le permet |

#### 8z. Apres la phase 8 : renderer custom, atmosphere, arbres, mer, meteo

La 3D dans la carte principale se fera par un renderer custom ajoute a MapLibre, et non en
attendant une API terrain native. Perimetre, ordre et effort sont dans
[ROADMAP-3D.md](docs/ios/ROADMAP-3D.md), avec le verdict mesure du spike `docs/ios/TERRAIN-SPIKE.md`.
Ce chantier commence apres la phase 8, sans bloquer aucun lot de parite.

#### 8b. Couches du monde (calques de carte)

| Lot | Taille | Source | Notes |
|---|---|---|---|
| **A-1** Aérien (ADS-B) | M | OpenSky Network (compte gratuit, quotas) ou `adsb.lol` (libre) | Avions, cap, altitude, identification au toucher ; interruption si quota ; pas de flux « militaire » officiel. |
| **A-2** Maritime (AIS) | M | AISHub (échange), ou flux ouvert gouvernemental ; MarineTraffic est commercial et écarté | Navires, cap, vitesse, type ; zones d'alerte UKMTO en calque séparé (source publique, scraping prudent, horodaté). |
| **A-3** Énergie et réseau | M | Electricity Maps (clé API, gratuit en tiers) pour le mix carbone ; Cloudflare Radar (jeton, gratuit) pour la qualité Internet, les pannes et les attaques | Calques horodatés, jamais présentés comme temps réel s'ils sont en retard ; cache agressif. |
| **A-4** NOTAM | M | FAA NOTAM API (identifiants OAuth2 sur demande, non obtenus : lot abandonné le 2026-10-30) | Aucune couche n'est livrée : l'accès NMS n'est pas self-serve. La ligne de calque reste désactivée avec « FAA credentials required » et le champ Keychain générique. Une intégration autorisée devra fournir des textes et zones par aéroport ou FIR, sans promesse de couverture mondiale. |
| **G-3** Satellites | M | TLE Celestrak (libre) + propagation locale | Livré par `7c5c4cff` : positions et trajectoires sur le globe G-2, identification, prochain passage au-dessus de la position. |

#### 8c. Savoir ouvert

| Lot | Taille | Contenu |
|---|---|---|
| **W-1** Wikidata et Wikivoyage | L | Fiches enrichies depuis Wikidata (population, ouverture, site, identifiants) et extraits Wikivoyage par ville/région, avec attribution CC BY-SA et lien source. Aucune image non libre. Le panneau lieu gagne une section « En savoir plus » et la carte un calque d'articles Wikivoyage géolocalisés. |

#### Règles pour toute la phase 8

- Une couche payante ou à clé n'entre que si la clé est fournie par l'utilisateur dans les réglages, jamais dans le binaire, et jamais dans `calibration.json`.
- Chaque couche affiche sa source, son horodatage et son état (frais, en retard, indisponible).
- Tout ce qui touche au trafic aérien ou maritime reste informatif : pas de conseil de sécurité, pas de remplacement des NOTAM officiels.
- Les données personnelles ne sortent pas : aucune position utilisateur envoyée à ces services sans action explicite.

Le découpage complet de ces lots, avec leurs fichiers, leurs preuves et leurs vagues, est dans
[docs/ios/BACKLOG-PHASE8.md](docs/ios/BACKLOG-PHASE8.md).

### Phase 5 : stabilisation (1 à 2 agents + humain)

- **S-1 Parité** : `FEATURES.md` ligne par ligne, ✅ / ⚠️ / ❌ iOS, dans `docs/ios/PARITY.md`. Une
  issue par écart.
- **S-2 Docs** : section iOS dans `docs/BUILDING.md`, « Platform seams » et « iOS » dans `SPEC.md`,
  installation par sideload dans le README du fork.
- **S-3 Release** : la branche `dist` de `gelinant/ios-builder` porte la dernière IPA et son
  manifeste AltStore/SideStore (`apps.json`), publiés par `scripts/ios/publish-sidestore.sh` après
  un build vert. Procédure et lien d'ajout : `docs/ios/SIDESTORE.md`. Les versions de dev sont
  croissantes (`0.1.<UTC>`) pour que SideStore propose les mises à jour.

### Hors V1

CarPlay (`car/`), routage hors ligne (`.obf`), voix neurales Piper/Kokoro et dictée (sherpa-onnx
iOS existe, V2), Street View (pas de WebView : rendu maison de `streetview/`, V2), D-pad, updater
APK, papier peint.

---

## 6. Graphe et jalons

```
P0-1 ─┬─ W-1 ─┐
      ├─ W-2 ─┼─ porte M0
      └─ W-3 ─┘
                F-1 → F-2 → F-3 (M1 : carte)
                            │
                     V-1 → V-2 (M2 : recherche)
                       │
        C-1 → { C-2, C-3, C-4, C-5, C-6, C-7, C-8 }   (parallèle)
                       │
   I-1 ─┬─ I-2 (C-2, C-6)          I-8 (dès F-3)
        ├─ I-3 (W-2, C-2)          M3 : fiche lieu
        ├─ I-4 (C-2, C-3)          M4 : itinéraire
        │    └─ I-5 (C-5, C-7)     M5 : navigation guidée
        ├─ I-6 (C-6)
        └─ I-7 (C-8)               M6 : V1 → phase 5
```

---

## 7. Risques

| # | Risque | Effet | Parade |
|---|---|---|---|
| 1 | Google bloque ou bride le trafic Apple | Plus de produit | W-1 avant tout. Identité Safari. Overlay signé `calibration-ios.json` pour corriger sans release. |
| 2 | WKWebView n'obtient pas les avis complets ou l'affluence | Fiche lieu appauvrie | W-2. Repli : `listentitiesreviews` et `reviewFeed` en HTTP, affluence depuis la réponse de recherche. |
| 3 | Dérive du fork (upstream publie chaque semaine) | Conflits sans fin | `:core` intact, déplacements fichier par fichier, merge hebdo + `rerere`, extraction proposée upstream (D10). |
| 4 | Android consomme mal la variante `jvm` de `:core-common` | D1 tombe | Vérifié dans F-1 avant tout déplacement ; repli décrit en D1. |
| 5 | SKIE en retard sur Kotlin 2.4.20 | Pont Swift pénible | KMP-NativeCoroutines, ou API callback écrite à la main dans `:ios-shared`. |
| 6 | Perf MapLibre iOS avec les couches Vela | UX | W-3, puis mesures dans I-1. |
| 7 | Arrière-plan iOS (localisation, audio) tué pendant une nav | Guidage coupé | Tests de conduite listés dans I-5 ; `pausesLocationUpdatesAutomatically = false`, session audio active pendant la nav. |
| 8 | Signature gratuite de 7 jours | Utilisateurs perdus | Source AltStore/SideStore (rafraîchissement auto) ; documenter le compte payant. |

---

## 8. Règles de la flotte

1. Un lot = une branche `ios/<lot>` = une PR vers `ios/main`. Personne ne pousse sur `main`.
2. Ne toucher que les chemins de son lot. Un autre fichier doit changer : le dire dans la PR.
3. **Android ne bouge pas.** Avant la PR :
   ```
   ./gradlew :core-common:jvmTest :core:testDebugUnitTest :app:assembleDebug
   ./gradlew :ios-shared:jvmTest            # dès F-3
   ```
   et le job `ios` vert sur le Mac.
4. Un déplacement vers `commonMain` = un commit de `git mv` seul, puis les modifications.
5. Aucune logique nouvelle dans une implémentation Android de couture : elle enveloppe l'existant.
6. Une couture nouvelle ou modifiée est décrite dans `SPEC.md` dans le même commit.
7. La PR dit : fait, reste, tests iPhone à faire, risques découverts.

### Prompt type

```
Tu travailles sur le portage iOS de Vela (repo : ssh://git@git.alt144.net:2222/antoine/alt144maps.git,
branche de base ios/main). Lis en entier PORTAGE_IOS.md puis CLAUDE.md (Rules, Traps,
What Vela never does, Location hygiene).

Ton lot : <ID> : <titre>. Tu ne fais QUE ce lot. Branche : ios/<id>.
Périmètre : <chemins>.

1. Liste les fichiers du périmètre et, pour chacun, ce qui l'empêche d'aller en commonMain.
   Donne l'ordre de déplacement (des feuilles vers la racine).
2. Un commit de git mv seul, puis les commits de modifications, docs dans le même commit.
3. Avant la PR : ./gradlew :core-common:jvmTest :core:testDebugUnitTest :app:assembleDebug.
   Pousse, attends le job ios du runner macOS, lis ses logs en cas d'échec et corrige.
4. Zéro changement de comportement Android.
5. PR vers ios/main : fait / reste / tests iPhone / risques.
Un fichier hors périmètre doit changer : ne le touche pas, note-le dans la PR.
```

### Prompt coordinateur

```
Tu coordonnes le portage iOS décrit dans PORTAGE_IOS.md. Tu tiens le tableau d'avancement dans
l'issue « iOS port tracker ». Tu lances les lots dans l'ordre du §6, jamais un lot dont une
dépendance n'est pas mergée. Tu relis chaque PR (périmètre, Android inchangé, job ios vert) et tu
merges dans ios/main. Chaque semaine : git merge origin/main dans ios/main (rerere activé), CI,
résolution. Tu remontes à l'humain les décisions marquées « proposé » au §3 et les résultats des
spikes W-1, W-2, W-3.
```
