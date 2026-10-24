# Carte de migration de `:core` vers `:core-common` (lot C-0)

Ce document dit, fichier par fichier, ce qui empêche chaque fichier de `core/src/main/java` de
passer en `commonMain`, de quoi il dépend dans le module, et dans quel ordre on peut le déplacer.
Les sections marquées « généré » sont réécrites par le script ; le reste est écrit à la main.

```
python3 scripts/ios/core_deps.py                                # résumé court
python3 scripts/ios/core_deps.py --md docs/ios/CORE-MIGRATION.md # régénère les sections générées
python3 scripts/ios/core_deps.py --json /tmp/opencode/core.json  # graphe complet
python3 scripts/ios/core_deps.py --file nav/NavEngine.kt         # un fichier : décl., dép., bloqueurs
python3 scripts/ios/test_core_deps.py                            # tests du script
```

Mesures prises sur `ios/main` au commit `3292423f`. Python 3, bibliothèque standard seulement,
environ 8 s.

## Méthode

1. **Lexique.** Chaque `.kt` est lu par un petit lexeur Kotlin : commentaires (KDoc compris) et
   texte des chaînes effacés, expressions de gabarit (`$x`, `${...}`) gardées comme du code,
   chaînes brutes et caractères gérés. Les références KDoc `[android.Foo]` ne comptent donc pas.
2. **Déclarations de premier niveau.** Classes, interfaces, objets, typealias, fonctions et
   propriétés au niveau 0 d'accolades et de parenthèses, avec leur receveur (fonctions
   d'extension). Les déclarations `private` de premier niveau sont exclues de l'index : elles
   sont invisibles hors du fichier.
3. **Résolution des dépendances internes**, par trois chemins :
   - imports explicites (`import app.vela.core.data.google.at`), y compris alias et `*` ;
   - noms du même paquet, sans import. Un type compte s'il apparaît nu ; une fonction s'il est
     appelé (`nom(`, `nom {`, `::nom`) ; une extension aussi après un point (`x.at(`) ; une
     propriété s'il apparaît nu. Un nom redéclaré dans le fichier (membre, local, paramètre)
     masque celui du paquet ;
   - noms entièrement qualifiés dans le code, comme `app.vela.core.data.NoGoogle.enabled`
     (le plus long préfixe qui est un paquet connu, puis le nom qui suit).
4. **Bloqueurs.** Une liste de règles (expressions régulières sur le code sans commentaires ni
   chaînes), chacune avec sa classe et sa couture ou son remplacement : voir la section
   « Bloqueurs ». Cas particulier `Locale` : seulement des constantes (`Locale.ROOT`,
   `Locale.US`) donne MECHANICAL ; un `Locale` utilisé comme valeur ou `Locale.getDefault()`
   donne SEAM (`PlatformLocale`).
5. **Classe propre d'un fichier** = la pire classe de ses bloqueurs : PURE (aucun), MECHANICAL
   (remplacements du §3.1 du plan, et quelques autres de même nature), SEAM (une couture),
   STAYS (OsmAnd, Hilt `@Module`, et six fichiers qui sont l'implémentation Android d'une
   couture : `LocationProvider`, `HeadingProvider`, `MotionProvider`, `Haptics`,
   `GoogleTransport`, `CoreModule`).
6. **Composantes fortement connexes** (Tarjan) puis **vagues** sur le graphe condensé.
   - Vague A : seulement PURE et MECHANICAL, et tout le cône de dépendances aussi. Vague N = 1 +
     la vague maximale de ses dépendances. C'est l'ordre de déplacement après C-1 et avant toute
     couture.
   - Vague B : la même chose en admettant aussi les SEAM (coutures F-2 posées). Les STAYS, et ce
     qui en dépend, ne bougent jamais sans couper un fichier.
7. **Lots** : par règles de chemin (voir `LOT_RULES` dans le script), la clôture V-1 passant en
   premier. C-1 est transversal : il est donné par remplacement et par paquet.
8. **Tests** (`core/src/test/java`) : mêmes règles, résolus contre le main et les autres tests.
   Un test est prêt pour `commonTest` si sa classe propre est PURE ou MECHANICAL et si tous ses
   sujets sont en vague A. On compte aussi l'usage de JUnit.
9. **C-8** : les fichiers de `app/src/main/java/app/vela/offline` sont analysés à part, avec
   leurs dépendances vers `:core`.

## Résumé (généré)

<!-- BEGIN GENERATED: summary -->
| Classe | Fichiers | Lignes |
|---|---|---|
| PURE | 56 | 5 339 |
| MECHANICAL | 56 | 7 913 |
| SEAM | 53 | 17 377 |
| STAYS | 7 | 1 225 |
| **total** | 172 | 31 854 |

- Arêtes internes (fichier → fichier de `:core`) : **380**.
- Déplaçables sans couture, une fois C-1 fait (PURE ou MECHANICAL, et toutes les dépendances aussi) : **94** fichiers, en **5** vagues.
- PURE ou MECHANICAL mais bloqués par une dépendance SEAM ou STAYS : **18**.
- Déplaçables une fois les coutures F-2 posées (tout sauf STAYS et ce qui en dépend) : **162**, en **8** vagues.
- Composantes fortement connexes de plus d'un fichier (cycles) : **2** (3, 2 fichiers).
- Clôture V-1 : **22** fichiers.

| Paquet | Fichiers | Lignes | PURE | MECH. | SEAM | STAYS | déplaçables (A) |
|---|---|---|---|---|---|---|---|
| `(racine)` | 1 | 53 | 1 | 0 | 0 | 0 | 1 |
| `config` | 8 | 983 | 3 | 2 | 3 | 0 | 3 |
| `data` | 51 | 8558 | 7 | 15 | 28 | 1 | 21 |
| `data/google` | 23 | 5515 | 10 | 9 | 4 | 0 | 16 |
| `data/naming` | 5 | 1433 | 0 | 4 | 1 | 0 | 0 |
| `data/tiles` | 1 | 46 | 1 | 0 | 0 | 0 | 1 |
| `data/transit` | 3 | 916 | 1 | 0 | 2 | 0 | 1 |
| `di` | 1 | 127 | 0 | 0 | 0 | 1 | 0 |
| `diag` | 2 | 133 | 1 | 0 | 1 | 0 | 1 |
| `feedback` | 1 | 77 | 0 | 0 | 0 | 1 | 0 |
| `i18n` | 2 | 2593 | 0 | 1 | 1 | 0 | 1 |
| `location` | 8 | 918 | 2 | 2 | 1 | 3 | 3 |
| `model` | 12 | 1125 | 11 | 1 | 0 | 0 | 12 |
| `nav` | 25 | 4787 | 9 | 15 | 1 | 0 | 21 |
| `net` | 3 | 208 | 0 | 1 | 1 | 1 | 1 |
| `replay` | 3 | 685 | 1 | 1 | 1 | 0 | 0 |
| `search` | 4 | 718 | 3 | 0 | 1 | 0 | 2 |
| `util` | 12 | 1586 | 3 | 5 | 4 | 0 | 8 |
| `voice` | 7 | 1393 | 3 | 0 | 4 | 0 | 2 |
<!-- END GENERATED: summary -->

## Bloqueurs (généré)

« Seul bloqueur » : nombre de fichiers où cette règle est la seule trouvée.

