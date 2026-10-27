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

## Carburant

La fiche affiche le prix au litre sous les pastilles d'action, comme Android. Deux sources
coexistent et ne se mélangent pas :

| Zone | Source | Ligne affichée |
|---|---|---|
| États-Unis | prix Google de la réponse de recherche | « $5.34/Regular », sans heure de relevé |
| Royaume-Uni et Irlande du Nord | Fuel Finder (`FuelGb`, `FuelGbStore`) | « 172.9p/E10 · 199.9p/B7 », puis la marque et l'âge du relevé |

Le fichier Fuel Finder est téléchargé seulement quand une station britannique sans prix est
ouverte. `PlaceStore` applique le fichier déjà en mémoire, sinon il le charge une fois et remplit
la fiche encore ouverte. Aucun prix n'est inventé : hors de la zone Fuel Finder, sans forecourt à
moins de 75 m, avec un relevé de plus de 21 jours ou un fichier de plus de 2 jours, la ligne reste
absente. La République d'Irlande est exclue par les polygones de `FuelGb.inUk`.

La marque vient du forecourt apparié, jamais du texte Google. L'âge est en jours calendaires
locaux : « Updated today », « Updated yesterday », « Updated N days ago ». Le fuseau est celui du
téléphone, y compris au changement d'heure.

La comparaison « Cheaper nearby » est une addition iOS, affichée seulement quand le fichier la
justifie : un autre forecourt à moins de 5 km, vendant le même grade, au moins 1 penny moins cher.
Elle nomme la marque et la distance. Sans donnée comparable, rien n'est affiché.

## Fermeture

Le statut Google reste la source principale. Une ligne discrète le complète :

- « Closes in N min » quand la fermeture tombe dans l'heure, le même seuil que l'avertissement de
  navigation Android ;
- « Closed today » quand les horaires hebdomadaires donnent la journée entière fermée ;
- « Temporarily closed » et « Permanently closed » restent les statuts rouges existants, sans
  doublon.

`ClosingTime.status` travaille sur l'instant courant et le fuseau IANA du téléphone. Une fermeture
à 1 h du matin lue à 23 h 30 est donc dans 90 minutes, et une fermeture à minuit reste après
l'arrivée du même jour. Les horaires hebdomadaires comprennent les plages qui passent minuit et
les lignes en 24 heures.

## Route et navigation

Les règles pures sont dans `PlaceTravelHints` :

- `closingWarning` reprend la fenêtre de 60 minutes d'Android (`NavController.closingMessage`),
  pour la destination comme pour un arrêt, avec le même calcul de minuit ;
- `fuelDetour` cherche le forecourt le moins cher à moins de 500 m de la ligne, fichier frais
  seulement, et rend son prix, sa marque et sa distance.

Les deux stores concernés appartiennent à d'autres lots et ne sont pas modifiés ici. Les points
d'accroche exacts sont :

- `ios-shared/src/commonMain/kotlin/app/vela/ios/nav/NavStore.kt`, dans `startNavigation`, après
  `val display = NavSession.destinationDisplay(...)` et avant `session.start(...)` : appeler
  `PlaceTravelHints.closingWarning(...)` avec `display.first`, `destinationPlace.statusText`,
  `openNow`, `nowEpochSec + (route.durationInTrafficSeconds ?: route.durationSeconds)` et le fuseau
  courant ; publier le résultat dans un nouveau champ de `NavUiState` pour `NavChrome` et la voix.
- le même endroit pour `fuelDetour` : charger `PlaceFuel.source(...)?.load()` avec le route
  retenu, publier le hint dans `NavUiState`, l'afficher dans le bandeau de navigation.
- `ios-shared/src/commonMain/kotlin/app/vela/ios/route/RouteStore.kt`, dans `route()`, après le
  `_state.update` qui pose `active = routes.firstOrNull()` : calculer le même hint pour l'aperçu
  avant le départ.

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
- `FuelGbTest` (common, JVM et iOS) : lecture des colonnes par nom, appariement et écart de
  marque, marque et âge de la fiche, comparaison à 1 penny et 5 km, prix Google et hors zone
  ignorés, fichier périmé, polygones irlandais, jours calendaires par fuseau.
- `ClosingTimeTest` (common) : compte à rebours sous l'heure, minuit, changement de fuseau,
  fermé aujourd'hui, fermetures permanente et temporaire, horaires 24 h et plages de nuit,
  avertissement d'arrivée avant et après la fermeture.
- `PlaceTravelHintsTest` (JVM) : détour carburant sur la ligne, station trop loin, fichier périmé,
  et la fenêtre de 60 minutes de l'avertissement d'arrivée.
- `PlaceFuelUITests.testFuelPlaceCard` et `.testClosingTimeCard` : captures `place-fuel.png` et
  `place-closing.png`, avec les libellés `place-fuel`, `place-fuel-nearby` et `place-closing`.
  Les deux lieux sont des fixtures ouvertes sans recherche ni requête Google.
