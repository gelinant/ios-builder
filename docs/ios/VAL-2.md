# Passe de sante VAL-2 de la suite UI iOS

Passe du 29 au 30 octobre 2026 sur `ios/main` au commit `9b4e66e5`. Aucun code Swift ni
Kotlin n'a ete modifie. Les quatre lots ont ete lances l'un apres l'autre, en avant-plan, via
`~/gmaps/ios-builder/scripts/mac-run.sh` avec `VELA_SKIP_ARCHIVE=1`. Le Mac LAN n'a pas ete
appele : `scripts/ios/lan-mac.sh` sort toujours 3.

Les resultats viennent de la branche `results` du runner. Chaque tag contient `log.txt`,
`summary.txt`, `app-log.txt` et les captures du lot.

## Methode et tags

| Lot | Tag | Classes demandees | Tests executes |
|---|---|---|---|
| B1 | `val2-b1-20261029-211557-25568` | 14 | 22 |
| B2 | `val2-b2-20261029-222047-32353` | 11 | 23 |
| B3 | `val2-b3-20261029-233144-24628` | 16 | 34 |
| B4 | `val2-b4-20261030-005900-29239` | 20 | 44 |

Deux classes demandees n'existent pas dans `iosApp/VelaUITests/` et sont retirees :

- `TerrainUITests` (B1) : seul `scripts/ios/ci-terrain-spike.sh` couvre le terrain.
- `TransitMapUITests` (B4) : la carte des lignes est couverte par `TransitLineViewUITests` et
  `TransitWiredUITests`.

Resultat brut : 123 tests, 99 verts, 24 rouges.

| Lot | Executes | Verts | Rouges |
|---|---|---|---|
| B1 | 22 | 20 | 2 |
| B2 | 23 | 17 | 6 |
| B3 | 34 | 30 | 4 |
| B4 | 44 | 32 | 12 |
| Total | 123 | 99 | 24 |

Note de lecture : `Map3DUITests.testBuildingsPitchAndRelief` a bien tourne et passe en 162,768 s
dans B1, mais `summary.txt` ne reprend pas sa ligne. La preuve est dans
`xcodebuild-uitest.log` (« Executed 1 test, with 0 failures »). `TransitWiredUITests` n'apparait
pas non plus dans `summary.txt` : son lanceur plante avant le premier test (voir plus bas).

## Tableau des echecs

