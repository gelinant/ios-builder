# Fiche lieu iOS

État des lots PLC-PAGE et PLC-REVIEW. La fiche ouvre sur les données du résultat de recherche, puis complète
avec la recherche ciblée (nom + adresse) et, si l'affluence manque encore, la page Google cachée.
Aucune section n'invente de données : quand Google omet une information, la fiche affiche un
texte vide explicite.

## Onglets

| Onglet | Contenu | Source | État vide |
|---|---|---|---|
| Overview | note, catégorie, prix, statut, horaires, actions, contact, Street View, affluence, résumé des avis, lieux liés, dernière actualité, aperçu À propos | réponse de recherche, détails, page cachée | « Google did not provide ... » selon la section |
| Reviews | note, répartition par étoiles, tri, recherche locale, avis, photos des auteurs, pagination, panneau complet | flux `qv9Egd`, page cachée, parcours de galerie | « No reviews to show » |
| About | description éditoriale, « From the owner », attributs | réponse de recherche et repli détails | « Google did not provide a description or attributes for this place. » |
| Photos | grille 3 colonnes, catégories, galerie plein écran avec légende | RPC `hspqX`, parcours caché | « Google did not provide photos for this place. » |
| Menu | photos dont la catégorie de galerie contient un mot « menu » | catégories du parcours caché | absent si Google ne donne aucune catégorie de menu |
| Updates | publications du propriétaire | `Place.updates` (réponse et repli) | onglet absent ; Overview montre la plus récente |

L'ordre est Overview, Reviews, About, Photos, Menu, Updates. `Updates` n'apparaît qu'à partir de
deux publications, comme sur Android ; Overview montre toujours la plus récente.

## Horaires

Le statut ouvre la semaine complète et les horaires des départements d'un grand magasin
(pharmacie, carburant, livraison). Un lieu fermé définitivement ou temporairement est signalé en
rouge, et ses horaires ne sont pas présentés comme valides.

## Avis

Le panneau complet reprend la présentation d'Android : note, nombre d'avis, puis les cinq barres
ambrées de la répartition `[5★ .. 1★]`. Les barres ne sortent que d'un histogramme réellement lu
dans la page Google, lors du parcours de galerie ou du repli de page. Le flux `qv9Egd` ne le porte
pas : quand aucun parcours n'a eu lieu, la fiche n'affiche aucune barre plutôt qu'une répartition
inventée. Les lignes sont accessibles une par une (`5 stars, 189 reviews`).

Les contrôles sont ceux de l'onglet Android : trois tris sur les avis déjà chargés (pertinence,
note décroissante, note croissante) et une recherche locale sur l'auteur ou le texte. La recherche
se déplie derrière la loupe et se vide quand on la referme. « More reviews » ajoute la page
suivante du flux ou demande une page à la page cachée ; les doublons auteur et texte sont fusionnés,
comme sur Android.

Quand Google affiche un avis traduit, la page porte sa mention de traduction. Le panneau montre le
texte que Google a envoyé et ajoute « Translated by Google » sous l'avis. Aucune traduction n'est
produite par Vela, et un avis sans mention n'en reçoit pas.

## Galerie

Les puces de catégorie suivent l'ordre des onglets de Google, sans doublon. La visionneuse plein
écran se balaie horizontalement, affiche la légende de la photo (catégorie et date, ou auteur et
ancienneté pour une photo d'avis) puis sa source. Google ne donne pas le nom du contributeur dans
la galerie sans compte : la source affichée est donc « Photos from Google Maps », pas un auteur
inventé.

Sur un lieu de restauration dont les catégories ne sont pas encore connues, la galerie propose une
puce « Menu » qui lance le parcours des catégories. C'est le même comportement qu'Android, et
l'onglet Menu de la fiche n'apparaît qu'une fois une catégorie contenant un mot menu lue.

## Affluence

Le sélecteur de jour et les barres horaires lisent l'histogramme hebdomadaire typique de Google.
Aucune donnée « en direct » n'est disponible dans le modèle partagé : la section écrit donc
« Typical busyness for <jour>, not live » et n'allume aucune barre comme si elle était actuelle.
La vue accepte une mesure `BusyNow` et ne l'affiche, avec la mention « Right now », que si une
source réelle en fournit une. C'est le repli honnête demandé par le lot : pas de barre « now »
calculée à partir du typique.

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
  la réponse au lieu d'inventer un graphique. Le modèle partagé ne transporte que la semaine
  typique, donc aucune barre « en direct » n'est dessinée.
- Histogramme des avis : le flux d'avis ne le donne pas. La fiche réutilise celui que le parcours
  de galerie ou le repli de page a lu, sans requête supplémentaire.
- Traductions : seuls les avis dont la page Google porte la mention de traduction sont signalés.
  Le flux `qv9Egd` ne transporte pas cette information.
- Galerie : le nom du contributeur n'existe pas dans la galerie sans compte, seulement une date et
  la source. Aucun auteur n'est affiché.

## Tests

- `PlaceUITests.testCompleteFixturePlace` : galerie, panneau d'avis complet, avatars décodés,
  repli d'affluence.
- `PlaceUITests.testDetailsHoursTabsActionsAndRelated` : horaires dépliés, pastilles d'action,
  captures des onglets About, Photos, Reviews, Menu et Updates quand ils existent, puis rangée
  des lieux liés et ouverture de l'un d'eux.
- `PlaceStoreTest` : ouverture d'un lieu lié, conservation des attributs, actualités et lieux
  liés à travers le repli détails, attributs venus du repli quand la réponse est tronquée,
  marqueur de traduction conservé depuis la page.
- `PlaceReviewsTest` : lecture de l'histogramme, refus d'un histogramme mal formé, fusion de
  pages sans doublon et clés de traduction.
- `PlaceReviewsUITests.testReviewsHistogramAndControls` : capture `reviews-histogram.png`, barres
  par étoile, tris et recherche.
- `PlaceReviewsUITests.testMoreReviewsAppendsAPage` : capture `reviews-more.png`, page suivante
  ajoutée ou vue limitée signalée.
- `PlaceReviewsUITests.testGalleryViewerSwipesWithCaptionAndSource` : capture
  `gallery-viewer.png`, légende, source et balayage vers la photo suivante.
