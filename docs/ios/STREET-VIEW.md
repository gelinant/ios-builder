# Street View interactif sur iOS

État au lot SV-HIST, sur la branche `ios/sv-hist`, après SV-1. Ce document décrit ce que le
visualiseur fait, comment il charge ses tuiles, ce que les tests prouvent et ce qui reste absent.
La référence fonctionnelle est `SPEC.md` 10.7. SV-1 couvre la consultation d'un panorama ; SV-HIST
ajoute l'historique des captures, le cône de cap et le cache de métadonnées.

## Entrées

- La vignette Street View de la fiche lieu est un bouton. Elle ouvre le visualiseur plein écran au
  point du lieu, avec l'identifiant de panorama et l'orientation que la fiche connaît déjà. La
  fiche reste ouverte derrière : fermer le visualiseur ramène à la fiche.
- `-VelaStreetViewFixture YES` (Debug seulement) ouvre directement le visualiseur sur une image
  équirectangulaire synthétique. C'est le repli du scénario de CI quand Google ne renvoie aucune
  imagerie à l'adresse du runner.
- Aucune WebView, aucun appel à la carte Google embarquée : le panorama est rendu par l'app.

## Métadonnées et choix du panorama

Tout passe par `StreetViewParser` en `:core-common`, sans clé d'API.

1. Si la fiche fournit un `svPanoId`, le magasin demande d'abord ce panorama par identifiant
   (`streetViewByPano`, `photometa/v1`). C'est le panorama exact de la vignette.
2. Sinon, ou si la réponse par identifiant est vide, il demande le panorama le plus proche
   (`streetView`) avec la rue de l'adresse (`StreetViewParser.streetOf`). La source Google commune
   préfère alors un panorama de la rue de l'adresse à celui d'une ruelle derrière la parcelle,
   exactement comme Android.
3. Sans imagerie, l'état porte `no_imagery` et l'écran affiche « No Street View imagery here ». Aucun
   panorama n'est inventé.

La direction d'ouverture est passée séparément (`initialFacingDeg`) : l'orientation de capture
(`headingDeg`) reste la référence de texture et n'est jamais écrasée. La fiche fournit l'azimut du
panorama vers le lieu quand elle le connaît. À l'ouverture, le cap affiché est donc celui de la
fiche ; il ne dépend pas de `headingDeg`, qui peut différer de 180° entre deux captures.

## Historique des captures

`StreetViewHistory` filtre la liste que Google renvoie dans `StreetViewPano.history` : entrées
valides, dédoublonnées par identifiant de panorama, triées de la plus récente à la plus ancienne.
La puce `street-view-history` n'apparaît que si cette liste contient au moins deux dates. Sans
historique, aucune liste n'est dessinée et la ligne de crédit affiche seulement la date de la
capture visible. Sans date du tout, rien n'est inventé.

Choisir une date dans `street-view-history-date-<n>` charge la capture par son identifiant
(`photometa/v1`), une seule requête de métadonnées, puis ses tuiles par le cache disque ou le
réseau. La capture ancienne apporte sa propre orientation de texture et sa propre pyramide
(416·2^z avant 2016). Le graphe de voisins et la liste de dates restent ceux du point de base :
revenir à la capture la plus récente restaure les flèches et la puce. Le cap courant est conservé :
la conversion passe par `yawForCompass` avec la nouvelle orientation de capture, donc l'image ne
tourne pas pendant le changement. Une métadonnée indisponible n'invente ni date ni orientation :
le visualiseur garde la pyramide et l'orientation du point de base avec l'identifiant de la
capture choisie.

Le parseur ne lit que l'année et le mois (`[1][6][7]`). Quand la métadonnée ne porte pas ces deux
champs, la puce et la date disparaissent au lieu d'afficher une valeur de remplacement.

## Rendu

`iosApp/Vela/StreetView/` :

- `StreetViewScene.swift` : une sphère SceneKit vue de l'intérieur pour le fond 360°, puis des
  quads de tuiles posés sur la sphère pour la zone regardée. La caméra est à l'origine ; le yaw 0
  regarde `u = 0.75` de l'équirectangulaire, comme `PanoramaView` sur Android. La conversion
  azimut vers yaw est centralisée dans `StreetViewTiles.yawForCompass` et testée sur JVM.
- `StreetViewTilesModel.swift` : niveau de base puis tuiles de détail, cache d'images borné,
  sélection des tuiles visibles, annulation du hors-champ, assemblage de la base.
- `StreetViewView.swift` : gestes, boussole, bouton nord, zoom, flèches de voisinage, crédits et
  ligne de debug.
