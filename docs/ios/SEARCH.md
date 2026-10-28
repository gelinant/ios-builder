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