<!-- BEGIN GENERATED: blockers -->
| Id | Détecte | Classe | Couture ou remplacement | Fichiers | Occurrences | seul bloqueur |
|---|---|---|---|---|---|---|
| `hilt-module` | @Module/@Provides Hilt | STAYS | Hilt | 1 | 5 | 0 |
| `osmand` | net.osmand (OsmAnd) | STAYS | OsmAnd | 1 | 13 | 0 |
| `android-context` | Context Android | SEAM | PlatformFiles/CoreGraph | 20 | 37 | 0 |
| `android-icu` | android.icu | SEAM | PlatformLocale/TextNormalizer | 1 | 1 | 0 |
| `android-location` | android.location | SEAM | LocationSource | 1 | 3 | 0 |
| `android-log` | android.util.Log | SEAM | Log | 4 | 36 | 0 |
| `android-other` | autre API android/androidx | SEAM | Android | 8 | 22 | 0 |
| `android-prefs` | SharedPreferences | SEAM | KeyValueStore | 11 | 17 | 0 |
| `android-sensors` | capteurs android.hardware | SEAM | HeadingSource | 3 | 12 | 0 |
| `android-speech` | TTS / audio Android | SEAM | SpeechSynth | 2 | 13 | 0 |
| `android-sqlite` | SQLite Android | SEAM | SqlDb | 3 | 30 | 0 |
| `crypto` | java.security / javax.crypto | SEAM | SignatureVerifier | 2 | 4 | 0 |
| `file` | java.io.File / java.nio.file | SEAM | PlatformFiles | 11 | 13 | 1 |
| `locale-seam` | Locale.getDefault / Locale(...) | SEAM | PlatformLocale | 5 | 41 | 0 |
| `net-conn` | java.net connexion | SEAM | VelaHttp | 1 | 3 | 0 |
| `normalizer` | java.text.Normalizer | SEAM | TextNormalizer | 4 | 9 | 2 |
| `okhttp` | okhttp3 | SEAM | VelaHttp | 21 | 44 | 0 |
| `platform-info` | System.getProperty / Runtime | SEAM | plateforme | 1 | 1 | 0 |
| `rhino` | Rhino | SEAM | JsEngine | 1 | 4 | 0 |
| `stream` | flux java.io | SEAM | PlatformFiles/VelaHttp (flux) | 12 | 26 | 0 |
| `threads` | Thread / Executor | SEAM | threads (hors liste) | 6 | 13 | 0 |
| `unicode` | Character.UnicodeScript | SEAM | TextNormalizer (scripts) | 5 | 68 | 0 |
| `xml` | parseur XML | SEAM | XML (hors liste) | 1 | 2 | 0 |
| `zip` | java.util.zip | SEAM | Unzip | 5 | 6 | 0 |
| `android-clock` | SystemClock | MECHANICAL | Clock | 3 | 24 | 0 |
| `atomic` | java.util.concurrent.atomic | MECHANICAL | atomicfu | 4 | 17 | 0 |
| `bigint` | BigInteger / BigDecimal | MECHANICAL | toULong(16) | 3 | 6 | 0 |
| `charset` | Charsets | MECHANICAL | encodeToByteArray / decodeToString | 6 | 7 | 0 |
| `concurrent-coll` | collections concurrentes | MECHANICAL | Map + verrou atomicfu | 5 | 13 | 1 |
| `dispatchers-io` | Dispatchers.IO | MECHANICAL | import kotlinx.coroutines.IO | 6 | 20 | 0 |
| `format` | String.format / .format( | MECHANICAL | util/Fmt | 15 | 28 | 2 |
| `hilt-inject` | @Inject / @Singleton | MECHANICAL | retirer @Inject (D3) | 22 | 109 | 1 |
| `io-exception` | IOException / ByteArrayOutputStream | MECHANICAL | kotlinx-io IOException ou exception maison | 3 | 4 | 0 |
| `java-util` | autre java.util (UUID, Base64, Random, TreeMap...) | MECHANICAL | kotlin.random / kotlin.uuid / Base64 / collections | 5 | 5 | 0 |
| `jvm-regex` | java.util.regex / RegexOption JVM | MECHANICAL | Regex Kotlin | 2 | 14 | 1 |
| `jvm-statics` | statiques JVM (Integer., Character., ...) | MECHANICAL | équivalent Kotlin | 9 | 14 | 0 |
| `locale-case` | Locale.ROOT / Locale.US | MECHANICAL | appels sans Locale | 8 | 12 | 0 |
| `lru-map` | LinkedHashMap accessOrder / removeEldestEntry | MECHANICAL | LRU maison | 1 | 4 | 0 |
| `math` | Math.* | MECHANICAL | kotlin.math | 45 | 179 | 22 |
| `net-codec` | URLEncoder / URI | MECHANICAL | util/UrlCodec | 8 | 18 | 0 |
| `org-json` | org.json | MECHANICAL | kotlinx.serialization (réécriture) | 2 | 13 | 0 |
| `reflection` | réflexion JVM | MECHANICAL | sans réflexion JVM | 8 | 14 | 0 |
| `synchronized` | synchronized | MECHANICAL | atomicfu synchronized | 10 | 58 | 0 |
| `systime` | System.currentTimeMillis / nanoTime | MECHANICAL | Clock | 10 | 33 | 0 |
| `time` | java.time / Calendar | MECHANICAL | kotlinx-datetime | 8 | 23 | 3 |
| `timeunit` | TimeUnit | MECHANICAL | kotlin.time.Duration | 9 | 24 | 0 |
| `volatile` | @Volatile | MECHANICAL | kotlin.concurrent.Volatile | 44 | 85 | 13 |
<!-- END GENERATED: blockers -->

## Lots (généré)

Colonnes : « Dép. » = fichiers de `:core` dont il dépend directement ; « Dépendants » = fichiers
qui dépendent de lui ; « Vague A/B » : voir la méthode ; dernière colonne : coutures du fichier,
ou les fichiers SEAM/STAYS de son cône qui le bloquent (« via »). `V-1 (model/util)` = le reste de
`model/` et `util/` que le plan range dans V-1 sans que la recherche en ait besoin. `RESTE` = ce
qui reste dans `:core`. `hors lot` = fichiers qu'aucun lot du plan ne cite.

<!-- BEGIN GENERATED: lots -->
#### V-1 (22 fichiers, 3037 lignes ; PURE 14, MECH. 6, SEAM 2, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `config/Notice.kt` | 23 | PURE | - | 0 | 2 | 1 | 1 |  |
| `config/VelaLinks.kt` | 140 | MECHANICAL | `volatile`×2 | 0 | 3 | 1 | 1 |  |
| `data/google/BrowserViewport.kt` | 46 | MECHANICAL | `math`×1, `volatile`×2 | 0 | 3 | 1 | 1 |  |
| `data/google/GoogleResponse.kt` | 59 | PURE | - | 0 | 10 | 1 | 1 |  |
| `model/Geo.kt` | 72 | MECHANICAL | `math`×17 | 0 | 73 | 1 | 1 |  |
| `model/StreetView.kt` | 70 | PURE | - | 0 | 4 | 1 | 1 |  |
| `nav/SpokenRoadNames.kt` | 25 | MECHANICAL | `volatile`×1 | 0 | 1 | 1 | 1 |  |
| `util/Jitter.kt` | 24 | MECHANICAL | `java-util`×1, `volatile`×1 | 0 | 3 | 1 | 1 |  |
| `VelaConfig.kt` | 53 | PURE | - | 1 | 11 | 2 | 2 |  |
| `data/google/RequestShape.kt` | 73 | MECHANICAL | `atomic`×4, `math`×1 | 1 | 3 | 2 | 2 |  |
| `model/Place.kt` | 235 | PURE | - | 2 | 31 | 2 | 2 |  |
| `model/PlaceList.kt` | 108 | PURE | - | 3 | 4 | 2 | 2 |  |
| `model/Route.kt` | 314 | PURE | - | 2 | 33 | 2 | 2 |  |
| `model/SavedPlace.kt` | 116 | PURE | - | 2 | 6 | 2 | 2 |  |
| `data/google/DirectionsPb.kt` | 174 | PURE | - | 4 | 2 | 3 | 3 |  |
| `data/google/SearchPb.kt` | 87 | PURE | - | 3 | 2 | 3 | 3 |  |
| `data/google/parse/PhotosParser.kt` | 113 | PURE | - | 1 | 2 | 3 | 3 |  |
| `data/google/parse/ReviewFeedParser.kt` | 69 | PURE | - | 1 | 2 | 3 | 3 |  |
| `data/MapDataSource.kt` | 170 | PURE | - | 6 | 8 | 4 | 4 |  |
| `voice/VelaPiper.kt` | 147 | SEAM | `android-context`×1, `android-prefs`×4, `file`×1, `volatile`×1 | 0 | 3 | - | 1 | PlatformFiles/CoreGraph / KeyValueStore / PlatformFiles |
| `config/Calibration.kt` | 349 | PURE | - | 5 | 6 | - | 4 | via VelaPiper |
| `data/google/parse/SearchParser.kt` | 570 | SEAM | `locale-seam`×1, `volatile`×2 | 5 | 2 | - | 5 | PlatformLocale |

#### V-1 (model/util) (16 fichiers, 1748 lignes ; PURE 9, MECH. 4, SEAM 3, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `model/ShortcutKind.kt` | 7 | PURE | - | 0 | 1 | 1 | 1 |  |
| `util/AddressQuery.kt` | 70 | PURE | - | 0 | 0 | 1 | 1 |  |
| `util/OpeningHours.kt` | 136 | MECHANICAL | `time`×2 | 0 | 0 | 1 | 1 |  |
| `util/OsmHours.kt` | 152 | PURE | - | 0 | 2 | 1 | 1 |  |
| `util/RoadNameShort.kt` | 64 | PURE | - | 0 | 0 | 1 | 1 |  |
| `util/ShapeMeasure.kt` | 34 | MECHANICAL | `math`×2 | 0 | 0 | 1 | 1 |  |
| `util/SunTimes.kt` | 93 | MECHANICAL | `math`×2 | 0 | 0 | 1 | 1 |  |
| `model/ParkedSpot.kt` | 13 | PURE | - | 1 | 1 | 2 | 2 |  |
| `model/SavedRoute.kt` | 40 | PURE | - | 1 | 2 | 2 | 2 |  |
| `model/Transit.kt` | 83 | PURE | - | 1 | 5 | 2 | 2 |  |
| `util/S2Cell.kt` | 82 | MECHANICAL | `jvm-statics`×1, `math`×2 | 1 | 1 | 2 | 2 |  |
| `model/PlaceArea.kt` | 31 | PURE | - | 1 | 0 | 3 | 3 |  |
| `model/StopDepartures.kt` | 36 | PURE | - | 1 | 2 | 3 | 3 |  |
| `util/NameScript.kt` | 93 | SEAM | `unicode`×29, `jvm-statics`×5 | 0 | 0 | - | 1 | TextNormalizer (scripts) |
| `util/PlaceNames.kt` | 659 | SEAM | `normalizer`×3, `unicode`×6, `jvm-statics`×1 | 0 | 2 | - | 1 | TextNormalizer / TextNormalizer (scripts) |
| `util/MvtLines.kt` | 155 | SEAM | `stream`×1, `zip`×1, `charset`×1, `jvm-statics`×2, `math`×2 | 1 | 0 | - | 2 | PlatformFiles/VelaHttp (flux) / Unzip |

#### C-2 (25 fichiers, 5457 lignes ; PURE 7, MECH. 14, SEAM 4, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `data/ClosingTime.kt` | 49 | PURE | - | 0 | 0 | 1 | 1 |  |
| `data/NoGoogle.kt` | 16 | MECHANICAL | `volatile`×1 | 0 | 1 | 1 | 1 |  |
| `data/OtherLocations.kt` | 11 | MECHANICAL | `volatile`×1 | 0 | 1 | 1 | 1 |  |
| `data/ReviewWords.kt` | 129 | PURE | - | 0 | 0 | 1 | 1 |  |
| `data/google/PbBuilder.kt` | 52 | PURE | - | 0 | 0 | 1 | 1 |  |
| `data/google/ReviewFeedDebug.kt` | 11 | MECHANICAL | `volatile`×1 | 0 | 1 | 1 | 1 |  |
| `net/GoogleUsage.kt` | 80 | MECHANICAL | `atomic`×5, `concurrent-coll`×5, `time`×1, `volatile`×1 | 0 | 2 | 1 | 1 |  |
| `data/google/PolylineCodec.kt` | 78 | MECHANICAL | `math`×4 | 1 | 7 | 2 | 2 |  |
| `data/google/StreetViewParser.kt` | 201 | MECHANICAL | `math`×11 | 2 | 1 | 2 | 2 |  |
| `data/CategoryFilter.kt` | 111 | MECHANICAL | `volatile`×1 | 1 | 1 | 3 | 3 |  |
| `data/MapLinkParser.kt` | 353 | MECHANICAL | `format`×1, `jvm-statics`×1, `locale-case`×1, `net-codec`×2 | 3 | 1 | 3 | 3 |  |
| `data/MyMapKml.kt` | 204 | MECHANICAL | `jvm-regex`×9 | 3 | 1 | 3 | 3 |  |
| `data/google/parse/EntityListParser.kt` | 60 | MECHANICAL | `format`×1 | 3 | 1 | 3 | 3 |  |
| `data/google/parse/ReviewsParser.kt` | 86 | PURE | - | 2 | 1 | 3 | 3 |  |
| `data/google/parse/ReviewsWebParser.kt` | 45 | PURE | - | 1 | 0 | 3 | 3 |  |
| `data/MockMapDataSource.kt` | 128 | MECHANICAL | `hilt-inject`×4, `math`×1 | 4 | 1 | 5 | 5 |  |
| `data/google/parse/StopDeparturesParser.kt` | 295 | MECHANICAL | `volatile`×1 | 5 | 0 | 5 | 5 |  |
| `data/google/parse/TransitParser.kt` | 434 | MECHANICAL | `time`×2 | 6 | 0 | 5 | 5 |  |
| `data/google/BrowserHeaders.kt` | 242 | SEAM | `okhttp`×1, `bigint`×1, `math`×2, `volatile`×1 | 0 | 4 | - | 1 | VelaHttp |
| `net/NetHealth.kt` | 52 | SEAM | `net-conn`×3, `okhttp`×2, `io-exception`×1, `systime`×4, `volatile`×3 | 0 | 1 | - | 1 | VelaHttp |
| `data/google/SuggestParser.kt` | 111 | MECHANICAL | `format`×2 | 4 | 1 | - | 5 | via VelaPiper |
| `data/google/parse/DirectionsParser.kt` | 284 | PURE | - | 5 | 1 | - | 5 | via VelaPiper |
| `data/google/GoogleSession.kt` | 55 | SEAM | `okhttp`×2, `dispatchers-io`×1, `hilt-inject`×4, `volatile`×1 | 2 | 1 | - | 6 | VelaHttp |
| `data/google/parse/PopularTimesParser.kt` | 84 | PURE | - | 4 | 1 | - | 6 | via SearchParser, VelaPiper |
| `data/google/GoogleMapsDataSource.kt` | 2286 | SEAM | `android-log`×21, `locale-seam`×2, `okhttp`×4, `atomic`×4, `bigint`×2, `concurrent-coll`×2, `dispatchers-io`×13, `format`×8, `hilt-inject`×4, `java-util`×1, `net-codec`×2, `reflection`×6, `systime`×12, `timeunit`×2, `volatile`×1 | 53 | 1 | - | - | Log / PlatformLocale / VelaHttp |

#### C-3 (19 fichiers, 5037 lignes ; PURE 3, MECH. 1, SEAM 15, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `data/OsmMaxspeed.kt` | 143 | MECHANICAL | `time`×2 | 0 | 0 | 1 | 1 |  |
| `data/tiles/MapStyle.kt` | 46 | PURE | - | 0 | 0 | 1 | 1 |  |
| `data/RouteEngine.kt` | 52 | PURE | - | 2 | 3 | 3 | 3 |  |
| `data/transit/TransitOrder.kt` | 21 | PURE | - | 1 | 0 | 3 | 3 |  |
| `data/ShortLinks.kt` | 70 | SEAM | `okhttp`×3, `net-codec`×3 | 0 | 1 | - | 1 | VelaHttp |
| `data/FuelGb.kt` | 305 | SEAM | `stream`×3, `zip`×1, `format`×2, `locale-case`×4, `math`×2, `time`×4 | 2 | 1 | - | 3 | PlatformFiles/VelaHttp (flux) / Unzip |
| `data/NdwBridgeOpenings.kt` | 153 | SEAM | `okhttp`×2, `stream`×1, `xml`×2, `zip`×1, `math`×1, `time`×1, `timeunit`×2, `volatile`×1 | 2 | 0 | - | 3 | VelaHttp / PlatformFiles/VelaHttp (flux) / XML (hors liste) / Unzip |
| `data/OverpassEndpoints.kt` | 60 | SEAM | `okhttp`×3, `net-codec`×2 | 1 | 5 | - | 3 | VelaHttp |
| `data/PhotonGeocoder.kt` | 112 | SEAM | `okhttp`×2, `math`×2, `net-codec`×2 | 3 | 1 | - | 3 | VelaHttp |
| `data/RouteBudget.kt` | 153 | SEAM | `okhttp`×1, `dispatchers-io`×2, `timeunit`×4 | 1 | 2 | - | 3 | VelaHttp |
| `data/FuelGbStore.kt` | 123 | SEAM | `crypto`×1, `file`×1, `okhttp`×2, `stream`×1, `charset`×1, `dispatchers-io`×1, `format`×1, `volatile`×2 | 3 | 0 | - | 4 | SignatureVerifier / PlatformFiles / VelaHttp / PlatformFiles/VelaHttp (flux) |
| `data/OverpassAlprCameras.kt` | 203 | SEAM | `okhttp`×1, `stream`×2, `math`×5, `timeunit`×3, `volatile`×1 | 3 | 0 | - | 4 | VelaHttp / PlatformFiles/VelaHttp (flux) |
| `data/OverpassPois.kt` | 186 | SEAM | `okhttp`×1, `stream`×4 | 5 | 0 | - | 4 | VelaHttp / PlatformFiles/VelaHttp (flux) |
| `data/OverpassSpeedCameras.kt` | 98 | SEAM | `okhttp`×1, `stream`×3, `format`×1, `locale-case`×1, `math`×1, `timeunit`×3, `volatile`×1 | 2 | 0 | - | 4 | VelaHttp / PlatformFiles/VelaHttp (flux) |
| `data/OverpassTrafficSignals.kt` | 146 | SEAM | `okhttp`×1, `stream`×4, `format`×1, `locale-case`×1, `math`×1 | 2 | 0 | - | 4 | VelaHttp / PlatformFiles/VelaHttp (flux) |
| `data/PaintedRoads.kt` | 440 | SEAM | `okhttp`×2, `stream`×3, `java-util`×1, `math`×8, `timeunit`×2 | 2 | 0 | - | 4 | VelaHttp / PlatformFiles/VelaHttp (flux) |
| `data/RouteGeometry.kt` | 1194 | SEAM | `okhttp`×2, `threads`×1, `math`×17, `reflection`×1 | 10 | 6 | - | 4 | VelaHttp / threads (hors liste) |
| `data/transit/Transitous.kt` | 784 | SEAM | `locale-seam`×2, `normalizer`×2, `okhttp`×2, `stream`×2, `threads`×2, `format`×1, `math`×8, `net-codec`×3, `org-json`×10, `systime`×1, `time`×8, `volatile`×1 | 7 | 1 | - | 4 | PlatformLocale / TextNormalizer / VelaHttp / PlatformFiles/VelaHttp (flux) / threads (hors liste) |
| `data/ValhallaRouter.kt` | 748 | SEAM | `okhttp`×4, `threads`×2, `reflection`×1, `timeunit`×4, `volatile`×3 | 7 | 1 | - | 5 | VelaHttp / threads (hors liste) |

#### C-4 (5 fichiers, 471 lignes ; PURE 1, MECH. 1, SEAM 3, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `config/PlaceJson.kt` | 81 | PURE | - | 2 | 1 | 3 | 3 |  |
| `config/BundleSignature.kt` | 26 | SEAM | `crypto`×3, `java-util`×1 | 0 | 1 | - | 1 | SignatureVerifier |
| `config/JsSandbox.kt` | 62 | SEAM | `rhino`×4, `reflection`×1, `synchronized`×1, `systime`×2 | 0 | 1 | - | 1 | JsEngine |
| `config/CalibrationStore.kt` | 263 | SEAM | `android-context`×2, `file`×1, `okhttp`×2, `charset`×2, `dispatchers-io`×1, `hilt-inject`×5, `net-codec`×2, `volatile`×3 | 6 | 4 | - | 5 | PlatformFiles/CoreGraph / PlatformFiles / VelaHttp |
| `config/JsTransforms.kt` | 39 | MECHANICAL | `hilt-inject`×4 | 4 | 1 | - | 6 | via BundleSignature, CalibrationStore, JsSandbox, BrowserHeaders (+1) |

#### C-5 (42 fichiers, 10116 lignes ; PURE 13, MECH. 24, SEAM 5, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `data/RoutingPrefs.kt` | 24 | MECHANICAL | `volatile`×5 | 0 | 2 | 1 | 1 |  |
| `i18n/DelayText.kt` | 18 | MECHANICAL | `volatile`×1 | 0 | 2 | 1 | 1 |  |
| `location/AlongRouteFilter.kt` | 108 | PURE | - | 0 | 0 | 1 | 1 |  |
| `location/FixRules.kt` | 27 | PURE | - | 0 | 0 | 1 | 1 |  |
| `location/SpeedKalman.kt` | 123 | MECHANICAL | `math`×1 | 0 | 0 | 1 | 1 |  |
| `nav/CameraAlerts.kt` | 104 | PURE | - | 0 | 1 | 1 | 1 |  |
| `nav/DetourEstimate.kt` | 30 | PURE | - | 0 | 0 | 1 | 1 |  |
| `nav/ExitLabel.kt` | 32 | PURE | - | 0 | 0 | 1 | 1 |  |
| `nav/SpeedingAlerts.kt` | 64 | PURE | - | 0 | 0 | 1 | 1 |  |
| `nav/CameraFacing.kt` | 81 | MECHANICAL | `math`×6 | 1 | 1 | 2 | 2 |  |
| `nav/Heading.kt` | 56 | MECHANICAL | `math`×4 | 1 | 1 | 2 | 2 |  |
| `nav/PassAlerts.kt` | 77 | MECHANICAL | `math`×1 | 1 | 0 | 2 | 2 |  |
| `nav/RouteProjection.kt` | 145 | MECHANICAL | `math`×5 | 1 | 15 | 2 | 2 |  |
| `data/RouteCorridor.kt` | 77 | MECHANICAL | `math`×1 | 2 | 0 | 3 | 3 |  |
| `nav/CameraDetour.kt` | 111 | MECHANICAL | `math`×8 | 3 | 1 | 3 | 3 |  |
| `nav/NavModels.kt` | 50 | PURE | - | 1 | 3 | 3 | 3 |  |
| `nav/RouteBar.kt` | 131 | PURE | - | 3 | 1 | 3 | 3 |  |
| `nav/RouteHeal.kt` | 38 | PURE | - | 1 | 1 | 3 | 3 |  |
| `nav/RouteRef.kt` | 211 | MECHANICAL | `volatile`×1 | 2 | 4 | 3 | 3 |  |
| `nav/RouteSmoothing.kt` | 235 | MECHANICAL | `java-util`×1, `math`×2 | 2 | 0 | 3 | 3 |  |
| `nav/RouteStops.kt` | 54 | MECHANICAL | `math`×4 | 3 | 0 | 3 | 3 |  |
| `nav/SavedRoutes.kt` | 133 | MECHANICAL | `math`×2 | 3 | 0 | 3 | 3 |  |
| `nav/SpokenDetail.kt` | 49 | MECHANICAL | `volatile`×1 | 1 | 1 | 3 | 3 |  |
| `nav/StepAudit.kt` | 103 | MECHANICAL | `math`×2 | 3 | 3 | 3 | 3 |  |
| `nav/TurnArrowGeometry.kt` | 163 | MECHANICAL | `math`×1 | 3 | 0 | 3 | 3 |  |
| `nav/RouteShields.kt` | 83 | PURE | - | 4 | 0 | 4 | 4 |  |
| `location/Stillness.kt` | 79 | SEAM | `android-context`×1, `android-sensors`×4, `reflection`×1, `synchronized`×4, `volatile`×1 | 0 | 0 | - | 1 | PlatformFiles/CoreGraph / HeadingSource |
| `data/naming/RoadNameTiles.kt` | 390 | SEAM | `stream`×1, `zip`×1, `charset`×1, `lru-map`×4, `math`×6, `synchronized`×9, `volatile`×2 | 1 | 4 | - | 2 | PlatformFiles/VelaHttp (flux) / Unzip |
| `data/naming/RoadCenter.kt` | 152 | MECHANICAL | `math`×7 | 2 | 1 | - | 3 | via RoadNameTiles |
| `i18n/NavStrings.kt` | 2575 | SEAM | `locale-seam`×33, `volatile`×1 | 2 | 6 | - | 3 | PlatformLocale |
| `data/OfflinePhrases.kt` | 41 | PURE | - | 2 | 1 | - | 4 | via NavStrings |
| `nav/NavEngine.kt` | 1118 | MECHANICAL | `math`×11, `volatile`×1 | 6 | 4 | - | 4 | via NavStrings |
| `data/naming/HybridRoute.kt` | 489 | MECHANICAL | `math`×1 | 5 | 2 | - | 5 | via RouteBudget, RouteGeometry, NavStrings |
| `data/naming/LineNamer.kt` | 328 | MECHANICAL | `math`×4, `volatile`×1 | 5 | 1 | - | 5 | via RouteBudget, RouteGeometry, RoadNameTiles, NavStrings |
| `nav/NavReplay.kt` | 187 | PURE | - | 4 | 1 | - | 5 | via NavStrings |
| `nav/ParkingLotTurn.kt` | 115 | MECHANICAL | `math`×1 | 5 | 2 | - | 5 | via RoadNameTiles, NavStrings |
| `data/naming/StretchNamer.kt` | 74 | MECHANICAL | `concurrent-coll`×2 | 2 | 1 | - | 6 | via RouteBudget, RouteGeometry, NavStrings |
| `replay/TripLog.kt` | 318 | PURE | - | 4 | 1 | - | 6 | via NavStrings |
| `replay/TripScrub.kt` | 302 | MECHANICAL | `math`×4 | 3 | 1 | - | 7 | via NavStrings |
| `replay/TripShareBatch.kt` | 65 | SEAM | `stream`×1, `zip`×2, `charset`×1 | 1 | 0 | - | 8 | PlatformFiles/VelaHttp (flux) / Unzip |
| `location/DemoTrace.kt` | 164 | MECHANICAL | `math`×10 | 5 | 0 | - | - | via DiagLog, NavStrings, LocationProvider, AtomicFiles |
| `nav/NavSession.kt` | 1392 | SEAM | `android-log`×2, `android-clock`×18, `atomic`×4, `dispatchers-io`×2, `format`×1, `hilt-inject`×4, `jvm-statics`×1, `locale-case`×1, `synchronized`×22, `volatile`×16 | 17 | 0 | - | - | Log |

#### C-6 (18 fichiers, 2329 lignes ; PURE 2, MECH. 2, SEAM 14, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `data/AmbientDiskCache.kt` | 71 | PURE | - | 2 | 0 | 3 | 3 |  |
| `data/PlaceImport.kt` | 158 | MECHANICAL | `format`×2, `jvm-regex`×5, `locale-case`×2 | 1 | 1 | 3 | 3 |  |
| `data/TakeoutCsv.kt` | 195 | MECHANICAL | `bigint`×3, `net-codec`×2 | 4 | 1 | 4 | 4 |  |
| `data/ImportResult.kt` | 63 | PURE | - | 1 | 2 | 5 | 5 |  |
| `data/OfflinePacks.kt` | 45 | SEAM | `android-sqlite`×6, `volatile`×1 | 0 | 2 | - | 1 | SqlDb |
| `data/OfflineRoot.kt` | 9 | SEAM | `file`×1, `volatile`×1 | 0 | 1 | - | 1 | PlatformFiles |
| `data/RecentSearchStore.kt` | 71 | SEAM | `android-context`×2, `android-prefs`×1, `hilt-inject`×5, `systime`×2 | 0 | 0 | - | 1 | PlatformFiles/CoreGraph / KeyValueStore |
| `data/StreetViewCache.kt` | 100 | SEAM | `file`×1 | 2 | 0 | - | 2 | PlatformFiles |
| `data/OfflineAddressStore.kt` | 540 | SEAM | `android-context`×2, `android-other`×1, `android-sqlite`×12, `concurrent-coll`×1, `format`×2, `hilt-inject`×5 | 3 | 1 | - | 3 | PlatformFiles/CoreGraph / Android / SqlDb |
| `data/OfflinePoiStore.kt` | 270 | SEAM | `android-context`×2, `android-other`×1, `android-sqlite`×12, `format`×1, `hilt-inject`×5, `locale-case`×1, `math`×3 | 5 | 1 | - | 3 | PlatformFiles/CoreGraph / Android / SqlDb |
| `data/ParkingStore.kt` | 83 | SEAM | `android-context`×2, `android-prefs`×1, `hilt-inject`×5 | 1 | 0 | - | 3 | PlatformFiles/CoreGraph / KeyValueStore |
| `data/PlaceCache.kt` | 88 | SEAM | `file`×1, `systime`×4 | 3 | 0 | - | 3 | PlatformFiles |
| `data/PlaceShortcutStore.kt` | 35 | SEAM | `android-context`×2, `android-prefs`×1, `hilt-inject`×5 | 2 | 0 | - | 3 | PlatformFiles/CoreGraph / KeyValueStore |
| `data/RecentPlaceStore.kt` | 73 | SEAM | `android-context`×2, `android-prefs`×1, `hilt-inject`×5, `systime`×2 | 1 | 0 | - | 3 | PlatformFiles/CoreGraph / KeyValueStore |
| `data/SavedRouteStore.kt` | 43 | SEAM | `android-context`×2, `android-prefs`×1, `hilt-inject`×5 | 1 | 0 | - | 3 | PlatformFiles/CoreGraph / KeyValueStore |
| `data/transit/TransitLineCache.kt` | 111 | SEAM | `file`×1, `synchronized`×3 | 2 | 0 | - | 5 | PlatformFiles |
| `data/PlaceListStore.kt` | 211 | SEAM | `android-context`×2, `android-prefs`×1, `hilt-inject`×5, `volatile`×1 | 5 | 0 | - | 6 | PlatformFiles/CoreGraph / KeyValueStore |
| `data/SavedPlaceStore.kt` | 163 | SEAM | `android-context`×2, `android-prefs`×1, `hilt-inject`×5 | 6 | 0 | - | 6 | PlatformFiles/CoreGraph / KeyValueStore |

#### C-7 (6 fichiers, 1246 lignes ; PURE 3, MECH. 0, SEAM 3, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `voice/NeuralSynth.kt` | 44 | PURE | - | 0 | 1 | 1 | 1 |  |
| `voice/SpeechText.kt` | 239 | PURE | - | 0 | 1 | 1 | 1 |  |
| `voice/SpeechLeadIn.kt` | 48 | SEAM | `android-context`×1, `android-other`×1, `android-speech`×3, `reflection`×1 | 0 | 1 | - | 1 | PlatformFiles/CoreGraph / Android / SpeechSynth |
| `voice/SpokenScript.kt` | 170 | SEAM | `android-icu`×1, `unicode`×29, `jvm-statics`×1, `synchronized`×3 | 0 | 1 | - | 1 | PlatformLocale/TextNormalizer / TextNormalizer (scripts) |
| `voice/PiperCatalog.kt` | 139 | PURE | - | 1 | 0 | - | 2 | via VelaPiper |
| `voice/VoiceGuide.kt` | 606 | SEAM | `android-context`×2, `android-log`×4, `android-other`×5, `android-speech`×10, `locale-seam`×3, `threads`×4, `unicode`×2, `android-clock`×3, `hilt-inject`×5, `jvm-statics`×1, `math`×1, `synchronized`×5, `volatile`×9 | 5 | 1 | - | 4 | PlatformFiles/CoreGraph / Log / Android / SpeechSynth / PlatformLocale / threads (hors liste) / TextNormalizer (scripts) |

#### C-8 (1 fichiers, 155 lignes ; PURE 0, MECH. 0, SEAM 1, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `data/OfflineRank.kt` | 155 | SEAM | `normalizer`×2 | 3 | 2 | - | 3 | TextNormalizer |

#### hors lot (10 fichiers, 1009 lignes ; PURE 4, MECH. 4, SEAM 2, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `data/ClockFormat.kt` | 30 | MECHANICAL | `format`×2, `locale-case`×1, `time`×3, `volatile`×1 | 0 | 3 | 1 | 1 |  |
| `data/LowDataMode.kt` | 13 | MECHANICAL | `volatile`×1 | 0 | 1 | 1 | 1 |  |
| `data/LowRamMode.kt` | 64 | MECHANICAL | `volatile`×1 | 0 | 1 | 1 | 1 |  |
| `diag/DiagEvent.kt` | 17 | PURE | - | 0 | 1 | 1 | 1 |  |
| `search/VoiceCommandExamples.kt` | 138 | PURE | - | 0 | 0 | 1 | 1 |  |
| `data/MapDeclutter.kt` | 51 | MECHANICAL | `math`×1 | 1 | 0 | 2 | 2 |  |
| `search/AreaNarrow.kt` | 25 | PURE | - | 1 | 0 | 3 | 3 |  |
| `search/QueryIntent.kt` | 530 | SEAM | `normalizer`×2 | 0 | 0 | - | 1 | TextNormalizer |
| `diag/DiagLog.kt` | 116 | SEAM | `android-context`×2, `android-prefs`×2, `file`×1, `hilt-inject`×5, `synchronized`×3, `systime`×1, `volatile`×2 | 2 | 3 | - | 2 | PlatformFiles/CoreGraph / KeyValueStore / PlatformFiles |
| `search/SearchKind.kt` | 25 | PURE | - | 1 | 0 | - | 4 | via OfflinePacks, OfflinePoiStore, OfflineRank |

#### RESTE (8 fichiers, 1249 lignes ; PURE 0, MECH. 0, SEAM 1, STAYS 7)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `util/AtomicFiles.kt` | 24 | SEAM | `file`×2, `charset`×1, `io-exception`×1 | 0 | 1 | - | 1 | PlatformFiles |
| `data/ObfRouteEngine.kt` | 528 | STAYS | `osmand`×13, `android-log`×9, `file`×2, `platform-info`×1, `threads`×2, `unicode`×2, `concurrent-coll`×3, `format`×2, `jvm-statics`×1, `math`×2, `org-json`×3, `reflection`×1, `synchronized`×5, `systime`×4, `timeunit`×1, `volatile`×2 | 6 | 1 | - | - | OsmAnd / Log / PlatformFiles / plateforme / threads (hors liste) / TextNormalizer (scripts) |
| `di/CoreModule.kt` | 127 | STAYS | `hilt-module`×5, `android-context`×2, `file`×1, `okhttp`×5, `hilt-inject`×9, `synchronized`×3, `timeunit`×3 | 9 | 0 | - | - | module Hilt |
| `feedback/Haptics.kt` | 77 | STAYS | `android-context`×2, `android-other`×3, `android-prefs`×1, `hilt-inject`×5 | 1 | 1 | - | - | Vibrator Android |
| `location/HeadingProvider.kt` | 76 | STAYS | `android-context`×2, `android-other`×3, `android-sensors`×4, `hilt-inject`×5, `math`×1 | 0 | 0 | - | - | implémentation Android de HeadingSource |
| `location/LocationProvider.kt` | 258 | STAYS | `android-context`×2, `android-location`×3, `android-other`×7, `android-prefs`×3, `threads`×2, `android-clock`×3, `hilt-inject`×5, `systime`×1, `volatile`×2 | 2 | 1 | - | - | implémentation Android de LocationSource |
| `location/MotionProvider.kt` | 83 | STAYS | `android-context`×2, `android-other`×1, `android-sensors`×4, `hilt-inject`×5 | 0 | 0 | - | - | capteurs Android (accéléromètre) |
| `net/GoogleTransport.kt` | 76 | STAYS | `okhttp`×1, `io-exception`×2, `reflection`×2, `volatile`×1 | 3 | 2 | - | - | hook Cronet (Interceptor OkHttp) |

#### C-1 (transversal : fichiers qui ont au moins un remplacement mécanique)

| Remplacement | Vers | Fichiers | Par paquet |
|---|---|---|---|
| `math` | kotlin.math | 43 | data 22, nav 12, util 4, location 2, model 1, replay 1, voice 1 |
| `volatile` | kotlin.concurrent.Volatile | 41 | data 25, nav 5, config 2, i18n 2, net 2, voice 2, diag 1, location 1, util 1 |
| `hilt-inject` | retirer @Inject (D3) | 17 | data 12, config 2, diag 1, nav 1, voice 1 |
| `format` | util/Fmt | 14 | data 13, nav 1 |
| `net-codec` | util/UrlCodec | 8 | data 7, config 1 |
| `synchronized` | atomicfu synchronized | 8 | data 2, voice 2, config 1, diag 1, location 1, nav 1 |
| `systime` | Clock | 8 | data 5, config 1, diag 1, net 1 |
| `time` | kotlinx-datetime | 8 | data 6, net 1, util 1 |
| `locale-case` | appels sans Locale | 8 | data 7, nav 1 |
| `jvm-statics` | équivalent Kotlin | 8 | util 4, voice 2, data 1, nav 1 |
| `timeunit` | kotlin.time.Duration | 7 | data 7 |
| `charset` | encodeToByteArray / decodeToString | 6 | data 2, util 2, config 1, replay 1 |
| `dispatchers-io` | import kotlinx.coroutines.IO | 6 | data 4, config 1, nav 1 |
| `reflection` | sans réflexion JVM | 6 | data 3, config 1, location 1, voice 1 |
| `java-util` | kotlin.random / kotlin.uuid / Base64 / collections | 5 | data 2, config 1, nav 1, util 1 |
| `concurrent-coll` | Map + verrou atomicfu | 4 | data 3, net 1 |
| `atomic` | atomicfu | 4 | data 2, nav 1, net 1 |
| `bigint` | toULong(16) | 3 | data 3 |
| `jvm-regex` | Regex Kotlin | 2 | data 2 |
| `android-clock` | Clock | 2 | nav 1, voice 1 |
| `io-exception` | kotlinx-io IOException ou exception maison | 2 | net 1, util 1 |
| `lru-map` | LRU maison | 1 | data 1 |
| `org-json` | kotlinx.serialization (réécriture) | 1 | data 1 |
<!-- END GENERATED: lots -->

## Vagues (généré)

<!-- BEGIN GENERATED: waves -->
Vague A : seulement PURE et MECHANICAL (après C-1, avant toute couture).

- **Vague 1** (40) : `config/Notice.kt`, `config/VelaLinks.kt`, `data/ClockFormat.kt`, `data/ClosingTime.kt`, `data/LowDataMode.kt`, `data/LowRamMode.kt`, `data/NoGoogle.kt`, `data/OsmMaxspeed.kt`, `data/OtherLocations.kt`, `data/ReviewWords.kt`, `data/RoutingPrefs.kt`, `data/google/BrowserViewport.kt`, `data/google/GoogleResponse.kt`, `data/google/PbBuilder.kt`, `data/google/ReviewFeedDebug.kt`, `data/tiles/MapStyle.kt`, `diag/DiagEvent.kt`, `i18n/DelayText.kt`, `location/AlongRouteFilter.kt`, `location/FixRules.kt`, `location/SpeedKalman.kt`, `model/Geo.kt`, `model/ShortcutKind.kt`, `model/StreetView.kt`, `nav/CameraAlerts.kt`, `nav/DetourEstimate.kt`, `nav/ExitLabel.kt`, `nav/SpeedingAlerts.kt`, `nav/SpokenRoadNames.kt`, `net/GoogleUsage.kt`, `search/VoiceCommandExamples.kt`, `util/AddressQuery.kt`, `util/Jitter.kt`, `util/OpeningHours.kt`, `util/OsmHours.kt`, `util/RoadNameShort.kt`, `util/ShapeMeasure.kt`, `util/SunTimes.kt`, `voice/NeuralSynth.kt`, `voice/SpeechText.kt`
- **Vague 2** (17) : `VelaConfig.kt`, `data/MapDeclutter.kt`, `data/google/PolylineCodec.kt`, `data/google/RequestShape.kt`, `data/google/StreetViewParser.kt`, `model/ParkedSpot.kt`, `model/Place.kt`, `model/PlaceList.kt`, `model/Route.kt`, `model/SavedPlace.kt`, `model/SavedRoute.kt`, `model/Transit.kt`, `nav/CameraFacing.kt`, `nav/Heading.kt`, `nav/PassAlerts.kt`, `nav/RouteProjection.kt`, `util/S2Cell.kt`
- **Vague 3** (30) : `config/PlaceJson.kt`, `data/AmbientDiskCache.kt`, `data/CategoryFilter.kt`, `data/MapLinkParser.kt`, `data/MyMapKml.kt`, `data/PlaceImport.kt`, `data/RouteCorridor.kt`, `data/RouteEngine.kt`, `data/google/DirectionsPb.kt`, `data/google/SearchPb.kt`, `data/google/parse/EntityListParser.kt`, `data/google/parse/PhotosParser.kt`, `data/google/parse/ReviewFeedParser.kt`, `data/google/parse/ReviewsParser.kt`, `data/google/parse/ReviewsWebParser.kt`, `data/transit/TransitOrder.kt`, `model/PlaceArea.kt`, `model/StopDepartures.kt`, `nav/CameraDetour.kt`, `nav/NavModels.kt`, `nav/RouteBar.kt`, `nav/RouteHeal.kt`, `nav/RouteRef.kt`, `nav/RouteSmoothing.kt`, `nav/RouteStops.kt`, `nav/SavedRoutes.kt`, `nav/SpokenDetail.kt`, `nav/StepAudit.kt`, `nav/TurnArrowGeometry.kt`, `search/AreaNarrow.kt`
- **Vague 4** (3) : `data/MapDataSource.kt`, `data/TakeoutCsv.kt`, `nav/RouteShields.kt`
- **Vague 5** (4) : `data/ImportResult.kt`, `data/MockMapDataSource.kt`, `data/google/parse/StopDeparturesParser.kt`, `data/google/parse/TransitParser.kt`

Vague B : en plus, les fichiers SEAM une fois leurs coutures posées (rien de STAYS). Seuls les fichiers qui ne sont pas déjà dans la vague A sont listés.

- **B1** (16) : `config/BundleSignature.kt`, `config/JsSandbox.kt`, `data/OfflinePacks.kt`, `data/OfflineRoot.kt`, `data/RecentSearchStore.kt`, `data/ShortLinks.kt`, `data/google/BrowserHeaders.kt`, `location/Stillness.kt`, `net/NetHealth.kt`, `search/QueryIntent.kt`, `util/AtomicFiles.kt`, `util/NameScript.kt`, `util/PlaceNames.kt`, `voice/SpeechLeadIn.kt`, `voice/SpokenScript.kt`, `voice/VelaPiper.kt`
- **B2** (5) : `data/StreetViewCache.kt`, `data/naming/RoadNameTiles.kt`, `diag/DiagLog.kt`, `util/MvtLines.kt`, `voice/PiperCatalog.kt`
- **B3** (15) : `data/FuelGb.kt`, `data/NdwBridgeOpenings.kt`, `data/OfflineAddressStore.kt`, `data/OfflinePoiStore.kt`, `data/OfflineRank.kt`, `data/OverpassEndpoints.kt`, `data/ParkingStore.kt`, `data/PhotonGeocoder.kt`, `data/PlaceCache.kt`, `data/PlaceShortcutStore.kt`, `data/RecentPlaceStore.kt`, `data/RouteBudget.kt`, `data/SavedRouteStore.kt`, `data/naming/RoadCenter.kt`, `i18n/NavStrings.kt`
- **B4** (13) : `config/Calibration.kt`, `data/FuelGbStore.kt`, `data/OfflinePhrases.kt`, `data/OverpassAlprCameras.kt`, `data/OverpassPois.kt`, `data/OverpassSpeedCameras.kt`, `data/OverpassTrafficSignals.kt`, `data/PaintedRoads.kt`, `data/RouteGeometry.kt`, `data/transit/Transitous.kt`, `nav/NavEngine.kt`, `search/SearchKind.kt`, `voice/VoiceGuide.kt`
- **B5** (10) : `config/CalibrationStore.kt`, `data/ValhallaRouter.kt`, `data/google/SuggestParser.kt`, `data/google/parse/DirectionsParser.kt`, `data/google/parse/SearchParser.kt`, `data/naming/HybridRoute.kt`, `data/naming/LineNamer.kt`, `data/transit/TransitLineCache.kt`, `nav/NavReplay.kt`, `nav/ParkingLotTurn.kt`
- **B6** (7) : `config/JsTransforms.kt`, `data/PlaceListStore.kt`, `data/SavedPlaceStore.kt`, `data/google/GoogleSession.kt`, `data/google/parse/PopularTimesParser.kt`, `data/naming/StretchNamer.kt`, `replay/TripLog.kt`
- **B7** (1) : `replay/TripScrub.kt`
- **B8** (1) : `replay/TripShareBatch.kt`

Jamais déplaçables sans couper un fichier (10) : STAYS, et ce qui en dépend : `data/ObfRouteEngine.kt`, `data/google/GoogleMapsDataSource.kt`, `di/CoreModule.kt`, `feedback/Haptics.kt`, `location/DemoTrace.kt`, `location/HeadingProvider.kt`, `location/LocationProvider.kt`, `location/MotionProvider.kt`, `nav/NavSession.kt`, `net/GoogleTransport.kt`
<!-- END GENERATED: waves -->

## Cycles (généré)

<!-- BEGIN GENERATED: cycles -->
- **3 fichiers** (PURE 3, MECH. 0, SEAM 0, STAYS 0) : `model/Place.kt`, `model/PlaceList.kt`, `model/SavedPlace.kt`
  - arêtes : Place → PlaceList (package) ; PlaceList → Place (package) ; PlaceList → SavedPlace (package) ; SavedPlace → Place (package)
- **2 fichiers** (PURE 0, MECH. 0, SEAM 2, STAYS 0) : `data/OfflinePoiStore.kt`, `data/OfflineRank.kt`
  - arêtes : OfflinePoiStore → OfflineRank (package) ; OfflineRank → OfflinePoiStore (package)
<!-- END GENERATED: cycles -->

Les deux cycles sont petits. `Place`/`PlaceList`/`SavedPlace` sont PURE : ils partent ensemble
en vague 2. `OfflinePoiStore`/`OfflineRank` est à cheval sur deux lots (C-6 et C-8) : il faut
qu'un seul agent les déplace, ou casser le cycle d'abord (voir les corrections).

## Clôture V-1 (généré)

<!-- BEGIN GENERATED: v1 -->
Racines : `data/google/parse/SearchParser.kt`, `data/google/GoogleResponse.kt`, `data/google/SearchPb.kt`, `data/google/RequestShape.kt`, `data/google/BrowserViewport.kt`, `util/Jitter.kt`, `config/Calibration.kt`.

Clôture transitive : **22 fichiers**, 3037 lignes.

Classes : PURE 14, MECHANICAL 6, SEAM 2, STAYS 0. Déplaçables en vague A : 19.

| Fichier | Lignes | Classe | Bloqueurs | Vague A | Tiré par |
|---|---|---|---|---|---|
| `config/Notice.kt` | 23 | PURE | - | 1 | Calibration |
| `config/VelaLinks.kt` | 140 | MECHANICAL | `volatile`×2 | 1 | VelaConfig |
| `data/google/BrowserViewport.kt` | 46 | MECHANICAL | `math`×1, `volatile`×2 | 1 | DirectionsPb, SearchPb |
| `data/google/GoogleResponse.kt` | 59 | PURE | - | 1 | SearchParser |
| `model/Geo.kt` | 72 | MECHANICAL | `math`×17 | 1 | MapDataSource, DirectionsPb, RequestShape, SearchPb, SearchParser (+4) |
| `model/StreetView.kt` | 70 | PURE | - | 1 | MapDataSource |
| `nav/SpokenRoadNames.kt` | 25 | MECHANICAL | `volatile`×1 | 1 | Route |
| `util/Jitter.kt` | 24 | MECHANICAL | `java-util`×1, `volatile`×1 | 1 |  |
| `VelaConfig.kt` | 53 | PURE | - | 2 | Calibration |
| `data/google/RequestShape.kt` | 73 | MECHANICAL | `atomic`×4, `math`×1 | 2 | DirectionsPb, SearchPb |
| `model/Place.kt` | 235 | PURE | - | 2 | MapDataSource, PhotosParser, ReviewFeedParser, SearchParser, PlaceList (+1) |
| `model/PlaceList.kt` | 108 | PURE | - | 2 | Place |
| `model/Route.kt` | 314 | PURE | - | 2 | MapDataSource, DirectionsPb |
| `model/SavedPlace.kt` | 116 | PURE | - | 2 | PlaceList |
| `data/google/DirectionsPb.kt` | 174 | PURE | - | 3 | Calibration |
| `data/google/SearchPb.kt` | 87 | PURE | - | 3 | Calibration |
| `data/google/parse/PhotosParser.kt` | 113 | PURE | - | 3 | MapDataSource |
| `data/google/parse/ReviewFeedParser.kt` | 69 | PURE | - | 3 | MapDataSource |
| `data/MapDataSource.kt` | 170 | PURE | - | 4 | SearchParser |
| `config/Calibration.kt` | 349 | PURE | - | - | SearchParser |
| `data/google/parse/SearchParser.kt` | 570 | SEAM | `locale-seam`×1, `volatile`×2 | - |  |
| `voice/VelaPiper.kt` | 147 | SEAM | `android-context`×1, `android-prefs`×4, `file`×1, `volatile`×1 | - | Calibration |

Bloqueurs cumulés de la clôture : `math`×19, `volatile`×9, `atomic`×4, `android-prefs`×4, `java-util`×1, `locale-seam`×1, `android-context`×1, `file`×1.

V-1 tel qu'écrit dans le plan (ajoute tout `model/` et `util/` sauf `AtomicFiles`) : **38 fichiers**, soit 16 de plus : `model/ParkedSpot.kt`, `model/PlaceArea.kt`, `model/SavedRoute.kt`, `model/ShortcutKind.kt`, `model/StopDepartures.kt`, `model/Transit.kt`, `util/AddressQuery.kt`, `util/MvtLines.kt`, `util/NameScript.kt`, `util/OpeningHours.kt`, `util/OsmHours.kt`, `util/PlaceNames.kt`, `util/RoadNameShort.kt`, `util/S2Cell.kt`, `util/ShapeMeasure.kt`, `util/SunTimes.kt`.
<!-- END GENERATED: v1 -->

Lecture : 20 des 22 fichiers sont PURE ou MECHANICAL. Deux arêtes seulement empêchent la clôture
de partir telle quelle :

- `config/Calibration.kt` → `voice/VelaPiper.kt`, pour une seule constante
  (`DEFAULT_VOICE_ID = app.vela.core.voice.VelaPiper.DEFAULT_VOICE_ID`). `VelaPiper` touche
  `Context`, `SharedPreferences` et `File`. Coupure : inverser la constante (la définir dans
  `Calibration` ou `VelaConfig`, `VelaPiper` la relit).
- `data/google/parse/SearchParser.kt` : un paramètre par défaut
  `lang = java.util.Locale.getDefault().language.lowercase()`. Coupure : `PlatformLocale` (F-2)
  ou faire passer la langue par l'appelant (`GoogleMapsDataSource` la calcule déjà).

Avec ces deux coupures, les 21 fichiers (sans `VelaPiper`) partent en 5 vagues. À noter que la
clôture tire `data/MapDataSource.kt` (et derrière lui `Route`, `StreetView`, `PhotosParser`,
`ReviewFeedParser`) uniquement parce que `CalibrationNeededException` y est déclarée. Sortir
l'exception dans son propre fichier ramène V-1 à 17 fichiers ; ce n'est pas nécessaire
puisque ces fichiers sont tous PURE.

## Points de coupe (généré)

<!-- BEGIN GENERATED: cuts -->
Fichiers SEAM ou STAYS qui bloquent des fichiers PURE ou MECHANICAL (par leur cône de dépendances). « Seul » = le fichier est la seule racine bloquante : le couper suffit.

| Racine | Classe | Couture | Fichiers bloqués | Seul | Symboles utilisés par les dépendants |
|---|---|---|---|---|---|
| `i18n/NavStrings.kt` | SEAM | PlatformLocale | 10 | 5 | `NavStringsRegistry` |
| `voice/VelaPiper.kt` | SEAM | PlatformFiles/CoreGraph, KeyValueStore, PlatformFiles | 6 | 4 | `VelaPiper` |
| `data/RouteBudget.kt` | SEAM | VelaHttp | 3 | 0 | `RerouteFallback`, `RouteBudget`, `abandonableAsync` |
| `data/RouteGeometry.kt` | SEAM | VelaHttp, threads (hors liste) | 3 | 0 | `RouteGeometry` |
| `data/naming/RoadNameTiles.kt` | SEAM | PlatformFiles/VelaHttp (flux), Unzip | 3 | 1 | `NamedLine`, `RoadNameTiles` |
| `config/BundleSignature.kt` | SEAM | SignatureVerifier | 1 | 0 | `BundleSignature` |
| `config/CalibrationStore.kt` | SEAM | PlatformFiles/CoreGraph, PlatformFiles, VelaHttp | 1 | 0 | `CalibrationStore` |
| `config/JsSandbox.kt` | SEAM | JsEngine | 1 | 0 | `JsSandbox` |
| `data/OfflinePacks.kt` | SEAM | SqlDb | 1 | 0 | `OfflinePacks` |
| `data/OfflinePoiStore.kt` | SEAM | PlatformFiles/CoreGraph, Android, SqlDb | 1 | 0 | `OfflinePoiStore` |
| `data/OfflineRank.kt` | SEAM | TextNormalizer | 1 | 0 | `OfflineRank` |
| `data/google/BrowserHeaders.kt` | SEAM | VelaHttp | 1 | 0 | `BrowserHeaders` |
| `data/google/parse/SearchParser.kt` | SEAM | PlatformLocale | 1 | 0 | `SearchParser` |
| `diag/DiagLog.kt` | SEAM | PlatformFiles/CoreGraph, KeyValueStore, PlatformFiles | 1 | 0 | `DiagLog` |
| `location/LocationProvider.kt` | STAYS | PlatformFiles/CoreGraph, LocationSource, Android, KeyValueStore, threads (hors liste) | 1 | 0 | `ReplayFix` |
| `util/AtomicFiles.kt` | SEAM | PlatformFiles | 1 | 0 | `AtomicFiles` |

Arêtes vers un fichier STAYS (à couper par une couture ou en déplaçant le symbole) :

- `data/google/GoogleMapsDataSource.kt` → `net/GoogleTransport.kt` : `AgedSession`
- `location/DemoTrace.kt` → `location/LocationProvider.kt` : `ReplayFix`
- `nav/NavSession.kt` → `feedback/Haptics.kt` : `Haptics`
<!-- END GENERATED: cuts -->

## Les 15 fichiers les plus dépendus (généré)

<!-- BEGIN GENERATED: top -->
| Fichier | Dépendants directs | Dépendants transitifs | Classe | Vague A | Bloqueurs |
|---|---|---|---|---|---|
| `model/Geo.kt` | 73 | 109 | MECHANICAL | 1 | `math`×17 |
| `model/Route.kt` | 33 | 51 | PURE | 2 | - |
| `model/Place.kt` | 31 | 42 | PURE | 2 | - |
| `nav/RouteProjection.kt` | 15 | 23 | MECHANICAL | 2 | `math`×5 |
| `VelaConfig.kt` | 11 | 29 | PURE | 2 | - |
| `data/google/GoogleResponse.kt` | 10 | 11 | PURE | 1 | - |
| `data/MapDataSource.kt` | 8 | 9 | PURE | 4 | - |
| `data/google/PolylineCodec.kt` | 7 | 14 | MECHANICAL | 2 | `math`×4 |
| `config/Calibration.kt` | 6 | 10 | PURE | - | - |
| `data/RouteGeometry.kt` | 6 | 8 | SEAM | - | `okhttp`×2, `threads`×1, `math`×17, `reflection`×1 |
| `i18n/NavStrings.kt` | 6 | 18 | SEAM | - | `locale-seam`×33, `volatile`×1 |
| `model/SavedPlace.kt` | 6 | 42 | PURE | 2 | - |
| `data/OverpassEndpoints.kt` | 5 | 5 | SEAM | - | `okhttp`×3, `net-codec`×2 |
| `model/Transit.kt` | 5 | 6 | PURE | 2 | - |
| `config/CalibrationStore.kt` | 4 | 5 | SEAM | - | `android-context`×2, `file`×1, `okhttp`×2, `charset`×2, `dispatchers-io`×1, `hilt-inject`×5, `net-codec`×2, `volatile`×3 |
<!-- END GENERATED: top -->

## Tests (généré)

`assert(message, ...)` compte les appels JUnit dont le message vient en premier
(`assertEquals("msg", attendu, réel)`, `assertTrue("msg", cond)`). `kotlin.test` met le message en
dernier : ces appels sont à réordonner, et quand les trois arguments sont des `String`, une
conversion naïve compile et teste autre chose.

<!-- BEGIN GENERATED: tests -->
169 fichiers de test, 16971 lignes.

Classe propre des tests (mêmes règles que le main) : PURE 104, MECHANICAL 34, SEAM 30, STAYS 1.

| Statut | Tests |
|---|---|
| bloqué par le test lui-même | 31 |
| bloqué par ses sujets | 78 |
| commonTest (après C-1) | 60 |

Usage du framework de test :

| Motif | Fichiers | Occurrences |
|---|---|---|
| `org.junit` | 169 | 610 |
| `@Test` | 169 | 1244 |
| `assert(message, ...)` | 79 | 432 |
| `Assume` | 12 | 41 |
| `ressources` | 10 | 12 |
| `@Before/@After` | 9 | 9 |
| `@Rule` | 2 | 2 |
| `@Test(expected)` | 1 | 1 |

Bloqueurs dans les tests eux-mêmes : `math` 28 fichiers, `file` 22 fichiers, `platform-info` 13 fichiers, `systime` 10 fichiers, `okhttp` 9 fichiers, `format` 9 fichiers, `time` 7 fichiers, `threads` 5 fichiers, `timeunit` 5 fichiers, `net-codec` 4 fichiers, `locale-seam` 4 fichiers, `io-exception` 3 fichiers, `jvm-statics` 3 fichiers, `java-util` 3 fichiers, `charset` 2 fichiers, `stream` 2 fichiers, `zip` 2 fichiers, `synchronized` 2 fichiers, `reflection` 2 fichiers, `crypto` 1 fichiers, `unicode` 1 fichiers, `osmand` 1 fichiers, `volatile` 1 fichiers, `locale-case` 1 fichiers.

Tests prêts pour `commonTest` dès que leurs sujets ont bougé (60), par vague du sujet le plus tardif :

- après la vague 1 (22) : `AlongRouteFilterTest.kt`, `MapStyleTest.kt`, `OpeningHoursTest.kt`, `OsmHoursTest.kt`, `SpeedKalmanNoiseTest.kt`, `SpeedKalmanTest.kt`, `data/ClockFormatTest.kt`, `data/ClosingTimeTest.kt`, `data/LowRamModeTest.kt`, `data/OsmMaxspeedTest.kt`, `data/ReviewWordsTest.kt`, `location/FixRulesTest.kt`, `nav/CameraAlertsTest.kt`, `nav/DetourEstimateTest.kt`, `nav/ExitLabelTest.kt`, `nav/SpeedingAlertsTest.kt`, `net/GoogleUsageTest.kt`, `util/AddressQueryTest.kt`, `util/JitterTest.kt`, `util/RoadNameShortTest.kt`, `util/SunTimesTest.kt`, `voice/SpeechTextTest.kt`
- après la vague 2 (11) : `HeadingTest.kt`, `SavedPlacePointTest.kt`, `data/MapDeclutterTest.kt`, `data/google/PolylinePrecisionTest.kt`, `model/FullAddressTest.kt`, `model/SavedPlaceStreetTest.kt`, `nav/CameraFacingTest.kt`, `nav/PassAlertsTest.kt`, `nav/RouteProjectionBearingTest.kt`, `nav/RouteProjectionTest.kt`, `util/S2CellTest.kt`
- après la vague 3 (21) : `CameraDetourTest.kt`, `DirectionsPbAvoidTest.kt`, `DirectionsPbWaypointsTest.kt`, `EntityListParserTest.kt`, `MapLinkDirectionsTest.kt`, `MapLinkParserTest.kt`, `PlaceAreaTest.kt`, `ReviewsPhotoTest.kt`, `RouteStopsTest.kt`, `SavedRoutesTest.kt`, `data/CategoryFilterTest.kt`, `data/MyMapKmlTest.kt`, `data/PlaceImportTest.kt`, `data/RouteCorridorAheadTest.kt`, `data/google/parse/ReviewFeedParserTest.kt`, `data/transit/TransitOrderTest.kt`, `nav/RoadLabelTest.kt`, `nav/RouteBarTest.kt`, `nav/StepAuditTest.kt`, `nav/TurnArrowGeometryTest.kt`, `search/AreaNarrowTest.kt`
- après la vague 4 (2) : `data/TakeoutCsvTest.kt`, `nav/RouteShieldsTest.kt`
- après la vague 5 (4) : `data/ImportFormatsTest.kt`, `data/TransitAlternativesTest.kt`, `data/google/parse/StopDeparturesParserTest.kt`, `data/google/parse/TransitSubwayTest.kt`

Tests bloqués par leur propre code (31) :

| Test | Classe | Bloqueurs |
|---|---|---|
| `HoursProbeTest.kt` | SEAM | `file`×1, `okhttp`×2, `platform-info`×4, `net-codec`×3 |
| `PlaceCacheTest.kt` | SEAM | `file`×1 |
| `SearchSnapTest.kt` | SEAM | `file`×2 |
| `ShortLinksTest.kt` | SEAM | `okhttp`×1, `threads`×2, `net-codec`×1 |
| `SpokenRoadNamesTest.kt` | SEAM | `locale-seam`×1 |
| `StreetViewCacheTest.kt` | SEAM | `file`×1 |
| `VelaLogicTest.kt` | SEAM | `file`×2, `okhttp`×2, `platform-info`×4, `format`×1, `math`×16 |
| `data/FuelGbTest.kt` | SEAM | `crypto`×1, `file`×1, `okhttp`×5, `stream`×1, `zip`×1, `format`×1, `io-exception`×1, `time`×1 |
| `data/ObfCellsProbeTest.kt` | SEAM | `file`×1, `platform-info`×1, `format`×2, `systime`×2 |
| `data/ObfHhProbeTest.kt` | SEAM | `file`×1, `platform-info`×1, `format`×2, `systime`×4 |
| `data/ObfOutsideDataProbeTest.kt` | SEAM | `file`×1, `platform-info`×1, `format`×1, `systime`×2 |
| `data/ObfRoadNamesProbeTest.kt` | SEAM | `file`×1, `platform-info`×1, `unicode`×4, `jvm-statics`×1 |
| `data/ObfRouteEngineTest.kt` | STAYS | `osmand`×1 |
| `data/ObfSpeedLimitProbeTest.kt` | SEAM | `file`×1, `platform-info`×1 |
| `data/ObfStopProbeTest.kt` | SEAM | `file`×1, `platform-info`×1, `systime`×4 |
| `data/PaintedRoadsBakeTest.kt` | SEAM | `file`×1, `platform-info`×2, `format`×5, `systime`×2 |
| `data/RerouteFallbackTest.kt` | SEAM | `threads`×4, `systime`×6, `timeunit`×2 |
| `data/google/BrowserHeadersTest.kt` | SEAM | `okhttp`×1 |
| `data/google/GoogleHealthProbeTest.kt` | SEAM | `file`×1, `okhttp`×7, `platform-info`×1, `threads`×3, `format`×4, `net-codec`×2, `reflection`×1, `synchronized`×2, `timeunit`×2 |
| `data/google/ReviewFeedProbeTest.kt` | SEAM | `file`×1, `okhttp`×7, `platform-info`×1, `threads`×1, `net-codec`×2, `reflection`×1, `synchronized`×2, `timeunit`×2 |
| `data/naming/NamingStudyTest.kt` | SEAM | `file`×4, `okhttp`×2, `platform-info`×12, `threads`×16, `format`×20, `java-util`×2, `timeunit`×6 |
| `data/naming/RoadCenterTest.kt` | SEAM | `file`×2, `okhttp`×2, `platform-info`×1, `format`×1, `math`×5, `systime`×2, `timeunit`×1 |
| `data/transit/TransitLineCacheTest.kt` | SEAM | `file`×1 |
| `data/transit/TransitousPlanTest.kt` | SEAM | `locale-seam`×1, `math`×1 |
| `data/transit/TransitousTest.kt` | SEAM | `file`×2, `time`×1 |
| `i18n/NavStringsTest.kt` | SEAM | `locale-seam`×5 |
| `nav/NavEngineChainTest.kt` | SEAM | `locale-seam`×1, `math`×2 |
| `nav/RouteSmoothingTest.kt` | SEAM | `file`×1, `math`×8 |
| `replay/TripShareBatchTest.kt` | SEAM | `stream`×1, `zip`×1, `charset`×1, `io-exception`×1 |
| `util/AtomicFilesTest.kt` | SEAM | `file`×3 |
| `util/PlaceNamesTest.kt` | SEAM | `file`×2, `jvm-statics`×3 |
<!-- END GENERATED: tests -->

## C-8 : `app/offline` (généré)

<!-- BEGIN GENERATED: c8 -->
| Fichier (app/offline) | Plan | Lignes | Classe | Bloqueurs | Dép. :core | Dép. app/offline | Dép. :core non déplaçables (A) |
|---|---|---|---|---|---|---|---|
| `CellStore.kt` |  | 189 | SEAM | `android-context`×2, `file`×1, `okhttp`×2, `zip`×1, `android-clock`×5, `dispatchers-io`×2, `hilt-inject`×5, `org-json`×9, `synchronized`×4, `timeunit`×2, `volatile`×3 | util/AtomicFiles | CountingInputStream, ObfStore, PlacesTileStore, PoiPackStore, StorageLocation | AtomicFiles |
| `CountingInputStream.kt` |  | 17 | SEAM | `stream`×1 | - | - | - |
| `GlyphPackStore.kt` |  | 125 | SEAM | `android-context`×1, `android-log`×2, `file`×1, `okhttp`×2, `zip`×1, `dispatchers-io`×1, `timeunit`×2 | config/VelaLinks | StorageLocation | - |
| `LegacyGraphs.kt` |  | 19 | SEAM | `file`×1 | - | - | - |
| `LocalBasemapTiles.kt` |  | 120 | SEAM | `android-log`×3, `file`×1, `okhttp`×7, `lru-map`×2, `math`×2, `synchronized`×2, `volatile`×3 | net/NetHealth | PmtilesReader, RegionPolys, ReleaseRedirects, StreamedPmtiles | NetHealth |
| `MaxspeedOverlayStore.kt` |  | 63 | SEAM | `android-context`×2, `okhttp`×2, `dispatchers-io`×1, `hilt-inject`×5, `org-json`×3, `volatile`×1 | model/Geo | RegionPolys | - |
| `ObfStore.kt` |  | 136 | SEAM | `android-context`×2, `file`×1, `okhttp`×2, `dispatchers-io`×1, `hilt-inject`×5, `org-json`×14, `synchronized`×5, `timeunit`×2 | util/AtomicFiles | RegionCatalog, StorageLocation | AtomicFiles |
| `OfflineMaps.kt` |  | 148 | SEAM | `android-context`×1, `org-json`×4 | - | - | - |
| `OverlayTileStore.kt` |  | 132 | SEAM | `android-context`×2, `file`×1, `okhttp`×2, `dispatchers-io`×2, `hilt-inject`×5, `org-json`×9, `synchronized`×2, `timeunit`×2 | util/AtomicFiles | CountingInputStream, RegionCatalog, StorageLocation | AtomicFiles |
| `PlacesArchiveSearch.kt` | **C-8** | 203 | SEAM | `file`×1, `jvm-statics`×2, `math`×1 | data/OfflineRank, model/Geo, model/Place, util/OsmHours | PmtilesReader | OfflineRank |
| `PlacesTileStore.kt` |  | 607 | SEAM | `android-context`×3, `android-other`×1, `file`×1, `okhttp`×2, `android-clock`×5, `dispatchers-io`×4, `hilt-inject`×7, `math`×1, `org-json`×15, `reflection`×3, `synchronized`×6, `timeunit`×2, `volatile`×3 | model/Geo, util/AtomicFiles | PmtilesCompact, PmtilesPatch, PmtilesReader, RegionPolys, StorageLocation | AtomicFiles |
| `PmtilesCompact.kt` | **C-8** | 156 | SEAM | `file`×2, `zip`×1, `io-exception`×3, `reflection`×1 | - | PmtilesPatch, PmtilesReader | - |
| `PmtilesPatch.kt` | **C-8** | 260 | SEAM | `android-log`×1, `crypto`×1, `file`×2, `zip`×1, `format`×2, `io-exception`×1, `org-json`×2, `reflection`×1 | - | PmtilesCompact, PmtilesReader | - |
| `PmtilesReader.kt` | **C-8** | 438 | SEAM | `file`×2, `okhttp`×2, `stream`×1, `zip`×1, `lru-map`×1, `math`×5, `synchronized`×2 | - | - | - |
| `PoiPackStore.kt` |  | 257 | SEAM | `android-context`×2, `android-log`×1, `android-sqlite`×4, `file`×1, `okhttp`×2, `zip`×1, `dispatchers-io`×3, `hilt-inject`×5, `org-json`×6, `reflection`×1, `synchronized`×2, `timeunit`×2 | data/OfflinePacks, util/AtomicFiles | CountingInputStream, RegionCatalog, StorageLocation | OfflinePacks, AtomicFiles |
| `RegionCatalog.kt` | **C-8** | 78 | SEAM | `android-context`×2, `file`×1, `okhttp`×2, `dispatchers-io`×1, `hilt-inject`×5, `org-json`×3 | util/AtomicFiles | RegionPolys | AtomicFiles |
| `RegionPacks.kt` |  | 42 | PURE | - | - | RegionCatalog | - |
| `RegionPick.kt` |  | 34 | PURE | - | - | PlacesTileStore, RegionCatalog | - |
| `RegionPolys.kt` | **C-8** | 101 | SEAM | `android-context`×1, `org-json`×3, `volatile`×1 | - | - | - |
| `ReleaseRedirects.kt` |  | 53 | SEAM | `okhttp`×3, `concurrent-coll`×2, `systime`×1, `time`×1 | - | - | - |
| `RoadNameTileSource.kt` |  | 68 | SEAM | `android-context`×1, `file`×1, `okhttp`×6, `dispatchers-io`×1, `io-exception`×1, `org-json`×3, `systime`×1, `timeunit`×3, `volatile`×2 | VelaConfig, data/naming/RoadNameTiles | PmtilesReader, StorageLocation | RoadNameTiles |
| `StorageLocation.kt` |  | 105 | SEAM | `android-context`×1, `android-other`×2, `android-prefs`×1, `file`×1, `reflection`×2 | data/OfflineRoot | - | OfflineRoot |
| `StreamedPmtiles.kt` |  | 90 | SEAM | `crypto`×1, `okhttp`×6, `concurrent-coll`×2, `format`×1, `timeunit`×1 | - | PmtilesReader, ReleaseRedirects | - |
<!-- END GENERATED: c8 -->

## Précision (vérification à la main)

Vingt-six fichiers vérifiés à la main : `SearchParser`, `Geo`, `Calibration`, `NavEngine`, `Place`,
`ParkingStore`, `DelayText`, `PlaceNames`, `NavStrings`, `RouteProjection`, `RouteCorridor`,
`MapDataSource`, `SearchPb`, `SpeechText`, `QueryIntent`, `JsTransforms`, `LineNamer`, `Route`,
`CategoryFilter`, `Stillness`, `OpeningHours`, `StepAudit`, `TripLog`, `GoogleMapsDataSource`,
`DemoTrace`, `NavSession`. Contrôle des dépendances par une seconde méthode indépendante (tout
identifiant du fichier qui porte le nom d'une déclaration de `:core`, quel que soit le paquet),
puis lecture des cas différents ; contrôle des bloqueurs par `grep` des imports et des appels.

- **Dépendances : aucune arête manquante ni en trop trouvée.** Les seuls écarts entre les deux
  méthodes étaient des homonymes d'un autre paquet sans import (`Route` de `QueryIntent`, qui est
  `QueryIntent.Route`), donc de vraies non-dépendances. Un défaut a été trouvé et corrigé pendant
  la vérification : les fonctions `private` de premier niveau (`fun m()` de `NavReplay`) étaient
  indexées.
- Une seule arête du graphe repose uniquement sur des noms en minuscules du même paquet
  (`StreetViewParser` → `GoogleResponse` : `at`, `int`, `str`, ...), et elle est réelle. Aucun nom
  de premier niveau n'est déclaré dans deux fichiers du même paquet. Le risque de faux positifs
  par homonymie est donc faible dans ce code.
- **Bloqueurs : exacts sur l'échantillon**, comptes d'occurrences compris (par exemple `math`×5
  de `RouteProjection`, deux sur la même ligne). Les totaux recoupent le §1.1 du plan :
  `synchronized` 58 occurrences, `String.format`/`.format(` 28, `okhttp3` 21 fichiers,
  `javax.inject`/`dagger` 22 fichiers. Un faux positif a été retiré (`\p{M}+` pris pour un
  quantificateur possessif).
- Limites connues : pas de typage. `.format(` compte aussi un `DateTimeFormatter.format` (déjà
  bloqué par `java.time`) ; `.toByteArray()` et `String(bytes)` ne sont que des notes car le
  receveur est inconnu ; une extension appelée sans receveur explicite dans un bloc `with` n'est
  vue que si elle est appelée comme une fonction. Un fichier qui dépend d'un objet seulement par
  un type inféré (sans jamais écrire son nom) n'aurait pas d'arête : ce cas ne casse pas la
  compilation d'un déplacement, puisque l'inférence passe par un autre symbole qui, lui, est
  compté.

Estimation : plus de 98 % des arêtes et des bloqueurs justes. Avant de déplacer un fichier,
`--file` donne en une commande ses déclarations, ses arêtes (avec les symboles) et ses bloqueurs
avec la ligne.

## Surprises

1. **`i18n/NavStrings.kt` bloque la navigation.** 2 575 lignes, 25 langues, et `java.util.Locale`
   utilisé comme valeur (`override val locale: Locale = Locale("pt", "BR")`, 33 occurrences). Il
   bloque 10 fichiers par son cône, dont `NavEngine`, `NavReplay`, `TripLog`, `OfflinePhrases`.
   Le remplacer par une étiquette de langue (`String` BCP-47 ou une petite `value class`) est un
   changement local, sans couture ; avec lui, la vague A passe de 94 à 103 fichiers.
2. **`Calibration` dépend de `VelaPiper`** pour une constante (voir V-1). Sans cette coupure, la
   recherche ne peut pas partir.
3. **C-8 n'est pas « offline pur ».** Les six fichiers que le plan cite (`PmtilesReader`,
   `PmtilesCompact`, `PmtilesPatch`, `RegionCatalog`, `RegionPolys`, `PlacesArchiveSearch`) sont
   tous SEAM : `java.io.File`/`RandomAccessFile`, `okhttp3`, `java.util.zip`, `org.json`,
   `MessageDigest`. Seuls `RegionPacks` et `RegionPick` sont PURE dans `app/offline`.
   `OfflineRank`, cité dans C-8, est en fait dans `:core` (`data/OfflineRank.kt`), en cycle avec
   `OfflinePoiStore`, et utilise `java.text.Normalizer`.
