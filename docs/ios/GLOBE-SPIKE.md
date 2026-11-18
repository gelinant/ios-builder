# G-1 : verdict sur le globe natif de MapLibre

> Question : la pre-release `ios-v2026.10.19-globe` de MapLibre Native, construite avec
> `MLN_WITH_GLOBE`, est-elle assez solide pour que G-2 l'intègre à la carte Vela plutôt que de
> livrer un écran Globe séparé en MapLibre GL JS ? Réponse : **oui, adopter le natif**, avec quatre
> conditions de mise en œuvre (plafond de zoom arrière, fond hors du globe, revalidation à chaque
> release, essai PMTiles) décrites au §5. Le globe tourne, se manipule, conserve une caméra
> bornée et coûte 16,5 Mio à l'app de démonstration. L'atmosphère n'est pas rendue et le fond
> autour de la planète reste blanc : c'est un travail de G-2, pas un motif de repli.

## 1. Méthode

- **Release épinglée.** `scripts/ios/fetch-maplibre-globe.sh` télécharge
  `MapLibre.dynamic.xcframework.zip` depuis la release GitHub `ios-v2026.10.19-globe`, avec la
  taille (169 968 107 octets) et le SHA-256
  `ae9c967acf220111d8fb1c8f066d23cff0d91c5ec827c8f68770d4cd55f799e8` inscrits dans le script.
  Une release supprimée, un asset renommé, une taille ou une somme qui diffère font échouer le
  script avant toute construction. Le script vérifie aussi que le binaire exporte
  `isCoordinateOccluded:`, symbole propre au build globe. L'archive n'est jamais commitée :
  `tools/ios-globe-spike/Vendor/` est ignoré.
- **Application jetable.** `tools/ios-globe-spike/` (XcodeGen, SwiftUI) ne partage aucun fichier
  avec `iosApp/`. Un seul `MLNMapView`, un sélecteur Mercator / Globe, un bandeau de caméra
  (`zoom`, `bearing`, `pitch`, `lat`, `lon`) et un pilote automatique qui bascule la projection,
  règle z3, tourne 90 degrés en 10 s, recule de z3 à z0 en 10 s, sonde les bornes, puis incline à
  45 degrés. La projection est une propriété du document de style : `"projection": {"type":
  "globe"}`. Le style de test est local et dessine trois couches OpenFreeMap (`landcover`, `water`,
  `boundary`) pour que la planète soit lisible sans dépendre d'un style serveur.
- **Mesures.** `mapViewDidFinishRenderingFrame` compte les images rendues pendant chaque animation.
  La taille de l'app est comparée à `GlobeBaseline`, une app SwiftUI vide construite dans le même
  projet, sans MapLibre. Les bornes sont lues après des demandes hors limites (`setZoomLevel(-3)`,
  `setZoomLevel(30)`, pitch 80). `isCoordinateOccluded:` est interrogé au centre et à l'antipode.
- **Gestes.** Un test XCUITest lance l'app en mode geste à z2, pince deux fois puis balaie
  horizontalement, et lit le bandeau de caméra après chaque geste.
- **Où.** Runner `macos-latest` du builder, macOS 26.6.2, Xcode 26.6 (17F113), simulateur iPhone 17
  (iOS 26.5), écran 402 x 874 pt à 3x.
- **Reproduction.** Depuis le worktree :
  `~/gmaps/ios-builder/scripts/mac-run.sh /home/antoine/gmaps/wt/g1-globe g1-globe scripts/ios/ci-globe-spike.sh`
  (script `scripts/ios/ci-globe-spike.sh`, `$OUT` fourni par le workflow, `STATUS`, `log.txt` et
  `summary.txt` dans `$OUT`).

## 2. Runs

Deux lancements, budget consommé.

| Run | Tag | Résultat |
|---|---|---|
| 1 | `g1-globe-20261028-132357-18120` | échec de compilation : cinq noms Swift importés du framework (`setCenter`, `isRotateEnabled`, `isPitchEnabled`, `isZoomEnabled`) ; aucune app lancée |
| 2 | `g1-globe-20261028-134040-28343` | vert : build, pilote automatique, trois captures, test de gestes passé |

