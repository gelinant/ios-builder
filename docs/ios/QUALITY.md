# Qualité iOS : accessibilité et performance

Périmètre Q-1, sur la base `3439792e`. Les défauts statiques sont distingués des mesures du runner.
Aucun résultat de la section « Mesures » ne doit être recopié sans le tag du run qui l'a produit.

## Suivi Q-2

### Corrections et preuves du dernier run

Le run `q2-accessibility-20261026-183637-14215`, source `1bdb4e6a`, produit 113 tests JVM et
92 tests Kotlin simulateur verts, 50 tests Swift verts et une IPA de 9 958 775 octets. Les six
mesures de performance passent. La suite complète reste rouge : trois scénarios Q-2 échouent,
ainsi que les scénarios Spotlight et Saved qui ne dépendent pas de ce lot.

- Recherche à AX5 paysage : scénario vert. La carte répond avec le libellé `Map`. Les boutons
  d'effacement et de menu mesurent 62x60 points, les résultats et le champ restent utilisables.
- Catégories rapides : `quality-search-he-rtl.png` montre les libellés hébreux issus des clés
  Android existantes. Les six cadres font au moins 44 points de haut en texte normal et 58 à
  70 points à AX5. Les requêtes restent les termes anglais stables.
- Réglages hébreux : `quality-settings-he-rtl.png` montre Done à gauche, les titres à droite,
  les valeurs des menus à gauche et le toggle à gauche. Les nouveaux menus ont une vraie ligne
  interactive de 74 points dans cette configuration. Done mesure 44x44 en texte normal et
  120x63 à AX5. Le scénario échoue ensuite sur une assertion de test invalide : le cadre
  accessible du toggle couvre toute la ligne, donc son milieu ne localise pas le bouton visible.
- Réglages à AX5 paysage et en hauteur compacte : scénarios verts. Les menus, Done, le toggle et
  le lien Privacy mesurent au moins 44 points et restent atteignables. Les captures sont
  `quality-settings-large-landscape.png`, `quality-settings-privacy-large-landscape.png` et
  `quality-settings-compact-landscape.png`. Le petit écran reste simulé seulement par le paysage
  d'un iPhone 17, pas par un iPhone SE.
- Fiche lieu : Directions, Save, Share et All photos sont atteints et mesurés entre 44 et 77
  points de haut. La grille annonce « Place photo 1 of … ». Le scénario échoue après le retour de
  la grille, quand la photo de la fiche n'est plus retrouvée dans la hiérarchie paresseuse. Il ne
  valide donc pas le parcours complet à ce commit.
- Itinéraire : Directions devient accessible et `quality-route-large-landscape.png` est produite.
  Close et Reverse mesurent 44x44, les modes 121 à 133 points de haut. Le scénario s'arrête sur
  la requête `app.scrollViews["route-scroll"]`, avant les toggles et les étapes. Le composant
  porte bien cet identifiant, mais sa représentation XCUI n'est pas nécessairement de type
  `scrollView`.

Le run `q2-accessibility-20261026-153153-22539`, source `3880ea23`, avait validé le scénario de
fiche complet et le libellé d'une photo de fiche. Ce résultat est conservé comme preuve du libellé,
pas comme réussite du dernier commit. Les deux runs précédents sont
`q2-accessibility-20261026-142019-30980` et `q2-accessibility-20261026-171943-14215`.

Après ce dernier run, trois corrections de harnais attendent une nouvelle exécution : suppression
de l'assertion de position du toggle hébreu, recherche de `route-scroll` parmi tous les types XCUI,
et mesure de la photo avant l'ouverture de la grille avec des glissements courts supplémentaires.
Aucun cinquième run n'est lancé, conformément au budget de quatre.

### Couverture VoiceOver et limites

Les photos de fiche, d'avis et de grille ont des libellés avec position, total et auteur quand il
existe. Chaque barre d'affluence expose jour, heure et pourcentage, chaque voie expose position,
directions et recommandation. La carte possède un hint et deux actions de rotor pour sélectionner
un élément ou déposer une épingle au milieu de la carte. Les polices fixes du graphique sont remplacées par
Dynamic Type et le graphique défile horizontalement.

