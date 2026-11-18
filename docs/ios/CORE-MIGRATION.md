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

Mesures prises sur `ios/main` au commit `3292423f`, sections générées régénérées après C-3b (branche `ios/c3b-transitous`). Python 3, bibliothèque standard seulement,
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
| PURE | 10 | 561 |
| MECHANICAL | 6 | 450 |
| SEAM | 28 | 3 456 |
| STAYS | 15 | 1 600 |
| **total** | 59 | 6 067 |

- Arêtes internes (fichier → fichier de `:core`) : **38**.
- Déplaçables sans couture, une fois C-1 fait (PURE ou MECHANICAL, et toutes les dépendances aussi) : **14** fichiers, en **1** vagues.
- PURE ou MECHANICAL mais bloqués par une dépendance SEAM ou STAYS : **2**.
- Déplaçables une fois les coutures F-2 posées (tout sauf STAYS et ce qui en dépend) : **43**, en **3** vagues.
- Composantes fortement connexes de plus d'un fichier (cycles) : **0**.
- Clôture V-1 : **0** fichiers.

| Paquet | Fichiers | Lignes | PURE | MECH. | SEAM | STAYS | déplaçables (A) |
|---|---|---|---|---|---|---|---|
| `data` | 8 | 1011 | 1 | 2 | 2 | 3 | 2 |
| `data/google` | 2 | 72 | 0 | 0 | 2 | 0 | 0 |
| `data/tiles` | 1 | 46 | 1 | 0 | 0 | 0 | 1 |
| `di` | 7 | 437 | 0 | 0 | 0 | 7 | 0 |
| `diag` | 2 | 136 | 1 | 0 | 1 | 0 | 1 |
| `feedback` | 1 | 78 | 0 | 0 | 0 | 1 | 0 |
| `i18n` | 1 | 16 | 0 | 0 | 1 | 0 | 0 |
| `location` | 4 | 502 | 0 | 0 | 1 | 3 | 0 |
| `model` | 1 | 31 | 1 | 0 | 0 | 0 | 1 |
| `net` | 2 | 114 | 0 | 0 | 1 | 1 | 0 |
| `platform` | 11 | 415 | 0 | 1 | 10 | 0 | 1 |
| `replay` | 1 | 65 | 0 | 0 | 1 | 0 | 0 |
| `search` | 4 | 718 | 3 | 0 | 1 | 0 | 3 |
| `util` | 8 | 1264 | 1 | 3 | 4 | 0 | 4 |
| `voice` | 6 | 1162 | 2 | 0 | 4 | 0 | 1 |
<!-- END GENERATED: summary -->

## Bloqueurs (généré)

« Seul bloqueur » : nombre de fichiers où cette règle est la seule trouvée.

