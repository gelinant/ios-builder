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

### Coût du panneau

Le scrape de la page d'avis diffuse un instantané complet à chaque carte lue. Ces instantanés sont
analysés sur `Dispatchers.IO` et seul le dernier en attente est gardé : le fil principal ne reçoit
que la liste déjà analysée. Les avatars et les photos d'avis sont demandés à la taille que la ligne
dessine (128 px et 320 px), et l'échantillonnage des pixels d'avatar se fait hors du fil principal.
La page Google cachée qui a répondu est détruite aussitôt. Le panneau calcule son filtre, son tri et
ses en-têtes une fois par rendu. Mesure du run `bugfix-reviews-20261029-145914-15506` :
`reviews_swipe_answer_ms=898`, `mainloop_stall_ms=457`, 41 fps, capture `reviews-swipe.png`, test
`PlaceReviewsUITests.testSwipeKeepsThePanelResponsive`.

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

Les succursales à la même adresse sont groupées par SRCH-BRANCH : une pastille `N locations`
apparaît quand la réponse de recherche porte des voisins (même rue, suites retirées, moins de
60 m), et la liste « Also at this location » s'ouvre sous la fiche. Le groupe est recalculé à
chaque ouverture, donc la fiche d'origine reste dans la même liste.

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

### Câblage dans le sélecteur et la navigation

Le sélecteur et la navigation sont maintenant branchés sur ces deux règles.

Dans `RouteStore`, `RouteState.closingHint` et `RouteState.fuelHint` sont recalculés à chaque jeu
d'itinéraires, y compris après un changement de mode, d'évitement, d'arrêt ou de départ, et après
le choix d'une autre variante (`select`). `publishHints` repart de l'itinéraire actif :

- `closingHint` prend le statut Google de la destination réelle (inversée ou non) et l'heure
  d'arrivée `maintenant + durée` ; un statut absent, une arrivée à plus de 60 minutes de la
  fermeture ou une destination inconnue laissent la rangée absente ;
- `fuelHint` charge le fichier Fuel Finder une seule fois par processus, via `PlaceFuel.source`
  ou la source injectée des tests, et seulement quand la ligne touche la zone couverte par
  `FuelGb.inUk`. Un fichier de plus de deux jours ne rend aucun détour ;
- une nouvelle demande annule la passe précédente (`hintJob`), et `close`, `fail` ou une erreur
  sans origine remettent les deux champs à `null`. Un indice ne survit donc jamais à
  l'itinéraire qui l'a produit.

Les deux rangées du sélecteur sont `route-closing` et `route-fuel-detour` dans
`RouteSheets.swift`. La seconde nomme la marque, le prix au litre et la distance hors ligne. Le
texte commun vit dans `TravelHintText`, pour que le bandeau dise les mêmes heures.

Dans `NavStore`, `NavUiState.closingWarning` est calculé au départ depuis le lieu de destination
conservé, puis recalculé à chaque changement d'itinéraire du `NavSession` (reroutage ou variante
plus rapide acceptée) avec la durée restante. `NavChrome` l'ajoute comme une seule ligne discrète
sous la manœuvre (`nav-closing`), à l'intérieur de la carte, sans toucher aux voies, aux
panneaux, à l'aperçu d'étape ni à l'ETA par arrêt. `stop()` l'efface.