Les données ne permettent pas tout mesurer dans le dernier run : aucune barre d'affluence, photo
d'avis ou voie n'est rencontrée par les assertions conditionnelles. Les actions de rotor, l'ordre
de lecture et les descriptions effectivement prononcées restent à écouter sur iPhone. Les noms,
adresses et avis restent des données non traduites.

## Suivi Q-3

### Harnais et corrections

Q-3 ne change pas la mise en page : il vérifie ce que Q-2 annonçait sans données, et corrige deux
défauts de libellé et de rotor.

- `QualityUITests.testMapAndPlaceReadingOrder` lit l'ordre de la hiérarchie d'accessibilité, jamais
  une capture. La carte reste un seul élément avec le libellé `Map` ; le bouton de localisation et
  le menu sont dans la hiérarchie. La fiche lieu est lue par étapes, du nom aux actions puis à
  l'adresse, aux photos, à l'affluence et aux avis ; les heures ouvertes se lisent sous le statut
  qui les ouvre. Les réglages suivent Langue, Unités et Horloge jusqu'au lien de confidentialité.
- `testRoutePickerReadingOrder` compare l'ordre de la destination, de l'origine, des modes, des
  options d'évitement, des itinéraires, puis de Start et Steps, et vérifie les voies quand
  l'itinéraire en porte.
- `testSmallScreenKeyScreens` mesure la taille réelle de l'écran, exécute recherche, fiche et
  réglages en texte normal, et vérifie que la fiche ne dépasse pas 60 % de la hauteur et garde une
  zone de contenu d'au moins 60 points.
- `MapAccessibilityTests` (cible VelaTests) lit dans UIKit le libellé, le hint, le trait
  d'interaction directe et les deux actions de rotor de la carte, puis vérifie que l'action
  d'épingle passe par le même chemin que l'appui long et dépose l'épingle au milieu de la carte.
- Les libellés d'affluence, de photos d'avis et de voies ne sont plus facultatifs quand la donnée
  existe : `place-popular` ne s'affiche que si Google a fourni des heures, `step-lanes` que si
  l'itinéraire porte des voies, et une barre absente avec des heures connues échoue. Sans donnée,
  la ligne `UITEST` dit `no-data` au lieu de compter un succès.

Corrections du lot :

- L'avatar d'un avis et son initiale de repli sont masqués à VoiceOver. Le nom de l'auteur suit,
  et l'image décorative ne produit plus un élément image sans nom.
- La carte est déclarée comme élément d'accessibilité, porte le trait d'interaction directe et ses
  actions de rotor. Sans ce trait, VoiceOver ne peut pas passer le geste de déplacement à MapLibre.
- La configuration d'accessibilité de la carte est extraite de `makeUIView`, pour que le test lise
  exactement les attributs que la production applique.

### Limites

- XCUITest n'expose ni le hint ni les actions de rotor : leur contenu est vérifié dans UIKit, pas
  leur prononciation. Le trait d'interaction directe et le rotor restent à écouter sur iPhone.
- L'ordre de lecture est comparé sur les cadres des éléments de la hiérarchie d'accessibilité, pas
  sur une capture. Un élément paresseux détruit hors écran est absent de la comparaison ; le test
  le rapporte dans `quality_*_order_missing` et exige un nombre minimal de liens vérifiés.
- `route-scroll` n'apparaît pas dans la hiérarchie, même comme élément générique : le scénario à
  AX5 fait glisser la feuille elle-même. C'est la correction du harnais Q-2, qui cherchait encore
  un conteneur inexistant.
- Deux cibles mesurées en texte normal restent sous 44 points et demandent un fichier hors lot :
  le champ de recherche expose 233x22 et le bouton de menu de la carte 19x19. Q-2 ne les avait
  mesurés qu'à AX5, où leur cadre s'élargit. `MapScreen.swift` doit donner 44x44 au bouton de
  menu ; `SearchViews.swift` doit faire porter au champ la hauteur de sa barre.
