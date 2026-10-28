# Lieux enregistrés : raccourcis, lignes, partage et Takeout

Ce document précise les choix des lots L-1, L-2 et SAV-EDIT. Les preuves de scénarios sont
consignées dans [TESTING-IOS.md](TESTING-IOS.md) et la matrice de parité reste
[FEATURES-IOS.md](FEATURES-IOS.md).

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

## Éditeur de listes

Le lot SAV-EDIT remplace la feuille de nom seule par un éditeur de liste qui enregistre le nom, la
couleur, l'icône et le son en une écriture. Le nom est validé avant l'enregistrement : vide, plus de
40 caractères ou identique à une autre liste (sans tenir compte de la casse) affichent un message et
laissent le bouton Save désactivé. L'icône est soit un symbole SF, soit `emoji:X`; l'emoji libre
alimente la même clé. Les couleurs reprennent la palette Android.

Les listes se réordonnent par glisser (le bouton Reorder active les poignées) et se déplacent aussi
par le menu, qui garde Move up et Move down. Les entrées d'une liste se réordonnent de la même façon
par glisser ; l'ordre est persisté dans `PlaceList.places`. Les opérations groupées vérifient que les
identifiants reçus correspondent exactement au contenu affiché avant d'écrire, donc un identifiant
inconnu ne supprime jamais une ligne.

## Sélection multiple et actions groupées

Un appui long sur une ligne ou le bouton Select ouvre le mode sélection, disponible pour les
lieux enregistrés et pour les entrées d'une liste. La barre du bas affiche le compte, All, Move to
list, Rename (une seule ligne), Remove et Done. Move to list propose les autres listes et la création
d'une nouvelle liste qui reçoit la sélection dès son enregistrement. Remove demande confirmation.
Le déplacement en masse conserve l'icône propre à chaque lieu, comme l'action Android. La feuille
d'un lieu garde ses cases à cocher par liste : plusieurs appartenances se modifient sans fermer la
feuille.

## Son et retour haptique

Une liste peut choisir Off, Ping, Bell, Double, Low ou Say its name. Le choix est enregistré dans
`PlaceList.alert`, la même clé que sur Android. Choisir un son le joue immédiatement, et ajouter un
lieu à une liste qui a un son joue aussi ce son, puis un retour haptique.

Aucun nouvel asset audio n'est livré : `SavedSoundPlayer` synthétise les quatre tonalités avec
AVAudioEngine à partir des fréquences et durées de `PassAlerts`, table partagée avec Android. La
session audio est `.ambient` avec `mixWithOthers`, donc un aperçu ne coupe ni le guidage ni une autre
application. Say its name passe par `VelaNavVoice`. Les retours haptiques (sélection, déplacement,
réordonnancement, aperçu) utilisent `AppleNavHaptics`, la même implémentation UIKit que les
manœuvres.

L'alerte au passage pendant la conduite dépend du flux de position et du bandeau de la carte. Le
stockage et le choix du son sont prêts, mais le branchement de `PassAlerts` sur les positions de
conduite reste à faire dans un lot qui touche `MapScreen.swift` et `NavModel.swift`.

## Notes et renommage des entrées

Le menu d'une entrée propose Rename et Add note. La note est enregistrée par `PlaceListStore.setNote`
dans toutes les listes qui contiennent le lieu, et s'affiche sous l'adresse. Le renommage réutilise
`SavedStore.renamePlace`, qui met à jour le lieu enregistré et ses entrées de liste.

## App Intents et Spotlight

`SavedState.indexRows()` produit les lignes publiées : les lieux enregistrés puis chaque entrée de
liste, avec une clé qui inclut la liste. Un renommage, un déplacement d'une liste à l'autre ou une
suppression change donc la charge utile au prochain état observé. `SpotlightIndexer` observe déjà
`SavedStore.state` et remplace les trois domaines à chaque lot modifié, ce qui réindexe le titre et
supprime les entrées périmées. Les intents lisent `VelaSavedContent.current`, construit à partir du
même état, donc ils voient les mêmes noms et appartenances après une édition.

## Preuve du lot

Le run `l1-saved-polish-20261026-181057-20440` réussit les trois scénarios L-1 et produit
`saved-home.png`, `saved-route.png` et `saved-import.png`. Il compte 119 tests Kotlin JVM, 98 tests
Kotlin simulateur et 54 tests Swift, tous verts. La suite UI complète reste rouge sur deux sujets
indépendants de ces scénarios : l'indexation du fixture Spotlight et la persistance des récents du
scénario Saved existant. L'IPA du run contient bien le code de ce lot, mais ces deux écarts empêchent
de la présenter comme une validation complète de la V1.

