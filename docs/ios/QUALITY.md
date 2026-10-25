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
  itération `XCTMemoryMetric` pour carte, recherche, fiche lieu, navigation et hors ligne. La métrique
  mémoire compare l'avant/après du bloc : ce n'est pas une empreinte résidente absolue. Les valeurs
  restent dans le journal `xcodebuild` et le résultat XCTest.

Le lancement Mac reste `scripts/ios/ci-ipa.sh`, qui exécute aussi les scénarios existants. Les
captures Q-1 sont nommées `quality-*.png`. Le simulateur choisi par la CI est un iPhone 17 : il ne
prouve ni un petit écran, ni un iPhone physique, ni VoiceOver en écoute.

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

Les runs seront ajoutés ici avec leurs tags. En l'absence de tag, la valeur est « non mesurée ».

| Mesure | Résultat | Preuve |
|---|---|---|
| Run de compilation et scénarios Q-1 | Non mesuré | À renseigner après le premier run |
| Lancement, `XCTApplicationLaunchMetric` | Non mesuré | `xcodebuild-uitest.log.gz`, test `testApplicationLaunchMetric` |
| Delta mémoire après carte | Non mesuré | Test `testMapMemoryMetric` |
| Delta mémoire après recherche | Non mesuré | Test `testSearchMemoryMetric` |
| Delta mémoire après fiche lieu | Non mesuré | Test `testPlaceMemoryMetric` |
| Delta mémoire pendant navigation | Non mesuré | Test `testNavigationMemoryMetric` |
| Delta mémoire après carte/recherche hors ligne | Non mesuré | Test `testOfflineMemoryMetric` |
| Grands textes et paysage | Non mesuré | Captures `quality-*-large-landscape.png` |
| Hébreu RTL | Non mesuré | Captures `quality-search-he-rtl.png` et `quality-settings-he-rtl.png` |
| Petit écran et VoiceOver en écoute | Non mesuré | Exige un simulateur SE ou un iPhone et une passe humaine |

## Coût connu de la page cachée W-2

W-2 a mesuré un processus WebContent à **319 Mo** après chargement d'une page de 1200x1000 points à
@3x. Le simulateur a aussi subi dix plantages du processus GPU au run
`w2-webview-spike-20261024-213209-27315`. Ces nombres appartiennent au spike, pas à une fiche lieu de
la version courante. `HiddenWebView` désactive WebGL seulement sur simulateur et détruit la vue après
120 s d'inactivité (`HiddenWebView.swift:145-179`). Sur iPhone, la carte WebGL continue donc à coûter
mémoire, GPU et batterie tant que la page n'est pas détruite.

## Plan de mesure sur iPhone

1. **Lancement** : build Release resigné, appareil redémarré, cinq lancements après fermeture et cinq
   après redémarrage pour distinguer cache chaud et froid. Relever le temps jusqu'à la première carte
   interactive avec un signpost, pas seulement jusqu'à `applicationDidFinishLaunching`.
2. **Mémoire par scénario** : Instruments Allocations et VM Tracker après stabilisation de la carte,
   60 résultats, fiche avec 20 photos et avis, cinq minutes de `sf-market`, puis Monaco installé et
   recherche hors ligne. Relever footprint de l'app, WebContent, GPU et fichiers mappés. Fermer la
   fiche et répéter pour repérer ce qui reste retenu.
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

Q-2 doit d'abord fermer les cibles sous 44 points, les libellés des photos et toute impossibilité
d'atteindre une action à grand texte. Les corrections de production doivent rester dans le lot
propriétaire de l'écran concerné ou être coordonnées avec lui. Les résultats de performance doivent
ensuite produire des budgets reproductibles, pas des seuils inventés à partir d'un seul run.
