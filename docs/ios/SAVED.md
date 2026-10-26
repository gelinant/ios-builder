# Lieux enregistrés : raccourcis, lignes, partage et Takeout

Ce document précise les choix du lot L-1. Les preuves de scénarios sont consignées dans
[TESTING-IOS.md](TESTING-IOS.md) et la matrice de parité reste [FEATURES-IOS.md](FEATURES-IOS.md).

## Maison et Travail

Les lignes Maison et Travail de Saved ouvrent directement la fiche du lieu, qui propose Directions.
Les boutons correspondants de la carte ouvrent en plus le choix d'itinéraire en un geste. Tous ces
chemins, y compris Siri et `vela://navigate/home` ou `work`, passent par
`SavedModel.openShortcut`. Celui-ci lit `SavedState.home` ou `SavedState.work`, puis sélectionne le
`SavedPlace` complet. Il ne dépend donc ni d'une recherche récente, ni d'un quick save, ni d'une
appartenance à une liste.

## Itinéraires enregistrés

`SavedRouteStore` conserve une polyligne encodée, les extrémités, le mode, le nom et la date. Il ne
conserve ni durée, ni trafic, ni étapes. `SavedRouteDirections` ajoute la géométrie stockée aux
réponses du routeur de planification, sans envelopper la source utilisée par `NavSession` pour les
recalculs en conduite.

Le choix « Saved line » est ainsi présenté à côté des itinéraires nouvellement calculés :

- la distance affichée est celle de la géométrie décodée ;
- le nom est visible sur la ligne et le nom, le mode et la date figurent dans Saved ;
- aucune ETA, donnée de trafic ou étape n'est fabriquée ;
- la ligne sert à la prévisualisation sur la carte, tandis que Start et Steps sont désactivés pour
  ce choix ;
- un itinéraire calculé voisin peut être sélectionné pour obtenir le guidage actuel.

La durée négative dans `Route` est seulement un marqueur interne d'ETA inconnue. Elle n'est jamais
présentée comme une durée. Les instances `Route` des lignes inchangées sont mises en cache et
réutilisées sans copie, conformément à la règle d'identité de `RouteStore` et `NavSession`. Une
réouverture explicite force l'offre même depuis un nouveau point de départ. Si le routeur échoue,
la ligne reste disponible seule au lieu de perdre aussi la géométrie locale. Un changement de mode,
des arrêts ou une inversion qui ne correspond plus à la destination retire cette offre.

Les lignes enregistrées se renomment et se suppriment dans Saved. Les runs Android avec arrêts ne
sont pas transformés en ligne forcée : le choix d'itinéraire iOS ne sait pas encore restaurer leurs
arrêts.

## Partage

Le partage d'un lieu conserve l'URL Google canonique. `ShortLinks` sait résoudre les liens courts
entrants, mais ne fournit aucune API de création d'un lien court sortant. L'app ne prétend donc pas
produire un `maps.app.goo.gl`.

Android permet l'export d'une liste. iOS partage maintenant ce même JSON portable depuis le menu de
la liste, sous forme de fichier dans la feuille système. Ce fichier peut être réimporté. Android ne
propose pas de partage d'un itinéraire enregistré : aucun nouveau format de partage n'a été inventé
pour cette donnée.

## Import Takeout

Le sélecteur de documents utilise `SavedDocumentReader`, et le fixture tente le même chemin avant
son contenu de secours fourni par XCUITest. La lecture appelle
`startAccessingSecurityScopedResource`, puis libère la portée dans un `defer`, y compris si le
décodage UTF-8 échoue. Le texte est lu entièrement avant le lancement des recherches, donc la portée
n'a pas besoin de rester ouverte pendant celles-ci.

Un import annulé enregistre les lieux déjà trouvés et conserve les anciennes entrées qui n'ont pas
encore été revérifiées. L'état redevient non occupé, y compris si l'annulation précède le premier
tour de la coroutine. À la fin normale d'un nouvel import, la liste contient seulement son résultat :
une entrée précédemment importée dont la recherche échoue désormais ne reste pas indéfiniment.
Les recherches relancent `CancellationException` au lieu de la convertir en simple absence de
résultat.

Les tests JVM couvrent l'annulation avec persistance partielle, la suppression des entrées périmées
et l'identité des lignes. Les tests Swift vérifient l'équilibrage de la portée et le fichier de
partage. Le scénario UI importe deux repères locaux sans réseau depuis `TakeoutFixture.csv`.

## Preuve du lot

Le run `l1-saved-polish-20261026-181057-20440` réussit les trois scénarios L-1 et produit
`saved-home.png`, `saved-route.png` et `saved-import.png`. Il compte 119 tests Kotlin JVM, 98 tests
Kotlin simulateur et 54 tests Swift, tous verts. La suite UI complète reste rouge sur deux sujets
indépendants de ces scénarios : l'indexation du fixture Spotlight et la persistance des récents du
scénario Saved existant. L'IPA du run contient bien le code de ce lot, mais ces deux écarts empêchent
de la présenter comme une validation complète de la V1.