| Classe / test | Tag | Assertion | Preuve (log, capture, hierarchie) | Categorie | Prochaine action |
|---|---|---|---|---|---|
| `GlobeUITests.testSwitchToGlobeAndBack` | B1 | `:86 the downloaded region did not mount: none` | La region fictive est installee (`offline-installed-monaco` et `offline-ready` trouves a t=191,82 s et 195,21 s), le blocage reseau est touche (t=197,44 s), la feuille fermee (t=198,32 s), puis `offline-map-debug` reste absent pendant 60 s. `offline-map-debug` renvoie `none`, donc pas `remote>0`. | harnais | Attendre `offline-debug map=<octets>` superieur a 0 avant de couper le reseau, puis relancer la classe seule avec une capture de la feuille hors ligne. |
| `WorldLayersUITests.testWorldLayersStartHidden` | B1 | `:30 aviation must stay disabled while not installed` | `AviationLayerUITests` tourne avant dans le meme lot, installe la couche et la laisse sur `on`. La ligne `layers-debug` des autres tests du lot affiche `world_layers=4 world_on=1`. `-VelaResetSettings` ne remet pas les couches installees a zero. | harnais | Ajouter une remise a zero de l'etat des couches monde entre classes, ou demarrer la classe sur un conteneur neuf. |
| `SavedFinishingUITests.testListEditingSelectionAndSound` | B2 | `:263 Failed to synthesize event: Neither element nor any descendant has keyboard focus` | Le champ `saved-name-field` existe a `{{32.0, 77.7}, {338.0, 22.0}}` et porte deja `UI Finish`. `replaceText` ne tape pas le champ quand `app.keyboards.count` est non nul, meme si le focus est sur un autre champ. | harnais | Tester `hasKeyboardFocus` sur le champ lui-meme, pas la presence globale du clavier, et refaire le tap coordonnee tant que le champ n'a pas le focus. |
| `SavedFinishingUITests.testSavedLineReopensBesideComputedRoutes` | B2 | `:75 saved route row missing` | Le nom est tape dans `saved-name-field` sans verifier le focus ni la valeur, puis `saved-name-save` est touche et huit `swipeUp` sur l'application ne trouvent pas la ligne. La classe utilise ailleurs `replaceText` justement parce que le premier tap d'une feuille fraiche est perdu. | harnais | Reutiliser `replaceText`, asserter la valeur du champ et la creation de la ligne avant de la chercher. |
| `SearchCommandUITests.testTypedAndSpokenCommands` | B2 | `:146 wrong command kind: none` | `waitUntil` voit bien `cmd_kind=directions` a t=44,02 s, puis `reportKind` relit la ligne a t=47,49 s, apres l'ouverture de la fiche, et obtient une ligne sans `cmd_kind`. Le parseur a donc classe la commande. | harnais | Lire la ligne une seule fois et passer la valeur a `reportKind` au lieu de la relire apres l'ouverture de la fiche. |
| `SearchUITests.testAddressSearchMergesWithoutDuplicateRows` | B2 | `:171 Google and Photon did not return the typed house number` | Les lignes `search-result` existent des t=13,21 s, mais aucune ne porte `1 Ferry Building` pendant 30 s. Aucun rapport `address_hits` n'est produit. La meme requete Photon rendue en direct renvoie bien `housenumber=1, street=Ferry Building`. | environnement | Rejouer la classe seule en conservant les reponses Google et Photon brutes, et journaliser le nombre de lignes retenues par source. |
| `SearchUITests.testPhotonAddressSearchShowsTheTypedHouseNumber` | B2 | `:226 neither Google nor Photon returned the typed house number` | Meme requete, meme absences, 130,8 s. Les lignes existent mais aucune ne porte le numero tape. `testNoGoogleSearchReturnsPhotonRows` passe dans le meme lot, donc Photon repond pour « Ferry Building » sans numero. | environnement | Meme rejeu que ci-dessus, avec `photon_address_hits` lu avant l'assertion. |
| `UnifiedSearchUITests.testFindSavedTransitWikiSettingAndPlace` | B2 | `:160 no place row: offline=0 results=0 suggestions=8 area=0 dropped=0 searches=0 unified=11 ulocal=12ms` | La recherche n'est pas soumise (`searches=0`, `results=0`) et les 8 suggestions sont locales : aucune ligne `search-suggestion` de valeur `network` en 90 s. Les etapes wiki, reglage et coordonnee passent avant. | environnement | Rejouer seul, journaliser le nombre de suggestions reseau et le code de la reponse d'autocompletion Google. |
| `NavArrivalUITests.testWaypointArrivalParkingAndEnd` | B3 | `:29 no driving route: routes=2 active=0 mode=DRIVE loading=0 seconds=491 meters=3482 steps=6` | La route est prete (`routes=2`, `loading=0`) au moment exact ou l'attente de 120 s expire. Le meme scenario avait deja echoue juste avant l'echeance dans BUG-HUNT. | flake | Porter l'attente a 180 s et rejouer ; la route arrive apres la limite. |
| `NavBannerUITests.testLanesShieldPreviewAndPerStopEta` | B3 | `:58 the swipe did not open the step preview: preview=-1 ... navlanes=0` | Le `swipeLeft` est synthetise sur `nav-banner` a t=58,16 s, mais `preview` reste a -1 et `nav-preview-hint` n'apparait pas. Les voies, le bouclier et l'ETA par arret passent avant le geste. | harnais | Remplacer `swipeLeft` par un glissement coordonnee de plus de 110 points, comme les autres gestes de la suite, et journaliser `bannerOffset`. |
| `PlaceFuelUITests.testClosingTimeCard` | B3 | `:34 no closing countdown` | Le test demarre a 00:20:32 (log). La fixture ferme 25 min plus tard, soit 00:45, rendu `12:45 AM`. `ClosingTime.closingMinuteOfDay` transforme tout `12:xx AM` en `24:xx` (`!pm && h == 12 -> 24`), soit 1485 minutes, donc jamais « closing soon ». | produit | Traiter `12:xx AM` comme 0:xx, et garder 24:00 uniquement pour `12:00 AM` pile. |
| `PlaceReviewsUITests.testSwipeKeepsThePanelResponsive` | B3 | `:132 Failed to get matching snapshots: Timed out while evaluating UI query` | Apres un seul `swipeUp` sur `place-reviews-scroll`, « App event loop idle notification not received » a t=97,45 s, puis trois requetes XCUITest expirent (128,48 s, 159,53 s). Aucune capture `reviews-swipe.png` n'est produite. La classe `PlaceReviews` perd 1 test sur 4. | produit | Ferme par `REVIEWS-REG`, run `reviews-reg-20261030-031615-22545` : la page d'affluence etait creee pendant le balayage. Voir la section Correctif REVIEWS-REG. |
| `AppearanceUITests.testThemesSpeedAndVehicle` | B4 | `:66 XCTAssertTrue failed - ... unit=imperial` | La ligne lue est `theme=dark look=bright map=dark icon=large label=xl speed=1 unit=imperial vehicle=ufo detail=compact`. Le test attend encore `unit=mph`. | harnais | Asserter `unit=imperial`, deja recommande par BUG-HUNT. |
| `IncomingLinksUITests.testIncomingDirectionsLinkWithTwoStopsKeepsTheirOrder` | B4 | `:56 the first stop is not in the chooser` | Le chooser compact est ouvert avec la destination, les modes et Start, sans ligne d'arret. `DirectionsUITests.testWaypointAndDepartureTime` deplie la feuille avant de chercher les arrets et passe. | harnais | Corrige le 30 octobre (`ios/harness-2`, `harness-2-20261030-021429-28682`) : depliage puis `reveal` dans `route-sheet`. |
| `IncomingLinksUITests.testIncomingDirectionsLinkWithOneStopOpensIt` | B4 | `:76 the link's stop is not in the chooser` | Meme chooser compact, meme absence. | harnais | Corrige le 30 octobre (`ios/harness-2`, `harness-2-20261030-021429-28682`) : meme depliage puis `reveal`. |
| `IntentsUITests.testDeepLinkOpensSavedPlace` | B4 | `:38 XCTAssertEqual failed: ("nil") is not equal to ("Optional("route=place error=0")")` | Le lieu s'ouvre avec le bon nom, puis `intents-debug` est illisible : `MapScreen` masque le bloc debug des que la fiche lieu est ouverte. | harnais | Corrige le 30 octobre (`ios/harness-2`, `harness-2-20261030-021429-28682`) : `intents-debug` passe dans la couche invisible et `debugValue` le lit fiche ouverte. |
| `IntentsUITests.testParkingDeepLinkOpensPlaceAndCleansUp` | B4 | `:69 XCTAssertEqual failed: ("nil") is not equal to ("Optional("route=parking error=0")")` | Meme bloc debug masque par la fiche. | harnais | Corrige le 30 octobre (`ios/harness-2`, `harness-2-20261030-021429-28682`) : meme couche invisible, `debugValue`. |
| `LocalizationUITests.testFrenchTransitWorldAndSearchSurfaces` | B4 | `:122 no search-everywhere row` | Les couches monde francaises passent. Apres `typeText("coffee")`, la ligne `unified-search-everywhere` n'existe pas en 20 s. Le test ne verifie ni le focus ni le contenu du champ et ne defile pas le panneau. | harnais | Corrige le 30 octobre (`ios/harness-2`, `harness-2-20261030-021429-28682`) : valeur du champ assertee, puis `reveal` dans `search-suggestions`. |
| `OfflineAreaUITests.testFrameAreaAndPreferences` | B4 | `:87 the area download did not install its region` | La progression apparait (`area_progress_seen=1`), se termine a `area_pct=100 pieces=5/5`, puis `offline-installed-monaco` et `area-sheet-ready` restent absents 30 s. La feuille hors ligne ne liste pas la region telechargee. | produit | Journaliser `areaReady`, `completedId` et les regions installees apres la fin, puis corriger l'enregistrement de la region. |
| `OfflineUITests.testMonacoDeltaUpdateStorageAndWorldFallback` | B4 | `:143 update was not offered after rev 2` | Le bouton de manifeste est trouve et touche, la region fictive est installee (`offline_fixture_world=1`), mais `offline-update-monaco` reste absent. `reveal` ne fait que `swipeUp` alors que la carte de mise a jour est au-dessus du catalogue. | harnais | Corrige le 30 octobre (`ios/harness-2`, `harness-2b-20261030-025719-28692`) : `reveal` vers le haut dans `offline-sheet`, apres avoir rendu la ligne de suppression atteignable. |
| `OfflineUITests.testMonacoDownloadOfflineMapAndSearch` | B4 | `:78 XCTAssertTrue failed` (`offline-test-block` absent) | La region reelle s'installe et `offline-regions.png` montre « Monaco is ready ». Apres la relance, la feuille ne montre que Done : les boutons Debug de la barre (`offline-test-block`, `offline-test-reset`) ont disparu. | harnais | Verifier que `app.launch()` apres `terminate()` repasse bien `-VelaOfflineTest YES`, ou relancer avec des arguments explicites. |
| `PrivacyUITests.testRequestCounterAndClearHistory` | B4 | `:230 the Debug line still counts requests after the clear: none` | Le compteur passe de 8 a 0 et `privacy-counter-cleared` est capture. `settings-debug` renvoie `none` : la ligne est la premiere section du `Form`, le test a defile jusqu'a la page Privacy et ne remonte pas. | harnais | Corrige le 30 octobre (`ios/harness-2`, `harness-2c-20261030-033716-10838`) : `scrollTo` vise les `Form` nommes et `reveal` remonte jusqu'a `settings-debug`. |
| `TransitTimeUITests.testTimeEverywhere` | B4 | `:146 no options sheet` | Le tap sur `transit-options-open` donne `Computed hit point {-1, -1} after scrolling to visible` a t=112,37 s. Le bouton existe mais n'a aucun point de toucher, donc la feuille ne s'ouvre pas. | produit | Rendre `transit-options-open` atteignable dans la feuille d'itineraire, puis asserter `isHittable` avant le tap. |
| `TransitWiredUITests.testTapTransitEverywhereAndSeeTheLine` | B4 | `VelaUITests/VelaUITestCase.swift:79: Fatal error: Unexpectedly found nil while implicitly unwrapping an Optional value` | `wired_line_departures=0`, puis le lanceur plante. La suite redemarre et affiche « Executed 0 tests ». `launchWired()` construit un `XCUIApplication` local sans assigner `self.app`. | harnais | Assigner `self.app = app` dans chaque lanceur local, ou proteger `debugText` par `guard let app`. |

