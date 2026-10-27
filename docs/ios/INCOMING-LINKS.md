# Liens entrants Google Maps et Vela

DL-2 ajoute les arrêts intermédiaires : `MapLinkParser` lit déjà les formes d'arrêt de Google et
signale désormais un arrêt illisible ; Swift porte les arrêts dans `VelaIncomingLink` et
`RouteStore.directionsFromPointWithStops` les pose à l'ouverture, dans l'ordre du lien.

DL-1 fait entrer les liens de cartes dans Vela sans seconde voie de routage : `VelaDeepLinkCenter`
reste le point d'entrée, `VelaDeepLinkRouter` garde les URL `vela://`, et un analyseur de liens
externes remet à la même file une route `VelaDeepLink.incoming`. Le lancement à froid
(`-VelaOpenURL` en Debug, URL de lancement en production) et l'ouverture à chaud (`onOpenURL`)
passent par cette file unique. Une URL reçue avant l'affichage de la carte reste en attente et
`MapScreen` la consomme une fois. Ses arrêts voyagent dans la même valeur, donc un lien reçu avant
que la carte soit prête garde ses arrêts jusqu'à la consommation.

## Formes acceptées

| Forme | Exemple | Résultat |
|---|---|---|
| `vela://` | `vela://search?q=coffee` | Route interne existante, inchangée |
| Fiche Google | `https://www.google.com/maps/place/Davis+Food+Co-op/@38.5449,-121.7405,17z/data=...` | Nom, point, zoom et identifiant de lieu ; fiche du lieu |
| Recherche Google | `https://www.google.com/maps/search/coffee` | Liste de résultats |
| Recherche classique | `https://maps.google.com/?q=Davis+Food+Co-op` | Liste de résultats |
| Itinéraire Maps URLs | `https://www.google.com/maps/dir/?api=1&origin=...&destination=...&travelmode=walking` | Choix d'itinéraire avec départ, arrivée et mode |
| Itinéraire en chemin | `https://www.google.com/maps/dir/Sacramento,+CA/Davis,+CA/` | Départ et arrivée par leurs noms |
| Itinéraire avec un arrêt | `https://www.google.com/maps/dir/Sacramento,+CA/Davis,+CA/Woodland,+CA/Folsom,+CA/` | Départ, arrivée et arrêt intermédiaire, dans l'ordre du lien |
| Itinéraire avec plusieurs arrêts | `https://www.google.com/maps/dir/A/B/C/D/E/` | Tous les lieux du chemin entre le départ et l'arrivée deviennent des arrêts |
| Arrêts Maps URLs | `https://www.google.com/maps/dir/?api=1&origin=A&destination=D&waypoints=B%7CC` | Arrêts séparés par un tube, brut ou encodé, noms ou coordonnées |
| Arrêts enchaînés | `https://maps.google.com/maps?saddr=A&daddr=B+to:C+to:D` | Chaque `to:` ajoute un arrêt avant l'arrivée |
| Itinéraire classique | `https://maps.google.com/maps?saddr=A&daddr=B&dirflg=w` | Départ, arrivée et mode |
| Navigation Google | `google.navigation:q=2000+Sutter+Pl,+Davis,+CA&mode=w` | Choix d'itinéraire |
| Lien court | `https://maps.app.goo.gl/...`, `https://goo.gl/maps/...` | Une requête au raccourcisseur, puis la cible est analysée sur le téléphone |
| `geo:` | `geo:38.5449,-121.7405`, `geo:0,0?q=coffee`, `geo:38.5,-121.7?q=Nom` | Point, recherche ou lieu nommé |

`MapLinkParser` et `ShortLinks` de `:core-common` font l'analyse et la résolution. Swift ne
réimplémente pas les formes Google : `iosApp/Vela/Links/IncomingLink.swift` recopie seulement le
résultat dans une valeur Swift (`VelaIncomingLink`) pour que la carte n'ait pas à tenir un objet
Kotlin.

## Règles d'ouverture

- Une fiche avec un nom et un point ouvre directement la fiche à ce point, sous le nom du lien.
  Le chargement des détails remplit ensuite adresse, horaires et avis. Une fiche sans point mais
  avec un identifiant de lieu utilise la cellule S2 de cet identifiant comme point d'ancrage. Un
  nom sans point ni identifiant est cherché, et le premier résultat ouvre.
- Un point sans nom ouvre un repère inversement géocodé, comme un appui long.
- Un itinéraire ouvre le choix d'itinéraire sur l'arrivée, avec le départ quand le lien le nomme
  par un point ou par un nom. Le mode du lien est appliqué au choix courant sans être enregistré
  comme préférence.