## 3. Résultats

### 3.1 Taille et temps

| Mesure | Valeur |
|---|---|
| Archive téléchargée | 169 968 107 octets (162,1 Mio), 8 s |
| xcframework décompressé | 603 564 Kio (589,4 Mio) : tranche device 191 Mio, tranche simulateur 398 Mio |
| App spike, Debug simulateur | 17 112 Kio (16,7 Mio) |
| App témoin sans MapLibre | 232 Kio (0,23 Mio) |
| Delta d'app | 16 880 Kio (16,5 Mio), dont `MapLibre.framework` 16 720 Kio (16,3 Mio) |
| Binaire de l'app | 40 344 octets |
| Build app et tests | 8 s après un build témoin de 26 s |
| Aller-retour de projection | 0,003 s pour le style local à trois couches |

Le delta de 16,5 Mio est une mesure Debug simulateur, sans élagage ni archive. Le gain de 208 Kio
annoncé dans le backlog n'est pas reproductible ici : il n'existe pas de build Mercator de
référence dans ce projet jetable. L'ordre de grandeur à retenir pour G-2 est « un framework de
16 Mio dans l'app », pas « 208 Kio ».

### 3.2 Images par seconde

| Animation | Images | Durée | fps | Images par seconde utiles |
|---|---:|---:|---:|---|
| Rotation de 90 degrés à z3 | 614 | 11,02 s | 55,7 | plafond simulateur 60 Hz |
| Reculement z3 vers z0 | 606 | 11,00 s | 55,1 | plafond simulateur 60 Hz |

Les fps du simulateur sont proches du plafond de 60 Hz et ne mesurent pas un iPhone : ni le GPU,
ni la chauffe, ni le throttling ne sont représentés. Le temps de rendu par image rapporté par le
délégué est resté à zéro dans cette version du framework, donc il n'est pas cité. La preuve utile
est l'absence de chute visible pendant les deux animations, pas la valeur absolue.

### 3.3 Caméra et occlusion

| Sonde | Résultat |
|---|---|
| `minimumZoomLevel` | 0 |
| `maximumZoomLevel` | 22 |
| `maximumPitch` | 59,999999999999993 (60) |
| `setZoomLevel(-3)` puis lecture | -0,0897 |
| `setZoomLevel(30)` puis lecture | 22 |
| pitch 80 puis lecture | 60 |
| `isCoordinateOccluded` au centre, z0 | faux |
| `isCoordinateOccluded` à l'antipode, z0 | vrai |

Deux constats pour G-2. D'abord, `minimumZoomLevel = 0` ne borne pas une demande
programmatique : la caméra accepte -0,09, alors que le pincement s'arrête vers 0,03. Il faut
clamper la caméra explicitement, sans se fier à la propriété. Ensuite, l'occlusion fonctionne :
G-2 peut masquer les épingles passées derrière la planète au lieu de les laisser flotter.

### 3.4 Zoom arrière maximal utile

La caméra descend à z0 (et même à -0,09 par appel direct), mais la planète rétrécit sans rien
apporter. Sur la capture inclinée à z1, le disque mesure 1 096 px sur 1 206 px de large, soit
90,9 % de l'écran. À z0, par la loi du facteur 2 par niveau, il ferait environ 548 px, soit 45,4 %
de la largeur, avec une marge blanche de plus en plus grande. **Le zoom arrière maximal utile est
donc z1, pas z0.** G-2 doit plafonner le globe à z1 (ou à 0,9 près) tant que le fond hors planète
n'est pas habillé.

### 3.5 Gestes

| Geste | Avant | Après |
|---|---|---|
| Pincement arrière (échelle 0,25) | zoom 2,00, lon 0,00 | zoom 0,03, lon 0,51 |
| Pincement avant (échelle 2,5) | zoom 0,03 | zoom 1,16, bearing 329,3 |
| Balayage horizontal | zoom 1,16, lon 0,29, bearing 329,3 | zoom 1,22, lon 136,71, bearing 34,7 |