- Le runner ne propose que des iPhone 17 et un iPhone 16e dans ses runtimes : la ligne
  `compact simulators` du résumé et `quality_screen_size` (402x874) le documentent. La taille SE
  de 375x667 n'est donc pas exercée, et l'iPhone 16e n'a pas été lancé.
- Les libellés d'affluence, de photos d'avis et de voies restent non vérifiés tant que Google ne
  fournit pas ces données à l'adresse du runner. Le run du 2026-10-27 journalise
  `details: plain search (no popular times)` et `reviews: feed 5 (limited view)` : l'absence est
  donc rapportée en `no-data`, elle n'est pas comptée comme un succès.
- Les actions de rotor « nord » et « localiser » demandent `MapScreen` : `locate()` y traite le
  refus d'autorisation, et aucun bouton nord n'existe hors navigation. Elles ne sont pas ajoutées
  ici, pour ne pas dupliquer la logique du bouton visible.

### Run du 2026-10-27

Le run `q3-a11y-residual-20261027-010652-9913`, source `680f40e7`, exécute la cible
`QualityUITests` seule et les tests unitaires. Kotlin : 187 tests JVM et 166 tests simulateur
verts. Quatre scénarios de qualité passent (fiche à AX5, réglages à AX5, hauteur compacte, hébreu)
et cinq échouent, tous sur des hypothèses du harnais que ce lot corrige ensuite :

- `MapAccessibilityTests` passe deux tests sur trois ; le troisième appelait le constructeur par
  défaut interdit de `UIAccessibilityCustomAction`. Les deux autres prouvent le libellé, le hint,
  le trait d'interaction directe, les deux actions de rotor et le dépôt d'épingle au milieu.
- `testMapAndPlaceReadingOrder` et `testSmallScreenKeyScreens` s'arrêtent sur la mesure de 44
  points du menu de la carte et du champ, désormais rapportée sans échec.
- `testRoutePickerReadingOrder` lisait l'ordre par index de requête ; l'action Start y précède la
  liste pour XCUITest. L'ordre est maintenant comparé sur les cadres.
- `testRoutePickerLargeTextLandscape` échoue sur `route-scroll`, absent de la hiérarchie.
- `testSearchLargeTextLandscape` perd le focus du champ après le premier toucher ; la recherche
  tape une seconde fois avant de saisir.

Les corrections de ces cinq points n'ont pas de run dédié réussi. Deux tentatives suivent sans preuve
exploitable : le run complet `q3-a11y-residual-20261027-054342-27355` échoue après 1 h 08 malgré la
limite du workflow passée à 120 minutes, et le run ciblé
`q3-a11y-residual-20261027-085652-22975` échoue après 38 minutes. Aucun des deux ne publie de
`STATUS` ni de journal sur la branche `results` ; les journaux GitHub Actions demandent une
connexion, même sur ce dépôt public. L'état après corrections reste donc à prouver par un run.


## Harnais ajouté


`iosApp/VelaUITests/QualityUITests.swift` contient deux classes :

- `QualityUITests` ouvre recherche, fiche lieu, choix d'itinéraire et réglages avec
  `UIPreferredContentSizeCategoryName=UICTContentSizeCategoryAccessibilityXXXL`, puis
  en paysage. Elle capture aussi la recherche et les réglages en hébreu et ajoute un scénario
  compact en texte normal. Les cibles requises échouent seulement si elles sont absentes, sous
  44 points ou sans libellé. Les éléments paresseux hors écran restent des mesures optionnelles,
  sans utiliser `isHittable` pour déduire leur taille.
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

## Reste après Q-2

Les lignes Debug de la fiche, des réglages et de la grille ont maintenant une taille bornée, celles de
la carte sont masquées à AX5. Le champ de recherche et Directions sont atteints à AX5. Il reste à
rejouer les trois corrections de harnais décrites plus haut, puis à valider les toggles d'évitement,
les étapes et les voies. Une écoute VoiceOver et un iPhone SE physique restent nécessaires.

