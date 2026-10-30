# Hors ligne avancé sur iOS

État au 2026-10-27, branche `ios/o3-offline-advanced`. Ce document complète la section hors ligne
de `SPEC.md` et la ligne « Hors ligne » de `PARITY.md`. Il décrit les deltas, le comptage du
stockage, le petit zoom monde et ce que les cellules de grille demanderaient encore.

## Manifestes lus

`RegionCatalog` lit les quatre manifestes `{regions:[...]}` comme Android :

| Manifeste | Adresse | Champs utilisés |
|---|---|---|
| routage | `VelaLinks.obfManifest()` | catalogue des régions, `bbox`, `rev` |
| packs de lieux | `VelaLinks.poiPackManifest()` | `url`, `sizeMb`, `installedMb`, `rev`, `counts`, `delta` |
| archives de lieux | `VelaLinks.placesManifest()` | `url`, `sizeMb`, `rev`, `delta` |
| fond de carte | `VelaLinks.basemapManifest()` | `url`, `sizeMb`, `rev`, `delta` |

Le monde et les polices n'ont pas de manifeste. L'archive monde vient de
`VelaLinks.worldBasemap()`, le paquet de glyphes de `VelaLinks.mapFontsPack()`.

Un `delta` vaut `{url, fromRev, sizeMb}`. Il ne s'applique qu'à une pièce installée dont la
révision est exactement `fromRev`. Un `rev` plus récent sans delta, une révision intermédiaire ou
un delta refusé déclenchent le téléchargement complet de la pièce, et l'interface affiche le
nombre de pièces prises par delta et le nombre retéléchargées.

## Révisions installées

Les révisions sont dans `noBackupDir/offline/revs.json`, une entrée par dossier
(`packs`, `places`, `maps`). Le fichier est remplacé atomiquement après chaque pièce. Un ancien
marqueur de région, qui n'a pas de révision, reste lisible et vaut révision 0. Le marqueur de
région `regions/<id>.json` garde les identifiants, les boîtes et le pack partagé, comme avant.

## Mise à jour par delta

`OfflineUpdates.decide` choisit `NONE`, `DELTA` ou `FULL`. Le plan de mise à jour ne contient que
les pièces dont la révision du manifeste dépasse la révision installée.

### Packs de lieux

Le delta est un petit SQLite `del_<table>` et `ins_<table>`, produit par
`scripts/poipack_delta.py`. `PackDelta` lit d'abord les lignes du delta, puis les applique dans une
seule transaction : suppression par tuple complet, insertion, vérification des `counts` du
manifeste, commit. Une erreur, une table absente ou un compte faux annule la transaction et la
pièce est téléchargée entière. Le paquet est fermé pour la lecture (`OfflinePacks.reload`) pendant
l'écriture puis rouvert.

### Archives PMTiles

Le patch est un `.vpatch` produit par `scripts/pmtiles-make-patch.py`. `PmtilesPatch.apply`
écrit les tuiles puis le répertoire, et ne déplace l'en-tête de 127 octets qu'en dernier. La
vérification finale compare l'empreinte de toutes les tuiles à `toFingerprint` ; un écart tronque
le fichier à sa taille d'avant et le téléchargement complet prend le relais. Un patch interrompu
laisse donc l'ancien en-tête valide. `PmtilesCompact` récupère ensuite l'espace des tuiles
remplacées quand il dépasse un cinquième du fichier, sans réseau ; un refus laisse l'archive
correcte.

Le téléchargement d'un patch passe par `URLSessionRegionDownloader` et écrit
`<id>.vpatch` ou `<id>.delta.db` à côté de la cible. L'installeur Swift vérifie le statut, la
longueur, la magie PMTiles, SQLite ou `VELAPTCH`, avant de laisser Kotlin appliquer.

## Stockage

Le panneau hors ligne affiche :