Le pincement se comporte comme sur une carte : il s'arrête près de z0 et revient. Le balayage
confirme la note de release : sur le globe, le glissement fait tourner la planète et change aussi
le cap, la longitude passe de 0,29 à 136,71 en un seul balayage à z1,16. C'est conforme au
comportement voulu (le lieu sous le doigt reste sous le doigt) mais très sensible à bas zoom : G-2
doit régler la vitesse de rotation ou borner le cap si la carte principale devient désorientante.

### 3.6 Captures

Les trois fichiers sont dans `results/g1-globe-20261028-134040-28343/` du builder.

| Fichier | État réel |
|---|---|
| `globe-z3.png` | z3, cap 36,6 degrés, pendant la rotation, la planète remplit l'écran |
| `globe-z0.png` | **défaut de capture** : le simulateur a mis une quinzaine de secondes à écrire la première image, l'app avait déjà incliné la caméra ; le bandeau affiche zoom 1,00, pitch 45 |
| `globe-tilted.png` | z1, pitch 45, cap 20, planète entière dans un fond blanc ; identique à `globe-z0.png` |

La capture z0 manque donc à cause du décalage entre les marqueurs de l'app et `simctl io
screenshot`, pas à cause du globe. L'état z0 est prouvé par le rapport (`atZoom: 0`, occlusion
centre faux et antipode vrai, zoom minimal 0) et par le reculement mesuré, mais il n'a pas
d'image propre. Un prochain passage devrait tenir chaque état jusqu'à l'accusé de réception de la
capture, ou capturer dans l'app. Le budget de deux lancements ne permet pas de le refaire ici.

La capture inclinée montre aussi le défaut visuel principal : hors de la planète, l'écran est
blanc. La couche `background` du style ne remplit pas la zone hors globe. MapLibre ne fournit ni
ciel ni atmosphère dans ce build (aucune chaîne `atmosphere` dans le binaire), et le blanc est le
fond par défaut de `MLNMapView`. G-2 doit poser un fond sombre derrière la carte ou dessiner une
atmosphère en SwiftUI ; sans cela le globe flotte dans du blanc.

## 4. Verdict

**Adopter le globe natif pour G-2.** La pre-release construit, s'installe, rend, se manipule et
expose l'occlusion. Le coût mesuré est de 16,5 Mio dans l'app et le changement de projection est
immédiat sur un style local. Les défauts constatés sont soit des réglages de G-2 (zoom plafonné à
z1, fond sombre, sensibilité du glissement), soit des manques assumés du build (atmosphère
absente, pré-release à revalider). Aucun ne justifie un écran GL JS séparé, qui perdrait les
calques, les épingles, les itinéraires et le hors ligne de la carte principale.

Le repli prévu par D15 et G-2, s'il devenait nécessaire, resterait un écran Globe séparé en
MapLibre GL JS dans une WKWebView, en lecture seule, avec une entrée depuis la carte : un lien et
non un remplacement de projection, donc sans retour de caméra ni calques.

## 5. Risques et conditions pour G-2

1. **Pré-release.** La release est marquée pre-release, le tag est figé et l'API peut changer.
   G-2 doit vendorer `MapLibre.xcframework`, remplacer le paquet SPM, et revalider à chaque
   montée de version. Le script de fetch doit être rejoué avec le nouveau tag, la taille et la
   somme, jamais avec `latest`. Le framework pèse 589 Mio décompressé et 162 Mio en archive : le
   cache du runner et le temps de téléchargement comptent.
2. **Atmosphère absente.** Pas de ciel, pas de halo, pas d'étoiles, et le fond hors planète est
   blanc par défaut. Un fond sombre suffit à rendre la planète lisible ; une atmosphère réaliste
   demanderait un rendu Metal ou une couche GL JS, hors périmètre de G-2.
3. **Bascule de projection par rechargement de style.** Les 0,003 s mesurées portent sur un style
   local de trois couches. Le style réel a six variantes, des sources distantes, des couches
   ajoutées par `MapController` et des PMTiles hors ligne. G-2 doit mesurer le rechargement réel,
   conserver la caméra (milieu, zoom, cap, inclinaison) et réappliquer les calques après
   `styleDidLoad`.
4. **PMTiles et hors ligne non testés.** Le spike ne charge ni PMTiles ni tuiles en cache. Le
   globe avec une source hors ligne n'est pas prouvé ; c'est le premier essai à faire en G-2.
5. **Bornes incohérentes.** `minimumZoomLevel` à 0 n'empêche pas un zoom programmatique à -0,09.
   Clamper la caméra et le geste séparément.
6. **fps simulateur seulement.** 55 fps sur le Mac du runner ne disent rien d'un iPhone SE ou d'un
   iPhone 12. La passe iPhone de G-2 reste obligatoire, avec chauffe et batterie.
7. **Notices.** `python3 scripts/ios/check_notices.py` reste vert (29 entrées, 7 bibliothèques,
   21 sources). `tools/` n'est pas scanné par le script. G-2 devra mapper le framework vendoré
   vers la notice `maplibre` dans `VENDOR_FRAMEWORKS` ; aucune notice nouvelle n'est nécessaire.

## 6. Ce que devient G-2

- `iosApp/project.yml` : remplacer le paquet SPM `MapLibre` par
  `Vendor/MapLibreGlobe.xcframework` (ou un nom voisin), avec le script de fetch et la somme
  épinglée.
- `MapView.swift` et `MapController.swift` : projeter le globe seulement quand la feuille de
  couches le demande, conserver la caméra dans les deux sens, clamper le zoom arrière à z1 en
  globe, et poser un fond sombre derrière la carte.
- `MapStyleBuilder.swift` et `LayersView.swift` : ajouter `"projection": {"type": "globe"}` au
  document chargé, mesurer le rechargement, réappliquer épingles, itinéraires et PMTiles.
- `GlobeSettings.kt` et son test : projection, conservation de caméra, drapeau hors ligne.
- `GlobeUITests` : `globe.png`, `globe-mercator.png`, `globe-offline.png`, plus une capture z1
  pour le plafond de zoom arrière.
- Vérifier sur un iPhone réel les fps, la chauffe et la sensibilité du glissement à z1 ; si le
  glissement reste trop nerveux, borner le cap en globe ou passer la rotation sur un bouton.

## 7. Livraison G-2

G-2 livre le globe natif dans l'application, à la suite du verdict du §4.

### 7.1 Ce qui est branché

- **Framework.** `iosApp/project.yml` ne référence plus le paquet SPM `MapLibre` 6.31.0 : le
  binaire est `Vendor/MapLibre.xcframework`, récupéré par
  `scripts/ios/fetch-maplibre-globe.sh app`. Le script garde le tag `ios-v2026.10.19-globe`, la
  taille 169 968 107 octets et la somme SHA-256 du §1. Il est appelé avant XcodeGen
  (`preGenCommand`) et avant la compilation de l'app, donc le projet généré pointe toujours sur un
  fichier réel. `iosApp/Vendor/` reste ignoré par Git. `scripts/ios/check_notices.py` mappe le
  framework vendu vers la notice `maplibre`, qui existait déjà.
- **Projection.** `MapStyleBuilder` écrit `"projection": {"type": "globe"}` dans le document de
  style quand le réglage le demande, et retire la clé en Mercator. Le réglage est stocké par
  `GlobeSettingsStore` dans `:ios-shared`, sous la clé stable `map_projection`, avec les valeurs
  `mercator` et `globe`. La feuille de couches expose une ligne `Globe` (`layer-globe`), masquée
  en explication si le framework lié n'est pas le build globe (`isCoordinateOccluded:` absent).
- **Caméra.** Avant le rechargement, `MapController` capture le centre, le zoom, le cap et
  l'inclinaison. `styleDidLoad` les remet en une passe non animée, puis compare la caméra réelle
  à la capture. La ligne `globe_camera_kept=1` est la preuve du test.
- **Bascule.** Le style en ligne reçoit un nom de cache qui contient la projection ; le style hors
  ligne est recopié à côté de l'archive PMTiles avec un suffixe `-globe` ou `-mercator`. Les deux
  URL diffèrent, donc MapLibre recharge réellement le style, et `styleDidLoad` réapplique routes,
  épingles enregistrées, formes, calques locaux, trafic, caméras, arbres, marquages, libellés et
  la source `pmtiles://` de la région téléchargée.