## Preuve SAV-EDIT

Les tests JVM `SavedStoreTest` couvrent le déplacement et la suppression en masse, le refus d'une
cible absente, l'ordre des listes et des entrées après relance, la validation du nom, les notes et
la mise à jour des lignes Spotlight. `SavedFinishingUITests.testListEditingSelectionAndSound` crée
deux listes, ajoute un lieu, ouvre le mode sélection, enregistre un son, vérifie le refus d'un nom
vide, déplace la sélection vers l'autre liste et contrôle le son à l'ajout. Il produit
`saved-selection.png` et `saved-editor.png`.

La fusion avec L-2 garde les deux jeux de commandes dans `SavedViews.swift` : le menu d'export et
Find my car de L-2, et l'éditeur de liste, la sélection multiple, le réordonnancement, les sons et
les notes de SAV-EDIT. La vérification Linux
`:core-common:jvmTest :ios-shared:jvmTest :ios-shared:compileKotlinIosSimulatorArm64` passe, avec
943 tests JVM pour `core-common` et 271 pour `ios-shared`, dont les aller-retours d'export L-2 et
les tests d'édition SAV-EDIT.

Le build simulateur est vérifié par la compilation GitHub `sav-edit-merge-20261027-185347-22573`
sur le runner Mac, `compile check green`, le Mac LAN étant désactivé. Cette compilation ne rejoue
pas les tests Swift ni les scénarios UI.

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

## Import d'une liste Google et d'un fichier My Maps

IMP-GOOGLE ajoute les deux chemins d'import que L-1 et L-2 laissaient de côté. Le menu d'import de
Saved propose désormais « Google Maps list link » et « KML, KMZ or other file ». Les autres formats
(JSON Vela, GPX, GeoJSON, CSV Takeout) passent toujours par `SavedStore.importFile`.

### Liste Google partagée

Le lien est collé dans une feuille dédiée, jamais ouvert par `UIApplication.open`. Avec Google
autorisé, `SavedGoogleListFetcher` charge la page dans le `HiddenWebView` existant, donc avec les
cookies de consentement et de session déjà semés. Le script partagé de `SavedListImport` lit
l'identifiant de liste dans l'URL quand le lien direct le porte, sinon dans la page où le lien court
a abouti. Il appelle ensuite la RPC publique `/maps/preview/entitylist/getlist`, la même que
l'import Android, et renvoie le corps brut. `EntityListParser` en tire le titre, l'auteur, la
description et les lieux avec leur adresse, leur note et leur identifiant de lieu.

Trois étapes alimentent la progression : page chargée, liste localisée, réponse récupérée. Le
bouton Cancel de Saved arrête la page en cours ; la réponse tardive est ignorée. Une page de
consentement, une liste privée ou une forme de réponse changée ne produit aucun lieu : l'état passe
à `GOOGLE_UNREADABLE` et le message dit que le lien n'a pas montré de liste partagée. Aucun lieu
n'est inventé, aucun nom de repli n'est fabriqué.

Avec « Use Vela without Google », `SavedStore.beginGoogleListImport` refuse avant toute requête.
La feuille explique que l'import de lien a besoin de Google et renvoie vers le fichier. Le message
`GOOGLE_DISABLED` reste visible dans Saved. Le chemin KML n'est pas touché par ce réglage.

### Fichier KML et KMZ

Le sélecteur de documents lit les octets dans sa portée de sécurité avec `SavedImportReader`. Un
KMZ est dézippé par `SavedKmz`, qui lit le répertoire central du ZIP et gonfle l'entrée `.kml` avec
`Inflater(nowrap)` côté JVM et `platform.zlib` en fenêtre brute côté iOS. Un KML simple passe par le
même importeur.

`MyMapKml.lists` découpe le document en une liste par dossier `<Folder>`, dans l'ordre du fichier.
Chaque entrée garde son nom, sa coordonnée, sa note tirée de la description et ses indices
d'icône : la couleur de l'épingle et, quand le fichier la lie, l'image d'icône. La couleur de la
liste reprend la première couleur d'épingle du dossier. Un fichier sans dossier, ou un KML que
`MyMapKml` ne reconnaît pas, devient une liste plate lue par `PlaceImport`. Les lignes et zones
d'un fichier My Maps restent dans `PlaceList.shapes`, comme pour un import Android.