- `StreetViewModel.swift` : miroir SwiftUI de `StreetViewStore`, l'état Kotlin du lot.

Le glissement horizontal suit le doigt et boucle à 360°. Le glissement vertical s'arrête à 85°
vers le haut ou le bas. Le pincement et les boutons + / - règlent le champ horizontal entre 30° et
110°, la plage d'Android. Le champ vertical se déduit du rapport largeur/hauteur de la fenêtre.

La boussole affiche le cap vrai (N/NE/E… et degrés). Son cône de cap, de la largeur du champ
horizontal, suit la direction regardée, comme le cône qu'Android dessine sur la carte ; l'aiguille
nord tourne à l'envers du panorama. Le bouton « Face north » remet le cap à 0° sans toucher à
l'orientation de capture du panorama. Le visualiseur iOS est plein écran, donc le cône est dans le
cadran et non sur la carte.

Les flèches de voisinage viennent du graphe de `StreetViewParser` : une flèche par panorama voisin
dans l'arc visible, à son azimut relatif. Un toucher recharge le voisin par son identifiant
(`streetViewByPano`), jamais par une recherche au plus proche, donc on avance sur la même capture
et pas sur une autre année au même endroit. C'est une étape, pas une navigation automatique.

La ligne de crédit affiche le libellé du lieu, la date de capture et le copyright quand les
métadonnées les portent. Le panneau haut répète le libellé et la date.

## Tuiles, réseau et cache

Le niveau de base est le plus haut niveau dont la largeur ne dépasse pas 1024 px (deux tuiles sur un
panorama moderne). Il est assemblé en une image et affiché tout de suite. Le niveau de détail est le
plus haut niveau sous 4096 px de large, comme la cible d'Android ; seules les tuiles qui recouvrent
le champ visible, avec une tuile de marge, sont demandées. La grille est dimensionnée depuis la
liste de niveaux du panorama lui-même : les captures antérieures à 2016 font 416·2^z et non
512·2^z.

- Les requêtes passent par le client HTTP commun (`CoreGraph.http`, donc `URLSession` sur iOS) avec
  les en-têtes d'image de l'identité Safari (`StreetViewTiles.REFERER`, `ACCEPT`).
- L'URL est le modèle public `streetviewpixels-pa.googleapis.com/v1/tile` construit par
  `StreetViewTiles.url` et vérifié par un test JVM.
- Le disque passe par `StreetViewCache` : tuiles sous le dossier de cache en
  `svtiles/<pano>-<z>-<x>-<y>.jpg`, plafonnées à 24 Mo et 512 fichiers, les plus anciennes
  supprimées en premier. Les métadonnées des panoramas vus sont enregistrées sous
  `<filesDir>/svcache`, ce qui rend un changement de capture ou une réouverture servis par le
  disque sans nouvelle requête. Un même identifiant de panorama et la même tuile donnent toujours
  la même clé ; deux captures différentes ne partagent jamais une tuile.
- En mémoire, l'image décodée est gardée dans un `NSCache` de 64 entrées ; côté Kotlin, seules les
  requêtes en vol sont mémorisées. Un changement de point de vue annule les requêtes hors champ
  (`cancelTiles`), et la fermeture annule tout.
- Rien n'est demandé hors ligne ni quand Google est désactivé : `NoGoogle` coupe le panorama et les
  tuiles.

Performance : la sphère de fond fait 64 × 32 segments et une texture de 1024 × 512 au plus ; les
tuiles de détail affichées sont au nombre d'une dizaine à une vingtaine sur un écran de téléphone.
SceneKit rend en continu à 60 images/s pendant que le visualiseur est ouvert, puis l'écran est
détruit à la fermeture. Aucune texture 8192 × 4096 n'est créée.

## Tests

JVM (`ios-shared/src/commonTest/.../streetview/`) :

- `StreetViewTilesTest` : URL exacte, clé de cache, clés distinctes entre deux captures, niveaux
  moderne et 416, conversion azimut/yaw, sélection des tuiles visibles et bouclage au raccord,
  bornes aux pôles.
- `StreetViewHistoryTest` : liste dédoublonnée, valide et triée, date unique sans historique,
  absence de date sans invention.
- `StreetViewStoreTest` : rue de l'adresse transmise, panorama de vignette demandé par identifiant,
  repli au plus proche, aucune imagerie, marche par identifiant et conservation du panorama courant
  en cas d'échec, changement de capture avec orientation et historique du point de base, seconde
  visite d'une capture ancienne servie par le cache sans requête, repli sans métadonnée, cache
  disque avant réseau, client HTTP et en-têtes d'image, fermeture.
