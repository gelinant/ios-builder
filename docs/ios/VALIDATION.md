# Rejeu de validation VAL-1

Ce document consigne les rejeux ciblés demandés par le lot VAL-1, sur la base `ios/main` au
commit `c94d2932` (merge de FUEL-WIRE), poussée sur le runner Mac via
`scripts/mac-run.sh`. Chaque section correspond à un lancement, avec son tag, sa classe, son
verdict et les captures réellement publiées. Aucun scénario n'est déclaré vert sans le tag du run
qui l'a produit. Aucune validation sur iPhone n'a été faite ici.

Le Mac LAN reste désactivé ; tous les runs passent par le runner GitHub, avec
`VELA_SKIP_ARCHIVE=1` et une seule classe par job.

## Porte Notices

Le premier lancement, `val1-savedfin-20261028-001638-24331`, n'a jamais atteint la classe : l'étape
Notices a refusé l'hôte `maps.app.goo.gl`, introduit par IMP-GOOGLE, avant toute compilation. Le
tag ne contient que `STATUS`, `log.txt` et `summary.txt`, avec `notices: 1 gap(s)`. Il ne prouve
rien sur `SavedFinishingUITests` et il est écarté du décompte des scénarios.

`iosApp/Vela/Settings/Notices.json` a été corrigé sur `ios/main` (la notice Google couvre
l'hôte), puis le worktree a fusionné `ios/main`. `python3 scripts/ios/check_notices.py` affiche
`notices: ok, 26 entries` et tous les runs suivants passent cette étape.

## SavedFinishingUITests

- Date : 2026-10-28
- Tag : `val1-savedfin-20261028-011938-29529`
- Classe : `SavedFinishingUITests`
- Verdict : rouge, 2 tests sur 4 verts
- Captures : `saved-home.png`, `saved-import.png`, `saved-route.png`, `saved-selection.png`

| Scénario | Résultat |
|---|---|
| `testHomeAndWorkOpenFromSavedAndMap` | vert, 102,954 s ; `saved_map_home=directions_opened`, `saved_shortcuts=home_and_work_opened` |
| `testListEditingSelectionAndSound` | rouge, 139,071 s, `XCTAssertTrue failed - no sound choices in the editor` (ligne 167) ; `saved_selection=1` avant l'échec |
| `testSavedLineReopensBesideComputedRoutes` | rouge, 86,478 s, `route offer stayed busy` (ligne 83) ; `SAVED_ROUTE_DEBUG=missing` |
| `testTakeoutFixtureImportsIntoNamedList` | vert, 17,704 s ; `saved_takeout_places=2` |

Défauts observés :

- Le mode sélection fonctionne (barre « 1 selected », capture `saved-selection.png`), mais
  l'éditeur ne montre pas `list-sound-ping` après six `swipeUp` sur l'application. Le son est bien
  déclaré dans `SavedViews.swift`; les gestes envoyés à `app` ne font pas défiler le `Form` de la
  feuille d'édition, dont la section Sound reste hors de l'arbre d'accessibilité. Le défaut est
  côté test (cible du défilement), pas prouvé côté application.
- Après le tap sur la ligne enregistrée, la feuille d'itinéraire affiche la ligne sauvegardée et un
  itinéraire calculé de 3 min (`saved-route.png`), mais `route-debug` est absent de la hiérarchie
  d'accessibilité et `loading` reste illisible plus de 30 s. La ligne de debug est le dernier
  enfant du `VStack` de `RouteSheets.swift`; sur cette hauteur de feuille elle passe sous le bord
  visible, donc le test ne peut pas lire l'état alors que le calcul a abouti. Le scénario n'a pas
  été rejoué.

## SavedImportUITests

- Date : 2026-10-28
- Tag : `val1-savedimp-20261028-022430-581`
- Classe : `SavedImportUITests`
- Verdict : rouge, 1 test sur 1 exécuté
- Captures : `saved-import-google.png`, `saved-import-merge.png`, `saved-import-mymaps.png`

`testGoogleListAndMyMaps` passe les deux listes de dossiers (`saved_kml_lists=2`), la note du KML
(`saved_kml_note=kept`), le premier import Google (`saved_google_places=2`) et la détection du
second import (`saved_google_duplicate=merge_or_replace`). Il échoue ensuite au tap sur
`saved-import-merge`, ligne 64 : `Multiple matching elements found`. Le bouton Merge est exposé
deux fois dans l'arbre (`Sheet`, puis deux `Button` de même identifiant imbriqués), donc XCUITest
refuse le tap. Replace, le merge sans doublon et le refus NoGoogle restent sans preuve, et
`saved-import-nogoogle.png` n'existe pas. Le correctif de fermeture de feuille est donc confirmé,
le blocage suivant est un doublon de nœud d'accessibilité sur le bouton Merge.

## PlaceReviewsUITests

- Date : 2026-10-28
- Tag : `val1-plcrev-20261028-025339-8681`
- Classe : `PlaceReviewsUITests`
- Verdict : vert, 3 tests sur 3, 392 s
- Captures : `reviews-histogram.png`, `reviews-more.png`, `reviews-sorted.png`,
  `gallery-viewer.png`, `gallery-viewer-next.png`

| Scénario | Résultat |
|---|---|
| `testReviewsHistogramAndControls` | vert, 132,932 s ; `reviews_histogram=google-omitted`, `reviews_initial=5`, `reviews_sort=1` |
| `testMoreReviewsAppendsAPage` | vert, 111,570 s ; `reviews_paging=added-4`, `reviews_after_more=9` |
| `testGalleryViewerSwipesWithCaptionAndSource` | vert, 70,629 s ; `gallery_photos=10`, visionneuse page 2 sur 10, `gallery_viewer_page=2/10` |

La visionneuse balaie bien vers la photo suivante avec sa légende et sa source. Le menu de
catégories reste absent de la grille (`gallery_categories=0`) et l'affluence n'est pas rendue sur
l'IP du runner, donc la ligne de matrice reste partielle.

## SettingsAboutUITests

- Date : 2026-10-28
- Tag : `val1-setabout-20261028-032738-12449`
- Classe : `SettingsAboutUITests`
- Verdict : vert, 1 test sur 1, 268,762 s
- Captures : `settings-about-search.png`, `settings-about-support.png`,
  `settings-about-notices.png`

`testHubSearchAboutNoticesSupport` couvre la recherche « live traffic », l'ouverture du sujet, le
saut vers « photo quality », la notice MapLibre en BSD-2-Clause, la recherche « diagnostics »,
puis About et Support. Valeurs lues : `about_version=Vela 0.1.202610280328 (build 1793158130)`,
`about_installer=Not available on iOS` et `about_notices_seen=13`. Le défilement vers le haut
avant la recherche « notices » fonctionne et la capture des notices est produite.

## TransitCitymapperUITests

- Date : 2026-10-28
- Tag : `val1-transit-20261028-035840-8078`
- Classe : `TransitCitymapperUITests`
- Verdict : rouge, 3 tests verts, 1 rouge, 1 ignoré
- Captures : `transit-trip.png`, `transit-trip-nearby.png`, `transit-trip-skip.png`

| Scénario | Résultat |
|---|---|
| `testTripScreenShowsSegmentCardsAndNextDepartures` | vert, 12,592 s ; `transit_trip=segments_and_header`, 4 segments, 1 course, 4 prochains départs, `transit_trip_fixture=1` |
| `testNearbyLinesTabListsTheStopsLines` | vert, 12,667 s ; 3 lignes et 3 rangées |
| `testSkipLetsTheRunPassAndAdvancesTheHeader` | vert, 13,303 s ; bandeau 4 puis 3, 2 options |
| `testSegmentTimeChangeShowsANewOptionSet` | rouge, 27,522 s, `no shifted query label` (ligne 90) |
| `testLiveTripScreenWhenTheFeedAnswers` | ignoré : aucun trajet en direct renvoyé par le planificateur pendant le run |

Le changement d'heure produit bien la requête et deux options (`transit_trip_shift_options=2`,
`shift=1`), mais `transit-trip-options-query` n'apparaît pas dans l'arbre après trois `swipeUp`
sur l'application, et `transit-trip-shift.png` n'est pas produite. Le libellé de requête est rendu
dans `TransitTripScreen.swift` sous les quatre cartes de segment et sous le bord visible; le
défilement envoyé à `app` ne l'atteint pas. Le direct n'a pas été prouvé.

