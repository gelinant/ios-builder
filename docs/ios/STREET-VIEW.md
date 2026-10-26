# Street View interactif sur iOS

État au lot SV-1, sur la branche `ios/sv1-street-view`. Ce document décrit ce que le visualiseur
fait, comment il charge ses tuiles, ce que les tests prouvent et ce qui reste absent. La référence
fonctionnelle est `SPEC.md` 10.7 ; ce lot reprend la partie consultation d'un panorama, pas la
machine à remonter le temps.

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
panorama vers le lieu quand elle le connaît.

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

La boussole affiche le cap vrai (N/NE/E… et degrés) et son aiguille tourne à l'envers du panorama.
Le bouton « Face north » remet le cap à 0° sans toucher à l'orientation de capture du panorama.

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
- Le disque est géré par `PlatformFiles` sous le dossier de cache : `svtiles/<pano>-<z>-<x>-<y>.jpg`,
  plafonné à 24 Mo et 512 fichiers, les plus anciens supprimés en premier.
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

- `StreetViewTilesTest` : URL exacte, clé de cache, niveaux moderne et 416, conversion azimut/yaw,
  sélection des tuiles visibles et bouclage au raccord, bornes aux pôles.
- `StreetViewStoreTest` : rue de l'adresse transmise, panorama de vignette demandé par identifiant,
  repli au plus proche, aucune imagerie, marche par identifiant et conservation du panorama courant
  en cas d'échec, cache disque avant réseau, client HTTP et en-têtes d'image, fermeture.

Scénario interface `StreetViewUITests.testStreetViewFromPlace` : ouvre « Davis Food Co-op », fait
apparaître la vignette, ouvre le visualiseur, glisse, zoome, remet au nord, ferme et vérifie le
retour de la fiche. Si Google ne fournit pas de panorama au runner, il relance avec
`-VelaStreetViewFixture YES` et exécute les mêmes gestes ; le résumé porte
`street_view_mode=live` ou `fixture`. Captures : `street-view.png`, `street-view-zoom.png`.

La ligne de debug `street-view-debug` porte `pano=`, `loading=`, `error=`, `yaw=`, `pitch=`,
`fov=`, `bearing=`, `tiles=`, `level=`, `neighbors=` et `fixture=`. Elle ne contient aucune
coordonnée.

## Limites assumées

- Pas d'historique : `StreetViewPano.history` est parsé, mais aucune puce de dates n'est dessinée.
  Une capture ancienne n'est pas accessible dans ce lot.
- Pas de retour de pose vers la carte : Android dessine un cône de vue et un point sous la fenêtre
  Street View. Ici le visualiseur est plein écran et la carte ne bouge pas.
- Pas d'entrée par appui long sur la carte. L'entrée est la vignette de la fiche ; le lancement
  fixture est réservé aux tests.
- Pas de transition en fondu entre deux panoramas : la nouvelle texture remplace l'ancienne.
- Le sens vertical de la texture SceneKit (origine en bas à gauche supposée) est à confirmer sur
  les captures du runner. Un retournement est un changement d'une ligne dans
  `StreetViewScene.sphereGeometry`, pas une refonte.
- Le rendu, les gestes et la mémoire restent à vérifier sur iPhone réel ; la CI est un simulateur.

## À vérifier sur iPhone

1. Ouvrir une fiche avec vignette, toucher la vignette, vérifier que le panorama n'est ni miroir ni
   à l'envers, et que le texte des devantures se lit.
2. Glisser dans les deux sens jusqu'au raccord 360°, monter et descendre jusqu'aux limites, pincer
   et utiliser les boutons de zoom.
3. Toucher la boussole nord et vérifier que le cap affiché revient à 0°.
4. Marcher avec une flèche sur quelques panoramas, vérifier l'orientation du nouveau panorama et
   le crédit mis à jour.
5. Fermer le visualiseur et vérifier que la fiche lieu et la carte reviennent dans le même état.
6. En mode avion et avec Google désactivé, vérifier le message d'absence d'imagerie et l'absence de
   requêtes.
7. Mesurer la mémoire et la batterie sur plusieurs minutes de panorama, puis en mode sombre.