- **Plafond de zoom.** Le globe est borné à z1 par `minimumZoomLevel` et par un clamp explicite
  dans `regionDidChange`, car G-1 a mesuré que la propriété seule acceptait -0,09. La ligne
  `globe_zoom_clamp=1` accompagne le zoom courant dans `globe-debug`.
- **Fond hors planète.** `MLNMapView.backgroundColor` et la couche du même nom passent au bleu
  nuit `#090D14` (0,035 / 0,051 / 0,078) en globe, et restent blancs en Mercator. Aucune
  atmosphère n'est inventée : le build n'en porte pas.

### 7.2 Ce qui survit et ce qui ne survit pas

Survivent au changement de projection, par le rejeu de `styleDidLoad` : les itinéraires et le
trajet de navigation, les épingles de résultats et d'arrêts, les épingles enregistrées (annotations),
les formes enregistrées, les calques OSM, les deux rasters Google et Esri, les arbres, les
marquages peints, les libellés du style, les arrêts et lignes Transitous, les TLE du calque monde
et la source PMTiles d'une région téléchargée. La caméra revient au zoom, au centre, au cap et à
l'inclinaison d'avant.

Ne survivent pas, par construction : la position d'un curseur de feuille ouverte, les animations
en cours (une bascule les termine), et l'atmosphère, que ce build ne rend pas. Une carte en
Mercator garde le comportement d'avant.

