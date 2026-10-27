# Recherche par adresse et par lieu sur iOS (I-2c)

État : branche `ios/i2c-photon-search`. Ce document décrit la recherche en ligne sans Google sur
iOS : ce qui répond, dans quel ordre, ce qui reste hors ligne, et les limites de Photon.

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

## Tests

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