<!-- BEGIN GENERATED: blockers -->
| Id | Détecte | Classe | Couture ou remplacement | Fichiers | Occurrences | seul bloqueur |
|---|---|---|---|---|---|---|
| `hilt-module` | @Module/@Provides Hilt | STAYS | Hilt | 7 | 47 | 0 |
| `osmand` | net.osmand (OsmAnd) | STAYS | OsmAnd | 1 | 13 | 0 |
| `android-context` | Context Android | SEAM | PlatformFiles/CoreGraph | 14 | 24 | 0 |
| `android-icu` | android.icu | SEAM | PlatformLocale/TextNormalizer | 1 | 1 | 0 |
| `android-location` | android.location | SEAM | LocationSource | 1 | 3 | 0 |
| `android-log` | android.util.Log | SEAM | Log | 3 | 26 | 1 |
| `android-other` | autre API android/androidx | SEAM | Android | 7 | 22 | 0 |
| `android-prefs` | SharedPreferences | SEAM | KeyValueStore | 5 | 14 | 0 |
| `android-sensors` | capteurs android.hardware | SEAM | HeadingSource | 3 | 12 | 0 |
| `android-speech` | TTS / audio Android | SEAM | SpeechSynth | 2 | 13 | 0 |
| `android-sqlite` | SQLite Android | SEAM | SqlDb | 1 | 14 | 0 |
| `crypto` | java.security / javax.crypto | SEAM | SignatureVerifier | 1 | 3 | 0 |
| `file` | java.io.File / java.nio.file | SEAM | PlatformFiles | 7 | 9 | 2 |
| `locale-seam` | Locale.getDefault / Locale(...) | SEAM | PlatformLocale | 3 | 9 | 1 |
| `net-conn` | java.net connexion | SEAM | VelaHttp | 1 | 3 | 0 |
| `normalizer` | java.text.Normalizer | SEAM | TextNormalizer | 3 | 11 | 2 |
| `okhttp` | okhttp3 | SEAM | VelaHttp | 12 | 26 | 4 |
| `platform-info` | System.getProperty / Runtime | SEAM | plateforme | 1 | 1 | 0 |
| `rhino` | Rhino | SEAM | JsEngine | 1 | 4 | 0 |
| `stream` | flux java.io | SEAM | PlatformFiles/VelaHttp (flux) | 3 | 6 | 0 |
| `threads` | Thread / Executor | SEAM | threads (hors liste) | 3 | 8 | 0 |
| `unicode` | Character.UnicodeScript | SEAM | TextNormalizer (scripts) | 5 | 68 | 0 |
| `zip` | java.util.zip | SEAM | Unzip | 2 | 3 | 0 |
| `android-clock` | SystemClock | MECHANICAL | Clock | 3 | 7 | 0 |
| `charset` | Charsets | MECHANICAL | encodeToByteArray / decodeToString | 1 | 1 | 0 |
| `concurrent-coll` | collections concurrentes | MECHANICAL | Map + verrou atomicfu | 1 | 3 | 0 |
| `format` | String.format / .format( | MECHANICAL | util/Fmt | 1 | 2 | 0 |
| `hilt-inject` | @Inject / @Singleton | MECHANICAL | retirer @Inject (D3) | 14 | 105 | 0 |
| `io-exception` | IOException / ByteArrayOutputStream | MECHANICAL | kotlinx-io IOException ou exception maison | 4 | 6 | 0 |
| `java-util` | autre java.util (UUID, Base64, Random, TreeMap...) | MECHANICAL | kotlin.random / kotlin.uuid / Base64 / collections | 1 | 1 | 0 |
| `jvm-statics` | statiques JVM (Integer., Character., ...) | MECHANICAL | équivalent Kotlin | 6 | 11 | 0 |
| `math` | Math.* | MECHANICAL | kotlin.math | 8 | 12 | 3 |
| `org-json` | org.json | MECHANICAL | kotlinx.serialization (réécriture) | 1 | 3 | 0 |
| `reflection` | réflexion JVM | MECHANICAL | sans réflexion JVM | 7 | 9 | 0 |
| `synchronized` | synchronized | MECHANICAL | atomicfu synchronized | 3 | 9 | 0 |
| `systime` | System.currentTimeMillis / nanoTime | MECHANICAL | Clock | 6 | 14 | 0 |
| `time` | java.time / Calendar | MECHANICAL | kotlinx-datetime | 1 | 2 | 1 |
| `timeunit` | TimeUnit | MECHANICAL | kotlin.time.Duration | 3 | 5 | 0 |
| `volatile` | @Volatile | MECHANICAL | kotlin.concurrent.Volatile | 4 | 6 | 0 |
<!-- END GENERATED: blockers -->

## Lots (généré)

Colonnes : « Dép. » = fichiers de `:core` dont il dépend directement ; « Dépendants » = fichiers
qui dépendent de lui ; « Vague A/B » : voir la méthode ; dernière colonne : coutures du fichier,
ou les fichiers SEAM/STAYS de son cône qui le bloquent (« via »). `V-1 (model/util)` = le reste de
`model/` et `util/` que le plan range dans V-1 sans que la recherche en ait besoin. `RESTE` = ce
qui reste dans `:core`. `hors lot` = fichiers qu'aucun lot du plan ne cite.

<!-- BEGIN GENERATED: lots -->
#### V-1 (model/util) (8 fichiers, 1271 lignes ; PURE 2, MECH. 3, SEAM 3, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `model/PlaceArea.kt` | 31 | PURE | - | 0 | 0 | 1 | 1 |  |
| `util/AddressQuery.kt` | 70 | PURE | - | 0 | 0 | 1 | 1 |  |
| `util/OpeningHours.kt` | 136 | MECHANICAL | `time`×2 | 0 | 0 | 1 | 1 |  |
| `util/ShapeMeasure.kt` | 34 | MECHANICAL | `math`×2 | 0 | 0 | 1 | 1 |  |
| `util/SunTimes.kt` | 93 | MECHANICAL | `math`×2 | 0 | 0 | 1 | 1 |  |
| `util/MvtLines.kt` | 155 | SEAM | `stream`×1, `zip`×1, `charset`×1, `jvm-statics`×2, `math`×2 | 0 | 0 | - | 1 | PlatformFiles/VelaHttp (flux) / Unzip |
| `util/NameScript.kt` | 93 | SEAM | `unicode`×29, `jvm-statics`×5 | 0 | 0 | - | 1 | TextNormalizer (scripts) |
| `util/PlaceNames.kt` | 659 | SEAM | `normalizer`×3, `unicode`×6, `jvm-statics`×1 | 0 | 2 | - | 1 | TextNormalizer / TextNormalizer (scripts) |

#### C-2 (4 fichiers, 253 lignes ; PURE 0, MECH. 1, SEAM 3, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `data/MockMapDataSource.kt` | 128 | MECHANICAL | `hilt-inject`×4, `math`×1 | 0 | 1 | 1 | 1 |  |
| `data/google/BrowserHeadersOkHttp.kt` | 29 | SEAM | `okhttp`×1 | 0 | 1 | - | 1 | VelaHttp |
| `net/NetHealth.kt` | 53 | SEAM | `net-conn`×3, `okhttp`×2, `io-exception`×1, `systime`×4 | 0 | 1 | - | 1 | VelaHttp |
| `data/google/AndroidGoogleSource.kt` | 43 | SEAM | `okhttp`×1 | 3 | 1 | - | 3 | VelaHttp |

#### C-3 (2 fichiers, 232 lignes ; PURE 1, MECH. 0, SEAM 1, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `data/tiles/MapStyle.kt` | 46 | PURE | - | 0 | 0 | 1 | 1 |  |
| `data/OverpassPois.kt` | 186 | SEAM | `okhttp`×1, `stream`×4 | 1 | 0 | - | - | VelaHttp / PlatformFiles/VelaHttp (flux) |

#### C-5 (3 fichiers, 169 lignes ; PURE 0, MECH. 0, SEAM 3, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `i18n/NavStringsLocale.kt` | 16 | SEAM | `locale-seam`×4 | 0 | 1 | - | 1 | PlatformLocale |
| `location/Stillness.kt` | 88 | SEAM | `android-context`×1, `android-sensors`×4, `reflection`×1 | 0 | 0 | - | 1 | PlatformFiles/CoreGraph / HeadingSource |
| `replay/TripShareBatch.kt` | 65 | SEAM | `stream`×1, `zip`×2 | 0 | 0 | - | 1 | PlatformFiles/VelaHttp (flux) / Unzip |

#### C-6 (1 fichiers, 10 lignes ; PURE 0, MECH. 0, SEAM 1, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `data/OfflineRoot.kt` | 10 | SEAM | `file`×1 | 0 | 1 | - | 1 | PlatformFiles |

#### C-7 (6 fichiers, 1162 lignes ; PURE 2, MECH. 0, SEAM 4, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `voice/NeuralSynth.kt` | 44 | PURE | - | 0 | 1 | 1 | 1 |  |
| `voice/SpeechLeadIn.kt` | 48 | SEAM | `android-context`×1, `android-other`×1, `android-speech`×3, `reflection`×1 | 0 | 1 | - | 1 | PlatformFiles/CoreGraph / Android / SpeechSynth |
| `voice/SpokenScript.kt` | 173 | SEAM | `android-icu`×1, `unicode`×29, `jvm-statics`×1 | 0 | 1 | - | 1 | PlatformLocale/TextNormalizer / TextNormalizer (scripts) |
| `voice/VelaPiper.kt` | 147 | SEAM | `android-context`×1, `android-prefs`×4, `file`×1, `volatile`×1 | 0 | 2 | - | 1 | PlatformFiles/CoreGraph / KeyValueStore / PlatformFiles |
| `voice/PiperCatalog.kt` | 139 | PURE | - | 1 | 0 | - | 2 | via VelaPiper |
| `voice/VoiceGuide.kt` | 611 | SEAM | `android-context`×2, `android-log`×4, `android-other`×5, `android-speech`×10, `locale-seam`×3, `threads`×4, `unicode`×2, `android-clock`×3, `hilt-inject`×5, `jvm-statics`×1, `math`×1 | 5 | 1 | - | 2 | PlatformFiles/CoreGraph / Log / Android / SpeechSynth / PlatformLocale / threads (hors liste) / TextNormalizer (scripts) |

#### hors lot (19 fichiers, 1346 lignes ; PURE 5, MECH. 2, SEAM 12, STAYS 0)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `data/MapDeclutter.kt` | 51 | MECHANICAL | `math`×1 | 0 | 0 | 1 | 1 |  |
| `diag/DiagEvent.kt` | 17 | PURE | - | 0 | 1 | 1 | 1 |  |
| `platform/AndroidClock.kt` | 8 | MECHANICAL | `android-clock`×1, `systime`×2 | 0 | 1 | 1 | 1 |  |
| `search/AreaNarrow.kt` | 25 | PURE | - | 0 | 0 | 1 | 1 |  |
| `search/SearchKind.kt` | 25 | PURE | - | 0 | 0 | 1 | 1 |  |
| `search/VoiceCommandExamples.kt` | 138 | PURE | - | 0 | 0 | 1 | 1 |  |
| `platform/AndroidLog.kt` | 23 | SEAM | `android-log`×13 | 0 | 1 | - | 1 | Log |
| `platform/AndroidPlatformLocale.kt` | 16 | SEAM | `android-other`×2, `locale-seam`×2 | 0 | 1 | - | 1 | Android / PlatformLocale |
| `platform/AndroidSqlDbs.kt` | 92 | SEAM | `android-context`×1, `android-sqlite`×14 | 0 | 1 | - | 1 | PlatformFiles/CoreGraph / SqlDb |
| `platform/JvmSignatureVerifier.kt` | 25 | SEAM | `crypto`×3, `java-util`×1 | 0 | 1 | - | 1 | SignatureVerifier |
| `platform/JvmTextNormalizer.kt` | 16 | SEAM | `normalizer`×6 | 0 | 1 | - | 1 | TextNormalizer |
| `platform/OkHttpVelaHttp.kt` | 77 | SEAM | `okhttp`×7, `io-exception`×2, `reflection`×2, `timeunit`×1 | 0 | 4 | - | 1 | VelaHttp |
| `platform/RhinoJsEngine.kt` | 64 | SEAM | `rhino`×4, `reflection`×1, `synchronized`×1, `systime`×2 | 0 | 1 | - | 1 | JsEngine |
| `platform/SharedPrefsKeyValueStores.kt` | 34 | SEAM | `android-context`×1, `android-prefs`×4 | 0 | 1 | - | 1 | PlatformFiles/CoreGraph / KeyValueStore |
| `search/QueryIntent.kt` | 530 | SEAM | `normalizer`×2 | 0 | 0 | - | 1 | TextNormalizer |
| `data/KeptLabel.kt` | 26 | PURE | - | 1 | 0 | - | 2 | via PlaceNames |
| `diag/DiagLog.kt` | 119 | SEAM | `android-context`×2, `android-prefs`×2, `file`×1, `hilt-inject`×5, `systime`×1 | 2 | 3 | - | 2 | PlatformFiles/CoreGraph / KeyValueStore / PlatformFiles |
| `platform/AndroidPlatformFiles.kt` | 29 | SEAM | `file`×1 | 1 | 1 | - | 2 | PlatformFiles |
| `platform/OkHttpRouteHttp.kt` | 31 | SEAM | `okhttp`×1, `reflection`×1 | 1 | 1 | - | 2 | VelaHttp |

#### RESTE (16 fichiers, 1624 lignes ; PURE 0, MECH. 0, SEAM 1, STAYS 15)

| Fichier | Lignes | Classe | Bloqueurs | Dép. | Dépendants | Vague A | Vague B | Couture / bloqué par |
|---|---|---|---|---|---|---|---|---|
| `util/AtomicFiles.kt` | 24 | SEAM | `file`×2, `io-exception`×1 | 0 | 2 | - | 1 | PlatformFiles |
| `data/ObfRouteEngine.kt` | 528 | STAYS | `osmand`×13, `android-log`×9, `file`×2, `platform-info`×1, `threads`×2, `unicode`×2, `concurrent-coll`×3, `format`×2, `jvm-statics`×1, `math`×2, `org-json`×3, `reflection`×1, `synchronized`×5, `systime`×4, `timeunit`×1, `volatile`×2 | 0 | 1 | - | - | OsmAnd / Log / PlatformFiles / plateforme / threads (hors liste) / TextNormalizer (scripts) |
| `data/OpenServicesHttp.kt` | 51 | STAYS | `okhttp`×2 | 1 | 0 | - | - | clients OkHttp des services ouverts (VelaHttp Android) |
| `data/OverpassStreaming.kt` | 31 | STAYS | `okhttp`×3 | 0 | 1 | - | - | Overpass bloquant en flux OkHttp (OverpassPois) |
| `di/CoreModule.kt` | 142 | STAYS | `hilt-module`×7, `android-context`×2, `file`×1, `okhttp`×5, `hilt-inject`×11, `synchronized`×3, `timeunit`×3 | 5 | 0 | - | - | module Hilt |
| `di/GoogleModule.kt` | 24 | STAYS | `hilt-module`×3, `hilt-inject`×6 | 0 | 0 | - | - | Hilt |
| `di/NavModule.kt` | 51 | STAYS | `hilt-module`×4, `okhttp`×1, `hilt-inject`×7 | 4 | 0 | - | - | Hilt / VelaHttp |
| `di/OfflineModule.kt` | 39 | STAYS | `hilt-module`×6, `android-context`×2, `hilt-inject`×10 | 1 | 0 | - | - | Hilt / PlatformFiles/CoreGraph |
| `di/PlatformModule.kt` | 86 | STAYS | `hilt-module`×12, `android-context`×3, `okhttp`×1, `hilt-inject`×16 | 9 | 0 | - | - | Hilt / PlatformFiles/CoreGraph / VelaHttp |
| `di/StoresModule.kt` | 62 | STAYS | `hilt-module`×11, `hilt-inject`×14 | 1 | 0 | - | - | Hilt |
| `di/TransitModule.kt` | 33 | STAYS | `hilt-module`×4, `hilt-inject`×7 | 0 | 0 | - | - | Hilt |
| `feedback/Haptics.kt` | 78 | STAYS | `android-context`×2, `android-other`×3, `android-prefs`×1, `hilt-inject`×5 | 0 | 1 | - | - | Vibrator Android |
| `location/HeadingProvider.kt` | 76 | STAYS | `android-context`×2, `android-other`×3, `android-sensors`×4, `hilt-inject`×5, `math`×1 | 0 | 0 | - | - | implémentation Android de HeadingSource |
| `location/LocationProvider.kt` | 255 | STAYS | `android-context`×2, `android-location`×3, `android-other`×7, `android-prefs`×3, `threads`×2, `android-clock`×3, `hilt-inject`×5, `systime`×1, `volatile`×2 | 1 | 0 | - | - | implémentation Android de LocationSource |
| `location/MotionProvider.kt` | 83 | STAYS | `android-context`×2, `android-other`×1, `android-sensors`×4, `hilt-inject`×5 | 0 | 0 | - | - | capteurs Android (accéléromètre) |
| `net/GoogleTransport.kt` | 61 | STAYS | `okhttp`×1, `io-exception`×2, `reflection`×2, `volatile`×1 | 1 | 1 | - | - | hook Cronet (Interceptor OkHttp) |

#### C-1 (transversal : fichiers qui ont au moins un remplacement mécanique)

| Remplacement | Vers | Fichiers | Par paquet |
|---|---|---|---|
| `math` | kotlin.math | 6 | util 3, data 2, voice 1 |
| `reflection` | sans réflexion JVM | 5 | platform 3, location 1, voice 1 |
| `jvm-statics` | équivalent Kotlin | 5 | util 3, voice 2 |
| `systime` | Clock | 4 | platform 2, diag 1, net 1 |
| `hilt-inject` | retirer @Inject (D3) | 3 | data 1, diag 1, voice 1 |
| `io-exception` | kotlinx-io IOException ou exception maison | 3 | net 1, platform 1, util 1 |
| `android-clock` | Clock | 2 | platform 1, voice 1 |
| `java-util` | kotlin.random / kotlin.uuid / Base64 / collections | 1 | platform 1 |
| `timeunit` | kotlin.time.Duration | 1 | platform 1 |
| `synchronized` | atomicfu synchronized | 1 | platform 1 |
| `charset` | encodeToByteArray / decodeToString | 1 | util 1 |
| `time` | kotlinx-datetime | 1 | util 1 |
| `volatile` | kotlin.concurrent.Volatile | 1 | voice 1 |
<!-- END GENERATED: lots -->

## Vagues (généré)

<!-- BEGIN GENERATED: waves -->
Vague A : seulement PURE et MECHANICAL (après C-1, avant toute couture).

- **Vague 1** (14) : `data/MapDeclutter.kt`, `data/MockMapDataSource.kt`, `data/tiles/MapStyle.kt`, `diag/DiagEvent.kt`, `model/PlaceArea.kt`, `platform/AndroidClock.kt`, `search/AreaNarrow.kt`, `search/SearchKind.kt`, `search/VoiceCommandExamples.kt`, `util/AddressQuery.kt`, `util/OpeningHours.kt`, `util/ShapeMeasure.kt`, `util/SunTimes.kt`, `voice/NeuralSynth.kt`

Vague B : en plus, les fichiers SEAM une fois leurs coutures posées (rien de STAYS). Seuls les fichiers qui ne sont pas déjà dans la vague A sont listés.

- **B1** (22) : `data/OfflineRoot.kt`, `data/google/BrowserHeadersOkHttp.kt`, `i18n/NavStringsLocale.kt`, `location/Stillness.kt`, `net/NetHealth.kt`, `platform/AndroidLog.kt`, `platform/AndroidPlatformLocale.kt`, `platform/AndroidSqlDbs.kt`, `platform/JvmSignatureVerifier.kt`, `platform/JvmTextNormalizer.kt`, `platform/OkHttpVelaHttp.kt`, `platform/RhinoJsEngine.kt`, `platform/SharedPrefsKeyValueStores.kt`, `replay/TripShareBatch.kt`, `search/QueryIntent.kt`, `util/AtomicFiles.kt`, `util/MvtLines.kt`, `util/NameScript.kt`, `util/PlaceNames.kt`, `voice/SpeechLeadIn.kt`, `voice/SpokenScript.kt`, `voice/VelaPiper.kt`
- **B2** (6) : `data/KeptLabel.kt`, `diag/DiagLog.kt`, `platform/AndroidPlatformFiles.kt`, `platform/OkHttpRouteHttp.kt`, `voice/PiperCatalog.kt`, `voice/VoiceGuide.kt`
- **B3** (1) : `data/google/AndroidGoogleSource.kt`

Jamais déplaçables sans couper un fichier (16) : STAYS, et ce qui en dépend : `data/ObfRouteEngine.kt`, `data/OpenServicesHttp.kt`, `data/OverpassPois.kt`, `data/OverpassStreaming.kt`, `di/CoreModule.kt`, `di/GoogleModule.kt`, `di/NavModule.kt`, `di/OfflineModule.kt`, `di/PlatformModule.kt`, `di/StoresModule.kt`, `di/TransitModule.kt`, `feedback/Haptics.kt`, `location/HeadingProvider.kt`, `location/LocationProvider.kt`, `location/MotionProvider.kt`, `net/GoogleTransport.kt`
<!-- END GENERATED: waves -->

## Cycles (généré)

<!-- BEGIN GENERATED: cycles -->
Aucun cycle.
<!-- END GENERATED: cycles -->

Les deux cycles sont petits. `Place`/`PlaceList`/`SavedPlace` sont PURE : ils partent ensemble
en vague 2. `OfflinePoiStore`/`OfflineRank` est à cheval sur deux lots (C-6 et C-8) : il faut
qu'un seul agent les déplace, ou casser le cycle d'abord (voir les corrections).

## Clôture V-1 (généré)

<!-- BEGIN GENERATED: v1 -->
Racines : `data/google/parse/SearchParser.kt`, `data/google/GoogleResponse.kt`, `data/google/SearchPb.kt`, `data/google/RequestShape.kt`, `data/google/BrowserViewport.kt`, `util/Jitter.kt`, `config/Calibration.kt`.

Clôture transitive : **0 fichiers**, 0 lignes.

Classes : PURE 0, MECHANICAL 0, SEAM 0, STAYS 0. Déplaçables en vague A : 0.

| Fichier | Lignes | Classe | Bloqueurs | Vague A | Tiré par |
|---|---|---|---|---|---|

Bloqueurs cumulés de la clôture : .

V-1 tel qu'écrit dans le plan (ajoute tout `model/` et `util/` sauf `AtomicFiles`) : **8 fichiers**, soit 8 de plus : `model/PlaceArea.kt`, `util/AddressQuery.kt`, `util/MvtLines.kt`, `util/NameScript.kt`, `util/OpeningHours.kt`, `util/PlaceNames.kt`, `util/ShapeMeasure.kt`, `util/SunTimes.kt`.
<!-- END GENERATED: v1 -->

**V-1 est fait** (branche `ios/v1-search-core`) : les 21 fichiers de la clôture (sans
`VelaPiper`, qui reste dans `:core`) sont dans `core-common/src/commonMain`. Le script ne lit que
`core/src/main` : la clôture ci-dessus est donc vide, et un fichier de `:core` qui dépend d'un
fichier déplacé n'a plus d'arête vers lui (ce qui est juste : la dépendance est satisfaite en
common). Le texte qui suit décrit l'état d'avant V-1.

Pièges rencontrés pendant V-1, utiles aux lots suivants :

- Un membre `internal` d'un fichier déplacé n'est plus visible de `:core` (autre module) : il
  passe `public`.
- Un smart cast sur une propriété publique d'un autre module est refusé
  (`HybridRoute` : `m.instructionNoRoad!!`).
- Kotlin/Native refuse `,` et les parenthèses dans un nom de test entre accents graves ; la JVM
  les accepte. `compileTestKotlinIosSimulatorArm64` le voit sous Linux.
- `StringBuilder.replace(début, fin, texte)` n'existe que sur la JVM : `setRange`.
- `Math.toRadians`/`toDegrees` : `util/Kmp.kt`, mêmes constantes que le JDK 17.

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
| `util/PlaceNames.kt` | SEAM | TextNormalizer, TextNormalizer (scripts) | 1 | 1 | `PlaceNames` |
| `voice/VelaPiper.kt` | SEAM | PlatformFiles/CoreGraph, KeyValueStore, PlatformFiles | 1 | 1 | `VelaPiper` |

Arêtes vers un fichier STAYS (à couper par une couture ou en déplaçant le symbole) :

- `data/OverpassPois.kt` → `data/OverpassStreaming.kt` : `OverpassStreaming`
<!-- END GENERATED: cuts -->

## Les 15 fichiers les plus dépendus (généré)

<!-- BEGIN GENERATED: top -->
| Fichier | Dépendants directs | Dépendants transitifs | Classe | Vague A | Bloqueurs |
|---|---|---|---|---|---|
| `platform/OkHttpVelaHttp.kt` | 4 | 5 | SEAM | - | `okhttp`×7, `io-exception`×2, `reflection`×2, `timeunit`×1 |
| `diag/DiagLog.kt` | 3 | 3 | SEAM | - | `android-context`×2, `android-prefs`×2, `file`×1, `hilt-inject`×5, `systime`×1 |
| `util/AtomicFiles.kt` | 2 | 6 | SEAM | - | `file`×2, `io-exception`×1 |
| `util/PlaceNames.kt` | 2 | 2 | SEAM | - | `normalizer`×3, `unicode`×6, `jvm-statics`×1 |
| `voice/VelaPiper.kt` | 2 | 3 | SEAM | - | `android-context`×1, `android-prefs`×4, `file`×1, `volatile`×1 |
| `data/MockMapDataSource.kt` | 1 | 1 | MECHANICAL | 1 | `hilt-inject`×4, `math`×1 |
| `data/ObfRouteEngine.kt` | 1 | 1 | STAYS | - | `osmand`×13, `android-log`×9, `file`×2, `platform-info`×1, `threads`×2, `unicode`×2, `concurrent-coll`×3, `format`×2, `jvm-statics`×1, `math`×2, `org-json`×3, `reflection`×1, `synchronized`×5, `systime`×4, `timeunit`×1, `volatile`×2 |
| `data/OfflineRoot.kt` | 1 | 1 | SEAM | - | `file`×1 |
| `data/OverpassStreaming.kt` | 1 | 1 | STAYS | - | `okhttp`×3 |
| `data/google/AndroidGoogleSource.kt` | 1 | 1 | SEAM | - | `okhttp`×1 |
| `data/google/BrowserHeadersOkHttp.kt` | 1 | 2 | SEAM | - | `okhttp`×1 |
| `diag/DiagEvent.kt` | 1 | 4 | PURE | 1 | - |
| `feedback/Haptics.kt` | 1 | 1 | STAYS | - | `android-context`×2, `android-other`×3, `android-prefs`×1, `hilt-inject`×5 |
| `i18n/NavStringsLocale.kt` | 1 | 2 | SEAM | - | `locale-seam`×4 |
| `net/GoogleTransport.kt` | 1 | 1 | STAYS | - | `okhttp`×1, `io-exception`×2, `reflection`×2, `volatile`×1 |
<!-- END GENERATED: top -->

## Tests (généré)

`assert(message, ...)` compte les appels JUnit dont le message vient en premier
(`assertEquals("msg", attendu, réel)`, `assertTrue("msg", cond)`). `kotlin.test` met le message en
dernier : ces appels sont à réordonner, et quand les trois arguments sont des `String`, une
conversion naïve compile et teste autre chose.

<!-- BEGIN GENERATED: tests -->
67 fichiers de test, 8468 lignes.

Classe propre des tests (mêmes règles que le main) : PURE 19, MECHANICAL 9, SEAM 38, STAYS 1.

| Statut | Tests |
|---|---|
| bloqué par le test lui-même | 39 |
| bloqué par ses sujets | 11 |
| commonTest (après C-1) | 17 |

Usage du framework de test :

| Motif | Fichiers | Occurrences |
|---|---|---|
| `org.junit` | 65 | 243 |
| `@Test` | 65 | 439 |
| `assert(message, ...)` | 34 | 216 |
| `ressources` | 14 | 17 |
| `Assume` | 12 | 41 |
| `@Before/@After` | 7 | 7 |
| `@Rule` | 3 | 3 |
| `assertArrayEquals` | 3 | 7 |
| `@Test(expected)` | 1 | 1 |

Bloqueurs dans les tests eux-mêmes : `file` 28 fichiers, `okhttp` 14 fichiers, `platform-info` 13 fichiers, `systime` 11 fichiers, `format` 11 fichiers, `timeunit` 10 fichiers, `time` 8 fichiers, `locale-seam` 8 fichiers, `threads` 6 fichiers, `synchronized` 6 fichiers, `math` 5 fichiers, `io-exception` 5 fichiers, `reflection` 5 fichiers, `net-codec` 4 fichiers, `stream` 4 fichiers, `zip` 4 fichiers, `volatile` 4 fichiers, `crypto` 2 fichiers, `jvm-statics` 2 fichiers, `android-prefs` 2 fichiers, `android-context` 2 fichiers, `android-other` 2 fichiers, `java-util` 2 fichiers, `charset` 2 fichiers, `locale-case` 1 fichiers, `xml` 1 fichiers, `unicode` 1 fichiers, `osmand` 1 fichiers, `atomic` 1 fichiers.

Tests prêts pour `commonTest` dès que leurs sujets ont bougé (17), par vague du sujet le plus tardif :

- après la vague 0 (7) : `CanesRouteTest.kt`, `StreetViewSearchTest.kt`, `config/VelaLinksTest.kt`, `data/ValhallaMatchTest.kt`, `data/naming/RoadNameTilesTest.kt`, `data/naming/StretchNamerTest.kt`, `nav/ParkingLotTurnTest.kt`
- après la vague 1 (10) : `MapStyleTest.kt`, `OpeningHoursTest.kt`, `OsmHoursTest.kt`, `PlaceAreaTest.kt`, `data/MapDeclutterTest.kt`, `data/MyMapKmlTest.kt`, `search/AreaNarrowTest.kt`, `search/SearchKindTest.kt`, `util/AddressQueryTest.kt`, `util/SunTimesTest.kt`

Tests bloqués par leur propre code (39) :

| Test | Classe | Bloqueurs |
|---|---|---|
| `HoursProbeTest.kt` | SEAM | `file`×1, `okhttp`×2, `platform-info`×4, `net-codec`×3 |
| `SearchSnapTest.kt` | SEAM | `file`×2, `locale-seam`×7 |
| `ShortLinksTest.kt` | SEAM | `okhttp`×1, `threads`×2, `net-codec`×1 |
| `SpokenRoadNamesTest.kt` | SEAM | `locale-seam`×1 |
| `VelaLogicTest.kt` | SEAM | `file`×2, `locale-seam`×1, `okhttp`×2, `platform-info`×4, `format`×1, `math`×16 |
| `config/RealCalibrationBundleTest.kt` | SEAM | `file`×2 |
| `data/FuelGbOracle.kt` | SEAM | `stream`×3, `zip`×1, `format`×2, `locale-case`×3, `math`×1, `time`×4 |
| `data/FuelGbTest.kt` | SEAM | `crypto`×1, `file`×1, `okhttp`×5, `zip`×1, `format`×1, `io-exception`×1 |
| `data/NdwKxmlOracle.kt` | SEAM | `stream`×1, `xml`×2, `time`×1 |
| `data/ObfCellsProbeTest.kt` | SEAM | `file`×1, `platform-info`×1, `format`×2, `systime`×2 |
| `data/ObfHhProbeTest.kt` | SEAM | `file`×1, `platform-info`×1, `format`×2, `systime`×4 |
| `data/ObfOutsideDataProbeTest.kt` | SEAM | `file`×1, `platform-info`×1, `format`×1, `systime`×2 |
| `data/ObfRoadNamesProbeTest.kt` | SEAM | `file`×1, `platform-info`×1, `unicode`×4, `jvm-statics`×1 |
| `data/ObfRouteEngineTest.kt` | STAYS | `osmand`×1 |
| `data/ObfSpeedLimitProbeTest.kt` | SEAM | `file`×1, `platform-info`×1 |
| `data/ObfStopProbeTest.kt` | SEAM | `file`×1, `platform-info`×1, `systime`×4 |
| `data/OpenDataParityTest.kt` | SEAM | `stream`×1, `time`×1 |
| `data/OpenDataRequestSnapshotTest.kt` | SEAM | `crypto`×1, `file`×1, `okhttp`×6, `zip`×1, `format`×1, `io-exception`×1, `synchronized`×3, `time`×2, `timeunit`×1, `volatile`×1 |
| `data/PaintedRoadsBakeTest.kt` | SEAM | `file`×1, `platform-info`×2, `format`×5, `systime`×2 |
| `data/RerouteFallbackTest.kt` | SEAM | `threads`×4, `systime`×6, `timeunit`×2 |
| `data/RouterRequestSnapshotTest.kt` | SEAM | `file`×1, `okhttp`×6, `synchronized`×3, `timeunit`×1, `volatile`×1 |
| `data/StoresAndroidCompatTest.kt` | SEAM | `android-context`×1, `android-other`×1, `android-prefs`×9, `file`×2, `systime`×1 |
| `data/google/BrowserHeadersOkHttpTest.kt` | SEAM | `okhttp`×1 |
| `data/google/GoogleHealthProbeTest.kt` | SEAM | `file`×1, `locale-seam`×1, `okhttp`×7, `platform-info`×1, `threads`×3, `format`×4, `net-codec`×2, `reflection`×1, `synchronized`×2, `timeunit`×2 |
| `data/google/GoogleRequestSnapshotTest.kt` | SEAM | `android-context`×1, `android-other`×1, `android-prefs`×7, `file`×4, `okhttp`×6, `reflection`×2, `synchronized`×2, `timeunit`×1 |
| `data/google/ReviewFeedProbeTest.kt` | SEAM | `file`×1, `okhttp`×7, `platform-info`×1, `threads`×1, `net-codec`×2, `reflection`×1, `synchronized`×2, `timeunit`×2 |
| `data/naming/NamingStudyTest.kt` | SEAM | `file`×4, `okhttp`×2, `platform-info`×12, `threads`×16, `format`×20, `java-util`×2, `timeunit`×6 |
| `data/naming/RoadCenterTest.kt` | SEAM | `file`×2, `okhttp`×2, `platform-info`×1, `format`×1, `math`×5, `systime`×2, `timeunit`×1 |
| `data/transit/TransitCategoryWordsTest.kt` | SEAM | `file`×2 |
| `data/transit/TransitLineCacheTest.kt` | SEAM | `file`×1 |
| `data/transit/TransitousRequestSnapshotTest.kt` | SEAM | `file`×1, `locale-seam`×5, `okhttp`×5, `synchronized`×3, `time`×1, `timeunit`×1, `volatile`×1 |
| `i18n/NavStringsSnapshotTest.kt` | SEAM | `file`×1, `locale-seam`×2, `reflection`×1 |
| `i18n/NavStringsTest.kt` | SEAM | `locale-seam`×5 |
| `nav/RouteSmoothingTest.kt` | SEAM | `file`×1, `math`×8 |
| `platform/AndroidPlatformFilesTest.kt` | SEAM | `file`×1, `locale-seam`×2 |
| `platform/OkHttpVelaHttpTest.kt` | SEAM | `okhttp`×6, `threads`×3, `atomic`×5, `io-exception`×4, `reflection`×4, `timeunit`×6 |
| `replay/TripShareBatchTest.kt` | SEAM | `stream`×1, `zip`×1, `charset`×1, `io-exception`×1 |
| `util/AtomicFilesTest.kt` | SEAM | `file`×3 |
| `util/PlaceNamesTest.kt` | SEAM | `file`×2, `jvm-statics`×3 |
<!-- END GENERATED: tests -->

## C-8 : `app/offline` (généré)

<!-- BEGIN GENERATED: c8 -->
| Fichier (app/offline) | Plan | Lignes | Classe | Bloqueurs | Dép. :core | Dép. app/offline | Dép. :core non déplaçables (A) |
|---|---|---|---|---|---|---|---|
| `CellStore.kt` |  | 189 | SEAM | `android-context`×2, `file`×1, `okhttp`×2, `zip`×1, `android-clock`×5, `dispatchers-io`×2, `hilt-inject`×5, `org-json`×9, `synchronized`×4, `timeunit`×2, `volatile`×3 | util/AtomicFiles | CountingInputStream, ObfStore, PlacesTileStore, PmtilesFiles, PoiPackStore, StorageLocation | AtomicFiles |
| `CountingInputStream.kt` |  | 17 | SEAM | `stream`×1 | - | PmtilesFiles | - |
| `GlyphPackStore.kt` |  | 125 | SEAM | `android-context`×1, `android-log`×2, `file`×1, `okhttp`×2, `zip`×1, `dispatchers-io`×1, `timeunit`×2 | - | StorageLocation | - |
| `LegacyGraphs.kt` |  | 19 | SEAM | `file`×1 | - | - | - |
| `LocalBasemapTiles.kt` |  | 122 | SEAM | `android-log`×3, `file`×1, `okhttp`×7, `lru-map`×2, `math`×2, `synchronized`×2, `volatile`×3 | net/NetHealth | PmtilesFiles, ReleaseRedirects, StreamedPmtiles | NetHealth |
| `MaxspeedOverlayStore.kt` |  | 64 | SEAM | `android-context`×2, `okhttp`×2, `dispatchers-io`×1, `hilt-inject`×5, `org-json`×3, `volatile`×1 | - | - | - |
| `ObfStore.kt` |  | 138 | SEAM | `android-context`×2, `file`×1, `okhttp`×2, `dispatchers-io`×1, `hilt-inject`×5, `org-json`×14, `synchronized`×5, `timeunit`×2 | util/AtomicFiles | PmtilesFiles, StorageLocation | AtomicFiles |
| `OfflineMaps.kt` |  | 148 | SEAM | `android-context`×1, `org-json`×4 | - | - | - |
| `OverlayTileStore.kt` |  | 133 | SEAM | `android-context`×2, `file`×1, `okhttp`×2, `dispatchers-io`×2, `hilt-inject`×5, `org-json`×9, `synchronized`×2, `timeunit`×2 | util/AtomicFiles | CountingInputStream, PmtilesFiles, StorageLocation | AtomicFiles |
| `PlacesTileStore.kt` |  | 611 | SEAM | `android-context`×3, `android-other`×1, `file`×1, `okhttp`×2, `android-clock`×5, `dispatchers-io`×4, `hilt-inject`×7, `math`×1, `org-json`×15, `reflection`×3, `synchronized`×6, `timeunit`×2, `volatile`×3 | util/AtomicFiles | PmtilesFiles, StorageLocation | AtomicFiles |
| `PmtilesFiles.kt` |  | 43 | SEAM | `file`×1, `okhttp`×2 | platform/AndroidLog | - | AndroidLog |
| `PoiPackStore.kt` |  | 260 | SEAM | `android-context`×2, `android-log`×1, `android-sqlite`×4, `file`×1, `okhttp`×2, `zip`×1, `dispatchers-io`×3, `hilt-inject`×5, `org-json`×6, `reflection`×1, `synchronized`×2, `timeunit`×2 | util/AtomicFiles | CountingInputStream, PmtilesFiles, StorageLocation | AtomicFiles |
| `RegionPick.kt` |  | 36 | PURE | - | - | PlacesTileStore | - |
| `ReleaseRedirects.kt` |  | 53 | SEAM | `okhttp`×3, `concurrent-coll`×2, `systime`×1, `time`×1 | - | - | - |
| `RoadNameTileSource.kt` |  | 69 | SEAM | `android-context`×1, `file`×1, `okhttp`×6, `dispatchers-io`×1, `io-exception`×1, `org-json`×3, `systime`×1, `timeunit`×3, `volatile`×2 | - | PmtilesFiles, StorageLocation | - |
| `StorageLocation.kt` |  | 105 | SEAM | `android-context`×1, `android-other`×2, `android-prefs`×1, `file`×1, `reflection`×2 | data/OfflineRoot | PmtilesFiles | OfflineRoot |
| `StreamedPmtiles.kt` |  | 91 | SEAM | `crypto`×1, `okhttp`×6, `concurrent-coll`×2, `format`×1, `timeunit`×1 | - | PmtilesFiles, ReleaseRedirects | - |
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

## C-5 : bilan (à la main)

- En common : `nav/` entier (dont `NavSession`), `i18n/NavStrings`, `voice/SpeechText`, `replay/TripLog`
  et `TripScrub`, `data/naming/`, `RouteGeometry`, `ValhallaRouter`, `RouteBudget`, `RouteEngine`,
  `RouteCorridor`, `OfflinePhrases`, `location/` pur (`SpeedKalman`, `AlongRouteFilter`, `FixRules`,
  `DemoTrace`, `ReplayFix`), `model/SavedRoute` et `GoogleMapsDataSource` (le routeur hybride).
- Restent dans `:core` : `TripShareBatch` (écrit un zip), `Stillness` (capteurs), `NavStringsLocale`
  (pont `java.util.Locale`), `ObfRouteEngine` (OsmAnd, derrière `RouteEngine`), `AndroidGoogleSource`
  et `OkHttpRouteHttp` (clients Android).
- Coutures ajoutées : `NavVoice` (implémentée par `VoiceGuide`), `NavHaptics` (`Haptics`), `RouteHttp`
  (`OkHttpRouteHttp` : un client dérivé par tentative bornée, délais connect/read/write/call).
  Utilitaires : `gunzip` (zlib sur iOS), `LruMap`, `LockedMap`, `LockedList`, `monotonicNanos`.
- `NavStrings` : `language` et `region` en clair (« he », pas « iw ») ; `javaLocale` côté Android
  redonne le code historique.

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