Limites assumées de ce câblage : la navigation ne contrôle que la destination, pas chaque arrêt
(contrairement à `maybeWarnClosingSoon` d'Android, qui demande l'heure d'arrivée de chaque arrêt) ;
le bandeau de navigation n'ajoute pas de seconde ligne carburant, le détour restant dans le
sélecteur pour ne pas dépasser le budget de hauteur de la carte.

## Manques Google et manques du portage

- Badges « Revendiqué par le propriétaire » et « Vérifié » : absents du modèle commun et des
  réponses analysées. Rien n'est affiché.
- Succursales à d'autres adresses et suivi `searchBranches` d'Android : non portés. Le groupe
  vient uniquement de la réponse de recherche déjà en mémoire, donc aucune requête
  supplémentaire, mais aucune succursale hors de cette réponse. Les lieux liés de
  `similarPlaces` restent affichés séparément.
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
  liés à travers le repli détails, attributs venus du repli quand la réponse est tronquée.
- `FuelGbTest` (common, JVM et iOS) : lecture des colonnes par nom, appariement et écart de
  marque, marque et âge de la fiche, comparaison à 1 penny et 5 km, prix Google et hors zone
  ignorés, fichier périmé, polygones irlandais, jours calendaires par fuseau.
- `ClosingTimeTest` (common) : compte à rebours sous l'heure, minuit, changement de fuseau,
  fermé aujourd'hui, fermetures permanente et temporaire, horaires 24 h et plages de nuit,
  avertissement d'arrivée avant et après la fermeture.
- `PlaceTravelHintsTest` (JVM) : détour carburant sur la ligne, station trop loin, fichier périmé,
  et la fenêtre de 60 minutes de l'avertissement d'arrivée.
- `RouteStoreTest.pickerHintsFollowEachRecalculatedRoute` (JVM) : les deux rangées apparaissent,
  survivent à un recalcul, disparaissent quand la nouvelle ligne ou la nouvelle durée ne
  correspondent plus, et `close` les efface.
- `RouteStoreTest.staleFuelFileAndAFarRouteShowNoDetour` (JVM) : un fichier de plus de deux jours ne
  rend rien, et une ligne hors zone Fuel Finder ne demande même pas le fichier.
- `NavStoreTest.closingWarningSurvivesARouteSwapAndClearsOnEnd` (JVM) : la ligne apparaît au
  départ, disparaît sur un itinéraire plus court, revient avec le long, et `stop` l'efface.
- `FuelWireTests` (Swift) : les heures de fermeture et d'arrivée, minuit compris, et la phrase du
  détour avec sa marque, son prix et sa distance.
- `PlaceFuelUITests.testFuelPlaceCard` et `.testClosingTimeCard` : captures `place-fuel.png` et
  `place-closing.png`, avec les libellés `place-fuel`, `place-fuel-nearby` et `place-closing`.
  Les deux lieux sont des fixtures ouvertes sans recherche ni requête Google.

## Partage (SHR-PLACE)

Le bouton Partager de la fiche et celui du choix d'itinéraire ouvrent la feuille système
`UIActivityViewController`. Aucun service maison n'est ajouté : les destinations sont celles que
l'utilisateur a déjà installées.

Pour un lieu, `ShareLinks` construit le lien canonique de Google quand Google est autorisé : le
lien exact de la fiche par son cid non signé, sinon une recherche nom et point, comme
`SavedStore.sharePlaceUrl` et Android. Le texte porte le nom puis l'adresse, sans répéter le nom
quand l'adresse commence déjà par lui. Le lien est un second élément de la feuille, après le
texte, pour qu'une application qui n'accepte qu'un élément garde au moins le texte.

Il n'existe aucune API de création de lien court, ni sur Android ni sur iOS : aucun
`maps.app.goo.gl` n'est fabriqué, et le réglage « Open shared Google Maps links » de PR-1, qui ne
concerne que les liens courts entrants, ne change donc rien à un partage sortant. Le test JVM
vérifie que le lien produit n'est pas reconnu par `ShortLinks.isShortener`.

Sans Google, aucun lien Google n'est construit. Le partage utilise l'objet OpenStreetMap du lieu
quand son identifiant le porte (`osm:n123`, `osm:node/123` ou la même référence derrière
`overture:`), sinon une recherche Photon sur le nom et l'adresse, deux liens que l'application
sait déjà lire. Quand aucun lien ne peut être construit, le texte reprend le repère keyless
d'Android, `geo:lat,lng?q=lat,lng(nom)`.

Pour un itinéraire, le texte donne l'origine, la destination, les arrêts dans l'ordre et le mode,
puis l'ETA seulement quand le modèle en fournit une : une durée inconnue, marquée négative dans
le modèle partagé, ne produit aucune ligne ETA. Le lien Google Directions n'est ajouté que si
Google est autorisé, avec l'origine omise quand elle vaut la position de l'appareil, ce que Google
traite déjà comme l'origine absente, et les arrêts dans l'ordre.

La feuille de partage est un processus distant. XCUITest ne peut donc pas lire son contenu :
`ShareUITests.testPlaceShareContentsAndRouteText` contrôle l'ouverture de la feuille par son hôte
`ActivityListView`, capture `share-place.png` et `share-route.png`, et lit le contenu exact dans
la valeur d'accessibilité de débogage du bouton Partager, qui est la charge utile remise à la
feuille. `ShareLinksTest` couvre le lien cid, le repli nom et point, le repère `geo`, les liens
OpenStreetMap et Photon, le texte d'itinéraire sans durée et les deux cas NoGoogle.

## Preuve SHR-PLACE

Sous Linux, `:core-common:jvmTest :ios-shared:jvmTest :ios-shared:compileKotlinIosSimulatorArm64`
passe avec 967 tests JVM pour `core-common` (dont `ShareLinksTest`) et 321 pour `ios-shared`,
zéro échec.

Le run Mac `shr-place-20261028-010341-61` exécute `ShareUITests.testPlaceShareContentsAndRouteText`
en 61,968 s : les deux feuilles sont ouvertes (`share_place_sheet=ActivityListView`,
`share_route_sheet=ActivityListView`), les captures `share-place.png` et `share-route.png` montrent
l'en-tête `google.com` de la feuille, et les assertions de contenu passent sur le miroir de
débogage, nom et adresse du lieu, lien Google, puis origine, destination, mode, ETA et lien
Directions. Le statut du run est `failed` uniquement à cause de
`NavStoreTest.trafficOfferIsMirroredAndAcceptanceAdoptsTheCandidate`, déjà rouge sur les branches
`imp-google` et `set-about` du même runner ; les 131 tests Swift et le scénario de partage sont
verts. Une première demande, `shr-place-20261027-230109-30910`, n'a publié aucun résultat.

## Savoir ouvert (W-1)

L'onglet Overview gagne une section « Learn more » sous les lieux liés. Elle lit deux sources
ouvertes et n'affiche que ce qu'elles donnent :

| Champ | Source | Propriété |
|---|---|---|
| Population | Wikidata | P1082 |
| Ouverture | Wikidata | P1619, tronquée à la précision de la déclaration (`1889`, `1889-03` ou `1889-03-31`) |
| Site officiel | Wikidata | P856, seulement une URL http(s) |
| Identifiant | Wikidata | l'identifiant de l'élément, cliquable vers sa page |
| Extrait | Wikivoyage | les trois premiers paragraphes de la page, nettoyés |

Un champ absent n'est pas dessiné. La section n'apparaît que pour un lieu dont l'identifiant
porte un élément Wikidata (`wikidata:Q90`, `wd:Q90` ou `Q90`). Un identifiant Google `0x...:0x...`
ou OpenStreetMap `osm:...` n'en nomme aucun : la fiche ne montre alors pas la section et n'émet
aucune requête. Elle n'en émet pas non plus tant que le calque Wikivoyage est éteint. Le
bouton du calque se trouve dans « World layers » de la feuille des couches.

La langue suit celle de l'interface, puis les autres langues préférées du système, puis l'anglais.
Wikidata est interrogé avec `languages=xx|en` et le libellé retenu est le premier présent.
Wikivoyage utilise la sitelink de la même langue quand elle existe, sinon la sitelink anglaise.
Chaque source est mise en cache 24 h dans le magasin `vela_wiki`, sous une clé qui contient la
liste des langues : changer de langue ne sert donc jamais un texte de l'autre langue.

Aucune image Wikimédia n'est affichée dans ce lot. Le nettoyage supprime les balises `img`,
les figures, les tableaux, les scripts et les styles ; l'extrait ne porte que du texte. La section
renvoie vers la page source par « Read the full article on Wikivoyage ».

Licences : Wikidata est CC0 1.0. Wikivoyage est CC BY-SA 4.0, avec l'attribution exacte
« Wikivoyage contributors, CC BY-SA 4.0 » sous l'extrait, dans la fiche et dans les notices de
l'application. Le texte de Wikivoyage ne peut être réutilisé sans cette attribution et sans la
même licence.

Limites assumées :

- Google ne fournit pas d'identifiant Wikidata. La section n'apparaît donc que pour les lieux
  dont l'identifiant vient déjà de Wikidata, ou pour le scénario de test qui ouvre Paris (Q90).
- Un élément Wikidata peut être incomplet, faux ou sans sitelink Wikivoyage. Dans ce cas la fiche
  montre les champs présents, ou seulement les faits quand aucun article n'existe.
- La couverture de Wikivoyage est inégale : beaucoup de restaurants et de commerces n'ont pas de
  page. Aucun extrait n'est inventé.
- Les API Wikimedia imposent leurs propres limites. Un échec réseau laisse la section absente,
  sans message trompeur.
- Aucune image n'est chargée, donc aucune vérification de licence de fichier, au prix d'une fiche
  moins illustrée que la page source.

Tests : `WikiStoreTest` couvre les champs Wikidata, l'extrait nettoyé, le repli de langue, le cache
de 24 h, l'absence d'image et les deux cas sans requête (aucun identifiant, calque éteint), plus le
filtre du calque par viewport. `PlaceKnowledgeUITests.testWikidataAndWikivoyage` ouvre Paris (Q90)
en direct, capture `place-wikidata.png`, `place-wikivoyage.png` et `wiki-layer.png`, puis inscrit
`wiki_fields`, `wikivoyage_chars` et `wiki_image=none` au résumé.

Sous Linux, `:core-common:jvmTest :ios-shared:jvmTest :ios-shared:compileKotlinIosSimulatorArm64`
passe avec 995 tests JVM pour `core-common` et 441 pour `ios-shared`, zéro échec.

Preuve Mac : les runs `w1-wiki-20261028-121356-27419` et `w1-wiki-20261028-123655-16128`
compilent l'application et ouvrent la fiche de Paris. Le premier échoue parce que les requêtes
Wikimedia partaient sans User-Agent (403 sur `www.wikidata.org` et `api.wikimedia.org`). Le second
montre la section chargée en direct dans l'arbre d'accessibilité :

    wiki_fields=3 wiki_image=none wiki_language=en wiki_id=Q90
    Wikivoyage contributors, CC BY-SA 4.0
    Wikidata, CC0 1.0
    Source: Paris on Wikivoyage

La capture `place-knowledge-debug.png.png` du run montre l'extrait de Paris, le lien
« Read the full article on Wikivoyage » et les deux attributions. Le scénario échouait malgré tout
parce que l'identifiant `place-knowledge` posé sur le conteneur remplaçait ceux des champs ; il est
maintenant posé sur le seul titre. Le test et les captures `place-wikidata.png`,
`place-wikivoyage.png` et `wiki-layer.png` restent à confirmer sur un run Mac après cette
correction d'identifiants.

## Atlas Obscura et Gastro Obscura

La fiche lieu porte deux lignes de lien, jamais un calque, un article, une photo ou un résultat
de recherche. Les conditions du site réservent le service à un usage personnel et non commercial
et interdisent de copier ou distribuer une partie du service ; `robots.txt` interdit en plus
`/search*`. Vela n'a demandé aucune autorisation et n'en suppose aucune. La notice
`atlas-obscura` de `Settings/Notices.json` le dit, avec les deux noms et l'hôte
`www.atlasobscura.com`.

| Ligne | Condition d'affichage | Adresse |
|---|---|---|
| Explore nearby on Atlas Obscura | le lieu a des coordonnées finies | `https://www.atlasobscura.com/search?q=&location=&nearby=true&lat=<6 décimales>&lng=<6 décimales>` |
| Food places on Gastro Obscura | le lieu a des coordonnées et une catégorie de nourriture ou de boisson | `https://www.atlasobscura.com/gastro/places` |

Les deux adresses sont construites dans `ObscuraLinks` (Kotlin), jamais en Swift. L'hôte est une
constante. La latitude est bornée à `-90..90` et la longitude à `-180..180`, puis arrondie à six
décimales fixes. Aucun texte du lieu n'entre dans l'URL : pas de nom, pas d'adresse, pas de
requête libre. Une coordonnée non finie rend `nearbyUrl` nul, donc la ligne disparaît.

La règle « nourriture seulement » est `ObscuraLinks.isFood` : des mots entiers de la catégorie
Google (`restaurant`, `cafe`, `bar`, `bakery`, `wine`, `grocery`, et leurs variantes) décident de
la seconde ligne. Une station-service, un musée ou une ville ne l'affichent pas. Gastro n'offre
aucun filtre par position : son adresse ne porte donc ni `lat` ni `lng`, et le libellé ne promet
pas une recherche par proximité.

La ligne ouvre `SFSafariViewController`, la même feuille web que les articles de la couche wiki.
Vela ne lit aucune réponse, ne garde aucun titre, aucun texte et aucune photo, et ne demande
aucune image au site. La feuille se ferme par son contrôle de fermeture : « Done » avant iOS 26,
la croix « Close » depuis, parce que le style par défaut de `SFSafariViewController` a changé. Les
captures de recette sont `place-atlas-obscura.png` et `place-gastro-obscura.png`, avec les lignes
`obscura_action=atlas_nearby` et `obscura_action=gastro_places`.