4. **Trois arêtes vers STAYS** : `GoogleMapsDataSource` → `GoogleTransport` (pour l'objet
   `AgedSession`, qui doit devenir le `RequestTag` de `HttpRequest`), `NavSession` → `Haptics`,
   `DemoTrace` → `LocationProvider` (pour le type `ReplayFix`). Il faut sortir ces symboles avant
   de déplacer ces fichiers.
5. **Coutures absentes de la liste fermée du §3.1** :
   - `Character.UnicodeScript` (68 occurrences dans `NameScript`, `SpokenScript`, `PlaceNames`,
     `VoiceGuide`, `ObfRouteEngine`) : Kotlin common n'a que `Char.category`, pas les scripts.
     Il faut une table maison (plages Unicode) ou une couture ; `TextNormalizer` ne le couvre pas.
   - Fils : `Thread.sleep` (`RouteGeometry`, `ValhallaRouter`), `Executors` (`Transitous`),
     `Thread { }` (`VoiceGuide`). À remplacer par des coroutines (`delay`, `Dispatchers.IO`).
   - Hachage : `MessageDigest` SHA-256 (`FuelGbStore`, `PmtilesPatch`, `StreamedPmtiles`), à
     ajouter à `SignatureVerifier` ou en Kotlin pur.
   - XML : `NdwBridgeOpenings` lit du XML avec `org.xmlpull`/`kxml2` (fourni par Android).
   - Retour haptique (`Haptics`), dont `NavSession` dépend.
