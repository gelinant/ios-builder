# Fiche lieu iOS

État du lot PLC-PAGE. La fiche ouvre sur les données du résultat de recherche, puis complète
avec la recherche ciblée (nom + adresse) et, si l'affluence manque encore, la page Google cachée.
Aucune section n'invente de données : quand Google omet une information, la fiche affiche un
texte vide explicite.

## Onglets

| Onglet | Contenu | Source | État vide |
|---|---|---|---|
| Overview | note, catégorie, prix, statut, horaires, actions, contact, Street View, affluence, résumé des avis, lieux liés, dernière actualité, aperçu À propos | réponse de recherche, détails, page cachée | « Google did not provide ... » selon la section |
| Reviews | avis, photos des auteurs, pagination, panneau complet | flux `qv9Egd`, page cachée | « No reviews to show » |
| About | description éditoriale, « From the owner », attributs | réponse de recherche et repli détails | « Google did not provide a description or attributes for this place. » |
| Photos | grille 3 colonnes, catégories, galerie plein écran | RPC `hspqX`, parcours caché | « Google did not provide photos for this place. » |
| Menu | photos dont la catégorie de galerie contient un mot « menu » | catégories du parcours caché | absent si Google ne donne aucune catégorie de menu |
| Updates | publications du propriétaire | `Place.updates` (réponse et repli) | onglet absent ; Overview montre la plus récente |

L'ordre est Overview, Reviews, About, Photos, Menu, Updates. `Updates` n'apparaît qu'à partir de
deux publications, comme sur Android ; Overview montre toujours la plus récente.

## Horaires

Le statut ouvre la semaine complète et les horaires des départements d'un grand magasin
(pharmacie, carburant, livraison). Un lieu fermé définitivement ou temporairement est signalé en
rouge, et ses horaires ne sont pas présentés comme valides.

## Lieux liés

« People also search for » vient de `Place.similarPlaces`, rempli par le parseur de recherche
commun. Chaque carte ouvre la fiche du lieu lié par le même chemin de chargement (détails,
galerie, avis), sans nouvelle recherche. Si Google omet la rangée, la fiche le dit.

« Also at this location » n'est pas disponible : l'état iOS n'expose pas `placesHere`, que le
view-model Android remplit. Voir les manques ci-dessous.

## Actions

Directions, Enregistrer, Listes, Partager, Appeler et Site Web. Le bouton propre à Google
(Order online, Reserve a table, Book online) apparaît seulement quand le parseur a livré un
libellé et une URL http(s). Aucun badge « revendiqué » ou « vérifié » n'est affiché : le modèle
commun ne transporte pas cette information.

## Menu et actualités

Les deux sections sont implémentées parce que les parseurs communs les fournissent déjà :
`Place.photoCategories` (parcours de galerie) pour le menu, `Place.updates` pour les publications.
Il n'y a pas de requête supplémentaire : le menu réutilise les photos déjà chargées et les
actualités arrivent avec la fiche.

## Requêtes

Un seul chargement par section et par lieu : recherche ciblée pour les détails, `hspqX` pour la
première page de photos, flux d'avis à l'ouverture de l'onglet Reviews, page cachée seulement si
les détails ou la galerie restent incomplets. Ouvrir un lieu lié annule les chargements du
précédent et repart sur son propre identifiant.

## Manques Google et manques du portage

- Badges « Revendiqué par le propriétaire » et « Vérifié » : absents du modèle commun et des
  réponses analysées. Rien n'est affiché.
- « Also at this location » : `placesHere` vit encore dans le view-model Android ; non exposé par
  `MapSession` sur iOS. Les lieux liés de `similarPlaces` sont, eux, affichés.
- Menu : seulement les photos dont la catégorie Google contient un mot menu. Google ne fournit
  ni plats, ni prix, ni carte structurée.
- Actualités : uniquement les publications que la réponse de recherche ou la page ciblée
  contiennent, dix au maximum, sans pagination.
- Affluence : dépend de la page cachée ; en vue limitée, la fiche explique que Google restreint
  la réponse au lieu d'inventer un graphique.

## Tests

- `PlaceUITests.testCompleteFixturePlace` : galerie, panneau d'avis complet, avatars décodés,
  repli d'affluence.
- `PlaceUITests.testDetailsHoursTabsActionsAndRelated` : horaires dépliés, pastilles d'action,
  captures des onglets About, Photos, Reviews, Menu et Updates quand ils existent, puis rangée
  des lieux liés et ouverture de l'un d'eux.
- `PlaceStoreTest` : ouverture d'un lieu lié, conservation des attributs, actualités et lieux
  liés à travers le repli détails, attributs venus du repli quand la réponse est tronquée.