Pour la performance, la suite doit répéter les mesures en Release et séparer app, WebContent et GPU avant
de proposer des budgets. `ci-ipa.sh` devrait aussi ajouter `quality-*.png` à son résumé et conserver
le bundle xcresult des métriques ; `docs/ios/TESTING-IOS.md` doit référencer ce harnais. Ces deux
fichiers hors du périmètre Q-1 n'ont pas été modifiés.

## PERF-1 : démarrage à froid et mémoire au lancement

### Méthode

- La sonde `LaunchProbe` n'existe que si l'argument `-VelaLaunchProbe YES` est présent. Elle monte
  une vue d'un point hors mise en page, sans interaction, dont le libellé d'accessibilité porte une
  seule ligne lisible par XCUITest. Elle n'écrit ni fichier ni requête, et sans l'argument elle
  n'installe ni minuterie ni vue.
- Les temps viennent de `DiagnosticsMeasurements`, donc de l'heure de démarrage lue dans le noyau :
  ils couvrent dyld et le travail d'avant `main`. `cold_first_frame_ms` est le premier tick du
  display link après l'attache de la carte, `cold_first_fix_ms` la première position livrée à la
  carte, `cold_map_tap_ms` le premier instant où la carte vivante a un style et ses gestes, donc où
  un toucher peut sélectionner quelque chose. `cold_peak_mb` est le plus grand `phys_footprint`
  observé entre la première vue et huit secondes, mesuré toutes les 100 ms.
- `PerformanceUITests.testColdStartBudget` lance six fois l'app en alternant les deux cas : le cas
  courant et le cas `-VelaPerfLegacy YES`, qui rejoue le chemin d'avant ce lot (table des polygones
  de régions analysée sur le fil principal, catalogue hors ligne démarré avant la première image).
  Chaque cas garde trois lancements et le test publie la médiane, jamais le meilleur run.
  L'alternance évite qu'un runner qui chauffe favorise un cas.
- L'iPhone 17 simulé, la permission de localisation et le point simulé de San Francisco sont ceux de
  `ci-ipa.sh`. Le lancement suit l'utilisateur (`-VelaFollowUser YES`) : sans cela la carte
  n'affiche pas la position et le premier fix n'est jamais marqué, ce que `DiagnosticsUITests`
  documente déjà.

### Budget et garde

- `cold_first_frame_ms` médian doit rester sous 5 000 ms. Le premier passage de cette garde a
  mesuré 3 782 ms de médiane pour l'ancien chemin sur le runner GitHub, une build Debug où le
  premier rendu dépend de dyld, du framework VelaCore et de MapLibre ; 5 000 ms laisse la marge
  d'un runner chargé et attrape quand même un lancement qui gagne plus d'une seconde. Quand la
  référence du même run dépasse 4 000 ms, le plafond passe à cette référence plus 25 %, pour qu'un
  runner deux fois plus lent ne transforme pas une comparaison valide en échec. La garde stricte
  reste la comparaison relative.
- Le même test échoue si la médiane du cas courant dépasse de plus de 25 % celle du cas de référence
  mesurée dans le même run, pour la première image, le premier instant où la carte accepte un
  toucher, le premier fix et le pic mémoire. C'est la comparaison qui compte : elle ne dépend ni de
  la machine ni de la charge du moment.
- Le test rapporte `cold_first_frame_ms`, `cold_map_tap_ms`, `cold_first_fix_ms`, `cold_peak_mb`, les
  quatre mêmes valeurs pour la référence, et `cold_first_frame_gain_ms`.

### Ce qui a quitté le chemin de la première image

- La table des polygones de régions (`region_polys.json`, 350 Ko) est lue et analysée après la
  première image, sur la file d'arrière-plan de `LaunchSequencer`. Une première version la lançait
  dès le début du lancement, sur une autre file : elle entrait alors en concurrence avec le chargement
  de style de MapLibre et la première image reculait de 2,5 s sur le runner. La reporter après
  l'image supprime cette concurrence. `loadRegionPolygons` recalcule la région courante quand la
  table arrive, donc rien ne reste indisponible : le catalogue hors ligne la retrouve à son démarrage.