- le total, puis le fond de carte, les lieux, les packs de lieux et les polices, par catégorie ;
- pour chaque région installée, sa taille réelle et le détail pack, lieux, fond de carte ;
- `world=1` dans la ligne de débogage et « World basemap installed » quand le petit zoom monde est
  présent.

Les tailles par catégorie comptent chaque fichier une fois, même si un pack parent sert plusieurs
régions. La taille d'une région compte les fichiers qu'elle référence. Les glyphes sont partagés
et ne sont donc pas répétés par région.

`deleteCategory(region, kind)` supprime une seule catégorie (`pack`, `places`, `basemap`). Un
fichier encore utilisé par une autre région reste. Quand plus aucune pièce ne reste, le marqueur
de région est supprimé et la région redevient disponible au téléchargement.

Avant tout téléchargement, `OfflineStorage` exige la taille estimée du plan plus 64 Mo de marge
sur le volume `offline/`. Un volume inconnu (0) ne bloque pas. Un manque de place donne
`errorKey = no_space`, aucun plan durable n'est écrit et aucun fichier n'est partiel.

## Petit zoom monde

`basemap/world.pmtiles` est téléchargé après le fond de carte de la région, une fois par
installation. C'est une pièce optionnelle : son échec ne fait pas échouer la région. L'archive
n'entre jamais dans la liste des fonds de carte de région et n'est proposée que hors ligne
(`NoGoogle`, réseau absent ou mode test), quand aucune archive de région ne couvre le point ou
quand aucune tuile de route n'y répond. Le style reste celui d'`OfflineStyleFactory`, donc zéro
URL distante. En ligne, le fond de carte du réseau reprend la main.

## Cellules de grille

Les cellules ne sont pas implémentées sur iOS. Android les traite dans `CellStore`, propre au
module `:app`, avec des parties de pack, de lieux et de routage et un manifeste `cells-<region>`.
Il n'existe pas d'implémentation commune réutilisable. Pour les ajouter il faudrait :

1. déplacer dans `:core-common` la lecture du manifeste de cellules et la sélection des parties
   qui touchent la vue, sans dépendre de `Context` ;
2. ajouter un dossier `offline/cells` aux `StorageLocation` iOS et une catégorie de stockage ;
3. écrire l'installeur des parties avec les mêmes contrôles de magie et le même marqueur que les
   régions ;
4. monter plusieurs archives à la fois dans `OfflineStyleFactory` et `MapController`, ce qui
   demande une couture de style multi-sources absente aujourd'hui (`MLNVectorTileSource` est
   ajouté après le chargement du style) ;
5. ajouter un scénario UI avec deux cellules voisines et une suppression par catégorie.

Sans les points 1 et 4, une cellule ne peut pas être dessinée par la carte iOS.

## Preuves

Tests JVM : `RegionCatalogTest` (comptes et delta), `PackDeltaTest` (application et annulation),
`OfflineUpdatesTest` (choix du delta, espace libre, monde, révisions, catégories) et
`OfflinePatchTest` (patch réel accepté, archive modifiée refusée et laissée intacte).

Scénario UI `OfflineUITests.testMonacoDeltaUpdateStorageAndWorldFallback`, avec des manifestes et
des pièces synthétiques servis par un `URLProtocol` de débogage
(`scripts/ios/offline_fixture.py`) : téléchargement de Monaco, passage en révision 2, trois deltas,
suppression de la catégorie lieux, capture `offline-update.png` et `offline-storage.png`, puis
relance à Paris, blocage réseau et archive `world.pmtiles` avec zéro URL distante, capture
`offline-world.png`. Le scénario Monaco existant reste le contrôle du chemin réel.

## Limites

- Le monde n'a pas de manifeste : il n'est pas mis à jour par delta et sa taille estimée est une
  constante.
- Une mise à jour de région ne touche pas les glyphes.
- Le patch PMTiles s'applique en place. Une coupure de courant pendant l'ajout laisse un fichier
  plus long mais valide ; il n'y a pas de copie complète de secours, seulement la troncature sur
  empreinte fausse.
