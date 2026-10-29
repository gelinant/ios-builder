# Recherche par adresse et par lieu sur iOS (I-2c, SRCH-CARDS)

État : branche `ios/srch-area` pour la zone de recherche, après les filtres et le tri de
`ios/srch-filter` et les cartes de résultats de `ios/srch-cards` ; le reste décrit la recherche en
ligne sans Google livrée par `ios/i2c-photon-search`. Ce document couvre ce qui répond, dans quel
ordre, ce qui reste hors ligne et les limites de Photon.

## Sources

La recherche en ligne passe par `SearchStore` (`ios-shared/.../ios/search`). Trois sources se
partagent une réponse :

- **Google** par `GoogleMapsSource` quand l'option « Utiliser Vela sans Google » est off ;
- **Photon** (`photon.komoot.io`, l'API de komoot, sans clé) pour les adresses, et pour toute la
  recherche en ligne quand Google est off ;
- **le magasin installé** (`OfflineStore` : POI, adresses et rues des régions téléchargées), qui
  répond seul quand l'appareil n'a pas de réseau ou quand le mode hors ligne de test est actif, et
  qui complète toujours la réponse en ligne.

Le géocodeur inverse et la fiche lieu ne changent pas ici.

## Sans Google

`OfflineStore.offlineOnly()` vaut vrai dans trois cas : pas de réseau, mode hors ligne de test, ou
NoGoogle. `SearchStore` sépare le dernier des deux premiers : NoGoogle n'est pas une demande hors
ligne, Photon n'est pas Google. La recherche appelle donc la source, dont la branche NoGoogle de
`GoogleMapsSource` interroge Photon deux fois, comme Android :

- une requête classée par Photon (`limit=20`, biais doux `lat`/`lon`, sans cadre) ;
- une requête des environs (`limit=10`, cadre dur d'environ 60 km), pour les adresses partielles.

Les deux réponses sont fusionnées par identifiant OSM. Aucun hôte Google n'est contacté : la
branche revient avant `session.ensure()`, et le client HTTP refuse de toute façon un hôte Google
quand NoGoogle est actif (`PRIVACY.md`).

Les lignes installées sont cherchées en parallèle et fusionnées. Une région téléchargée garde donc
ses commerces et ses adresses, qui passent devant les résultats Photon quand ils portent la
requête. En cas d'échec de Photon (pas de réseau, serveur muet, réponse illisible), la recherche
retombe sur les lignes installées avec `usedOffline = true` ; elle ne retombe jamais sur Google.

Limite connue : avec NoGoogle et le mode hors ligne de test actif sur un appareil qui garde un
réseau, une requête Photon peut partir avant le repli local. Sur un vrai appareil sans réseau (ou
en mode avion), la requête échoue immédiatement et seules les lignes installées restent.

## Google autorisé

La recherche reste celle de Google. Pour une requête qui lit comme une adresse (chiffres en tête,
`AddressQuery`), une requête Photon part en parallèle (`limit=10`, biais doux). Les fenêtres de
recherche sont élargies à 40 km pour une adresse, même si la carte est très zoomée, comme Android
(`ADDRESS_SEARCH_SPAN_M`). Une réponse Google vide ou une adresse absente des résultats Google
laisse donc Photon répondre.

## Classement et doublons

`SearchMerge` applique les règles d'Android :

- une adresse tapée fait passer en tête les lignes qui portent réellement le numéro et le nom de
  rue, classées par score de rue puis par distance ;
- une ligne Photon qui porte le numéro tapé passe avant une ligne Google approximative ; quand
  Photon et Google décrivent le même lieu, l'identité Photon est gardée (numéro exact), et Google
  ne sert qu'à compléter un champ manquant ;
- une adresse estimée du magasin installé (`addr~`) disparaît dès qu'une ligne réseau, Photon ou
  Google, porte la même adresse ;
- les doublons sont écrasés par identifiant stable, identifiant de lieu Google, puis nom normalisé
  et distance inférieure à 60 m. Le même lieu ne produit donc ni deux lignes ni deux épingles, et
  la liste et les épingles lisent la même réponse.

## Suggestions

La saisie attend 320 ms après la dernière frappe : une requête par pause, jamais une par caractère.
Avec Google autorisé, l'autocomplétion Google répond en premier, complétée des adresses Photon et
des adresses installées ; quand Google ne rend rien, Photon et les adresses installées répondent.
Avec NoGoogle, il n'y a pas d'autocomplétion Google : Photon n'a pas d'endpoint de suggestion, donc
seules les adresses (Photon et magasin installé) apparaissent. Les noms de lieux ne sont pas
suggérés avant la validation. C'est un écart assumé avec Android, qui relance une recherche Photon
complète à chaque pause pour les noms ; iOS préfère ne pas doubler le trafic vers un serveur
public.

## Cartes de résultats (SRCH-CARDS)

Chaque ligne de la liste suit la carte Android : vignette photo, nom, note avec le nombre d'avis,
distance, prix et catégorie, statut ouvert ou fermé coloré en vert ou en rouge, puis l'adresse
complète. Les actions rapides sont sous le texte : Itinéraire toujours, Appeler seulement quand la
réponse Google porte un téléphone, Enregistrer toujours, avec l'icône pleine quand le lieu est déjà
enregistré. Le statut vient du texte de Google (`statusText`) et de `openNow`, jamais d'un code
numérique. Un lieu définitivement fermé s'affiche en rouge avec son libellé.

La vignette est la première URL photo de la réponse de recherche, redimensionnée à 400 x 300 comme
la cellule Android. Elle passe par `ImageLoader`, le cache mémoire déjà utilisé par la fiche lieu,
avec les en-têtes Safari de `MapSession.photoHeaders()`. La recherche ne fait donc aucune requête
Google supplémentaire par ligne, la réponse portant déjà les URL.

Les actions n'ajoutent aucun paramètre à `MapScreen.swift`, fichier sérialisé par la ruche
(`BACKLOG.md` section 3). La carte et la flèche de suggestion joignent le modèle par le registre
faible `SearchActions` défini dans `SearchModel.swift`. Le jour où `MapScreen` pourra être modifié,
les fermetures pourront être passées directement au panneau et le registre retiré.

## Priorité des suggestions et flèche

La priorité reprend Android : les lieux de l'utilisateur passent devant le réseau. `SearchModel`
pousse dans `SearchStore.setLocalPlaces` les lieux récemment ouverts, puis les lieux des listes,
puis les raccourcis enregistrés, lus dans la facette enregistrée. `SuggestionPriority` filtre ces
lieux sur le nom ou l'adresse, les déduplique, en garde six, puis ajoute jusqu'à huit lignes réseau
en écartant tout lieu déjà nommé par les lignes locales (même identifiant stable, même
`featureId`, ou même nom au même endroit).

Le délai de 320 ms, le dédoublonnage et la glace des suggestions après sélection ne changent pas.
Les lignes locales portent l'icône d'historique et arrivent sans requête. La flèche de retour de
chaque ligne remplit le champ avec le texte de la ligne, nom pour un lieu, requête pour une
suggestion de requête, sans lancer de recherche, comme Android. Les tests peuvent distinguer une
ligne locale d'une ligne réseau par la valeur d'accessibilité `local` ou `network`.

## Plus de résultats et en-tête

L'en-tête de la liste dit « Searching », « Search » ou « N results », comme avant. Quand Google a
pu paginer, une ligne « More results » ferme la liste ; chaque appui demande les trois pages
suivantes de la même requête, les ajoute sans doublon et masque la ligne quand une réponse est
vide. La première recherche iOS contient déjà les pages 0 à 2, la ligne commence donc page 3. Avec
NoGoogle, la ligne n'apparaît pas : Photon n'a pas de pagination équivalente. Ce libellé vient de
`mapscreen_more_results`, déjà présent dans les 24 langues.

## Filtres et tri (SRCH-FILTER)

L'en-tête de la liste porte un bouton de filtres, comme la rangée de puces d'Android. La feuille
propose le tri, puis Open now, la note minimale, le prix maximal et l'accessibilité. Une ligne
résume les réglages actifs sous l'en-tête.

- **Tri** : pertinence (l'ordre de la source), note décroissante, distance croissante. Une note
  ou une distance absente passe en dernier, comme `MapScreen.kt`.
- **Open now** : en plus de filtrer les lignes déjà reçues, la puce relance la même recherche
  Google avec le mot « open now » de la langue de l'app (`search_open_now_phrase`), exactement
  comme `MapViewModel.searchOpenNow`. La requête part vers le même
  `/search?tbm=map&q=...&pb=...`, avec le même `pb` calibré et le même encodage que sur Android :
  un espace devient `+`. Aucun jeton de filtre n'est ajouté au `pb`, puisque Google n'en documente
  pas et qu'Android n'en envoie pas. La boîte de recherche garde les mots de l'utilisateur.
- **Note, prix, accessibilité** : filtrage local de la réponse déjà reçue, sans requête
  supplémentaire. Une note absente échoue au plancher, un prix absent échoue au plafond (il peut
  le dépasser), et l'accessibilité vient du champ `wheelchairAccessible` de la réponse de
  recherche. Le repli sur les horaires hebdomadaires quand Google n'envoie pas de statut est
  porté par `PlaceHours` (même règle que `OpeningHours.statusAt` d'Android).
- **Comportement conservé** : le délai de 320 ms, le dédoublonnage, la priorité des suggestions et
  « More results » ne changent pas. Changer Open now relance une seule recherche, pas une seconde
  recherche parallèle ; les autres contrôles ne touchent pas au réseau. « More results » demande
  les pages suivantes de la requête reformulée, donc de la même réponse.

### Sans Google

Photon et les régions téléchargées ne portent ni note, ni niveau de prix, ni statut en direct, ni
attribut d'accessibilité. Les appliquer viderait la liste et ferait croire que rien n'est ouvert.
La feuille masque donc ces contrôles et affiche une ligne qui l'explique. Ce qui survit :

| Contrôle | Google | NoGoogle (Photon et régions) |
|---|---|---|
| Open now | oui, requête reformulée | masqué |
| Note minimale | oui, local | masqué |
| Prix maximal | oui, local | masqué |
| Accessibilité | oui, local | masqué |
| Tri pertinence | oui | oui, ordre de Photon |
| Tri note | oui | masqué |
| Tri distance | oui | oui, distance au biais, absente en dernier |

Le magasin passe aussi ces filtres à `supportedBy` : même si un réglage restait actif au moment
où NoGoogle s'active, le store le retire au lieu de rendre une liste fausse. Le mot « open now »
n'est jamais ajouté à une requête Photon.

### Tests

- JVM, `SearchFiltersTest` : filtres, tri, repli horaire, plage après minuit, matrice NoGoogle et
  encodage `q=` (`caf%C3%A9+jetzt+ge%C3%B6ffnet`).
- JVM, `SearchFiltersStoreTest` : Open now relance la même requête une seule fois puis le plain
  texte au retour, les autres contrôles ne touchent pas la source, NoGoogle retire les filtres.
- JVM, `SearchFilterRequestTest` : avec le vrai `GoogleMapsSource` iOS, la requête part vers
  `https://www.google.com/search?tbm=map...&q=coffee+open+now&pb=...`, et une recherche NoGoogle
  n'envoie que des requêtes Photon.
- Simulateur, `SearchFiltersUITests.testFiltersAndSort` : plancher de note à 4,0 puis tri par
  distance ; captures `search-filter-sheet` et `search-filtered`. Run
  `srch-filter-20261027-202426-27986` : test vert, 59 cartes toutes à 4,0 ou plus, tri de 213 m à
  2 414 m. Le run reste rouge sur `IncomingLinksTests`, un test Swift de DL-2 sans rapport avec ce
  lot, et non sur les tests Kotlin.

## Zone de recherche (SRCH-AREA)

Le bouton « Rechercher dans cette zone » apparaît au-dessus de la liste quand la carte a bougé
après une recherche. Il reste visible quand la liste est repliée, pour que la carte reste lisible
et que la liste rafraîchie soit à un appui. Le libellé vient de `mapscreen_search_this_area`, déjà
présent dans les 24 langues.

### Seuil de déplacement

Android arme le bouton dans `onCameraIdle`, qui ne se déclenche qu'après un geste de
l'utilisateur : un cadrage programmatique ne le montre jamais. iOS n'a qu'un rappel de viewport
pour tous les mouvements de caméra, sans drapeau de geste dans la façade de recherche. Le port
reprend donc le pas du pavé directionnel Android, 22 % de la vue (`docs/dpad.md`), comme seuil de
déplacement : un mouvement plus court est un cadrage ou un tremblement, pas un glissement. Le seuil est
calculé sur la plus petite des deux portées de la vue au moment de la recherche
(`SearchArea.moved`), donc il suit le zoom. Si la carte revient sur la vue d'origine, le bouton
disparaît.

### Recherche et restriction à la vue

`SearchStore.searchThisArea()` relance la requête avec le milieu et la hauteur de la vue actuels,
jamais avec ceux de la réponse affichée : un glissement suivi d'une recherche ne peut pas classer
les résultats autour de l'ancien point (issue #670). La réponse est ensuite restreinte à la vue avec
10 % de marge, comme `AreaNarrow` d'Android. Si aucune ligne ne tombe dans la vue, la réponse
complète reste : une liste vide annoncerait à tort qu'il n'y a rien. La même règle s'applique aux
lignes du magasin installé, et la restriction ne vaut que pour la recherche qui l'a demandée.

### Doublons et « More results »

`SearchMerge.mergeCounted` renvoie la liste fusionnée et le nombre de lignes perdues en doublon.
Le magasin expose ce nombre dans `SearchState.droppedDuplicates`, ce qui donne `dropped=<n>` dans
`search-debug`. L'ordre de la source est conservé : la première occurrence garde sa place et les
doublons suivants disparaissent. « More results » utilise `SearchMerge.appendCounted` : les lignes
déjà affichées restent dans le même ordre et les nouvelles sont ajoutées à la fin. Une page qui ne
contient que des doublons ou rien ne réaffiche pas le bouton ; le compteur de doublons augmente du
nombre exact de lignes écartées.

Le seuil de « More results » se lit sur la réponse complète, avant la restriction à la vue, comme
la taille de `res.places` chez Android. Une recherche de zone peut donc garder une liste courte et
un bouton « More results » encore utile.

### Sans Google

Avec NoGoogle, `searchThisArea()` relance la requête Photon avec le milieu de la vue comme biais
doux, et son cadre dur pour la variante des environs. Aucun hôte Google n'est contacté. Si Photon
échoue et qu'aucune ligne installée ne répond, la liste est vidée avec l'erreur : les anciennes
lignes ne survivent pas à une recherche de zone ratée.

### Emplacement et couture avec MapScreen

Le bouton vit dans `ResultsPanel` (`iosApp/Vela/Search/SearchViews.swift`) et lit le modèle par
`SearchActions`, donc `MapScreen.swift` n'a besoin d'aucune modification : le viewport arrive déjà
par `map.onViewportChange` puis `search.viewportChanged(viewport)`, et le magasin garde la vue
courante. Si la ruche libère `MapScreen.swift` et préfère la pastille flottante d'Android au-dessus
de la carte, le montage tient en une ligne dans `browserChrome`, entre `Spacer()` et
`mapActionButtons` :

```swift
SearchAreaButton(available: search.searchAreaAvailable)
```

Il faudra alors masquer la pastille quand une fiche lieu, un itinéraire ou une fiche POI est
ouverte, et retirer le même bouton de `ResultsPanel` pour ne pas l'afficher deux fois.

### Tests

- JVM, `SearchAreaTest` : seuil sous et au-dessus de 22 %, biais et hauteur de la vue après un
  glissement, restriction à la vue, doublons comptés sans réordonner, « More results » qui ajoute sans
  répéter, et échec NoGoogle qui ne garde pas la liste affichée.
- JVM, `NoGoogleAreaSearchTest` : avec le vrai `GoogleMapsSource` iOS, la recherche de zone
  n'émet que des requêtes `photon.komoot.io`, avec `lat` et `lon` du point atteint par le
glissement, et aucune
  requête Google.
- Simulateur, `SearchAreaUITests.testSearchThisAreaAndMoreResults` : un vrai glissement sur la
  carte après une recherche « coffee » fait apparaître le bouton, la capture
  `search-area-button` le montre, l'appui relance la recherche (le compteur `searches` de
  `search-debug` augmente), la capture `search-area-refreshed` montre la liste rafraîchie, les
  valeurs d'accessibilité des cartes prouvent zéro doublon, puis « More results » ajoute des
  lignes sans réordonner celles déjà affichées. Run `srch-area-20261027-234526-21366` : test vert
  en 412 s, 60 cartes avant le glissement, 54 après la recherche de zone, zéro doublon, puis
  « More results » de 54 à 113 cartes sans réordonner (12 glissements pour atteindre le bouton).
  Le même run passe 327 tests Kotlin JVM, 268 tests Kotlin simulateur et 131 tests Swift, sans
  échec.

### Limites

Le seuil remplace le drapeau de geste d'Android. Un cadrage programmatique qui déplacerait la
carte de plus de 22 % de la vue après une recherche offrirait le bouton à tort ; en pratique le
cadrage des épingles reste dans la vue de la recherche, et le test vérifie que la première réponse
ne montre pas le bouton. Le bouton est dans le panneau de résultats et non flottant sur la carte
tant que `MapScreen.swift` est sérialisé par la ruche.

## Tests

- JVM, `SearchCardsTest` : ordre récent puis enregistré puis réseau, dédoublonnage par nom et
  `featureId`, correspondance sur l'adresse, plafonds de six et huit lignes, survie des champs de
  carte (photo, note, avis, prix, statut, téléphone) à la fusion, et pagination qui ajoute sans
  doublon puis masque la ligne sur une réponse vide.
- Simulateur, `SearchUITests.testSuggestionPriorityAndArrow` : un lieu ouvert devient la première
  suggestion locale, la flèche remplit le champ sans soumettre, capture
  `search-suggestion-priority`.
- Simulateur, `SearchUITests.testResultCardFields` : une carte porte note et statut, une vignette
  est chargée, Itinéraire et Enregistrer sont présents, capture `search-card-fields`.
- JVM, `PhotonSearchStoreTest` : NoGoogle interroge la source sans seconde requête Photon, l'échec
  en ligne retombe sur le magasin installé, les suggestions d'adresse restent Photon, une demande
  vraiment hors ligne ne touche pas la source.
- JVM, `NoGooglePhotonSourceTest` : avec le vrai `GoogleMapsSource` iOS, une recherche NoGoogle
  n'émet que deux requêtes `photon.komoot.io` et aucune vers Google.
- JVM, `SearchMergeTest` : Photon gagne le doublon contre Google, mène sur le numéro tapé et fait
  disparaître l'estimation installée.
- Simulateur, `SearchUITests.testPhotonAddressSearchShowsTheTypedHouseNumber` (capture
  `search-photon`) et `SearchUITests.testNoGoogleSearchReturnsPhotonRows` (capture
  `search-photon-nogoogle`). Les scénarios Google existants restent inchangés.

## Limites de Photon

- Service public sans clé, politique d'usage raisonnable : pas de quota garanti, pas de SLA. Une
  panne ou une limitation se traduit par un repli local, jamais par une erreur bloquante.
- Couverture : OpenStreetMap uniquement. Les commerces récents ou les adresses absentes d'OSM
  manquent ; les catégories ne sont pas un langage de recherche (pas d'équivalent de « coffee »).
- Langues : Photon ne répond dans la langue de l'interface que pour `en`, `de` et `fr`. Les autres
  langues reçoivent les noms par défaut d'OSM. Pour une recherche classée, la source demande
  l'anglais quand la langue de l'app n'est pas prise en charge, afin que « eiffel tower » trouve
  le bon lieu.
- Le cadre dur des environs (environ 60 km) peut masquer une adresse voulue plus loin. C'est
  voulu pour une adresse partielle ; la requête classée, sans cadre, retrouve une ville ou un
  monument lointain.
- Aucun test sur iPhone réel pour ce lot : les scénarios tournent sur le simulateur, avec le
  réseau du runner.

## Succursales à la même adresse (SRCH-BRANCH)

L'état : branche `ios/srch-branch`, après les cartes et les filtres. La fiche lieu nomme les
autres fiches Google posées à la même adresse, comme la section « Also at this location »
d'Android. Rien n'est demandé à Google : le groupe est lu dans la réponse de recherche déjà
reçue. Une réponse sans voisin n'affiche donc ni puce ni liste, et une recherche qui n'a pas
rempli `results` (lien entrant, lieu enregistré rouvert) ne fabrique rien.

### Règles de groupe

`PlaceBranches` (`ios-shared/.../ios/search`) reprend `MapViewModel.othersAt` :

- la ligne de rue est comparée sans le complément (`Ste`, `Suite`, `Unit`, `Apt`, `Bldg`,
  `Fl`, `#`), sans la ville et sans la ponctuation ;
- deux fiches de la même ligne de rue sont retenues à moins de 60 m ;
- sans adresse d'un côté ou de l'autre, seule l'empreinte à moins de 15 m compte, pour ne pas
  prendre la boutique d'en face ;
- la fiche ouverte est écartée par identifiant de lieu Google, sinon par nom ;
- l'ordre de la réponse est gardé et la liste s'arrête à six fiches.

La puce « N locations » apparaît sous le statut de la fiche, avec l'identifiant d'accessibilité
`place-branch-chip`. Elle déplie la liste sous elle (`place-branch-list`, lignes
`place-branch-row`), avec le titre `place_also_at_location`. Ouvrir une ligne passe par le même
chemin que le reste de la fiche et relit le groupe : la fiche d'origine reste donc dans la liste,
à un appui. La puce et la liste se recalculent pour la nouvelle fiche, sans requête.

### Limites honnêtes

- Google ne joint pas toujours les voisins à la réponse de recherche. Dans ce cas la section
  reste absente, sans bouton qui demanderait une requête supplémentaire. Le réglage Android
  « Find other locations automatically » n'est donc pas porté : iOS n'a pas de `searchBranches`,
  et ajouter une requête contredirait le lot.
- Seules les fiches à la même adresse sont nommées. Les autres succursales d'une chaîne, à
  d'autres adresses, ne sont pas cherchées.
- Le groupe vient de la liste filtrée (`SearchStore.results`). Un filtre qui masque une fiche la
  masque aussi dans la section.
- Aucune puce n'est dessinée pour un lieu ouvert depuis un lien entrant, un lieu enregistré ou
  une épingle OSM, faute de réponse de recherche à lire.

### Tests

- JVM, `PlaceBranchesTest` : clé de rue et compléments, même rue à moins de 60 m, boutique d'en
  face écartée, empreinte sans adresse, fiche ouverte écartée par identifiant puis par nom,
  ordre conservé, plafond de six, réponse sans voisin, cohérence de la fixture.
- Simulateur, `SearchBranchUITests.testBranchChipAndShortcutEditor` : la fixture ouvre une
  boutique et trois voisins, vérifie la puce à 3, la liste, l'ouverture d'une succursale qui
  laisse la puce à 3, puis l'éditeur. Captures `place-branch-chip`, `place-branch-list`,
  `place-branch-opened` et `quick-chips-editor`.

## Raccourcis de recherche (SRCH-BRANCH)

La rangée de puces sous la barre de recherche suit maintenant le catalogue Android complet :
Restaurants, Coffee, Gas, Groceries, Things to do, Hotels, Bars, EV charging, Parking, Pharmacy,
ATMs, Parks, Hospitals, Banks, Post office, Campgrounds. Les requêtes restent les mots anglais
stables d'Android, les libellés viennent des clés `cat_*` déjà traduites. En région britannique,
irlandaise ou autre zone qui dit « petrol », la puce carburant envoie « Petrol station » mais
garde la clé `Gas station`, comme `CategoryQuery.fuel`.

Une puce « More » (`category-more`) ferme la rangée. Son menu liste toutes les puces dans
l'ordre enregistré, y compris celles qui sont éteintes : une catégorie cachée reste à un appui.
Les identifiants existants (`category-coffee`, etc.) ne changent pas.

### Éditeur

Réglages > Quick search buttons (`settings-quick-chips`) ouvre `QuickChipsEditor`. Chaque puce a
un interrupteur qui la retire de la rangée et deux boutons qui la montent ou la descendent. Une
puce éteinte garde sa place, donc la rallumer la remet où elle était. « Reset to default » efface
l'ordre et les masquages. Trois clés de `vela_settings` sont partagées avec Android :

| Clé | Contenu |
|---|---|
| `quick_chips_order` | clés dans l'ordre, séparées par une barre verticale ; vide = ordre du catalogue |
| `quick_chips_hidden` | clés éteintes, séparées par une barre verticale |

Android écrit `quick_chips_hidden` comme un `StringSet`. La couture `KeyValueStore` d'iOS ne
porte que des chaînes : iOS garde le même nom de clé et le même séparateur, et relit sa propre
suite `app.vela.ios.vela_settings`. Le format de l'ordre est identique des deux côtés.

### Limites honnêtes

- La rangée de recherche sur un itinéraire et la rangée voiture d'Android ne sont pas portées :
  MapScreen est sérialisé par la ruche et iOS n'a pas d'écran voiture. Seule la rangée de la
  carte et son menu More sont livrés.
- Le mode Android « catégories en un bouton ou masquées » (`category_chips`) n'est pas exposé :
  la rangée reste visible, avec le menu More.
- « Hide adult categories » retire Bars de la liste affichée, mais la clé garde sa place dans
  l'ordre enregistré.

### Tests

- JVM, `QuickChipsTest` : catalogue et ordre par défaut, requête carburant régionale sans
  changement de clé, ordre et masquage persistés entre deux instances, mêmes clés et même
  séparateur qu'Android, déplacement tenu aux extrémités, clé inconnue ignorée, remise à zéro.
- Simulateur, `SearchBranchUITests.testBranchChipAndShortcutEditor` : l'éditeur liste les puces,
  éteint Coffee, la remonte en tête, ferme et rouvre l'éditeur pour vérifier l'enregistrement,
  puis retrouve la puce More sur la carte. Captures `quick-chips-editor`,
  `quick-chips-reordered` et `search-more-chip`.

## Recherche unifiée (UNIFIED-SEARCH)

État : branche `ios/unified-search`, après la zone, les filtres, les cartes et les raccourcis. La
barre de recherche ne répond plus seulement aux lieux et aux adresses : elle trouve aussi les lieux
et listes enregistrés, les arrêts et lignes de transport, les réglages et actions de l'app, les
articles Wikivoyage et Wikipédia, et une coordonnée tapée ou collée. C'est le même champ, la même
pause de 320 ms et le même panneau sous la barre.

### Sources et coûts

Chaque ligne porte un type (`place`, `address`, `saved`, `list`, `stop`, `line`, `wiki`,
`setting`, `coord`, et `query` pour une suggestion de recherche). Les sources locales sont lues
dans l'état que l'app tient déjà, sans requête. Les sources en ligne tournent en parallèle, chacune
avec sa propre échéance : une source lente ajoute ses lignes en retard, elle ne retient jamais
celles des autres.

| Source | Coût | Échéance |
|---|---|---|
| Lieux récents, lieux de listes, raccourcis enregistrés | 0 requête, classement synchrone | aucune |
| Listes enregistrées | 0 requête, classement synchrone | aucune |
| Réglages et actions (`SettingsIndex`) | 0 requête, classement synchrone | aucune |
| Coordonnée tapée | 0 requête, analyse locale | aucune |
| Arrêt de transport déjà connu (épingle de carte, dernier tableau ouvert) | 0 requête | aucune |
| Ligne du dernier tableau d'arrêt | 0 requête | aucune |
| Arrêts Transitous dans la vue (0,12° x 0,18° au plus autour du centre) | 1 requête `api.transitous.org`, une par pause | 3,5 s |
| Wikivoyage et Wikipédia | 2 requêtes REST (une par projet), cache mémoire de 5 min | 4,5 s |
| Lieux et adresses Google ou Photon | la recherche existante, aucun appel ajouté | la source existante |

Les deux hôtes wiki sont `{langue}.wikivoyage.org` et `{langue}.wikipedia.org`, sur
`/w/rest.php/v1/search/page`. La langue de l'interface est demandée d'abord ; si les deux projets
échouent dans cette langue, la même requête repart en anglais. Rien n'est envoyé au-delà des mots,
de la langue et de l'agent utilisateur déjà utilisé par W-1. Aucun hôte Google n'est contacté par
ces sources, même quand Google est autorisé pour les lieux.

### Ordre et doublons

`UnifiedRanking` étend les règles de SRCH-CARDS :

- une correspondance locale exacte (le titre est la requête, ou un mot la commence) passe avant une
  correspondance locale partielle, qui passe elle-même avant toute ligne en ligne, même exacte ;
- dans un même palier, le score du type décide : coordonnée, lieu récent, lieu enregistré, liste,
  réglage, arrêt, ligne, article, lieu, adresse, suggestion de recherche ;
- un lieu déjà nommé par un lieu enregistré n'apparaît jamais une seconde fois, ni par identifiant
  de lieu ni par nom normalisé à moins de 60 m ;
- un arrêt connu localement et rendu par le flux est un seul arrêt (même type, même nom, même point
  à 100 m près) ; une ligne suit la même règle ;
- dix lignes locales et huit lignes en ligne au plus, vingt-quatre au total ;
- l'ordre de la source est conservé à score égal, et la position de la ligne de lieu reste celle de
  `SearchStore`, donc l'ouverture d'un lieu et le cadrage de la carte ne changent pas.

Une coordonnée est ajoutée par le magasin lui-même : la requête se suffit, aucune source n'est
interrogée et la ligne reste la première.

### Actions

- **Lieu récent ou enregistré** : ouvre sa fiche, comme la ligne de suggestion actuelle.
- **Liste** : ouvre la liste et ses lieux ; un lieu ouvre sa fiche.
- **Arrêt** : ouvre le tableau des prochains départs, celui de la carte.
- **Ligne** : rouvre le tableau de son arrêt, donc ses prochains départs.
- **Article** : ouvre une fiche de lecture avec le chapô déjà reçu et le lien vers la page
  complète ; aucune image et aucun HTML ne sont chargés, comme W-1.
- **Réglage** : ouvre Réglages avec la section et le libellé de la ligne. L'ancre de
  `SettingsIndex` voyage avec la ligne ; le formulaire s'ouvre en haut et la bannière nomme la
  section. `SettingsScreen` garde son propre défilement : ce lot ne peut pas le faire défiler, et
  la ligne visée est dans les premières sections dans les cas courants.
- **Coordonnée** : dépose une épingle (`MapPoiStore.longPress`) et montre la fiche avec Itinéraire.
- **Lieu ou adresse** : passe par `MapScreen.pickSuggestion`, donc le même cadrage et la même
  fiche qu'avant.

### Vitesse et focus

Le classement local est synchrone : `UnifiedSearchStore.setQuery` publie les lignes locales avant
de rendre la main, puis lance les sources en ligne après la pause de 320 ms. Le test JVM mesure ce
classement sous 120 ms avec 600 lieux enregistrés ; la ligne de débogage `search-debug` porte
`ulocal=<n>ms` et le test simulateur vérifie la borne. Aucune requête ne part par frappe : la
pause, la génération et l'annulation sont celles de `SearchStore`.

Quand une ligne prend la main, `SearchModel` vide le panneau et incrémente `unifiedBlurTick` ;
`SearchBar` voit ce compteur, retire le focus et ferme le clavier sans toucher au texte tapé. La
barre ne perd donc ni son focus ni son défilement pendant que les lignes arrivent : seul le
panneau change.

### États vides et « chercher partout »

Une source qui a répondu sans résultat le dit avec son nom : « Nothing saved matches », « No
transit stop nearby », « No wiki article matches ». Une source peut être encore en cours ; la
ligne « Searching transit and wiki » le montre sans bloquer la liste.

La ligne compacte « Search everywhere for "..." » envoie les mêmes mots à la recherche de lieux
existante (Google ou Photon), pour l'utilisateur qui voulait un lieu et dont la requête ne
ressemblait à rien de local. Elle ne crée aucune requête supplémentaire : c'est le `submit` actuel.

### Limites honnêtes

- Les lignes de transport ne sont cherchables qu'après avoir ouvert un arrêt : leur libellé vient
  du dernier tableau reçu. Transitous n'a pas de recherche de ligne par nom, et ce lot n'ajoute pas
  d'index mondial des lignes.
- Les arrêts en ligne sont cherchés dans la vue courante (au plus 0,12° x 0,18° autour du centre) et
  filtrés par nom : un arrêt très éloigné n'est pas trouvé.
- Les articles wiki dépendent de deux hôtes publics sans clé ni SLA ; un échec laisse les autres
  sources intactes. Le chapô vient de la recherche, pas de la page complète.
- Un réglage ouvre le formulaire en haut, pas exactement sur sa ligne, tant que `SettingsScreen`
  n'accepte pas d'ancre à l'ouverture.
- La ligne de coordonnée comprend les degrés décimaux (avec `geo:`, un signe et N/S/E/W) et pas les
  degrés-minutes-secondes.
- Aucun test sur iPhone réel pour ce lot.

### Tests

- JVM, `UnifiedSearchTest` : exact local avant partiel avant en ligne, lieu enregistré qui absorbe
  le doublon en ligne, source lente qui n'empêche pas la ligne rapide puis qui expire seule,
  une seule requête par pause, coordonnée locale sans appel, états vides par source, index de
  suggestion conservé, classement de 600 lieux sous 120 ms et formes de coordonnées acceptées ou
  refusées.
- Simulateur, `UnifiedSearchUITests.testFindSavedTransitWikiSettingAndPlace` : une liste importée
  par le vrai importateur, le tableau Ferry Building du fixture Debug, puis les lignes
  enregistrée, liste, arrêt, ligne, article, réglage, coordonnée et lieu. Captures
  `unified-saved`, `unified-list`, `unified-list-opened`, `unified-stop`, `unified-line`,
  `unified-wiki`, `unified-wiki-article`, `unified-setting`, `unified-setting-row`, `unified-coord`,
  `unified-coord-pin` et `unified-place` ; une ligne `UITEST unified_kind=...` par type.

Run `unified-search-20261028-172057-20579` : 522 tests Kotlin JVM et 425 tests Kotlin
simulateur sans échec, 151 tests Swift sans échec, les huit scénarios `SearchUITests` verts. Le
scénario unifié est vert sur `saved`, `list` et `stop`, puis rouge sur `line` : le fixture du
tableau avait été fermé avant que ses lignes n'arrivent, donc la mémoire du champ était vide. Le
test attend maintenant `transit-board-line` et cherche la ligne avant l'arrêt ; ce correctif est
dans la branche mais la demande de run suivante n'a pas rendu de `STATUS` dans la fenêtre du
service. Les étapes `wiki`, `setting`, `coord` et `place` restent donc à voir sur le runner.

La base `ios/main` de ce lot ne compilait pas : `MapSavedMarkers.swift` était vide, `SavedStore`
n'exposait pas `mapPins()` et `MapController` capturait `self` avant d'initialiser `savedStore`.
La branche porte ces trois raccords, repris de `ios/map-tap` et de `ios/transit-lineview`, pour que
le lot puisse être vérifié ; ils appartiennent aux lots MAP-TAP et SAV-MARK et devront être
fusionnés proprement.

## Commandes tapées et dictées (SRCH-CMD)

État : branche `ios/srch-cmd`, après la recherche unifiée et la dictée VO-2. Le champ de recherche
lit désormais les commandes avant d'envoyer la requête. La dictée passe par le même analyseur, donc
une phrase tapée et la même phrase dite produisent la même action.

La validation du champ transmet au modèle le texte qu'elle vient de committer, et l'analyse tourne
au tour de boucle suivant, quand la dernière frappe a rejoint la liaison SwiftUI. La commande ne
lit donc jamais un préfixe du texte tapé. `SearchModel.submit(text:viewport:)` repasse lui aussi
par l'analyseur : aucun appelant ne peut envoyer une phrase de commande à Google ou à Photon, et
une phrase inconnue garde le chemin de recherche ordinaire avec exactement les mots tapés. La
ligne de débogage porte `cmd_len=<n>`, la longueur du texte analysé, pour distinguer une phrase
inconnue d'un texte tronqué.

### Commandes

| Texte | Action |
|---|---|
| `home`, `take me home` | itinéraire vers le raccourci Maison enregistré |
| `work`, `get me to work` | itinéraire vers le raccourci Travail enregistré |
| `directions to X`, `navigate to X` | recherche X, puis choix d'itinéraire sur le premier résultat |
| `search along the route coffee`, `coffee along the route` | recherche coffee, puis corridor autour de l'itinéraire actif |
| `call Ada Lovelace` | résolution du contact et appel, avec la permission Contacts |
| `coffee near me` | recherche simple avec le remplissage retiré, comme Android |

`SearchCommands` (`:ios-shared`, `app.vela.ios.search`) ajoute seulement les deux formes que
`QueryIntents` ne connaît pas, l'appel et la recherche le long de la route. Tout le reste vient du
vocabulaire commun à Android, y compris Maison, Travail et les itinéraires. Une phrase non reconnue
reste une recherche simple : `Home Depot` et `call center` ne deviennent pas des actions.

Un nom de contact est gardé tel qu'il a été tapé ou entendu, sans être rangé en minuscules. La
langue de l'app choisit les préfixes ; l'anglais reste le repli, comme pour `QueryIntents`.

### Recherche le long de la route

La commande lit la ligne active de `RouteStore`, puis lance une seule recherche ordinaire. Le
corridor garde les résultats à 3 km ou moins de la ligne et les classe par détour, soit deux fois
la distance perpendiculaire, puis par distance parcourue. Chaque ligne affiche ce détour. Le nombre
de résultats trouvés et la largeur du corridor apparaissent dans la ligne de débogage :
`cmd_kind=along cmd_corridor_m=3000 cmd_found=N cmd_total=M`.

Sans itinéraire ouvert, la commande ne cherche pas au hasard : elle répond « Plan a route first,
then search along it. » Le scénario Debug peut fournir une ligne fixe à San Francisco
(`-VelaSearchCommandRoute`), et la fixture de commandes remplit Maison et Travail avec des lieux
réels, pour que la capture soit reproductible. Elle efface puis réécrit les deux raccourcis, donc
elle ne dépend pas de l'ordre de la remise à zéro ni de l'état du simulateur. Un lancement normal
n'ajoute ni raccourci ni ligne.

Une commande Maison ou Travail sans raccourci enregistré ne lance pas de recherche de lieu : elle
répond « No Home saved yet. Open Saved to set it, then ask again. », avec la même phrase pour
Travail. `cmd_kind` reste `home` ou `work`, donc le scénario distingue un raccourci absent d'une
phrase non reconnue.

### Contacts

`ContactsBridge` est le seul lecteur du carnet d'adresses. Il ne lit rien au lancement et n'écrit
rien sur disque. La première commande `call` demande l'accès au moment de l'utiliser, avec la
phrase calme de `NSContactsUsageDescription` : la recherche se fait sur ce téléphone, rien n'est
envoyé ni conservé. Un contact n'est lu qu'après l'accord, et seulement pour le nom demandé.

En cas de refus, la carte le dit et relance la même recherche de lieu dans Google ou OSM, sans
deuxième chemin de recherche. Si aucun contact ne porte de numéro, le message le dit et propose la
recherche de lieu. Le numéro trouvé est nettoyé avant l'ouverture de `tel:`. Les scénarios UI
peuvent nommer la réponse et un petit carnet avec `-VelaContactsPermission` et
`-VelaContactsFixture` ; ces options n'existent qu'en Debug et ne remplacent jamais le vrai
carnet en production.

### Tests

- JVM, `SearchCommandTest` : Maison, Travail, itinéraire, recherche simple, les formes le long de
  la route, l'appel, et les phrases ordinaires qui doivent rester des recherches.
- JVM, `SearchCommandCorridorTest` : corridor de 3 km, tri par détour, distance affichée et route
  absente qui rend tout le résultat.
- JVM, `VoiceDictationTest` : les phrases dictées le long de la route et d'appel passent par le
  même analyseur.
- Simulateur, `SearchCommandUITests.testTypedAndSpokenCommands` : Maison, Travail, itinéraire,
  corridor, appel refusé, phrase inconnue restée recherche, puis appel dicté accordé par la
  fixture. Le scénario tape la phrase, attend que le champ la porte entière, puis valide : la
  validation ne court plus après la dernière frappe. Pour Maison, il vérifie que le choix
  d'itinéraire nomme « Ferry Building » (`route-destination`) et que `searches` reste à 0 ; pour
  Travail, il nomme « Salesforce Tower » et vérifie aussi `searches=0`. Captures
  `search-command.png` et `search-along-route.png`, lignes `UITEST cmd_kind=` avec la valeur
  réellement publiée, `UITEST cmd_len=` et `UITEST cmd_contacts=denied|granted`.
- Run `srch-cmd-check7-20261029-180923-11072` : scénario vert en 252,8 s. Lignes du rapport :
  `cmd_kind=home cmd_len=4 cmd_searches=0`, `cmd_kind=work cmd_len=4 cmd_searches=0`,
  `cmd_kind=directions cmd_len=20`, `cmd_kind=along cmd_len=29 cmd_corridor_m=3000 cmd_found=54`,
  `cmd_kind=call cmd_len=17 cmd_contacts=denied`, `cmd_kind=- cmd_len=6 cmd_searches=4` pour la
  phrase inconnue, puis `cmd_kind=call cmd_contacts=granted` pour la dictée. Le choix d'itinéraire
  nommait « Ferry Building » pour Maison et « Salesforce Tower » pour Travail, donc les deux
  raccourcis venaient bien de la fixture. Les 8 tests `SearchUITests` restent hors de ce lot :
  `testAddressSearchMergesWithoutDuplicateRows` est rouge sur ce run (Google et Photon n'ont pas
  rendu le numéro tapé), alors qu'il était vert sur `srch-cmd-check5` ; c'est une dépendance au
  réseau des réponses enregistrées, pas le chemin des commandes.

### Limites

- La permission Contacts se demande sur le vrai carnet ; le runner la remplace par la fixture
  Debug, donc le scénario ne clique pas la boîte système d'iOS.
- Le classement par détour est propre à iOS ; Android garde l'ordre de parcours de
  `RouteCorridor`.

## Recherche le long de la route pendant la conduite (SRCH-ALONG)

État : branche `ios/srch-along`. La commande existante garde son comportement hors conduite. Pendant
une navigation guidée, elle ne part plus du point de départ : elle lit la progression de la
conduite et ne garde que la route encore devant la voiture. Un lieu dont la projection tombe sur la
partie déjà parcourue est écarté, donc il ne peut plus entrer dans le corridor ni dans l'ordre des
détours. Les distances affichées restent le détour, deux fois la distance perpendiculaire.

### Lecture de la progression

`NavStore.traveledMeters()` est un accesseur additif : il rend `NavState.traveledM`, la même
progression monotone que le trait gris de la route et le bandeau, et zéro hors navigation guidée.
`SearchModel` lit donc une seule source pour la conduite, jamais la distance d'un itinéraire
seulement prévu. Le tracé vient de `NavStore.line()`, donc une réorganisation ou un arrêt ajouté en
route change bien la ligne lue. Sans conduite, le chemin est celui d'avant : la ligne active du
choix d'itinéraire, sinon la ligne fixe du scénario Debug.

`SearchCommandCorridor.select` reçoit `traveledMeters`. Il calcule les projections sur la ligne
entière pour garder le repère global, puis refuse ce qui est derrière la voiture et rend
`routeMeters`, la longueur restante réellement utilisée. Le corridor garde sa largeur de 3000 m :
sur la ligne de test de 3339 m, un trajet de 1650 m laisse 1690 m de route et le corridor reste à
3000 m. La ligne de débogage le dit sans ambiguïté :
`cmd_from=origin|progress cmd_route_m=<mètres restants>`.

### Scénario

`SearchCommandUITests.testAlongRouteSkipsTheTravelledPart` ouvre l'itinéraire Market Street par le
lien de fixture, démarre la conduite, attend que le rejeu ait laissé 600 m derrière la voiture,
laisse la fixture de commandes soumettre « coffee along the route » par le même `submit` que le
champ, puis termine la conduite pour relire la ligne de débogage. Il exige `cmd_from=progress` et
`cmd_route_m` inférieur à la longueur totale de 400 m au moins, et publie les deux longueurs. Le
chrome de conduite n'a pas de champ de recherche : la fixture soumet la phrase elle-même, avec le
même analyseur et le même chemin que le clavier.

Les tests JVM `SearchCommandCorridorTest.travelProgressCutsTheTravelledPart` et
`noProgressKeepsTheWholeRoute` fixent les deux moitiés du contrat : 1650 m parcourus donnent
1690 m de corridor et écartent le lieu de départ, alors que sans progression la ligne entière de
3339 m reste et le lieu de départ est gardé.

### Limites

- Le scénario simulateur n'a pas encore de run vert : les deux runs Mac du lot ont échoué sur le
  déclenchement de la fixture, pas sur le corridor. Le premier run n'avait pas de bouton micro
  pendant la conduite, le second n'a pas vu la commande se déclencher. Le correctif final lit
  `NavStore.traveledMeters()` et se sert de la fixture de commandes déjà verte, mais il reste à
  vérifier sur le runner.
- Le corridor ne se resserre pas autour de la voiture : la largeur reste 3000 m de chaque côté de
  la route restante. Seule la partie derrière la voiture disparaît.
- La progression vient de la session de navigation. Une conduite libre n'a pas de route et garde
  donc le message « Plan a route first ».