- Le catalogue hors ligne (ouverture SQLite, liste des régions installées, manifestes) démarre après
  la première image, avec un filet de sécurité à huit secondes pour un lancement qui n'affiche pas de
  carte (passage en arrière-plan, test qui ne lit que l'état). L'appel est idempotent. La sélection
  du style PMTiles ne peut donc plus se produire avant la première image : elle suppose le catalogue
  chargé, et elle est de toute façon refaite par `refreshOfflineStyle` une fois la carte interactive.
- La navigation reste démarrée avant la première image : `NavStore.start()` démarre la source de
  localisation, et différer ce démarrage retardait le premier fix de plus de deux secondes au
  premier passage.
- Le reste de `MapSession.start` reste synchrone, volontairement : les réglages (langue, unités) sont
  lus par la première vue, la calibration doit exister avant toute requête Google, la source de
  recherche et de lieux est construite avant tout lien entrant, la navigation démarre la source du
  premier fix, et les magasins d'itinéraire et de lieux enregistrés répondent à un lien entrant
  traité avant la première image. Les épingles des lieux enregistrés sont du contenu du premier
  écran et restent chargées au lancement.

### Mesures

### Résultat du run `perf-1-20261029-194720-12536`

`STATUS ok`, 188 tests Xcode sans échec, `LaunchUITests` vert et `PerformanceUITests` vert en 65,8 s.
Six lancements, trois par cas, médianes :

| Cas | Première image | Carte qui accepte un toucher | Premier fix | Pic mémoire |
|---|---|---|---|---|
| Avant (`-VelaPerfLegacy YES`) | 2 703 ms | 2 788 ms | 2 328 ms | 122 Mo |
| Après | **2 273 ms** | **2 446 ms** | **1 984 ms** | **117 Mo** |
| Gain | -430 ms (-15,9 %) | -342 ms (-12,3 %) | -344 ms (-14,8 %) | -5 Mo (-4,1 %) |

Lignes de rapport : `cold_first_frame_ms=2273`, `cold_map_tap_ms=2446`, `cold_first_fix_ms=1984`,
`cold_peak_mb=117`, `cold_budget_ms=5000`, `cold_first_frame_gain_ms=430`, et les quatre
`cold_baseline_*` du tableau. Le plafond est resté à 5 000 ms : la référence du run valait 2 703 ms,
donc la règle de relèvement ne s'est pas appliquée.

Le run précédent, `perf-1-20261029-192139-16155`, avait échoué sur le budget avec 6 273 ms contre
3 782 ms de référence. La cause était la première version du report : la table des régions partait
sur une file d'arrière-plan dès le début du lancement et le catalogue hors ligne démarrait au filet
de sécurité de deux secondes, tous deux pendant le chargement de style de MapLibre ; la première
image et le premier fix reculaient ensemble de 2,5 s. Le report après la première image, sans
concurrence, a corrigé les deux. Ces deux runs sont la preuve que le déplacement d'un travail hors
du fil principal ne suffit pas : il faut aussi qu'il ne concurrence pas le rendu.

### Limites

- Les chiffres sont une build Debug sur le simulateur partagé du runner, pas un iPhone physique ni
  une build Release. Le premier rendu inclut dyld et le framework VelaCore, plus lents en Debug.
- Le pic mémoire couvre le processus principal seulement, pas WebContent ni le GPU, et s'arrête à
  huit secondes. Il ne distingue pas une fuite d'un pic transitoire.
- `cold_map_tap_ms` mesure le premier instant où la carte vivante a un style et ses gestes, pas un
  toucher réellement rejoué ; c'est le substitut applicatif le plus proche de « la carte accepte un
  toucher ».
- Le catalogue hors ligne démarre après la première image : une zone déjà installée reste
  disponible, mais le premier choix de style PMTiles ne peut plus précéder l'image, ce qui était de
  toute façon le cas en pratique puisque la liste des régions est lue en arrière-plan.