- Le scénario UI utilise des tuiles synthétiques. Il prouve la mécanique, pas le rendu réel d'une
  région ou du monde sur iPhone.

## Téléchargement d'une zone cadrée (OFF-AREA)

Le panneau hors ligne propose « Frame an area on the map ». La carte revient avec un cadre fixe,
assombri à l'extérieur, et la carte se déplace et se zoome dessous, comme le sélecteur d'Android
(`AREA_FRAME_*`, mêmes fractions : 7 % à gauche et à droite, 18 % en haut, 34 % en bas). Le cadre
n'est donc pas un rectangle que l'on redimensionne : on choisit ce qu'il couvre en déplaçant la
carte, et l'estimation suit le déplacement avec un délai de 200 ms.

### Ce qui est réellement téléchargé

iOS ne télécharge pas des tuiles carrées : l'unité est la région du catalogue qui contient le
milieu du cadre. Le panneau le dit (« Whole region: ... ») et le nomme. Le téléchargement installe
la carte vectorielle de la région, ses archives de lieux et son paquet de lieux quand les lieux
sont demandés, plus les polices une fois et le petit zoom monde quand il manque. La taille
affichée est la somme des tailles de manifeste des pièces réellement absentes du disque, donc un
nombre déjà installé n'est pas compté deux fois. Elle reste une estimation : les octets exacts
dépendent des archives.

L'estimation est marquée « Estimated download » et le panneau affiche toujours l'espace libre.
`OfflineStorage.fits` refuse le plan quand le volume ne peut pas contenir les pièces plus 64 Mo de
marge, avant toute écriture : le bouton est désactivé et la ligne rouge dit la taille nécessaire
et l'espace libre. Un volume inconnu (0) ne bloque pas, comme pour les régions.

Si la région est déjà installée sans données de caméras ni d'adresses, le cadre propose seulement
ces données supplémentaires. Sinon il écrit « Already downloaded ».

### Préférences

| Réglage | Clé | Défaut | Effet réel |
|---|---|---|---|
| Lieux | `offline_places_with_downloads` | activé | paquet de lieux et archives de lieux ; désactivé, seules la carte et les polices sont téléchargées |
| Caméras | `offline_area_cameras` | activé | pack de caméras Overpass pour la boîte de la région après l'installation |
| Adresses | `offline_area_addresses` | activé | index d'adresses Overpass autour du cadre, avec les rues nommées en repli |

Les trois réglages sont persistés et relus à la réouverture du cadre. La clé des lieux est celle
d'Android, donc un fichier de réglages écrit par l'une ou l'autre application reste valable. Les
deux autres clés sont propres à iOS.

Les adresses sont une vraie requête Overpass, lancée après l'installation et jamais bloquante :
la boîte du cadre est élargie à 10 km minimum (0,09 degré), plafonnée à 2 degrés, et versée dans
`OfflineAddressStore`. Sans réponse d'aucun miroir, aucune ligne n'est écrite et le panneau affiche
0 ligne au lieu de prétendre que la zone n'a pas d'adresse. Les caméras utilisent le même chemin
que le pack de région existant (`camera-packs/<id>.json`), avec les mêmes limites de 2 000 points
par type et de 12 degrés.

### Routage exclu

Le cadre, la carte, les lieux et les adresses sont livrés. Le routage hors ligne ne l'est pas :
D7 exclut le routeur `.obf`, et aucun autre moteur local n'existe. Le panneau et la fiche le
disent tous les deux : « Includes the map, places and addresses. It does not include offline
routing. » Aucun bouton ne promet un itinéraire hors ligne.

### Progression et reprise