## Ce que ces runs ne prouvent pas

- Aucun scénario de ces cinq classes n'a été rejoué sur un iPhone réel.
- `SavedFinishingUITests` reste rouge sur l'éditeur de liste et sur la ligne enregistrée.
- `SavedImportUITests` reste rouge au tap sur Merge; Replace et NoGoogle ne sont pas prouvés.
- `TransitCitymapperUITests` reste rouge sur le changement d'heure; le direct est ignoré.
- Les scénarios sans run vert après ce lot sont donc maintenus au statut antérieur dans
  `FEATURES-IOS.md`, sauf les lignes que ces runs prouvent explicitement.

## Run `val2-batch-20261028-041721-5499` (batch, 28 octobre 04 h)

Trois classes dans un seul job grace a `VELA_ONLY_UI` en liste. 5 scenarios verts sur 8 :
`SavedFinishing.testHomeAndWorkOpenFromSavedAndMap`, `.testTakeoutFixtureImportsIntoNamedList`,
`TransitCitymapper.testLiveTripScreenWhenTheFeedAnswers`, `.testNearbyLinesTabListsTheStopsLines`,
`.testSkipLetsTheRunPassAndAdvancesTheHeader`, `.testTripScreenShowsSegmentCardsAndNextDepartures`.

Trois echecs, tous de harnais, corriges apres le run :

