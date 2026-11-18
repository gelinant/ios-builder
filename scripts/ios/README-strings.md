# Chaînes Android vers String Catalog iOS

`strings_to_xcstrings.py` lit `app/src/main/res/values*/` et écrit un `Localizable.xcstrings`
(format String Catalog de Xcode 15+). Python 3, bibliothèque standard seule. Le fichier généré
n'est pas versionné : le build iOS le produit.

```
python3 scripts/ios/strings_to_xcstrings.py --out Localizable.xcstrings --report
python3 scripts/ios/strings_to_xcstrings.py --keys ios-keys.txt --out build/Localizable.xcstrings
python3 -m unittest scripts/ios/test_strings_to_xcstrings.py
```

Options : `--res` (défaut `app/src/main/res`), `--out` (`-` pour stdout), `--keys` (liste
blanche, une clé par ligne, `#` pour commenter ; un nom de `string-array` prend tous ses
éléments), `--report` (comptes par langue, éléments écartés, avertissements, sur stderr).

## Choix

- **Langues** : `values` = `en` (source). `values-xx-rYY` → `xx-YY`, `values-b+sr+Latn` →
  `sr-Latn`. Codes hérités : `iw` → `he`, `in` → `id`, `ji` → `yi`. Chinois : Xcode ne propose
  que `zh-Hans`, `zh-Hant` et `zh-HK`, donc `values-zh` et `zh-rCN` → `zh-Hans`, `zh-rTW` →
  `zh-Hant`. `values-pt` (portugais européen, à côté de `pt-rBR`) → `pt-PT`. `en-GB` retombe sur
  `en` côté iOS comme sur Android. Dossiers avec un autre qualificatif (`values-night`,
  `values-fr-land`) : ignorés, signalés s'ils contiennent des chaînes.
- **Valeurs** : décodées comme aapt2 (échappements `\' \" \\ \n \t \@ \? \uXXXX`, entités,
  CDATA, guillemets qui gardent les espaces, espaces fusionnés, bords coupés). Balises en ligne
  (`<b>`, `<i>`, `<u>`, `xliff:g`) aplaties en texte et comptées.
- **Formats** : `%s` → `%@`, `%1$s` → `%1$@`, `%n` → saut de ligne ; `%d` → `%ld` et
  `%1$d` → `%1$ld` car un `Int` Swift est un `CLong` 64 bits ; `%.1f`, `%%` inchangés.
  `formatted="false"` : copié tel quel, ne pas le passer à `String(format:)`.
- **`translatable="false"`** : seulement en `en`, avec `shouldTranslate: false` ; une traduction
  éventuelle est écartée (aujourd'hui `app_name` en ja, zh-Hans, zh-Hant, même valeur).
- **Pluriels** : `variations.plural` au niveau de la chaîne quand le compte est le premier
  argument (Foundation accorde sur le premier argument). Sinon (`area_pick_cells`, compte en
  `%2$d`) : substitution `%#@count@` avec `argNum` = position du compte et `%arg` dans les
  variantes. Le compte est le premier argument entier. `zero` est retiré sauf pour les langues
  CLDR qui ont cette catégorie (Apple l'applique à 0 partout, Android l'ignore ailleurs).
- **`string-array`** : clés indexées `nom[0]`, `nom[1]`... (aucune dans le dépôt aujourd'hui).
  Une valeur `@string/x` est résolue dans la langue, puis en `en`.
- Toutes les clés ont `extractionState: manual` pour que Xcode ne les marque pas obsolètes.
- Sortie stable : clés triées, indentation de deux espaces, séparateur ` : ` comme Xcode.

## Vérifications sur Mac (I-8)

`VelaTests/LocalizationTests.swift` exerce les vraies chaînes du catalogue : `%ld` avec un `Int`
64 bits et la substitution de `area_pick_cells`, dont le compte est l'argument 2 et l'argument 1
n'apparaît que dans les variantes. `kmr` (kurde kurmandji), absent des langues système iOS, reste
disponible dans le réglage de langue intégré à Vela ; Xcode produit `ku.lproj`, que `VelaL10n`
recherche explicitement.