La confirmation ferme le cadre et laisse une carte de progression au-dessus de la carte. Le plan
est écrit dans `region-download.json`, avec l'indicateur de zone, les deux extras et la boîte des
adresses : quitter la fiche, masquer la carte de progression, revenir par le globe ou tuer le
processus ne perd pas le téléchargement. La fiche hors ligne affiche la même progression
(`area-sheet-progress`) et le même résultat (`area-sheet-ready`). La croix masque la carte, elle
n'annule pas. « Cancel » efface l'intention durable avant l'annulation asynchrone, comme pour une
région.

### Preuves

- JVM `OfflineAreaTest` : fractions du cadre, tuiles et estimation, retrait des lieux quand la
  préférence est coupée, extras caméras et adresses, refus faute d'espace, région déjà installée,
  boîte d'adresses élargie puis refusée au-delà de 2 degrés, densité de l'archive et clés de
  préférence.
- Simulateur `OfflineAreaUITests.testFrameAreaAndPreferences` : cadre, estimation et espace libre,
  caméras et adresses coupées, progression, fiche après fermeture, style local à zéro URL
  distante, captures `offline-area-frame.png`, `offline-area-estimate.png`,
  `offline-area-progress.png`, `offline-area-sheet.png` et `offline-area-preferences.png`. Le
  scénario tourne sur les manifestes et pièces synthétiques d'O-3, avec le ralenti de test
  `-VelaOfflineAreaSlow` pour garder une image de progression.

### Limites

- L'unité reste la région du catalogue : un cadre serré dans une grande région télécharge la
  région entière. iOS n'a pas le téléchargement de tuiles carrées d'Android (`OfflineMaps`).
- Le polygone du catalogue fait foi quand il contient le milieu du cadre. Un polygone grossier qui
  l'exclut alors que sa boîte le contient retombe sur la boîte (le polygone de Monaco dans
  `region_polys.json` est un triangle qui rate la ville), pour ne pas refuser une zone téléchargeable.
- Les cellules de grille ne sont pas implémentées, donc un cadre ne peut pas se limiter à quelques
  cellules comme sur Android.
- Les caméras et les adresses sont des requêtes Overpass non contractuelles : hors réseau, elles
  ne rapportent rien et la carte déjà installée reste utilisable.
- Le coût des extras n'entre pas dans l'estimation de taille ; leur écriture est bornée par le
  plafond de points et la marge de 64 Mo.
- Pas encore de validation sur iPhone.


## Correctif de la chaîne de fixtures

Un téléchargement de région sur les fixtures s'arrêtait à `stage=pack pct=0 pieces=0/5` : les
manifestes synthétiques nomment leurs corps `pack-v1.zip`, `places-v1.pmtiles` ou
`world.pmtiles`, alors que le bundle les range sous `offline-fixture-<nom>`. Le protocole de
fixture cherchait donc un fichier absent, répondait 404, et la pièce échouait avant tout octet.
Le plan d'une zone ou d'une mise à jour à delta emprunte le même chemin.

`OfflineFixtureUrls.rewrite` est désormais le seul point de passage : `OfflineStore` réécrit
l'URL de chaque pièce et l'URL `delta` d'un plan quand les catalogues de fixture sont chargés,
juste avant le transfert. La réécriture est idempotente, donc un plan restauré depuis
`region-download.json` peut être relancé sans doubler le préfixe. Une URL réelle n'est jamais
touchée : l'hôte doit être `offline.fixture.invalid`. Le plan durable garde les noms des
manifestes ; la réécriture ne vaut que pour le transfert.

Une pièce non optionnelle est tentée une seconde fois après 500 ms avant que le plan échoue. Un
échec réel écrit `errorKey = download_failed`, la fiche hors ligne annonce les pièces complètes
qui seront réutilisées, et la carte de progression de zone affiche le même décompte au lieu de
prétendre que rien n'a été installé. Les pièces optionnelles (le monde) restent une tentative et
leur échec ne fait pas échouer la région.

