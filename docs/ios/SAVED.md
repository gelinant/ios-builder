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

## Partage et export

Le partage d'un lieu conserve l'URL Google canonique. `ShortLinks` sait résoudre les liens courts
entrants, mais ne fournit aucune API de création d'un lien court sortant. L'app ne prétend donc pas
produire un `maps.app.goo.gl`. Un partage de liste garde aussi le fichier Vela plutôt qu'un lien
Google, comme Android.

Le lot L-2 ajoute les exports que L-1 laissait de côté, toujours depuis la feuille système et avec
un nom de fichier lisible :

- un lieu, quick save ou entrée de liste, en JSON, GPX ou KML ;
- une liste entière, dans ces trois formats, depuis le menu de la liste ;
- tous les quick saves en JSON, GPX ou KML, et toutes les listes en JSON, depuis le menu de Saved ;
- « Everything » produit les deux fichiers JSON d'Android, quick saves et listes, dans une seule
  feuille de partage.

Le JSON est le format complet : il conserve l'identifiant, le nom, l'adresse, l'icône, l'épinglage,
le caractère point, la note, la couleur, la couche, les photos et l'appartenance aux listes. Un
export JSON réimporté dans une bibliothèque vide redonne exactement les mêmes lieux et les mêmes
listes, avec leurs identifiants et leurs entrées. GPX et KML ne portent que le nom, la coordonnée et
l'adresse, seules données que `PlaceImport` sait relire : l'identifiant, l'icône, l'épinglage, la
note, la couleur, la couche, les photos et l'appartenance aux listes y sont perdus. Un export GPX ou
KML d'une liste est donc un fichier plat de lieux, pas une liste. Les quick saves n'ont pas de
`featureId` dans le modèle `SavedPlace` ; aucun format ne peut donc le restituer, et les liens
partagés reconstruisent le cid depuis le lieu ouvert, pas depuis un quick save exporté.

`SavedExport` construit GPX et KML en texte, avec les coordonnées à six décimales et l'ordre
longitude, latitude de KML. Android n'écrit que le JSON : GPX et KML sont un ajout iOS parce que
l'import les lisait déjà, pas un format Android à égaler.

Android ne propose pas de partage d'un itinéraire enregistré : aucun nouveau format de partage n'a
été inventé pour cette donnée.

## Parking

La ligne du spot courant propose « Find my car ». Elle ferme Saved, sélectionne le lieu « Parked
car » avec la même fiche que le bouton P d'Android, et laisse donc Directions, marche comprise, sur
la fiche. Les lignes de l'historique se restaurent ou se suppriment une par une. « Clear history »
demande confirmation et ne touche pas au spot courant.

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

Une exécution qui échoue, par opposition à une annulation, ne laisse aucune liste à moitié écrite :
la liste créée par les sauvegardes progressives est supprimée, ou la liste existante retrouve ses
entrées d'avant le run. Le message le dit et l'état redevient non occupé. Saved affiche le nombre de
lignes traitées sur le total pendant l'import, avec le bouton Cancel ; la liste cible garde le nom
du fichier Takeout, comme Android.

Les tests JVM couvrent l'annulation avec persistance partielle, la suppression des entrées périmées,
l'identité des lignes, l'échec avec remise à zéro, les aller-retours JSON, GPX et KML, et la
restauration du parking. Les tests Swift vérifient l'équilibrage de la portée et les noms de fichiers
exportés.

Le scénario UI ouvre la feuille de partage d'une liste et prend `saved-export.png`, puis supprime la
liste. La feuille système et le sélecteur de fichiers sont des processus distants que XCUITest ne
peut pas piloter ; le test relit donc le document exact que l'export vient d'écrire et le confie au
même importeur au lancement suivant, ce qui produit `saved-import-back.png`. Le chemin du sélecteur
de documents lui-même reste couvert par les tests du lecteur et par le scénario Takeout L-1, et
demande une vérification sur iPhone. Un autre scénario ouvre « Find my car » depuis Saved et vérifie
la fiche du lieu et son bouton Directions. Le scénario L-1 importe aussi deux repères locaux sans
réseau depuis `TakeoutFixture.csv`.

## Preuve du lot

Le run `l1-saved-polish-20261026-181057-20440` réussit les trois scénarios L-1 et produit
`saved-home.png`, `saved-route.png` et `saved-import.png`. Il compte 119 tests Kotlin JVM, 98 tests
Kotlin simulateur et 54 tests Swift, tous verts. La suite UI complète reste rouge sur deux sujets
indépendants de ces scénarios : l'indexation du fixture Spotlight et la persistance des récents du
scénario Saved existant. L'IPA du run contient bien le code de ce lot, mais ces deux écarts empêchent
de la présenter comme une validation complète de la V1.

Pour L-2, la vérification Linux demandée passe : `:core-common:jvmTest`, `:ios-shared:jvmTest` et
`:ios-shared:compileKotlinIosSimulatorArm64`, avec 192 tests JVM dont les nouveaux aller-retours
d'export et l'échec Takeout.

Le run Mac ciblé `l2-saved-export-20261027-165047-28351` est vert : les deux scénarios
`SavedExportUITests` passent, `saved_export_roundtrip=1`, `saved_export_sheet=opened` et
`saved_find_my_car=opened`. Il produit `saved-export.png`, `saved-import-back.png` et
`saved-find-my-car.png`, 192 tests Kotlin JVM, 171 tests Kotlin simulateur et 87 tests Swift, tous
verts, puis une IPA de 20 593 961 octets. Un lancement de la suite UI complète avait été demandé
avant les corrections finales ; le runner l'a interrompu avant les scénarios, puis le délai du
workflow a expiré.

Le run ciblé `l2-saved-export-20261027-172143-9790` rejoue `SavedFinishingUITests` :
`testSavedLineReopensBesideComputedRoutes` et `testTakeoutFixtureImportsIntoNamedList` passent. Le
scénario Maison/Travail échoue sur son attente de 5 s de la feuille Saved alors que la hiérarchie
d'accessibilité montre ensuite `NavigationBar Saved` ouverte ; c'est un délai de simulation, pas un
état perdu. Les scénarios Saved existants, le sélecteur de documents et l'IPA restent à rejouer en
suite complète et sur iPhone.