## Correctif de harnais du 30 octobre (`ios/harness-2`)

Le helper partage `reveal(_:in:)` remplace les defilements disperses. Il resout le conteneur de
defilement par l'identifiant de la feuille, dans cet ordre : une `ScrollView`, `CollectionView` ou
`Table` qui porte cet identifiant ; sinon le premier conteneur de defilement a l'interieur de la
racine nommee (couvre le `Form` de Reglages, la `List` hors ligne et `route-scroll` dans
`route-sheet`) ; sinon la racine elle-meme si elle est assez haute pour un glissement. Sans
conteneur, il ne balaie rien : il ne touche jamais l'application derriere la feuille. Il repete le
geste jusqu'a ce que l'element existe **et** soit hittable, avec une direction `forward` par defaut
et `backward` pour remonter a une carte situee au-dessus. `debugValue(_:)` lit une ligne debug
avant l'ouverture d'une feuille, ou depuis la couche invisible de la carte quand elle existe.

`intents-debug` rejoint `tap-chain-debug`, `layers-debug` et `transit-debug` dans cette couche
invisible : la fiche lieu ne le masque plus. Aucun autre code applicatif n'a change.

| Tag | Classes | Executes | Verts | Rouges |
|---|---|---|---|---|
| `harness-2-20261030-021429-28682` | IncomingLinks, Intents, Localization, Privacy, Offline | 24 | 21 | 3 |
| `harness-2b-20261030-025719-28692` | Privacy, Offline | 7 | 5 | 2 |
| `harness-2c-20261030-033716-10838` | Privacy | 5 | 5 | 0 |