Les interrupteurs du cadre se lient directement aux propriétés publiées du modèle. Chaque
changement écrit la préférence dans le magasin avant de relancer l'estimation, et l'ouverture du
cadre relit `areaPreferences()` : un second cadre, ou une nouvelle session, affiche donc la valeur
réellement enregistrée sous `offline_area_cameras` et `offline_area_addresses`, celle que
`planArea` et `downloadArea` utilisent. Aucun défaut n'est réappliqué en silence.

Le bouton de débogage « Reset offline data for test » efface les fichiers, les révisions, le plan
en attente et les trois préférences de zone, puis reconstruit les lignes du catalogue ; un scénario
part donc toujours des défauts documentés. Le scénario Monaco réel s'en sert au début
pour ne pas hériter de la région de fixture, ni d'un plan en échec, laissé par le scénario
précédent. La relance du scénario de delta, elle, n'exige plus `-VelaOfflineFixture` : le drapeau
réinitialise le magasin à chaque lancement, ce qui effacerait justement la région et le monde que
la relance doit retrouver.

### Preuves

- JVM `OfflineFixtureTest` : une URL de plan de fixture arrive au téléchargeur sous le nom du
  bundle, la réécriture couvre pack, patch et delta et reste idempotente, une URL réelle est
  intacte, les deux interrupteurs persistent dans un nouveau magasin et le plan les reflète, et
  l'interrupteur des lieux retire toujours le paquet et les archives de lieux.
- Simulateur : `OfflineUITests.testMonacoDownloadOfflineMapAndSearch`,
  `OfflineUITests.testMonacoDeltaUpdateStorageAndWorldFallback` et
  `OfflineAreaUITests.testFrameAreaAndPreferences` passent avec les captures déjà nommées.
  La ligne `offline-download-debug` doit finir à `pieces=5/5` et la fiche doit afficher
  `offline-installed-monaco`.

## Fin definitive d'un telechargement

`OfflineState.downloads` compte les executions de `runDownload` dans le processus. La ligne de
session la publie avec le nombre de pieces, les regions installees et le monde. Une region
terminee passe dans `completedRegions` : un plan durable pour cette region est supprime sans
toucher au marqueur `regions/<id>.json`, qui reste la source de montage au lancement suivant.
La fin d'une region n'est donc pas suivie d'une seconde reprise, et l'archive reste montee.

Le magasin de fixture se prepare une fois par processus. Un second modele, ou un magasin neuf
cree pour une seconde presentation de la feuille, recoit les catalogues sans refaire le reset des
fichiers. Un magasin qui a deja les catalogues ne les recharge pas, donc une revision 2 acquise
par le bouton de fixture n'est pas ramenee a la revision 1.

## Controles de debogage et manifeste de fixture

Les boutons de scenario (Block network, Reset, Fixture: use update manifest) sont dans la barre
de navigation, donc ils ne dependent ni du defilement de la List ni d'une carte plus haute que la
feuille. Un bouton place au bas d'une telle carte est rapporte hittable mais le tap n'atteint pas
l'action : le compteur de taps reste a zero.

La ligne de session est portee par la valeur d'accessibilite du bouton Done, donc elle ne prend
aucune ligne et reste lisible quelle que soit la position de la List. En mode fixture, elle
ajoute `taps=N fixture=1 manifest=REV installed=N updatable=N`.

En mode test, l'explication longue du bouton Google est masquee dans la carte d'etat. La carte
reste alors dans la fenetre construite par la List, et les cartes Installed regions et zone
restent atteignables apres une reouverture de la feuille.

## Suppression d'une categorie

Les boutons de categorie et d'action portent `buttonStyle(.borderless)`. Sans ce style, plusieurs
boutons dans une meme rangee de List peuvent tous recevoir un seul tap : le scenario supprimait
alors pack, lieux et fond de carte d'un coup, et trois suppressions concurrentes bloquaient le
magasin. Une seule suppression de categorie tourne a la fois. Le scenario supprime les lieux
avant la mise a jour, depuis la feuille rouverte en haut, sans geste au-dessus des boutons.
