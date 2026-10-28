# Itinéraires vélo et sans Google (R-2)

Ce document décrit le choix de source par mode sur iOS, le profil vélo pondéré par la sécurité et
le chemin sans Google de bout en bout. Les règles communes restent dans `SPEC.md` 4.1 à 4.4 ; ce
fichier dit ce qu'iOS en applique, ce qui est prouvé et ce qui manque.

## Sources par mode

| Mode | Source par défaut | Repli | Google |
|---|---|---|---|
| Voiture | OSRM `routed-car` et Google, puis `HybridRoute` | Google si OSRM est muet, sinon route OSRM | Trafic et variantes, jamais avec NoGoogle |
| Marche | OSRM `routed-foot` | Google marche seulement si au moins 15 % plus courte et nommable | Comparaison uniquement |
| Vélo | Valhalla `costing: bicycle`, `use_roads` 0.1, `use_hills` 0.5, `bicycle_type` Hybrid | OSRM `routed-bike` quand le profil sûr est coupé ou ne répond pas | Jamais par défaut |
| Transports | Transitous | aucune pour l'instant | Jamais |

Le choix vit dans `GoogleMapsDataSource.directionsPlain` (common), que le chooser iOS utilise à
travers `IosGoogle.hybridSource`. `RouteStore` ne refait pas ce choix : il transmet le mode, les
étapes et les options. C'est la même chaîne que sur Android, donc une correction dans common
profite aux deux plateformes.

### Vélo

`RoutingPrefs.bikeSafe` est vrai par défaut. iOS lit la clé Android `bike_safe` de
`vela_settings` au démarrage de `RouteStore` et la recopie dans `RoutingPrefs`, si bien qu'une
préférence déjà enregistrée par Android est respectée. `RouteStore.setBikeSafe` existe pour une
future ligne de réglages iOS ; il persiste la clé et relance le calcul si le mode vélo est ouvert.
La feuille Réglages n'expose pas encore cette ligne, ce qui reste hors de ce lot.

Avec le profil sûr, la requête part vers `valhalla1.openstreetmap.de/route` et demande des
variantes (`alternates: 2`) pour un trajet sans arrêt. Les manœuvres Valhalla sont traduites dans
la grammaire OSRM, donc la voix, le bandeau et la liste d'étapes sont les mêmes que pour une
route OSRM. Une route vélo ne porte aucun trafic.

Le chooser affiche le libellé Android « Bike routes prefer bike lanes and quiet streets » sous
les variantes quand le profil sûr est actif (`route-bike-safe`). Le libellé « Fastest route now »
reste réservé à la plus rapide d'au moins deux propositions ; une variante à moins d'une minute
affiche « About the same time », les autres « X slower than the fastest route ». Une route vélo
n'affiche jamais de ligne de trafic.

Les données communes ne transportent ni dénivelé ni note de sécurité par segment : `Route` n'a
pas ces champs et Valhalla n'est pas lu pour eux. L'interface n'invente donc aucun chiffre de
dénivelé ni de « sécurité » chiffrée. Le seul signal de sécurité disponible est le choix du
profil, résumé par le libellé ci-dessus.

Si le profil sûr est coupé, ou si Valhalla ne répond pas, la chaîne rapide reprend : OSRM
`routed-bike`, puis Google comme sur Android. Ce repli n'est pas silencieux dans les
diagnostics (`VelaDirections`), mais l'interface ne le signale pas séparément.

### Marche

La marche sans arrêt interroge OSRM pied et, pour comparer seulement, Google marche. La règle est
une fonction unique, `GoogleMapsDataSource.googleWalkIsShorter` :

```text
open == null                       -> Google est proposé
google <= open * (1 - 0.15)        -> Google est proposé
sinon                              -> la route OSRM est gardée
```

`WALK_GOOGLE_SHORTER` vaut 0.15 dans common. Google doit en plus être nommable depuis les tuiles
de rues (`LineNamer`, attente de 8 s) ; sinon la route ouverte reste seule. Une route marche n'est
jamais alignée de force sur la ligne Google, conformément à `SPEC.md` 4.3.

## Sans Google

`NoGoogle.enabled` est appliqué par `SettingsStore` au démarrage et par le réglage
« Utiliser Vela sans Google ». Chaque méthode Google de `GoogleMapsSource` vérifie le drapeau
avant toute requête : recherche, détails, photos, avis, Street View, listes, et directions. Une
réponse vide est traitée comme « Google n'a pas répondu », jamais comme une erreur de calcul.

Conséquences par mode :