- Les arrêts intermédiaires du lien deviennent les arrêts du choix d'itinéraire, dans l'ordre du
  lien. Les coordonnées du lien sont utilisées telles quelles ; un arrêt nommé est cherché une
  fois, près de l'arrêt précédent ou du départ, comme un départ nommé. L'ordre affiché est l'ordre
  de trajet, et les flèches de R-1 restent disponibles pour le changer.
- Le `data=` d'un itinéraire de bureau fournit la coordonnée de chaque lieu, arrêts compris. Les
  points tirés sur l'itinéraire (`via`) ne sont pas des arrêts : ils ne sont pas repris.
- Une recherche affiche ses résultats au lieu d'ouvrir le premier.

## Refus et limites

- Un hôte autre que Google est refusé avant toute requête : `https://example.com/maps/...`,
  `javascript:`, `data:`, `mailto:` et tout autre schéma inconnu affichent l'erreur Vela.
- Un lien Google hors d'un chemin de cartes est refusé, par exemple
  `https://www.google.com/search?q=coffee`.
- Un lien réduit dont la cible n'est pas une carte Google, ou qui boucle vers un autre
  raccourcisseur, est refusé sans suivre la redirection.
- Un lien qui ne porte qu'un `cid` (`https://maps.google.com/?cid=...`) ne contient ni nom ni
  point. Vela l'analyse et ouvre un lieu enregistré dont l'identifiant de lieu se termine par ce
  nombre en hexadécimal. Sans lieu enregistré correspondant, il annonce le lien comme illisible et
  n'ouvre rien. Android a la même limite dans `ROADMAP.md` : Google ne donne la fiche que par une
  page, pas par une redirection.
- Un itinéraire dont un arrêt est illisible (entrée vide dans la liste, coordonnée hors limites,
  lieu vide dans le chemin) est refusé en entier avec un message explicite : Vela n'ouvre jamais
  un itinéraire auquel il manquerait un arrêt.
- Un arrêt nommé qu'aucune recherche ne trouve à moins de 50 km du trajet est refusé avec un
  message explicite, comme un lieu hors du trajet. Vela ne fabrique pas d'arrêt au hasard.
- Le choix d'itinéraire de Vela garde au plus 10 arrêts (`RouteStore.MAX_WAYPOINTS`). Un lien qui
  en porte davantage garde les 10 premiers et une alerte dit combien ont été laissés de côté ;
  l'API Maps URLs de Google n'en accepte elle-même que 9.
- Un lien `google.navigation:` et un `geo:` n'ont pas d'arrêt : les formes d'arrêt ne viennent que
  des itinéraires web.
- Une liste partagée Google (`maps/placelists`) est refusée : ses lieux vivent chez Google.
- Street View n'est pas ouvert par un lien entrant ; un lien Street View avec un point s'ouvre
  comme un repère à ce point.

## Confidentialité et réseau

- Aucune page web n'est chargée. Les URL `http` et `https` ne sont jamais données à un navigateur
  ou à `UIApplication.open`.
- Un lien direct qui porte déjà son nom, son point, son départ, ses arrêts ou son mode ne
  déclenche aucune requête pour lire le lien. La recherche d'un arrêt nommé, la recherche de nom
  et la fiche lieu utilisent les chemins Google habituels de Vela, comme une recherche tapée.
- Seul un lien court demande une requête, sans cookie, vers `maps.app.goo.gl` ou `goo.gl`. Elle
  lit la redirection et s'arrête. La requête ne garde que le code du lien : ses paramètres de
  requête et son fragment sont retirés avant l'envoi. Les paramètres de suivi d'un lien direct
  (`utm_*`, `g_ep`, `entry`) ne sont ni envoyés ni utilisés : l'analyse ne prend que le nom, les
  coordonnées, le mode et les identifiants.
- Le journal Debug `intents-debug` ne contient ni nom, ni coordonnée, ni URL. Il indique seulement
  la route (`route=link-place`, `route=link-search`, `route=link-directions`), `error=0|1`, et
  pour un itinéraire le nombre d'arrêts et de départ (`origin=0|1`, `stops=N`, `mode=…`).

## Types d'URL déclarés

`iosApp/project.yml` déclare `vela` et `geo` dans `CFBundleURLTypes`. iOS ne permet pas à une
application de s'inscrire pour `http` ou `https` : un lien Google Maps ouvert depuis Safari,
Messages ou Plans part donc vers l'application choisie par le système, pas vers Vela. Cela
demanderait des Universal Links et un fichier AASA hébergé par Google pour `app.vela.ios`, ce qui
n'est pas disponible. Les chemins réels pour ouvrir un lien Google dans Vela sur iPhone sont donc
un lien `vela://` ou `geo:`, le collage d'une URL dans la recherche, et une action Raccourcis qui
ouvre l'URL avec Vela. Le scénario `-VelaOpenURL` de Debug prouve le même pipeline que
`onOpenURL`.