- `StreetViewCacheTest` : fichier de tuile sous sa propre clé, lecture, absence, effacement.

Scénario interface `StreetViewUITests.testStreetViewFromPlace` : ouvre « Davis Food Co-op », fait
apparaître la vignette, ouvre le visualiseur, vérifie le cône de cap, ouvre la liste des dates,
choisit la capture précédente, vérifie que le cap ne tourne pas et que l'année change, revient à la
capture la plus récente, glisse, zoome, remet au nord, ferme et vérifie le retour de la fiche. Si
Google ne fournit pas de panorama au runner, il relance avec `-VelaStreetViewFixture YES` et
exécute les mêmes gestes ; le panorama de test porte trois dates. Le résumé porte
`street_view_mode=live` ou `fixture`, `street_view_dates`, `street_view_history_bearing` et
`street_view_history_year`. Captures : `street-view.png`, `street-view-cone.png`,
`street-view-history-list.png`, `street-view-history.png`, `street-view-zoom.png`.

La ligne de debug `street-view-debug` porte `pano=`, `loading=`, `error=`, `year=`, `month=`,
`yaw=`, `pitch=`, `fov=`, `bearing=`, `tiles=`, `base=`, `level=`, `neighbors=`, `hist=`
(capture ancienne affichée), `dates=` et `fixture=`. Elle ne contient aucune coordonnée.

Le run `sv1-street-view-20261026-210952-29650` exécute le scénario en mode `live` (panorama réel
`kwZQQxxOy-_Gcjs76I_Yrw`, 20 tuiles, 5 voisins) : le toucher de vignette, le glissement, le zoom,
le retour au nord et la fermeture passent. Ses captures ont toutefois révélé que SceneKit prend
l'origine V de la texture en haut à gauche : les tuiles étaient rendues à l'envers. La correction
(axe V direct, quads de détail tessellés) est poussée après ce run et demande un run ciblé de
confirmation.

## Limites assumées

- Pas de retour de pose vers la carte : Android dessine un cône de vue et un point sous la fenêtre
  Street View. Ici le visualiseur est plein écran et la carte ne bouge pas ; le cône de cap est donc
  dans le cadran de la boussole. Un retour de pose demanderait un point d'accroche dans
  `MapScreen.swift`, hors de ce lot.
- Le cache de métadonnées ne remplace pas une région téléchargée : le visualiseur ne connaît pas
  les régions hors ligne, donc il ne peut pas décider seul de ne rien demander dedans. Le blocage
  actuel est `NoGoogle`, qui coupe panorama et tuiles. Le cache disque sert d'abord, puis le réseau
  si la tuile ou la métadonnée manque.
- Pas d'entrée par appui long sur la carte. L'entrée est la vignette de la fiche ; le lancement
  fixture est réservé aux tests.
- Pas de transition en fondu entre deux panoramas : la nouvelle texture remplace l'ancienne.
- Le sens vertical de la texture SceneKit a été mesuré faux sur le premier run complet : l'origine
  V est en haut, la correction est dans le code mais aucune capture postérieure ne la confirme
  encore. C'est la première chose à vérifier au prochain run ciblé.
- Le rendu, les gestes et la mémoire restent à vérifier sur iPhone réel ; la CI est un simulateur.

## À vérifier sur iPhone

1. Ouvrir une fiche avec vignette, toucher la vignette, vérifier que le panorama est orienté vers
   le lieu comme la vignette, qu'il n'est ni miroir ni à l'envers, et que le texte des devantures
   se lit.
1b. Ouvrir la puce de dates, choisir une capture ancienne, vérifier que l'image ne tourne pas, que
   la date et le copyright affichés suivent la capture, puis revenir à la plus récente.
2. Glisser dans les deux sens jusqu'au raccord 360°, monter et descendre jusqu'aux limites, pincer
   et utiliser les boutons de zoom.
3. Toucher la boussole nord et vérifier que le cap affiché revient à 0°.
4. Marcher avec une flèche sur quelques panoramas, vérifier l'orientation du nouveau panorama et
   le crédit mis à jour.
5. Fermer le visualiseur et vérifier que la fiche lieu et la carte reviennent dans le même état.
6. En mode avion et avec Google désactivé, vérifier le message d'absence d'imagerie et l'absence de
   requêtes.
7. Mesurer la mémoire et la batterie sur plusieurs minutes de panorama, puis en mode sombre.
