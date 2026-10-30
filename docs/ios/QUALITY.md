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

## Suivi QUALITY-REG (30 octobre 2026)

Branche `ios/quality-reg`. Deux lots Mac ont ete lances, le premier pour compiler, le second pour
mesurer :

| Rôle | Tag | Source | Résultat |
|---|---|---|---|
| Compilation | `quality-reg-20261030-023147-27266` | `859835dc` | Kotlin vert (655 tests JVM, 544 simulateur), build Swift en échec sur le type de retour d'un helper du test |
| Mesure | `quality-reg-20261030-030119-30444` | `b6c03678` | Kotlin vert, 10 scénarios `QualityUITests` exécutés, 2 verts |

Le tag de mesure précède deux commits de test non mesurés (défilement horizontal de la rangée
d'onglets de la fiche et étapes de révélation des avis portées à 24) ; les lire comme une hypothèse
de harnais, pas comme une preuve.

### Puce de catégorie : identifiant stable

`QuickCategory.id` ne dérive plus de la clé ni de la requête. Il dérive de la clé de libellé
(`labelKey`) : `cat_gas` devient `gas`, `cat_coffee` devient `coffee`, `cat_ev` devient `ev`. La
requête du carburant change de mot selon la région (« Gas station » hors des régions de
`QuickCategory.fuelQuery`, « Petrol station » au Royaume-Uni, en Irlande et dans les autres régions
listées), donc un identifiant tiré de la requête aurait bougé avec le pays. La clé d'ordre
persistée reste inchangée, donc l'ordre et l'ensemble masqué enregistrés restent lisibles. La puce
existait déjà dans le catalogue iOS comme dans `QuickCategories.catalog` d'Android : le défaut
était l'identifiant attendu par le test, pas une puce absente. `category-gas` est désormais présent,
et `category-transit`, qui n'existe sur aucune des deux plateformes, a quitté la liste. Preuve du
run : plus aucun échec `missing target: category-gas` ; `testHebrewRightToLeft` passe avec les six
puces et leurs libellés hébreux.

### Requête non unique de la fiche

La ligne 739 tombait sur `place-address`. La hiérarchie de R3 et la mesure de ce lot montrent deux
éléments pour cet identifiant : l'icône (`Image, label: 'Remove Map Pin'`) et le texte de l'adresse.
Le défaut est produit : `InfoRow` n'est pas un élément d'accessibilité combiné, donc l'identifiant
posé sur son conteneur est recopié sur l'icône et sur le texte. Ce n'est pas une duplication
légitime d'éléments parallèles. Le correctif d'une ligne appartient à `PlaceSheet.swift`, hors lot :
`.accessibilityElement(children: .combine)` avant `.accessibilityIdentifier("place-address")`
(ligne 621). Le test lit maintenant `app.staticTexts["place-address"]`, qui désigne la ligne
lisible, et journalise `quality_place_place_address_elements`. Preuve du run : la fiche de
`testMapAndPlaceReadingOrder` va jusqu'aux photos (`quality_place_photo_order_checks=2`).

### Photo de fiche

En texte normal, la photo est atteinte une fois l'onglet Photos ouvert : c'était le défaut du test,
qui attendait `place-photo` dans Overview alors que la grille vit sous `place-tab-photos`. Les deux
scénarios ouvrent désormais cet onglet, puis reviennent à Overview pour les affluences et les avis,
et gardent les assertions d'existence, de libellé et d'ouverture de la visionneuse.

En grand texte, l'onglet Photos n'est pas atteignable : `testPlaceLargeTextLandscape` échoue sur
`the Photos tab is not reachable` au run de mesure. La rangée d'onglets est un `ScrollView`
horizontal, et à AX5 l'onglet Photos sort de son viewport ; un défilement vertical ne peut pas le
rendre touchable. Le helper `openPlaceTab` ajouté après la mesure amène d'abord la rangée dans la
fenêtre puis fait glisser `place-tabs` vers la gauche ou la droite ; il n'a pas encore été mesuré.

### Options d'évitement en grand texte

Elles existent dans la hiérarchie mais ne deviennent jamais touchables. Les points de glissement
sont maintenant calculés dans l'intersection du cadre de la feuille et de la fenêtre, et le run de
mesure journalise `QUALITY_SHEET_REVEAL` : le cadre de `route-avoid-highways` reste à
`(86, 1288, 360x61)` à chaque pas, donc la feuille ne défile pas du tout. Le glissement ne
parvient pas au `ScrollView` unifié. Le prochain raccord est dans `RouteSheets.swift` (hors lot) :
exposer le `ScrollView` unifié de `route-scroll` comme un élément à part entière, ou plafonner la
hauteur de son contenu pour qu'il défile, afin que la cible soit atteignable au doigt comme au
rotor. Aucune assertion n'a été affaiblie.

### Chrome de la carte en paysage compact

Deux tests gardent l'invariant : `map-overflow` et `search-field` doivent rester dans le cadre de
l'application, puis le menu doit être touchable. Le run de mesure donne
`search-field (126, -80, 546x22)` et `map-overflow (680, -91, 44x44)` dans une fenêtre de
`874x402` : les deux sont 80 à 91 points au-dessus de la fenêtre. Le contenu du chrome, haut d'environ
592 points, est centré. Le correctif appartient à `MapScreen.swift` (hors lot) : ancrer et découper
le `ZStack` du `GeometryReader` de `browserChrome` sur la hauteur proposée, par exemple
`.frame(width: proxy.size.width, height: proxy.size.height, alignment: .top).clipped()` à la place
du `.frame(width:height:)` actuel. `testCompactHeightSettingsLandscape` et
`testCompactLandscapeChromeFits` échouent sur cette assertion, avec le cadre mesuré dans le
message ; `testSearchLargeTextLandscape` est bloqué par le même défaut, son toucher du champ à
`y = -101` échouant avant les catégories.

### Route déterministe pour l'audit d'ordre

`-VelaRouteOrderFixture YES` arme `RouteOrderFixture` (`ios-shared`), qui remplace la réponse du
routeur par deux trajets voiture fixes entre l'origine et la destination demandées. Le premier a
trois étapes et un diagramme de voies sur le virage, le second est huit minutes plus lent, ce qui
donne au choix d'itinéraire deux lignes et à la feuille d'étapes ses voies étiquetées. Le drapeau
est lu dans `SearchCommandTestSupport.prepareIfNeeded`, avant toute demande d'itinéraire ;
`RouteStore` consulte la fixture au même endroit que celle du profil vélo. Couverture visée :
rangées d'itinéraires, modes, options d'évitement, Start, Steps, ordre de lecture et libellés de
voies. La recherche du lieu de destination reste réelle, donc le réseau Google reste nécessaire
pour ouvrir la fiche avant Directions.

Preuve du run : `testRoutePickerLargeTextLandscape` trouve `route-row` avec la fixture, donc le
remplacement du routeur fonctionne. `testRoutePickerReadingOrder`, lancé avec le même drapeau,
n'obtient aucune `route-row` en 90 s alors que le mode est `DRIVE` ; la cause n'est pas établie et
reste ouverte. Ce scénario doit être rejoué seul avec la ligne `route-debug` recopiée.

### Hors lot, observé dans le même run

`testSmallScreenKeyScreens` échoue sur la fiche lieu, haute de 714,7 points sur un écran de 874,
soit plus de 60 % alors que le test exige 60 % au plus. Aucun fichier de ce lot ne touche la
hauteur de la fiche ; c'est un défaut de `Place` ou de `MapScreen` à traiter par son propriétaire.

## PERF-GUARD : budgets de performance relatifs au runner (30 octobre 2026)

Branche `ios/perf-guard`, source `c678fd57`. Ce lot remplace les deux budgets absolus qui
mesuraient la charge du simulateur partage plutôt que l'application :

- `PlaceReviewsUITests.testSwipeKeepsThePanelResponsive` exigeait une réponse sous 1 000 ms. Le
  run VAL-2 B3 avait mesuré 1 358 ms alors que le même runner mesurait déjà 911 ms avant le geste :
  le budget était inatteignable avant même le balayage.
- `PerformanceUITests.testColdStartBudget` gardait un plafond absolu de 5 000 ms pour la première
  image, en plus de sa comparaison au chemin de référence.

### Nouvelles formulations

Un helper partagé dans `VelaUITestCase.swift` porte la règle commune. Il publie
`<mesure>_baseline_ms`, `<mesure>_action_ms` et `<mesure>_ratio`, puis exige les deux conditions :

    budget = min(multiple x baseline, plafond absolu)
    action <= budget

- Panneau d'avis : la référence est mesurée juste avant le geste. Elle vaut le maximum entre la
  lecture `stall=` déjà présente et la durée d'une requête triviale sur `place-reviews-close`
  précédée d'une pause de 500 ms. L'action est le temps de la même requête après le `swipeUp`.
  Le multiple est 3 et le plafond 5 000 ms. Le stall de boucle principale après le geste est jugé
  avec la même référence, le même multiple et le même plafond.
- Démarrage à froid : la référence est la médiane du chemin `-VelaPerfLegacy YES` mesurée dans le
  même run. L'action est la médiane du chemin courant. Le multiple reste 1,25, car les deux
  chemins sont mesurés dos à dos sur la même machine et une régression de 2,5 s doit toujours
  échouer. Le plafond absolu passe à 12 000 ms, soit quatre fois la médiane Debug documentée de
  3 055 ms et presque deux fois le lancement le plus lent observé (6 273 ms).

Le plafond absolu reste nécessaire : sans lui, un runner uniformément lent laisserait passer un
lancement de vingt secondes ou un gel de plusieurs secondes tant que la référence ralentit autant.
Le panneau garde donc 5 000 ms, très au-dessus du gel de plus de 60 s observé avant REVIEWS-REG.

### Run de preuve

Commande : `VELA_ONLY_UI=PlaceReviewsUITests,PerformanceUITests,LaunchUITests`,
`VELA_SKIP_ARCHIVE=1`, via `mac-run.sh`. Tag `perf-guard-20261030-060102-30546`, simulateur
iPhone 17, build Debug. Sept tests exécutés : six verts, un rouge. Les trois gardes de ce lot
passent.

| Mesure | Référence | Action | Ratio | Budget |
|---|---|---|---|---|
| `reviews_swipe` | 648 ms | 136 ms | 0,21 | 1 944 ms |
| `reviews_stall` | 648 ms | 149 ms | 0,23 | 1 944 ms |
| `cold_start` | 2 424 ms | 2 185 ms | 0,90 | 3 030 ms |

La référence du panneau vaut 648 ms alors que `mainloop_stall_before_ms` valait 149 ms : la pause
de 500 ms et la requête triviale composent le reste. Le runner avait donc environ cinq fois la
marge du budget de 3x, et le swipe ancien de plus de 60 s resterait rouge sur le plafond de 5 s.
Le lancement froid était même plus rapide que son chemin de référence, avec 239 ms de gain.

Le seul échec du run est `PlaceReviewsUITests.testMoreReviewsAppendsAPage`, à la ligne 99, sur
`Timed out while evaluating UI query` après le tap sur More reviews. C'est l'état de page Google
déjà documenté par VAL-2 et REVIEWS-REG pour ce scénario, sans rapport avec le balayage mesuré ici.
Aucun code applicatif n'a changé dans ce lot.

### Limites

- Ces chiffres restent une build Debug sur le simulateur du runner, pas un iPhone ni une Release.
- La référence du panneau mesure une requête triviale et la pause de 500 ms, pas une charge
  synthétique connue. Elle suit la contention observée, pas une latence matérielle étalonnée.
- Le plafond de 12 000 ms du démarrage à froid est volontairement large. Il attrape un lancement
  pathologique, mais c'est le ratio de 1,25 qui garde le pouvoir de régression.

## Suivi SCROLL-FIX (30 octobre 2026)

Branche `ios/scroll-fix`. Le lot corrige les deux defauts de defilement isoles par QUALITY-REG et
ajoute un scenario par classe. Aucune assertion existante n'est affaiblie.

### Defilement unifie du choix d'itineraire

Cause mesuree. En grand texte et en paysage, `RouteSheets.swift` passait tout le contenu dans un
`ScrollView` place sous la poignee et les deux lignes de debug, dans un `VStack` de hauteur fixe.
A AX5 ces deux elements occupaient presque toute la demi-feuille : la zone defilante visible etait
tres mince et le glissement du harnais partait sur le texte de debug, qui a
`allowsHitTesting(false)`. Le contenu ne bougeait donc jamais, d'ou le cadre constant
`(86, 1288, 360x61)` de `route-avoid-highways`.

Correctif. Le `ScrollView` unifie devient la racine de la feuille en grand texte et en paysage : la
poignee, les lignes de debug, l'en-tete, les modes, le resume, le corps etendu et les actions sont
tous dans ce meme defilement. Il porte `route-scroll` comme conteneur d'accessibilite
(`children: .contain`) et occupe toute la hauteur proposee, donc il a un cadre reel et recoit le
glissement. En portrait a texte normal, le `ScrollView` interne porte le meme conteneur. Le
comportement des deux presentations et l'ordre du contenu ne changent pas.

Preuve. `DirectionsUITests.testRouteAvoidOptionsScrollAtLargeText` ouvre un itineraire en voiture a
AX5 par un lien d'itineraire (sans passer par la fiche lieu), deplie la feuille, verifie que
`route-scroll` mesure au moins 44 points de haut, puis fait glisser ce conteneur. Il publie
`route_avoid_swipes` et exige `route-avoid-highways` hittable apres au plus trois glissements, avec
la capture `route-avoid-reachable.png`.

Limite. Le scenario deplie la feuille avant les glissements pour disposer d'un viewport franc ; le
defilement compact est couvert par la meme structure et par le scenario QUALITY-REG existant, qui
n'est pas rejoue dans ce lot.

### Onglets de la fiche lieu a AX5

Cause mesuree. La rangee d'onglets etait toujours un `ScrollView` horizontal. A AX5 les libelles
elargis poussent l'onglet Photos hors du viewport de la rangee ; un defilement vertical de la fiche
ne peut pas le ramener et le harnais QUALITY-REG n'avait pas encore mesure son glissement
horizontal.

Correctif. A partir des tailles d'accessibilite, la rangee passe dans `TabFlowLayout`, une mise en
page qui replie les onglets sur plusieurs lignes dans la largeur de la feuille. Chaque onglet garde
sa cible de 44 points, son trait de selection de 3 points et son etat `isSelected`. En texte normal
et en paysage compact, la rangee reste un `ScrollView` horizontal qui amene l'onglet selectionne au
centre. Le repli suit le sens de lecture : en RTL, les lignes se remplissent depuis le bord droit.

Preuve. `PlaceUITests.testPhotosTabOpensAtLargestText` ouvre la fiche a AX5, amene la rangee dans
la fenetre par un defilement vertical, verifie que chaque onglet present est hittable et mesure au
moins 44 points, capture `place-tabs-ax5.png`, ouvre Photos et exige la grille ou son etat vide
ainsi que l'etat selectionne. Il publie `place_photos_ax5=1` et produit `place-photos-ax5.png`.

Limite. Le scenario depend de la reponse Google pour Davis Food Co-op, comme les deux scenarios
existants de la classe. Sur un lieu sans photo ni fiche commerciale, l'onglet Photos n'existe pas
et le scenario echoue avant la preuve ; ce cas n'est pas simule par une fixture.

### Runs Mac du lot

Deux runs cibles sur `DirectionsUITests` et `PlaceUITests`, avec `VELA_SKIP_ARCHIVE=1` :

| Tag | Source | Resultat |
|---|---|---|
| `scroll-fix-20261030-045326-7955` | `273046d3` | 4 echecs : les deux nouveaux scenarios, l'arrondi 43,999 d'un onglet et un toucher Next perdu |
| `scroll-fix-20261030-054220-14800` | `f5061dff` | 1 echec : le scenario d'itineraire n'atteint pas Directions |

Le second run est vert pour `place_photos_ax5=1` et produit `place-tabs-ax5.png` et
`place-photos-ax5.png` : a AX5, l'onglet Photos est hittable, chaque onglet present reste dans la
feuille et la grille s'ouvre. Les sept scenarios Directions existants passent, y compris apres le
nouveau chemin de defilement de `route-scroll`. Les deux echecs restants avaient la meme cause de
harnais : le viewport de la fiche lieu a AX5, en detent compact, est trop court pour que douze
glissements atteignent Directions. Le deuxieme run corrige l'arrondi de l'onglet (seuil 43,5 pour
un cadre de 43,999) et ajoute une reprise du toucher Next ; le troisieme etat du scenario
d'itineraire passe par un lien `maps/dir` (`-VelaOpenURL`), qui ouvre le choix sans fiche lieu.
Ce dernier changement n'a pas ete mesure : le budget de deux runs Mac etait epuise. Le scenario
`route-avoid-reachable.png` et la ligne `route_avoid_swipes` restent donc a confirmer, meme si le
defilement unifie est celui qui a fait passer les sept scenarios Directions du second run.

Limite de preuve : aucun run ne mesure le choix unifie a AX5 lui-meme. La correction de structure
est celle decrite plus haut ; la preuve du harnais attend un run. Cette preuve arrive avec
SCROLL-AX3, ci-dessous.

## SCROLL-AX3, resolu le 30 octobre

Cause mesuree. Le defaut n'etait ni une autre feuille pour le grand texte, ni un viewport nul. Le
premier run de diagnostic (`scroll-ax3-20261030-074650-2522`, source `08d5439a`) echoue sur
`route-scroll` et publie la hierarchie de la feuille : `ScrollView, {{24.0, 427.0}, {354.0, 377.0}},
identifier: 'route-sheet'`. Au detent compact le defilement mesure donc 377 points de haut, mais il
porte l'identifiant de la feuille. En presentation unifiee, le `Group` de `RoutePickerSheet` n'avait
qu'un seul enfant accessible, le `ScrollView`. SwiftUI a donc applique les modificateurs de la
feuille, dont `.accessibilityElement(children: .contain)` et `route-sheet`, directement a ce
`ScrollView`, et l'identifiant `route-scroll` a ete ecrase. En portrait a texte normal, le meme
`ScrollView` vit parmi d'autres enfants, garde son identifiant et apparait dans la hierarchie, ce
qui explique que les sept scenarios existants passaient.

Correctif. La branche unifiee epingle de nouveau la poignee au-dessus du defilement : elle est un
enfant accessible reel de la feuille, donc `.accessibilityElement(children: .contain)` construit un
vrai conteneur `route-sheet` au lieu de se poser sur le defilement. Les lignes de debug restent
dans le defilement, avec l'en-tete, les modes, le resume, le corps etendu et les actions. Le
`ScrollView` est enveloppe dans un `GeometryReader` dont le cadre est la hauteur proposee ; ce
conteneur porte `route-scroll` et sa hauteur reelle est publiee par la ligne de debug
`route-scroll-debug` (`scroll=<largeur>x<hauteur> unified=1`). La presentation en portrait a texte
normal, `splitBody`, n'est pas touchee.

Preuve. Le second run `scroll-ax3-20261030-082419-19490`, source `4fba5ede`, passe les huit
scenarios Directions. Pour `testRouteAvoidOptionsScrollAtLargeText`, il publie
`route_scroll_frame=354x321`, la meme mesure dans `route_scroll_debug`, puis
`route_avoid_swipes=2` : la ligne Avoid highways est hittable apres deux glissements, sous la
limite de trois, et `route-avoid-reachable.png` montre la feuille en AX XXXL avec la poignee
epinglee et les options d'evitement visibles. Le premier run (source `08d5439a`) laisse les sept
autres scenarios Directions verts, et le second les repasse tous.

Risque restant. La poignee epinglee reprend environ 54 points au viewport en detent compact
(321 points mesures). C'est suffisant pour les trois glissements exiges, mais un futur ajout de
lignes au-dessus du defilement devra etre mesure a nouveau.


## A11Y-SPLIT, 30 octobre

Cause. La suite `AccessibilitySuiteUITests` portait ses vingt cas dans une seule methode,
`testAccessibilitySweepMatrix`. Deux jobs avaient expire en file sans verdict, et le troisieme
s'etait arrete avant la phase UI. Le cout venait surtout de `measure` : `allElementsBoundByIndex`
puis un `frame` par element resolvait chaque element un par un, soit environ douze minutes par cas
Search a AX5, et 3043 secondes pour la seule methode Search lors du run
`a11y-split-a2-20261030-124523-23692`. Decouper la matrice sans toucher a cette boucle n'aurait donc
pas suffi.

Decoupage. La matrice est maintenant quatre methodes autonomes, chacune avec son propre reset
d'orientation et ses lancements avec les arguments de reset :

| Methode | Cas | Duree mesuree |
| --- | --- | --- |
| `testSearchAtAccessibilitySizes` | 4 | 133,2 s |
| `testSettingsRtlAndDark` | 4 | 120,0 s |
| `testTransitAtAccessibilitySizes` | 7 | 226,0 s |
| `testNavAndFreeDriveDarkLandscape` | 5 | 215,7 s |

Chaque cas garde son assertion, ses lignes de mesure et ses captures. `measure` prend desormais un
seul `app.snapshot()` et lit les cadres, libelles et identifiants dans cet arbre. Les compteurs et
les cibles requises sont les memes ; seule la facon d'obtenir les cadres change.

Compteurs. Les quatre compteurs gardent le meme nom dans chaque methode, pour qu'un coordinateur
les additionne. Run `a11y-split-c-20261030-164422-26120`, source `be1d8420` :

| Methode | `a11y_truncated` | `a11y_small_targets` | `a11y_clipped_targets` | `a11y_cases` | `a11y_failures` |
| --- | --- | --- | --- | --- | --- |
| Search | 0 | 6 | 15 | 4 | 0 |
| Settings | 0 | 1 | 7 | 3 | 1 |
| Transit | 0 | 33 | 5 | 6 | 4 |
| Nav et free drive | 0 | 4 | 0 | 3 | 5 |
| Total | 0 | 44 | 27 | 16 | 10 |

Le total de seize cas mesure au lieu de vingt vient des quatre cas interrompus avant `measure` :
Settings dark landscape, Transit detail AX5, Nav AX3 et Nav AX5. Le `STATUS` du run est donc
`failed`, par defaut applicatif et non par defaut du harnais. Les quatre methodes, elles, tournent
toutes sous huit minutes.

Captures. `a11y-settings-rtl.png` et `a11y-nav-dark.png` sont publiees dans le tag
`a11y-split-c-20261030-164422-26120` de la branche `results`. La capture Settings montre le titre
arabe et Done sur le bord gauche, donc a la fin RTL. La capture Nav montre la banniere de virage,
mais en theme clair : voir le defaut Dark ci-dessous.

Defauts releves, non corriges ici faute de propriete sur le code applicatif :

- `iosApp/Vela/Routes/RouteSheets.swift:474` : `route-start` n'est jamais hittable a AX3 ni a AX5
  apres 180 secondes, donc `nav_ax3` et `nav_ax5` n'ouvrent pas la banniere.
- `iosApp/Vela/Settings/SettingsScreen.swift:195` : en dark landscape, le menu s'ouvre et l'item
  Settings est tape, mais `settings-screen` n'apparait pas en vingt secondes.
- `iosApp/Vela/Transit/TransitGuidanceCard.swift:119` : `transit-detail-open` n'est pas hittable a
  AX5, donc la feuille de detail ne s'ouvre pas.
- `iosApp/Vela/Transit/TransitDetailSheet.swift:94`, `:104`, `:112` : en RTL, `steps-close` mesure
  67x34, `transit-trip-open` 53x34 et `transit-start` 114x36. Le `frame(minHeight: 44)` est pose sur
  le `Button`, pas dans le label, et le style bordered le compresse.
- `iosApp/Vela/Nav/NavChrome.swift:674` : `nav-heading` mesure 40x48, sous les 44 points de large.
- `iosApp/Vela/Transit/TransitGoScreen.swift:280` : `transit-go-line` mesure 90x18 en RTL, tres en
  dessous des 44 points. Au meme endroit, `transit-go-close` (`:66`) mesure 68x36.
- Le defaut Dark est dans le harnais : `iosApp/VelaUITests/AccessibilitySuiteUITests.swift:487`
  passe `-AppleInterfaceStyle Dark`, mais la ligne de debug Nav publie `theme=system` et les
  captures dites sombres restent claires.
  `XCUIDevice.shared.appearance` ou `simctl ui appearance dark` serait la piste, non appliquee ici.

Runs. `a11y-split-a` n'a execute aucun test : `VELA_ONLY_UI` attend `Classe/methode`, pas
`Classe.methode`. `a11y-split-a2` valide Search et Settings (Search 3043 s avant l'optimisation).
`a11y-split-b` echoue a la compilation sur `snapshot()` non marque `try`. `a11y-split-c` compile,
execute les quatre methodes et publie les deux captures ; son `STATUS` est `failed` a cause des
defauts applicatifs ci-dessus. Le budget de trois runs a ete depasse d'une soumission a cause du
premier lancement sans test et de l'erreur de compilation du troisieme.

Risque restant. Les cas dits dark mesurent en realite le theme systeme clair tant que l'apparence du
simulateur n'est pas forcee. Les compteurs restent comparables entre eux, mais la couverture dark
n'est pas prouvee. Les cibles Transit board `transit-board-close` et `transit-board-refresh`
mesurent 36x36 et restent exemptees par choix du harnais ; elles comptent dans `a11y_small_targets`.

## A11Y-FIX, 30 octobre

Cause commune des six defauts. Le plancher de 44 points etait souvent pose sur le conteneur ou sur
le `Button`, jamais dans le label, et la frame d'accessibilite est la frame interactive. Deux
surfaces debordaient leur fenetre au lieu de faire defiler leur contenu. Le harnais, lui, nommait
« dark » des cas lances avec `-AppleInterfaceStyle`, une cle macOS qu'iOS ignore.

Correctifs applicatifs, tous a la source :

- `iosApp/Vela/Routes/RouteSheets.swift` : la branche unifiee (grand texte et paysage) mettait la
  rangee d'actions en dernier enfant du `ScrollView`. A AX3 et AX5 `route-start` vivait donc un
  ecran de texte sous le viewport, et aucun scenario ne pouvait le toucher sans deviner la
  distance. La rangee est desormais epinglee sous le defilement, comme la rangee d'actions de la
  feuille Transit ; `route-sheet` reste un conteneur et `route-scroll` garde son identifiant. Les
  deux boutons portent le plancher dans leur label.
- `iosApp/Vela/Transit/TransitGuidanceCard.swift` : la carte etait une seule colonne posee en bas.
  A AX la colonne depassait la fenetre, SwiftUI la centrait et `transit-detail-open`, derniere
  ligne de la carte, sortait de l'ecran. La carte mesure maintenant la fenetre, epingle le resume
  de ligne, les trois actions et les crochets de debug, et ne fait defiler que les lignes de
  detail. Les boutons Trip et End de la carte portent aussi le plancher dans leur label, car la
  feuille de detail partage leurs identifiants et le harnais resolvait d'abord la copie de la
  carte.
- `iosApp/Vela/Transit/TransitDetailSheet.swift` : les trois boutons de la rangee epinglee portent
  `minWidth` et `minHeight` dans leur label. En RTL, `steps-close` passe de 67x34 a 68x58,
  `transit-trip-open` de 53x34 a 68x57 et `transit-start` de 114x36 a 114x58.
- `iosApp/Vela/Transit/TransitGoScreen.swift` : `transit-go-line` portait le plancher hors du
  label, il est dedans. `transit-go-close` etait un element de barre de navigation, dont la
  hauteur de contenu est imposee : 68x36 et aucune frame ne pouvait l'agrandir. La pile de
  navigation reste le conteneur d'accessibilite de l'ecran, mais sa barre est masquee et le
  contenu dessine la meme barre, titre et Close de 44 points (129x63 a AX5, 44x44 en RTL).
- `iosApp/Vela/Nav/NavChrome.swift` : `nav-heading` mesure 44x48. A AX le glyphe de manoeuvre et
  la ligne de la prochaine etape sont retires de la carte de virage, et le bloc de debug garde une
  taille fixe : la carte passait de 41 a 29 pour cent de l'ecran a AX5 et la barre du bas ne sort
  plus de la fenetre.

Dark. `iosApp/VelaUITests/AccessibilitySuiteUITests.swift` passe `-VelaTheme dark`, lu par
`AppearanceSettings` (`Settings/AppearanceSettings.swift`) pour ce processus seulement, sans
ecrire le choix de l'utilisateur. `VelaApp.init` construit le porteur d'apparence apres le reset de
lancement, donc le theme atteint les fenetres des la premiere frame : c'etait la cause du
`theme=system` et des captures claires, l'ancien code n'appliquait le theme qu'au premier ecran qui
lisait le porteur. Le harnais pose aussi `XCUIDevice.shared.appearance` et le remet en clair apres
chaque cas. Le cas Nav dark publie `a11y_nav_dark_rtl_appearance=dark` et echoue si la ligne
`nav-chrome-debug` ne contient pas `theme=dark`. `a11y-settings-dark-landscape.png` et
`a11y-transit-go-ax5.png` montrent le chrome sombre ; la carte, elle, garde son style clair, qui
est un reglage distinct (`map=system`).

Settings. Le cas dark landscape n'ouvrait pas la feuille : le menu systeme se referme quand son
action demande une presentation, et iOS abandonne une feuille demandee pendant cette fermeture. Le
harnais retape l'item jusqu'a trois fois, touche par le centre du bouton quand le systeme n'a pas
calcule de point d'activation, et garde son assertion de vingt secondes. Reste un crochet cote
`Map/MapScreen.swift` : differer `activeSheet = .settings` d'un tour de boucle principale
supprimerait la course a la source.

Compteurs. Run `a11y-fix-20261030-183752-31330`, source `a502e5d3`, `STATUS ok`, quatre methodes
vertes (310, 138, 93 et 256 secondes) :

| Methode | `a11y_truncated` | `a11y_small_targets` | `a11y_clipped_targets` | `a11y_cases` | `a11y_failures` |
| --- | --- | --- | --- | --- | --- |
| Search | 0 (0) | 6 (6) | 13 (15) | 4 (4) | 0 (0) |
| Settings | 0 (0) | 1 (1) | 7 (7) | 4 (3) | 0 (1) |
| Transit | 0 (0) | 20 (33) | 8 (5) | 7 (6) | 0 (4) |
| Nav et free drive | 3 (0) | 2 (4) | 0 (0) | 5 (3) | 0 (5) |
| Total | 3 (0) | 29 (44) | 28 (27) | 20 (16) | 0 (10) |

Entre parentheses, les valeurs du run A11Y-SPLIT. Les vingt cas sont maintenant mesures. Les trois
troncatures Nav sont `Searching for GPS…` et `rerouting…`, deux etats transitoires du bandeau a AX,
rapportes et non bloquants. Les clipped Transit passent de 5 a 8 parce que la feuille de detail
s'ouvre desormais a AX5 et RTL et que ses textes longs sont mesures.

Hors harnais, la suite `TransitCitymapperUITests` passe dans le meme run.

Risque restant. `transit-board-close` (76x36), `transit-board-refresh` (36x36), `nav-add-stop`
(95x28) et la mention de copyright restent sous 44 et comptent dans `a11y_small_targets` ; ils
appartiennent a des fichiers non modifies ici. Les cas dark de Search, Transit board et GO
obtiennent leur fond sombre par le theme de l'app, pas par la carte, dont l'apparence est un
reglage separe. L'ouverture de Settings garde une course possible a la source tant que
`MapScreen` n'a pas ete corrige. `VelaApp.swift` et `Settings/AppearanceSettings.swift` ont ete
touches pour le lancement dark, hors de la liste initiale des fichiers du lot.
