# Recherche par adresse et par lieu sur iOS (I-2c, SRCH-CARDS)

État : branche `ios/srch-filter` pour les filtres et le tri, après les cartes de résultats et la
priorité des suggestions de `ios/srch-cards` ; le reste décrit la recherche en ligne sans Google
livrée par `ios/i2c-photon-search`. Ce document couvre ce qui répond, dans quel ordre, ce qui
reste hors ligne et les limites de Photon.

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
