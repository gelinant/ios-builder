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
(`NoGoogle`, réseau absent ou mode test), quand aucune archive de région ne couvre le centre ou
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
