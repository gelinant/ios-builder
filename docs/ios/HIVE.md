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
| V-1 remontée minimale (recherche) | en cours | `ios/v1-search-core` | |
| C-1 mécanique (hors V-1) | en cours | `ios/c1-mechanical` | |
| F-2 coutures de base | en cours | `ios/f2-seams` | |
| F-3a coquille iOS + IPA (Swift seul) | fait, mergé : **M1** | `ios/f3a-ios-shell` | IPA 3,2 Mo, carte OK sur simulateur ; à tester sur iPhone |
| F-3b `:ios-shared` + VelaCore.framework | en cours | `ios/f3b-ios-shared` | |
| W-2 spike WKWebView | en cours | `ios/w2-webview-spike` | |
| I-8a script de chaînes | fait, mergé | `ios/i8a-strings` | 1415 clés, 24 langues ; à vérifier sur Mac : `%d` vs `%ld`, `area_pick_cells` |

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
