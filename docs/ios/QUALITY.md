# Qualité iOS : accessibilité et performance

Périmètre Q-1, sur la base `3439792e`. Les défauts statiques sont distingués des mesures du runner.
Aucun résultat de la section « Mesures » ne doit être recopié sans le tag du run qui l'a produit.

## Harnais ajouté

`iosApp/VelaUITests/QualityUITests.swift` contient deux classes :

- `QualityUITests` ouvre recherche, fiche lieu, choix d'itinéraire et réglages avec
  `UIPreferredContentSizeCategoryName=UICTContentSizeCategoryAccessibilityXXXL`, puis
  en paysage. Elle capture aussi la recherche et les réglages en hébreu. Les cibles connues sont
  mesurées en points ; les cibles sous 44 points et les boutons sans libellé sont journalisés comme
  audit de référence sans faire échouer les autres scénarios.
- `QualityPerformanceUITests` mesure cinq lancements avec `XCTApplicationLaunchMetric` et exécute une
  itération `XCTMemoryMetric` pour carte, recherche, fiche lieu, navigation et hors ligne. La mesure
  démarre après l'apparition du champ de recherche. Xcode 26 émet `Absolute Memory Physical`, `Memory
  Physical` et `Memory Peak Physical` ; les valeurs sont conservées dans le journal `xcodebuild` et
  le résultat XCTest transitoire.

Le lancement Mac reste `scripts/ios/ci-ipa.sh`, qui exécute aussi les scénarios existants. Les
captures Q-1 sont nommées `quality-*.png`. Les métriques utilisent la build Debug du simulateur et
ne fixent pas un budget Release. Le simulateur choisi par la CI est un iPhone 17 : il ne prouve ni
un petit écran, ni un iPhone physique, ni VoiceOver en écoute.

## Audit d'accessibilité statique

### Défauts visibles dans le code

| Défaut | Référence | Effet et correction attendue |
|---|---|---|
| Les catégories rapides font 38 points de haut, sous la cible minimale de 44 points | `iosApp/Vela/Search/SearchPanels.swift:63-75` | Donner au bouton une zone interactive d'au moins 44x44 sans nécessairement agrandir la puce visuelle |
| Les toggles d'évitement n'ont que 5 points de padding vertical autour d'un texte caption | `iosApp/Vela/Routes/RouteSheets.swift:174-191` | Garantir 44 points de haut pour Avoid highways/tolls/ferries |
| Plusieurs boutons icône n'ont pas de cadre minimal : effacer la recherche, menu, fermer lieu/itinéraire | `SearchViews.swift:34-55`, `PlaceSheet.swift:38-44`, `RouteSheets.swift:90-102` | Mesurer le cadre XCUITest réel, puis appliquer une cible de 44x44 à tous les boutons concernés |
| Les boutons de photos de lieu, d'avis et de grille n'ont pas de `accessibilityLabel` | `PlaceSheet.swift:271-282`, `PlaceSheet.swift:517-526` et `GalleryViews.swift:64-73` | Annoncer « Photo du lieu, index sur total » ou « Photo de l'avis de … » et l'action d'ouverture |
| Le graphique d'affluence expose les heures, mais pas l'occupation de chaque barre | `PopularTimesView.swift:57-80` | Ajouter libellé et valeur d'accessibilité avec jour, heure et niveau, ou un résumé texte équivalent |
| Les voies sont regroupées sous le seul libellé « Lanes » | `RouteSheets.swift:372-391` | Faire énoncer chaque voie, les directions et si elle est conseillée |
| La carte a un identifiant mais aucun libellé, hint ou action accessible pour toucher un POI et déposer une épingle | `MapView.swift:13-33` ; aucun `accessibilityHint` dans les vues de production | Donner une description de la carte et des alternatives accessibles aux gestes, puis vérifier leur ordre dans VoiceOver |
| Des informations sont limitées à une ligne sans autre présentation : destination, origine, résultats et auteurs | `RouteSheets.swift:79-88`, `SearchViews.swift:199-221`, `PlaceSheet.swift:495-497` | Permettre le retour à la ligne ou une lecture complète par VoiceOver à grand texte |
| Les heures du graphique utilisent une police fixe de 9 points | `PopularTimesView.swift:71-75` | Employer un style Dynamic Type lisible et laisser le graphique défiler horizontalement si nécessaire |

Ces constats ne prétendent pas que tous les libellés absents du code produisent un silence VoiceOver :
SwiftUI peut composer un nom à partir du contenu. Les résultats XCUITest et une écoute sur iPhone
doivent confirmer le comportement effectif, en particulier pour les images distantes et la carte
MapLibre.

### Risques de mise en page à trancher par capture

- `SearchBar` impose 48 points de haut (`SearchViews.swift:57-59`) alors que le champ suit le texte
  dynamique. Vérifier que le placeholder, le curseur et les boutons ne sont pas rognés au plus grand
  réglage.
- Les feuilles lieu, itinéraire et étapes occupent 50 à 55 % de la hauteur (`MapScreen.swift:124-135`).
  En paysage, l'en-tête et les actions peuvent ne laisser presque aucune place au contenu défilant.
- Le bandeau de navigation n'a pas de règle pour rester sous un tiers de l'écran, et la caméra utilise
  des insets fixes (`NavChrome.swift`, `MapController.swift:124-155`). C'est aussi l'écart noté dans
  `FEATURES-IOS.md` pour `FEATURES.md:L124-L125`.
- Les alignements `leading` et `trailing` de SwiftUI doivent suivre le sens hébreu injecté par
  `SettingsModel.layoutDirection`. Vérifier visuellement les icônes, le champ, les toggles et les
  boutons de fermeture. Une capture ne prouve pas l'ordre de lecture VoiceOver.

## Mesures du runner Q-1

### Runs et limites de preuve

- `q1-parity-quality-20261025-220308-5939` : Kotlin vert, puis échec de compilation Swift sur quatre
  captures implicites de `self`. Le commit `16ae79f8` corrige les quatre lignes et l'avertissement
  associé au placeholder. Aucune mesure de ce run n'est reprise.
- `q1-parity-quality-20261025-221617-24690`, source `16ae79f8` : build simulateur et IPA produits,
  100 tests JVM et 79 tests simulateur Kotlin, 34 tests Swift verts. Les 6 tests de performance
  passent. L'interface compte 23 réussites et 3 échecs sur 26 tests : recherche et choix d'itinéraire
  à grand texte, plus le scénario P-1 déjà suivi.

Les captures et les échecs viennent d'une build **Debug**. Les lignes `velacore-debug`, `nav-debug`,
`place-debug` et leurs voisines suivent aussi Dynamic Type et peuvent occuper toute la hauteur en
paysage. Elles ne sont pas des défauts de production. Les échecs de mise en page ci-dessous sont donc
des faits mesurés dans cette configuration, à rejouer en Release ou avec les lignes Debug masquées
avant de conclure sur le seul code utilisateur. Aucun run supplémentaire n'est lancé après ces deux
runs, conformément au budget Q-1.

### Lancement et mémoire

Preuve : `xcodebuild-uitest.log.gz` du run `q1-parity-quality-20261025-221617-24690`. Les mémoires
sont les valeurs `Absolute Memory Physical (ios)` et `Memory Peak Physical (ios)` en fin de scénario,
en kilooctets affichés par XCTest. Les équivalents en Mio sont calculés par division par 1024. Une
itération par scénario, sans moyenne ni seuil de régression.

| Mesure | Résultat |
|---|---|
| `XCTApplicationLaunchMetric`, 5 lancements | Moyenne **3,055 s**, écart-type relatif 10,194 % ; valeurs de 2,642251 à 3,599886 s |
| Carte après stabilisation des tuiles | **106928,832 kB** (104,4 Mio), pic 107027,136 kB |
| Recherche « coffee » et résultats | **138910,784 kB** (135,7 Mio), pic 139009,088 kB |
| Fiche Davis Food Co-op | **222371,328 kB** (217,2 Mio), pic 224157,184 kB |
| Navigation démarrée sur `sf-market` | **246538,048 kB** (240,8 Mio), pic 246767,360 kB |
| Monaco monté puis recherche hors ligne | **130161,472 kB** (127,1 Mio), pic 130325,312 kB |

Le temps de lancement est une métrique de relance du processus sur simulateur, pas un démarrage à
froid d'un iPhone après redémarrage ni le délai jusqu'à une carte entièrement interactive. Les chiffres
mémoire sont des observations Debug ponctuelles, pas des budgets ni des preuves de fuite. Ils ne
distinguent pas WebContent du processus principal.

### Accessibilité mesurée

| Écran | Résultat du run `q1-parity-quality-20261025-221617-24690` |
|---|---|
| Recherche, AX5 paysage | **Échec avant la saisie** : le champ est à `y=-144` avec une taille de 497x64 et ne peut pas être rendu visible. `quality-map-large-landscape.png` montre les lignes Debug géantes. Aucune capture de résultats n'existe ; le défaut de production reste à isoler des lignes Debug. |
| Fiche lieu, AX5 paysage | Le test ouvre la fiche, mais `quality_place_missing_targets=7` : Directions, Save, Share, All photos, All reviews et les deux contrôles photo ne sont plus dans la hiérarchie accessible. Seule Close est mesurée, 66x63 points. `quality-place-large-landscape.png` ne montre que le titre et Close. |
| Choix d'itinéraire, AX5 | **Échec en amont** : `place-directions` existe mais reste non hittable après six balayages de la fiche (`QualityUITests.swift:229`). Le choix d'itinéraire n'est donc pas atteint et aucune capture paysage n'est produite. |
| Réglages, AX5 paysage | Test réussi et `quality-settings-large-landscape.png` produite. Done mesure 73x36 points. NoGoogle et le lien Privacy sont hors de la première vue. La capture est dominée par la ligne Debug, donc insuffisante pour juger les contrôles de production. |
| Recherche en hébreu | `quality-search-he-rtl.png` : champ, icônes et rangée de catégories suivent bien le sens RTL. Coffee, Restaurants et Gas restent en anglais, ce qui confirme des libellés non localisés dans `SearchPanels.swift:49-55`. |
| Réglages en hébreu | `quality-settings-he-rtl.png` : les textes sont hébreux, mais la feuille reste en disposition LTR. Libellés et titres de section restent à gauche, toggle et Done à droite. `MapScreen.swift:185-186` ne suffit pas à propager le sens RTL à la feuille présentée par `SettingsScreen`. |
| Cibles en hébreu | Trois cadres sous 44 points sur les contrôles mesurés : Done 54x36, Language 338x34 et Units 338x34. Ce sont les cadres accessibles des éléments, à confronter à leur zone de tap réelle avant correction. |
| VoiceOver | Aucun bouton visible sans libellé n'est remonté par les requêtes dans les écrans atteints. Cela ne couvre ni les photos hors écran, ni la carte, ni l'écoute réelle. Les absences statiques de la table précédente restent à corriger. |
| Petit écran et écoute VoiceOver | Non mesurés. Ils exigent un simulateur SE ou un iPhone et une passe humaine. |

Le bouton P-1 `place-photo-categories` est aussi resté non hittable dans ce run. Ce défaut est suivi
dans `PARITY.md` et ne doit pas être confondu avec les deux échecs du harnais Q-1.

## Coût connu de la page cachée W-2

W-2 a mesuré un processus WebContent à **319 Mo** après chargement d'une page de 1200x1000 points à
@3x. Le simulateur a aussi subi dix plantages du processus GPU au run
`w2-webview-spike-20261024-213209-27315`. Ces nombres appartiennent au spike, pas à une fiche lieu de
la version courante. `HiddenWebView` désactive WebGL seulement sur simulateur et détruit la vue après
120 s d'inactivité (`HiddenWebView.swift:145-179`). Sur iPhone, la carte WebGL continue donc à coûter
mémoire, GPU et batterie tant que la page n'est pas détruite. Le scrape photos utilise une vue de
1200x3200 points (`PhotosWebFetcher.swift:8`), trois fois plus haute que celle de la mesure W-2. Le
coût de cette configuration doit être mesuré séparément, sans extrapoler un total à partir de 319 Mo.

Le cache d'images est limité à 200 objets, sans `totalCostLimit` (`RemoteImage.swift:7-21`). Chaque
`UIImage` est conservé à sa taille décodée alors que les cellules peuvent être petites. Ce n'est pas
une fuite démontrée, car `NSCache` réagit à la pression mémoire, mais le pic avant éviction doit
faire partie de la mesure de galerie et de défilement des avis.

## Plan de mesure sur iPhone

1. **Lancement** : build Release resigné, appareil redémarré, cinq lancements après fermeture et cinq
   après redémarrage pour distinguer cache chaud et froid. Relever le temps jusqu'à la première carte
   interactive avec un signpost, pas seulement jusqu'à `applicationDidFinishLaunching`.
2. **Mémoire par scénario** : Instruments Allocations et VM Tracker après stabilisation de la carte,
   60 résultats, fiche avec 20 photos et avis, cinq minutes de `sf-market`, puis Monaco installé et
   recherche hors ligne. Relever footprint de l'app, WebContent, GPU et fichiers mappés. Fermer la
   fiche et répéter pour repérer ce qui reste retenu. Sur le runner, Q-2 peut aussi récupérer le PID
   avec `xcrun simctl spawn <udid> launchctl list`, puis lire le RSS de l'app et de WebContent avec
   `ps` sur l'hôte après chaque scénario. Ce complément sépare l'app de WebContent, ce que le
   scénario XCTest actuel ne permet pas.
3. **Page cachée** : comparer avant chargement, scrape terminé, 30 s après et après les 120 s de reap.
   Mesurer WebGL autorisé contre refusé sur le même iPhone et la même fixture. Vérifier que la page ne
   relance pas de minuteries après le résultat et que la destruction libère bien WebContent.
4. **Énergie et GPU** : Energy Log et compteurs GPU sur cinq minutes carte inactive, carte en
   déplacement, navigation et scrape caché. Répéter écran éteint pour la navigation. Aucun pourcentage
   de batterie ne doit être extrapolé à partir du simulateur.
5. **Fluidité** : XCTHitchMetric ou Instruments sur un balayage de 60 résultats, zoom de carte dense et
   replay de navigation. Comparer une build Release, avec les mêmes tuiles froides puis chaudes.
6. **Accessibilité humaine** : plus grand Dynamic Type et affichage agrandi, VoiceOver sur les quatre
   écrans Q-1, hébreu avec ordre de lecture, paysage et iPhone SE. Vérifier aussi Full Keyboard Access
   et Switch Control sans les confondre avec le D-pad Android.

## Lot suivant

Q-2 doit d'abord rendre la preuve indépendante des lignes Debug : les masquer ou limiter leur taille,
ou exécuter les scénarios de mise en page en Release. Il faut ensuite rouvrir le champ de recherche en
paysage AX5, atteindre Directions puis le choix d'itinéraire, et remettre les actions de la fiche dans
la hiérarchie accessible. La propagation RTL à `SettingsScreen`, les cibles sous 44 points, les
libellés des photos et les libellés anglais des catégories sont des corrections séparées à coordonner
avec les propriétaires de ces écrans. Les nouveaux contrôles doivent devenir des assertions une fois
la référence corrigée.

Pour la performance, Q-2 doit répéter les mesures en Release et séparer app, WebContent et GPU avant
de proposer des budgets. `ci-ipa.sh` devrait aussi ajouter `quality-*.png` à son résumé et conserver
le bundle xcresult des métriques ; `docs/ios/TESTING-IOS.md` doit référencer ce harnais. Ces deux
fichiers hors du périmètre Q-1 n'ont pas été modifiés.