## Vérifications

Linux (DL-2) : `:core-common:jvmTest`, `:ios-shared:jvmTest` et
`:ios-shared:compileKotlinIosSimulatorArm64` verts, dont les sept nouveaux tests d'arrêts
(`MapLinkDirectionsTest`) et les deux tests d'ouverture avec arrêts (`RouteStoreTest`).

Run Mac `dl1-full-20261026-174631-582` (DL-1) : 114 tests Kotlin JVM, 93 tests simulateur iOS et
65 tests Swift verts. Les trois scénarios `IncomingLinksUITests` d'alors passent et produisent
`incoming-place.png` (`incoming_place=Davis_Food_Co-op`) et `incoming-directions.png`
(`route=link-directions … origin=1 mode=DRIVE`, deux itinéraires). Le run complet était rouge
seulement sur `IntentsUITests.testSpotlightFixtureAddsAndDeletesThroughRealIndex` et
`SavedUITests.testSavedPlaceListAndRecentsPersist`, hors de ce lot. L'IPA non signée
`Vela-unsigned.ipa` faisait 9 964 557 octets.

DL-2 : aucun run Mac n'a produit de `STATUS` (le runner n'a rien publié depuis
`vo2-dictation-20261027-040248-1507`) ; les scénarios d'arrêts, la capture `link-stops.png` et
l'IPA restent donc à produire au prochain run.

Tests unitaires `VelaTests/IncomingLinksTests.swift` : fiche, recherche, itinéraire par
coordonnées et par noms, arrêts d'un chemin, arrêts Maps URLs nommés et en coordonnées, chaîne
`+to:`, `data=` avec les coordonnées d'arrêt, plafond à 10 arrêts avec les surnuméraires comptés,
arrêt illisible refusé, points tirés non repris, `geo:` point, recherche et lieu nommé,
`google.navigation:`, lien court résolu par un résolveur injecté, cible étrangère refusée, `cid`
seul analysé sans cible, schémas et hôtes refusés, paramètres de suivi sans effet et publication
directe sans résolveur.

Scénarios `VelaUITests/IncomingLinksUITests.swift` :

- `testIncomingPlaceLinkOpensThePlaceSheet` lance la fiche Davis Food Co-op et enregistre
  `incoming-place.png` ;
- `testIncomingDirectionsLinkOpensTheChooser` lance un itinéraire Sacramento vers Davis et
  enregistre `incoming-directions.png` ;
- `testIncomingDirectionsLinkWithOneStopOpensIt` lance Sacramento, un arrêt à Davis, Folsom, et
  enregistre `link-stop-single.png` (`link_stop_single=count=1 order=Davis`) ;
- `testIncomingDirectionsLinkWithTwoStopsKeepsTheirOrder` lance Sacramento, Davis, Woodland,
  Folsom, vérifie deux lignes d'arrêt et leur ordre à l'écran, et enregistre `link-stops.png`
  (`link_stops=count=2 order=Davis_Woodland`) ;
- `testMalformedStopLinkShowsTheVelaError` vérifie qu'une liste d'arrêts trouée affiche l'erreur
  et n'ouvre aucun itinéraire partiel ;
- `testBareCidLinkShowsTheVelaError` vérifie l'alerte et son bouton Saved.

Les captures ne dépendent pas des lignes de debug masquées par les tests d'accessibilité : elles
lisent `place-name`, `route-sheet`, `route-destination`, les lignes `route-waypoint-row` et
l'alerte système.

## À vérifier sur iPhone

- Ouvrir un lien `vela://place/...` depuis Safari, Messages et Notes.
- Depuis Google Maps, partager une fiche puis copier le lien : le coller dans la recherche de
  Vela, puis vérifier la fiche et l'itinéraire. Un lien Google Maps ouvert directement depuis
  Google Maps ne peut pas atteindre Vela sur iOS.
- Ouvrir un `geo:` depuis Contacts ou Calendrier et choisir Vela dans la feuille système.
- Coller un lien `maps.app.goo.gl` dans la recherche, avec et sans « Ouvrir les liens Google Maps
  partagés ».
- Coller un itinéraire Google Maps avec deux arrêts, puis vérifier dans le choix d'itinéraire que
  les deux arrêts sont dans l'ordre du lien, que les flèches les déplacent et que l'itinéraire
  calculé passe par eux.
- Coller un itinéraire avec plus de dix arrêts : vérifier l'alerte et les dix arrêts gardés.
- Vérifier qu'un lien Google Maps reçu dans Messages n'ouvre pas Vela automatiquement : c'est une
  limite d'iOS, pas un défaut du lot.