Les sept echecs harnais du tableau passent maintenant :

- `IncomingLinksUITests.testIncomingDirectionsLinkWithTwoStopsKeepsTheirOrder` et
  `testIncomingDirectionsLinkWithOneStopOpensIt` : le chooser est deplie, puis les arrets sont
  reveles dans `route-sheet` ; l'ordre et le nombre de lignes sont toujours verifies.
- `IntentsUITests.testDeepLinkOpensSavedPlace` et `testParkingDeepLinkOpensPlaceAndCleansUp` : la
  ligne `intents-debug` est lue par `debugValue` depuis la couche invisible, avec la meme egalite
  exacte qu'avant.
- `LocalizationUITests.testFrenchTransitWorldAndSearchSurfaces` : la valeur du champ est assertee,
  puis `unified-search-everywhere` est revele dans `search-suggestions`.
- `OfflineUITests.testMonacoDeltaUpdateStorageAndWorldFallback` : la ligne de suppression des
  places est rendue atteignable, puis la mise a jour est revelee vers le haut dans `offline-sheet`.
  Le test passe en 145 s, avec `offline_update_deltas=2` et `offline_update_full=0`.
- `PrivacyUITests.testRequestCounterAndClearHistory` : `scrollTo` vise `settings-screen` et
  `privacy-screen` au lieu de `scrollViews.firstMatch`, et la lecture de `settings-debug` remonte
  le `Form`. A zero, la page remplace le total par `privacy-counter-none` ; le test accepte les
  deux formes, ce qui prouve toujours que le compteur est vide.

