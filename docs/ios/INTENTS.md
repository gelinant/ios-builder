# App Intents, Siri et Spotlight

X-2 ajoute cinq actions iOS 17, un routeur d'URL interne et un index Core Spotlight. Aucun backend,
compte, entitlement Siri ou extension supplémentaire n'est nécessaire. Les actions ouvrent l'app et
réutilisent les stores et les écrans existants.

## Actions et raccourcis

| Action | Paramètre | Résultat |
|---|---|---|
| `NavigateHomeIntent` | Aucun | Ouvre Maison puis le choix d'itinéraire |
| `NavigateWorkIntent` | Aucun | Ouvre Travail puis le choix d'itinéraire |
| `WhereIsMyCarIntent` | Aucun | Ouvre la fiche du stationnement enregistré |
| `SearchVelaIntent` | `query`, texte obligatoire | Lance la recherche et affiche ses résultats |
| `NavigateToPlaceIntent` | Lieu enregistré ou élément de liste | Ouvre le lieu puis le choix d'itinéraire |

Maison et Travail se règlent depuis la fiche d'un lieu, puis Lists et Set as Home ou Set as Work.
Si le raccourci demandé n'est pas réglé, Siri annonce une erreur explicite et l'ouverture conduit à
Saved. Un lieu supprimé produit le même type de retour vers Saved. Le stationnement absent est aussi
signalé. Aucune action ne démarre le guidage sans confirmation : elle ouvre le choix d'itinéraire.

`VelaAppShortcuts` expose les cinq actions à Siri et à l'app Raccourcis. Les phrases sources sont en
anglais et leurs traductions françaises sont dans `fr.lproj/AppShortcuts.strings`. Une phrase de
recherche ne contient pas le texte libre : iOS n'autorise pas un paramètre `String` ouvert dans une
phrase d'App Shortcut. Siri le demande, ou l'utilisateur le fournit dans l'action Raccourcis. Les
lieux enregistrés sont des `AppEntity`, donc leurs noms peuvent servir à la sélection et à la
levée d'ambiguïté.

La reconnaissance et les langues réellement proposées dépendent des réglages Siri de l'appareil. Le
runner ne permet pas de parler à Siri ni de vérifier cette présentation système.

## Routeur d'URL interne

Le scheme `vela` est déclaré dans l'Info.plist généré. Les URL ne sont pas des liens publics et ne
contiennent aucun jeton.

| URL | État ouvert |
|---|---|
| `vela://search?q=coffee` | Résultats de la recherche demandée |
| `vela://place/<id>` | Fiche du lieu enregistré |
| `vela://place/<id>?list=<listId>` | Fiche d'un élément de liste |
| `vela://place/<id>?directions=1` | Fiche puis choix d'itinéraire |
| `vela://saved` | Feuille Saved |
| `vela://parking` | Fiche du stationnement courant |
| `vela://navigate/home` | Maison puis choix d'itinéraire |
| `vela://navigate/work` | Travail puis choix d'itinéraire |

Les paramètres `list` et `directions` peuvent être combinés. Le routeur exige une recherche non vide,
un seul identifiant de lieu et aucun paramètre inconnu. Les composants sont décodés comme des URL,
pas comme des formulaires : `%20` représente une espace et `+` reste un plus.

`VelaDeepLinkCenter` numérote chaque demande, y compris deux ouvertures identiques, puis `MapScreen`
la consomme une seule fois. Une erreur affiche une alerte avec Open Saved. Les lignes Debug
`intents-debug` et `spotlight-debug` ne contiennent ni requête, ni nom, ni coordonnée.

## Spotlight et confidentialité

L'index contient uniquement :

- les lieux de Saved et les éléments des listes ;
- Maison et Travail ;
- le stationnement courant.

Chaque élément porte un titre, l'adresse enregistrée lorsqu'elle existe, les coordonnées enregistrées
et l'URL interne d'ouverture. Il s'agit de données que l'utilisateur a explicitement sauvegardées.
Les recherches récentes, les lieux récents, l'historique de stationnement et les journaux ne sont pas
indexés. L'index Core Spotlight reste local au système, sans indexation publique ni serveur Vela.

`SpotlightIndexer` observe `SavedStore`. Une modification remplace les trois domaines Vela
`saved-places`, `shortcuts` et `parking`, ce qui met aussi à jour les suppressions et les anciens
éléments. Un changement qui ne touche que les récents ne réécrit pas l'index. L'identifiant Spotlight
est l'URL interne ; `CSSearchableItemActionType` la renvoie au même routeur que les App Intents.

## Vérifications automatiques

`VelaTests/IntentsTests.swift` couvre le format et les allers-retours du routeur, les URL invalides,
la répétition des ouvertures, la validation des paramètres, les erreurs de configuration et les
métadonnées Spotlight.

`VelaUITests/IntentsUITests.swift` couvre :

- la recherche par URL et `intents-search.png` ;
- l'enregistrement puis l'ouverture d'un lieu par son URL et `intents-place.png` ;
- l'erreur Maison absente et l'ouverture de Saved ;
- l'ouverture du stationnement, puis son nettoyage ;
- l'ajout et la suppression dans le vrai `CSSearchableIndex`.

Les arguments Debug utilisés par ces scénarios sont :

| Argument | Effet |
|---|---|
| `-VelaOpenURL <url>` | Envoie une URL au routeur au lancement |
| `-VelaOpenSavedLink YES` | Envoie l'URL du lieu enregistré le plus récent |
| `-VelaIntentTestReset YES` | Efface Maison, Travail et le stationnement courant |
| `-VelaIntentTestFixture parking` | Enregistre le point de stationnement fixture de San Francisco |
| `-VelaSpotlightTest add` | Indexe la fixture Davis sans observer les autres stores |
| `-VelaSpotlightTest delete` | Supprime les domaines Vela de l'index |

Ces hooks sont compilés en Debug seulement. Ils ne constituent pas des routes de production.

## Tests humains restants

Sur un iPhone avec Siri activé, vérifier les phrases anglaises et françaises, la demande d'une
recherche libre, la sélection d'un lieu enregistré et les erreurs Maison ou Travail absent. Vérifier
aussi les tuiles de l'app Raccourcis. Après avoir enregistré, renommé puis supprimé un lieu, vérifier
son apparition, sa mise à jour et sa disparition dans Spotlight, puis l'ouverture de chaque type de
résultat. Tester enfin le sideload : aucune signature ou capability supplémentaire ne doit être
demandée.
