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
| V-2 recherche iOS (M2) | attend F-3b | | |
| C-1 mécanique (hors V-1) | fait, mergé | `ios/c1-mechanical` | 12 fichiers devenus PURE ; `NavStrings` et `java.time` reportés au déplacement (C-5) |
| F-2 coutures de base | fait, mergé | `ios/f2-seams` | 7 coutures + `CoreGraph`, impl. Android dans `core/platform`, inutilisées pour l'instant |
| F-3a coquille iOS + IPA (Swift seul) | fait, mergé : **M1** | `ios/f3a-ios-shell` | IPA 3,2 Mo, carte OK sur simulateur ; à tester sur iPhone |
| P-0 carte de la logique de présentation | fait, mergé | `ios/p0-viewmodel-map` | `docs/ios/PRESENTATION-MAP.md` : `MapSession` unique + facettes, ~4,85 k lignes |
| F-3b `:ios-shared` + VelaCore.framework | en cours | `ios/f3b-ios-shared` | |
| W-2 spike WKWebView | fait, mergé : **go I-3** | `ios/w2-webview-spike` | scripts Android inchangés OK ; WebGL plante le GPU du simulateur ; course d'injection aussi présente sur Android |
| I-8a script de chaînes | fait, mergé | `ios/i8a-strings` | 1415 clés, 24 langues ; à vérifier sur Mac : `%d` vs `%ld`, `area_pick_cells` |

## IPA à tester

Toujours la dernière IPA validée par le coordinateur : branche `ipa` du builder,
<https://github.com/gelinant/ios-builder/raw/ipa/Vela-unsigned.ipa> (connecté à GitHub). Le
`README.md` de la branche dit quel build c'est et quoi tester.

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