Reste rouge dans ce lot, hors des sept : `OfflineUITests.testMonacoDownloadOfflineMapAndSearch`
echoue desormais a `:26` sur la hauteur de `offline-area-start`, 42,2 pt au lieu de 44 pt. C'est un
defaut de cible de toucher, pas un defaut de defilement, et il est anterieur au helper.

## Compte par classe

| Classe | Lot | Verts | Rouges |
|---|---|---|---|
| `AppearanceUITests` | B4 | 0 | 1 |
| `AviationLayerUITests` | B1 | 1 | 0 |
| `BikeProfileUITests` | B3 | 1 | 0 |
| `DirectionsUITests` | B3 | 7 | 0 |
| `EnergyRadarUITests` | B1 | 1 | 0 |
| `FreeDriveUITests` | B3 | 1 | 0 |
| `GlobeUITests` | B1 | 0 | 1 |
| `IncomingLinksUITests` | B4 | 4 | 2 |
| `IntentsUITests` | B4 | 3 | 2 |
| `LaunchUITests` | B1 | 2 | 0 |
| `LocalizationUITests` | B4 | 3 | 1 |
| `Map3DUITests` | B1 | 1 | 0 |
| `MapChromeUITests` | B1 | 1 | 0 |
| `MapGestureUITests` | B1 | 4 | 0 |
| `MapLayersUITests` | B1 | 6 | 0 |
| `MapPoiUITests` | B1 | 1 | 0 |
| `MapTapUITests` | B1 | 1 | 0 |
| `MaritimeUITests` | B1 | 1 | 0 |
| `NavAlertsUITests` | B3 | 3 | 0 |
| `NavArrivalUITests` | B3 | 0 | 1 |
| `NavBannerUITests` | B3 | 3 | 1 |
| `NavCameraUITests` | B3 | 1 | 0 |
| `NavLifecycleUITests` | B3 | 2 | 0 |
| `NavRenderUITests` | B3 | 1 | 0 |
| `NavRobustnessUITests` | B3 | 1 | 0 |
| `NavStopsUITests` | B3 | 1 | 0 |
| `NavUITests` | B3 | 1 | 0 |
| `OfflineAreaUITests` | B4 | 0 | 1 |
| `OfflineUITests` | B4 | 0 | 2 |
| `PlaceFuelUITests` | B3 | 1 | 1 |
| `PlaceKnowledgeUITests` | B1 | 1 | 0 |
| `PlaceObscuraUITests` | B3 | 2 | 0 |
| `PlaceReviewsUITests` | B3 | 3 | 1 |
| `PlaceUITests` | B3 | 2 | 0 |
| `PrivacyUITests` | B4 | 4 | 1 |
| `SavedExportUITests` | B2 | 2 | 0 |
| `SavedFinishingUITests` | B2 | 2 | 2 |
| `SavedImportUITests` | B2 | 1 | 0 |
| `SavedUITests` | B2 | 1 | 0 |
| `SearchAreaUITests` | B2 | 1 | 0 |
| `SearchBranchUITests` | B2 | 1 | 0 |
| `SearchCommandUITests` | B2 | 0 | 1 |
| `SearchFiltersUITests` | B2 | 1 | 0 |
| `SearchUITests` | B2 | 6 | 2 |
| `SettingsAboutUITests` | B4 | 1 | 0 |
| `SettingsUITests` | B4 | 2 | 0 |
| `SettingsVoiceUITests` | B4 | 1 | 0 |
| `StreetViewUITests` | B4 | 1 | 0 |
| `TransitAdvancedUITests` | B4 | 4 | 0 |
| `TransitCitymapperUITests` | B4 | 5 | 0 |
| `TransitGoUITests` | B4 | 1 | 0 |
| `TransitLineViewUITests` | B4 | 1 | 0 |
| `TransitModesUITests` | B4 | 1 | 0 |
| `TransitTimeUITests` | B4 | 0 | 1 |
| `TransitVehiclesUITests` | B4 | 1 | 0 |
| `TransitWiredUITests` | B4 | 0 | 1 |
| `TripsUITests` | B2 | 2 | 0 |
| `UnifiedSearchUITests` | B2 | 0 | 1 |
| `WorldLayersUITests` | B1 | 0 | 1 |