- voiture : OSRM et la route hybride sans trafic ni variantes Google ;
- marche : OSRM pied seul, sans même la requête de comparaison ;
- vélo : Valhalla ou OSRM `routed-bike`, sans Google ;
- transports : Transitous, service ouvert. Si aucun planificateur n'est branché,
  `RouteError.ModeUnavailable` s'affiche. Si Transitous ne renvoie rien,
  `RouteError.NoRoute` s'affiche. Aucun des deux ne retombe sur Google.

`RouteState.googleOff` reflète le drapeau au moment du calcul. Les messages d'erreur le disent :
« No drive route found. Google is off, so only open services were asked. » et, pour un mode sans
service ouvert, « Transit needs an open service that is not available in this build, and Google is
off. » L'utilisateur voit donc l'absence de solution au lieu d'une requête cachée.

### Preuve par compteur

En Debug seulement, `DebugRequestCounter` compte chaque requête HTTP de `URLSessionVelaHttp` en
deux catégories : hôtes Google (`google.com`, `googleapis.com`, `gstatic.com`,
`googleusercontent.com`, `ggpht.com`, `googlevideo.com`) et tous les autres. `RouteModel` remet le
compteur à zéro à l'ouverture du chooser et publie `netGoogle` et `netOpen` dans la ligne
`route-debug`. Le scénario UI `route-nogoogle.png` exige `googleOff=1`, `netGoogle=0`,
`netOpen>0` et au moins une route. Le compteur et la ligne n'existent pas dans l'archive Release.

## Étapes, heures et options

| Option | Voiture | Marche | Vélo | Transports |
|---|---|---|---|---|
| Étapes (jusqu'à 10) | oui, Google et OSRM via | oui, OSRM via | oui, Valhalla `type: through` | non, Transitous n'a pas de paramètre d'étape |
| Départ à / arrivée à | estimation typique seulement | non | non | oui, `time` Transitous |
| Éviter péages, autoroutes, ferries | oui | sans objet | non | sans objet |

Les évitements ne sont affichés que pour la voiture (`avoidSupported`). Valhalla et OSRM n'ont pas
de paramètre d'évitement utilisé par le profil vélo ou marche, et iOS ne prétend pas le contraire.
Pour la marche et le vélo, l'heure choisie ne change pas la requête : seule la voiture affiche une
estimation de plage typique, et seuls les transports envoient une heure.

## Tests et preuves

Linux, avec le verrou Gradle :

```
source ~/opt/env.sh
flock /tmp/opencode/gradle.lock ./gradlew --no-daemon -Pvela.iosOnly=true \
  :core-common:jvmTest :ios-shared:jvmTest :ios-shared:compileKotlinIosSimulatorArm64
```

- `BikeNoGoogleRoutingTest` (`ios-shared`, JVM) vérifie le corps Valhalla (profil, `use_roads`,
  `use_hills`, `bicycle_type`, variantes), l'absence de Valhalla quand le profil sûr est coupé,
  l'usage de `routed-bike`, les modes voiture et marche sans aucun hôte Google avec
  `NoGoogle.enabled`, et le seuil des 15 %.
- `RouteStoreTest` vérifie que la clé `bike_safe` est lue, que `setBikeSafe` persiste et relance
  le vélo, que `googleOff` est publié, et que les transports sans planificateur donnent
  `ModeUnavailable` au lieu d'un appel Google.
- `DirectionsUITests.testBikeRouteUsesTheSafetyProfile` produit `route-bike.png` et exige une
  route vélo avec `bikeSafe=1`.
- `DirectionsUITests.testNoGoogleDriveNeverAsksGoogle` produit `route-nogoogle.png` et exige
  `netGoogle=0`.

Les réponses HTTP réelles de référence restent celles du runner macOS (`directions-*-sf`,
`osrm-*-sf`) pour la voiture et la marche. Valhalla est simulé dans le test vélo : le corps de la
requête et le parseur sont testés, pas la disponibilité du service au moment du run.

## Limites

- La ligne Réglages « Bike routes prefer bike lanes and quiet streets » n'existe pas encore sur
  iOS. La valeur par défaut est celle d'Android, et la clé est déjà lue et écrite.
- Google reste joint, hors NoGoogle, pour la comparaison marche et pour le trafic et les variantes
  de la voiture. Ce sont les seules atteintes côté itinéraires.
- Le compteur Debug couvre les requêtes du processus, pas celles d'une WebView cachée. Aucun
  itinéraire n'utilise de WebView ; les fiches lieu et les avis restent hors de ce lot.
- La disponibilité de Valhalla, OSRM et Transitous dépend des services publics. Un échec affiche
  l'erreur honnête du mode, jamais une route fabriquée.