6. **API kotlinx JVM seules** : `Json.decodeFromStream` (Overpass*, `PaintedRoads`, `Transitous`)
   n'existe pas en common ; il faut passer par `String` ou `kotlinx-io`.
7. **`RegexOption.DOT_MATCHES_ALL`** (`MyMapKml`, `PlaceImport`) n'existe pas en common : il faut
   le drapeau en ligne `(?s)`.
8. **`"%.5f".format(x)` sans `Locale`** dans `SuggestParser` (identifiant `suggest:…`) et
   `OfflineAddressStore` (identifiant d'adresse) : sur Android, la sortie dépend de la langue du
   téléphone (virgule décimale en français). `util/Fmt` ne doit pas « corriger » ces appels sans
   décision, sinon les identifiants stockés changent ; les tests d'égalité de C-1 doivent fixer
   la `Locale` par défaut.
9. **`@Synchronized` est silencieusement sans effet sur Kotlin/Native** (`Stillness`,
   `TransitLineCache`) : le passage par atomicfu de C-1 est obligatoire, pas cosmétique.
10. **Les cycles sont rares** (2, de 3 et 2 fichiers) : le code est déjà en couches. Le graphe a
    380 arêtes et 5 vagues A seulement : beaucoup de fichiers peuvent bouger en parallèle.
11. **Tests** : les 169 tests sont en JUnit 4. 432 assertions dans 79 fichiers ont le message en
    premier ; 10 tests lisent des fixtures du classpath (`getResourceAsStream`), ce qui n'existe
    pas en `commonTest` (il faudra une petite couture de fixtures ou générer les fixtures en
    constantes) ; 12 utilisent `Assume` (pas d'équivalent `kotlin.test`).

## Risques

- **Précision du graphe** : analyse lexicale sans typage. Les arêtes servent à l'ordre ; la
  vérité reste la compilation `:core-common:compileKotlinIosArm64`. Un agent qui déplace un fichier
  le compile pour iOS, pas seulement pour la JVM.
- **MECHANICAL ne veut pas dire sans risque de sortie** : `String.format` (voir surprise 8),
  `java.time` → `kotlinx-datetime` (fuseaux, `DayOfWeek`), `Random` → `kotlin.random` (graine).
  Chaque remplacement garde un test d'égalité contre la JVM.
- **`org.json`** est rangé MECHANICAL (aucune couture), mais c'est une réécriture vers
  `kotlinx.serialization` (`ObfRouteEngine`, `Transitous` dans `:core` ; onze fichiers de
  `app/offline`).
- **Classement par chemin des lots** : les règles sont dans `LOT_RULES` ; un fichier mal rangé se
  corrige là, pas dans ce document.
- **`android-context` est souvent le seul bloqueur Android d'un store** : la couture est le
  `CoreGraph`, qui doit exister (F-2) avant C-6.

## Corrections proposées à `PORTAGE_IOS.md`, phase 3

1. **V-1** : ajouter les deux coupures (constante `DEFAULT_VOICE_ID` hors de `VelaPiper`, langue
   de `SearchParser` passée par l'appelant) et ajouter `data/MapDataSource.kt` (porteur de
   `CalibrationNeededException`), `VelaConfig`, `VelaLinks`, `DirectionsPb`, `PhotosParser`,
   `ReviewFeedParser`, `SpokenRoadNames`, `Notice` à la liste : ils sont dans la clôture. Retirer
   de V-1 la partie « tout `util/` » : `NameScript`, `PlaceNames`, `MvtLines` sont SEAM
   (`UnicodeScript`, `Normalizer`, flux) et la recherche n'en a pas besoin ; ils vont en C-7 ou
   avec `TextNormalizer`.
2. **C-1** : y ajouter les remplacements trouvés en plus du §3.1 : `Charsets` →
   `encodeToByteArray`, `URLEncoder`/`URLDecoder`/`URI` → `util/UrlCodec`, `TimeUnit` →
   `Duration`, `Dispatchers.IO` (import), `AtomicX` et `ConcurrentHashMap` → atomicfu,
   `RegexOption.DOT_MATCHES_ALL` → `(?s)`, `javaClass.simpleName` → `::class.simpleName`,
   `Long.parseUnsignedLong`/`numberOfTrailingZeros`/`Float.intBitsToFloat` → équivalents Kotlin,
   `Thread.sleep` → `delay`. Et, nouveau, **`NavStrings` : `Locale` → étiquette de langue**, qui
   débloque C-5.
3. **§3.1, liste fermée des coutures** : ajouter `Haptics` (ou faire de `NavSession` un appelant
   d'un callback), une table de scripts Unicode (dans `TextNormalizer` ou en Kotlin pur), le
   hachage SHA-256, et décider pour XML (`NdwBridgeOpenings`) : couture ou hors V1.
4. **C-2** : préciser qu'`AgedSession` sort de `net/GoogleTransport.kt` (STAYS) vers le common
   avant `GoogleMapsDataSource`. `GoogleMapsDataSource` dépend de 53 fichiers : c'est le dernier
   fichier de C-2, et il touche aussi C-3 (`RouteGeometry`, `ValhallaRouter`, `PhotonGeocoder`)
   et C-5 (`data/naming/*`, `NavStrings`, `StepAudit`).
5. **C-5** : ajouter `data/naming/` (5 fichiers), `i18n/`, `data/RouteCorridor`,
   `data/RoutingPrefs`, `data/OfflinePhrases`, `location/FixRules`, `AlongRouteFilter`,
   `Stillness`. `NavSession` dépend de `Haptics` et `VoiceGuide` : C-5 attend C-7 pour lui.
   `DemoTrace` attend que `ReplayFix` sorte de `LocationProvider`.
6. **C-6** : y ranger aussi `PlaceImport`, `TakeoutCsv`, `ImportResult` (lecture d'exports) et
   `AmbientDiskCache`. `CalibrationStore` reste en C-4 et `FuelGbStore` en C-3.
7. **C-8** : le requalifier « offline sur coutures » : les six fichiers ont besoin de
   `PlatformFiles` (accès aléatoire : `RandomAccessFile`), `Unzip`, `VelaHttp` et d'une réécriture
   `org.json`. Y rattacher `data/OfflineRank.kt` **avec** `data/OfflinePoiStore.kt` (cycle), ou
   casser le cycle avant.
8. **Fichiers qu'aucun lot ne cite** : `search/` (`QueryIntent` a besoin de `TextNormalizer`),
   `diag/` (`DiagLog` sur `PlatformFiles` + `KeyValueStore`), `data/LowDataMode`, `LowRamMode`,
   `ClockFormat`, `MapDeclutter`. Proposition : `search/` et `MapDeclutter` en C-2, `diag/` en
   C-6, les drapeaux en C-1 (ils sont PURE ou MECHANICAL, vague 1).
9. **Tests (tous les lots)** : la règle « tests correspondants vers `commonTest` » suppose une
   conversion JUnit → `kotlin.test` qui réordonne les messages (432 appels) et une solution pour
   les fixtures du classpath. Proposer un lot court « T-0 » : script de conversion et petit
   chargeur de fixtures, avant V-1.
10. **Sortie de phase** : la liste « ce qui reste dans `:core` » est déjà calculable :
    `python3 scripts/ios/core_deps.py` (section « Vagues », dernière ligne).