### 7.3 Coût et risques

Le coût mesuré par G-1 reste la référence : 589,4 Mio pour l'xcframework décompressé, 162,1 Mio
pour l'archive téléchargée, et environ 16,5 Mio pour l'app de démonstration Debug simulateur. Le
chiffre d'app n'est pas remesuré ici : l'IPA de G-2 n'a pas été pesé dans ce lot.

Risques assumés : la release est une pré-release, donc **toute montée de version de MapLibre exige
de rejouer `fetch-maplibre-globe.sh` avec le nouveau tag, la nouvelle taille et la nouvelle somme,
puis de revalider le globe** (projection, occlusion, gestes, PMTiles, caméra, captures). Le script
n'accepte jamais `latest`. Les fps restent mesurés sur simulateur ; la passe iPhone sur la chauffe,
la batterie et la sensibilité du glissement à z1 reste humaine. Le fond sombre remplace le blanc,
mais il n'y a ni ciel, ni halo, ni étoiles.

### 7.4 Preuves

- JVM : `app.vela.ios.map.GlobeSettingsTest` couvre la clé stable, la persistance, le repli sur
  Mercator pour une valeur inconnue et le plancher z1 (0,4 et -0,09 remontent à 1,0).
- Simulateur : `GlobeUITests.testSwitchToGlobeAndBack` capture `globe-in-app.png`, `globe-z1.png`,
  `globe-back.png` et `globe-offline.png`, puis écrit `globe_projection=globe|mercator`,
  `globe_zoom_clamp=1`, `globe_camera_kept=1` et `globe_offline=1`. La partie hors ligne installe
  la région fictive de Monaco, coupe le réseau et vérifie `archive=monaco.pmtiles remote=0`.
  L'archive de test est synthétique : la capture prouve que le PMTiles est monté dans le style du
  globe avec zéro URL distante, pas la cartographie d'une vraie région.
- Linux : `:core-common:jvmTest`, `:ios-shared:jvmTest` et
  `:ios-shared:compileKotlinIosSimulatorArm64` sont verts.
- Run Mac : `g2-globe-20261029-192003-25030`, `STATUS ok`, commit testé `583f4f87`. Le build
  simulateur, les 188 tests unitaires et les sept scénarios `GlobeUITests` et `MapLayersUITests`
  passent. Les quatre PNG sont dans `results/g2-globe-20261029-192003-25030/` du builder.