Repartition des 24 echecs : 16 harnais, 4 produit, 3 environnement, 1 flake.

## Trois defauts produit a corriger en premier

1. **Le panneau d'avis fige l'application apres un glissement.** Un seul `swipeUp` dans
   `place-reviews-scroll` suffit : la boucle principale ne repond plus pendant 60 s et XCUITest
   abandonne trois requetes. Impact utilisateur : la fiche d'un lieu devient inutilisable des que
   l'on parcourt ses avis, sur le chemin le plus courant d'une fiche restaurant ou commerce.
   ✅ Ferme par `REVIEWS-REG`, run `reviews-reg-20261030-031615-22545`. La cause n'etait pas le
   panneau : la page cachee des heures d'affluence etait creee sous le panneau pendant le
   balayage, et son DOM restait dans l'arbre d'accessibilite tant qu'elle chargeait.

2. **Le controle des options de transport n'a aucun point de toucher.** `transit-options-open`
   existe dans la feuille d'itineraire mais XCUITest calcule `{-1, -1}` apres le defilement.
   Impact utilisateur : impossible de changer l'heure de depart ou les options d'un trajet en
   transport en commun depuis ce bouton.

3. **Une zone hors ligne telechargee n'apparait pas dans les regions installees.** La progression
   atteint 100 % et 5 pieces sur 5, puis ni `offline-installed-monaco` ni `area-sheet-ready` ne
   sont publies. Impact utilisateur : l'utilisateur croit avoir telecharge une zone qui n'est ni
   listee ni utilisable hors ligne.

Quatrieme defaut, moins large mais reel : **une fermeture a `12:xx AM` n'affiche jamais le
compte a rebours**. `ClosingTime` transforme `12:45 AM` en 24:45, donc un commerce qui ferme a
00:45 ne montre pas « ferme dans 25 min ». Le correctif est local et sans risque.

## Correctif REVIEWS-REG (30 octobre)

Le defaut 1 est ferme par la branche `ios/reviews-reg`, run
`reviews-reg-20261030-031615-22545` (simulateur iPhone 17, iOS 26.5).

Cause mesuree dans le journal de VAL-2 B3 : 0,4 s apres le `swipeUp`, le processus 86002 cree
`popular: view created` pour la page cachee des heures d'affluence, sans aucune reponse avant la
fin du test. La page d'avis, elle, etait bien detruite apres sa reponse. Le gel vient donc de la
page d'affluence, et plus generalement de toute page Google cachee presente pendant un panneau
plein ecran : son DOM reste dans l'arbre d'accessibilite et chaque requete XCUITest le parcourt.

Correctif :

- les panneaux plein ecran d'avis et de galerie suspendent le scrape de details du lieu, et
  annulent son travail en cours, donc aucune page ne nait sous le panneau ;
- les pages d'affluence et de galerie sont detruites des qu'elles ont repondu, comme la page
  d'avis depuis `BUGFIX-REVIEWS` ;
- la WebView cachee vit dans un conteneur hors ecran dont tout le sous-arbre est masque a
  l'accessibilite ;