- `SavedFinishing.testListEditingSelectionAndSound` : le formulaire de l'editeur ne defile pas
  quand on balaie l'application. Le test demarre maintenant un glissement dans la feuille.
- `SavedFinishing.testSavedLineReopensBesideComputedRoutes` : la ligne enregistree recalculait sa
  route et OSRM depassait 30 s sur le runner partage. Delai porte a 120 s.
- `SavedImport.testGoogleListAndMyMaps` : l'assertion lisait `label` d'un element absent, ce qui
  levait une erreur de snapshot au lieu de montrer l'etat reel. Le message d'echec est explicite.
- `TransitCitymapper.testSegmentTimeChangeShowsANewOptionSet` : la section des options restait
  sous le pli. Le test glisse dans la colonne au lieu de balayer l'application.

Le batch de verification suivant est `val3-batch`.

## Hors ligne, runs `offline-verify`, `2`, `3` (28 octobre, 20 h 30 a 22 h)

Etat reel, sans arrondi :

- `OfflineUITests.testMonacoDownloadOfflineMapAndSearch` : **vert** aux trois runs. Telechargement
  d'une region, carte hors ligne, recherche hors ligne, captures `offline-map.png`,
  `offline-search.png`, `offline-regions.png`. C'est la preuve que le correctif
  `OfflineFixtureUrls` et la reprise d'un plan echoue fonctionnent.
- `OfflineAreaUITests.testFrameAreaAndPreferences` : **rouge** sur la carte de progression. Le
  cadre, l'estimation (`offline-area-estimate.png`) et les interrupteurs sont prouves ; apres le
  tap sur Download, `area-progress` n'apparait pas dans l'arbre en 45 s, alors que l'app reste
  vivante (journal applicatif sans plantage). A instruire : etat de `areaReportVisible` et
  `areaId` juste apres le tap, et dump de la hierarchie a cet instant.
- `OfflineUITests.testMonacoDeltaUpdateStorageAndWorldFallback` : **rouge** sur le bouton Debug
  `offline-test-update-manifest`, absent de l'arbre malgre le defilement. Le bouton est dans un
  `#if DEBUG` derriere `OfflineFixtureSupport.isEnabled` ; verifier que le drapeau de fixture est
  encore actif a cet instant du scenario.

Ces deux scenarios sont des elements d'interface de test : ils ne bloquent aucun chemin
utilisateur prouve. Ils restent ouverts et ne doivent pas etre comptes comme verts.