### Idempotence

Chaque brouillon d'import porte un `sourceId` stable : `list:<lien>` pour une liste Google et
`kml:<fichier>|<dossier>` pour un dossier de fichier. `importTarget` retrouve la liste déjà écrite
par cet identifiant, ou par son titre exact pour une liste créée avant ce lot. Un premier import
écrit directement. Un second import du même lien ou du même fichier ne touche à rien : il publie
`SavedState.pendingImport` et Saved demande Merge ou Replace. Merge ajoute seulement les lieux que
la liste ne contient pas, sans doublon d'identifiant ni de `featureId` ; Replace garde le nom,
l'icône, la couleur et le son de la liste et réécrit ses entrées. Un merge sans nouveauté répond
« Nothing new to import ». Aucun des deux chemins ne duplique silencieusement une liste.

Les deux chemins produisent la même forme `PlaceList` : entrées `ListPlace` dans l'ordre de la
source, note par entrée, couleur de liste, et `shapes` pour un fichier My Maps. SAV-EDIT lit donc
ces listes avec son éditeur, sa sélection multiple et son réordonnancement sans code dédié.

### Limites de la page Google

Ce que Google ne fournit pas de façon fiable, et que l'import ne prétend pas remplacer :

- une liste privée, ou une page qui exige une connexion, ne rend aucun lieu ;
- une page de consentement sans redirection vers la liste ne rend aucun lieu ;
- Google peut changer le chemin `getlist` ou la forme du tableau positionnel ; dans ce cas
  `EntityListParser` renvoie zéro lieu et l'import échoue proprement, sans invention ;
- une liste partagée ne porte ni couleur de liste ni icône : Vela emploie le bleu et l'icône
  signet par défaut ;
- la note d'une entrée vient du propriétaire de la liste ; une note vide reste vide ;
- l'ordre affiché est celui de la réponse, sans tri supplémentaire ;
- un lien de lieu ou d'itinéraire collé dans cette feuille n'est pas une liste et produit le même
  message honnête.

### Preuves

Les tests JVM `SavedImportTest` couvrent l'ordre, les notes et la couleur d'une liste Google, la
note d'un dossier KML, les indices d'icône, le second import qui demande Merge ou Replace, le merge
qui n'ajoute que les nouveautés, le refus NoGoogle alors que le KML passe, et les entrées
malformées (page de consentement, texte vide, faux KMZ, lien non Google). `SavedKmzJvmTest` couvre
le KML dégonflé, stocké et nommé autrement que `doc.kml`, ainsi qu'un ZIP sans KML. Les tests L-2 et
SAV-EDIT restent verts.

Le scénario `SavedImportUITests.testGoogleListAndMyMaps` rejoue une réponse de liste capturée, car
le simulateur du runner ne doit pas dépendre de la page Google vivante. Il vérifie les deux listes
de dossiers du fichier KML, la note conservée, l'import du lien, la proposition Merge ou Replace au
second import, le merge sans doublon, le Replace, le second import du même KML, puis le refus
NoGoogle avec le fichier toujours importable. Il produit `saved-import-mymaps.png`,
`saved-import-google.png`, `saved-import-merge.png` et `saved-import-nogoogle.png`. Le sélecteur de
documents et la page Google réelle restent des vérifications humaines, comme pour le Takeout L-1.

La vérification Linux demandée passe : `:core-common:jvmTest` (959 tests),
`:ios-shared:jvmTest` (349 tests, dont les douze nouveaux) et
`:ios-shared:compileKotlinIosSimulatorArm64`, sans échec.

Le run Mac ciblé `imp-google-20261027-232858-29118` compile l'application, `VelaCore` et le bundle
de tests, puis exécute le scénario. Il passe les deux listes de dossiers
(`saved_kml_lists=2`), la note du KML (`saved_kml_note=kept`) et le premier import Google
(`saved_google_places=2`). Il échoue ensuite sur l'offre Merge ou Replace : la feuille de lien
était encore en cours de fermeture quand l'import demandait la boîte de dialogue, que SwiftUI
ignore dans cet état. Le correctif fait démarrer l'import depuis `onDismiss` de la feuille, une
fois celle-ci fermée, et le scénario attend explicitement cette fermeture. Ce correctif attend un
nouveau run Mac : `saved-import-merge.png` et `saved-import-nogoogle.png` ne sont pas encore
produites.