- la ligne de debug du panneau publie `pages=` avec le nombre de pages cachees vivantes, et le test
  exige zero page apres le geste.

Mesures apres correctif : `reviews_swipe_answer_ms=103`, `mainloop_stall_ms=132` (132 ms avant le
geste), `reviews_swipe_fps=50`, `reviews_live_pages=0`, capture `reviews-swipe.png`, test vert en
28,9 s. Le test mesure la boucle principale, pas seulement le temps de reponse : il lit `stall=`
avant et apres le balayage et exige moins de 1000 ms.

Le lot ne rend pas les autres tests de la classe verts pour autant.
`testMoreReviewsAppendsAPage` reste rouge sur une page Google qui ne rend aucun onglet
(`tabs=[]`, `body=58`) pendant plus de deux minutes, puis sur une requete XCUITest de 30 s. C'est
un etat de page Google, pas le gel du panneau. `PlaceUITests.testDetailsHoursTabsActionsAndRelated`
reste rouge sur `43.999999999999886 < 44.0` pour la cible d'un onglet, un arrondi de harnais.

## Ce qui est vert

Les classes suivantes ont passe en entier et ne doivent pas etre rejouees pour cette passe :

- Carte et chrome : `LaunchUITests` (2), `MapTapUITests`, `MapChromeUITests`, `MapGestureUITests`
  (4, dont verrou du nord, position de depart, rotation et appui long), `MapPoiUITests`.
  Les deux P1 de BUG-HUNT restent fermes.
- Couches : `MapLayersUITests` (6, dont styles, noms, numeros, sorties, trafic, satellite et
  paquet camera hors ligne), `Map3DUITests`, `AviationLayerUITests`, `MaritimeUITests`,
  `EnergyRadarUITests`, `PlaceKnowledgeUITests`.
- Recherche : `SearchUITests` 6 sur 8 (coffee, suggestions, categorie, cartes, NoGoogle),
  `SearchFiltersUITests`, `SearchBranchUITests`, `SearchAreaUITests`.
- Enregistres et trajets : `SavedUITests`, `SavedImportUITests` (Google et My Maps),
  `SavedExportUITests` (2, dont le retour depuis la feuille de partage),
  `SavedFinishingUITests` 2 sur 4 (Maison et Travail, fixture Takeout), `TripsUITests` (2).
- Itineraires et navigation : `DirectionsUITests` 7 sur 7 (voiture, marche, transport, velo,
  eviter les cameras, NoGoogle, etapes), `BikeProfileUITests`, `FreeDriveUITests`,
  `NavUITests`, `NavAlertsUITests` (3), `NavLifecycleUITests` (2, dont la reprise apres relance),
  `NavRobustnessUITests`, `NavRenderUITests`, `NavCameraUITests`, `NavStopsUITests`,
  `NavBannerUITests` 3 sur 4.
- Transports : `TransitCitymapperUITests` 5 sur 5, **y compris le trajet en direct**,
  `TransitAdvancedUITests` 4, `TransitGoUITests`, `TransitLineViewUITests`, `TransitModesUITests`,
  `TransitVehiclesUITests`.
- Reglages et surfaces : `SettingsUITests` (2), `SettingsVoiceUITests`, `SettingsAboutUITests`,
  `StreetViewUITests`, `LocalizationUITests` 3 sur 4, `PrivacyUITests` 4 sur 5.
- Liens et intentions : `IncomingLinksUITests` 4 sur 6 (lieu, directions simple, lien malforme,
  CID), `IntentsUITests` 3 sur 5 (recherche, Home sans valeur, Spotlight).

## Ce que cette passe ne prouve pas

- Aucun scenario n'a ete rejoue sur un iPhone.
- Les trois echecs de recherche (adresse et place) sont classes environnement sur la foi des
  lignes presentes et absentes ; ils demandent un rejeu avec les reponses Google et Photon
  brutes avant de conclure cote application.
- `GlobeUITests` et `OfflineUITests` ne prouvent pas si l'archive locale se monte encore : dans
  les deux cas la preuve s'arrete avant, sur un controle de scenario absent.
- `NavArrivalUITests` est un flake de delai, pas une preuve que le guidage avec arret est casse.
- `TransitWiredUITests` n'a execute aucun test : son plantage ne dit rien sur la fonction.
