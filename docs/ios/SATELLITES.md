# Satellites sur le globe (G-3)

État au 2026-10-30, branche `ios/sdp4`, depuis `ios/main` après G-3. Ce document décrit le calque
satellites : la propagation SGP4 et SDP4 côté Kotlin, la source CelesTrak et sa politesse, le
cache disque, les filtres, le passage suivant, le dessin sur le globe et en Mercator, et la carte
de détail.

## Ce qui est branché

- **Propagation locale.** `core-common/src/commonMain/kotlin/app/vela/core/sat/Sgp4.kt` porte SGP4
 pour les orbites proches de la Terre (Vallado, Crawford, Hujsak et Kelso, AIAA 2006-6753,
 constantes WGS-72), et `Sdp4.kt` porte SDP4 pour l'espace lointain. Le même état TEME est produit,
 puis tourné en ECEF avec le temps sidéral de Greenwich et la vitesse de rotation terrestre, avant
 la latitude, la longitude et l'altitude géodésiques WGS-84.
- **Aiguillage automatique.** Une période inférieure à 225 minutes reste sur SGP4 ; une période de
 225 minutes ou plus prend SDP4, avec les périodiques luni-solaires, les taux séculaires et
 l'intégrateur de résonance demi-jour et jour. Les GPS, Molniya et géostationnaires ne sont donc
 plus refusés : dès qu'un de leurs TLE est en cache, il est dessiné. Les groupes interrogés sont
 `stations`, `weather`, `science` et `gnss` : les géostationnaires météo arrivent réellement, et le
 groupe `gnss` apporte les constellations de navigation (GPS, GLONASS, Galileo, BeiDou, SBAS), donc
 les GPS de ce groupe sont eux aussi dessinés par SDP4.
- **Refus explicites, jamais d'approximation.** Un TLE de plus de 30 jours est refusé, ainsi qu'un
 TLE de plus d'un jour dans le futur, un objet dont l'orbite est retombée au sol (rayon SGP4 sous
 un rayon terrestre), une excentricité hors bornes et un jeu de deux lignes invalide (somme de
 contrôle, champs, longueur).
- **Source.** `SatelliteStore` interroge CelesTrak GP (`celestrak.org`) par groupe : `stations`,
 `weather`, `science`, `gnss`. Le texte TLE et l'heure de récupération sont écrits dans le magasin
 `vela_satellites`, que `UserDefaultsKeyValueStores` persiste sur disque. Un nouveau processus
 relit le cache et ne redemande rien tant que la fenêtre de deux heures n'est pas finie.
- **Politesse CelesTrak, appliquée comme l'acceptation l'exige :**
 - un cycle de rafraîchissement au plus toutes les deux heures, qu'il réussisse ou non ; un
  déplacement de caméra ne déclenche donc jamais de requête ;
 - dans un cycle, une requête par groupe, dans l'ordre `stations`, `weather`, `science`, `gnss` ;
 - la première réponse qui n'est pas 2xx arrête le cycle immédiatement : les groupes suivants ne
  sont pas demandés, l'ancien cache reste et la couche dit son âge ;
 - l'heure de la tentative est enregistrée même en cas d'échec, pour qu'aucune caméra ne
  transforme une panne en rafale de requêtes.
- **Filtres.** Les satellites sont propagés à l'instant courant, puis gardés seulement s'ils sont
 au-dessus de l'horizon de l'observateur (position de l'utilisateur quand la carte en a une,
 sinon le centre de la vue) et dans la vue. Sous un zoom 2, la vue est la planète entière et le
 cadre ne coupe rien, ce qui est le cas du globe à z1. Les plus hauts dans le ciel passent en
 premier, avec un plafond de 120. Une part du plafond est réservée à chaque bande d'orbite, basse,
 moyenne et haute : une constellation de navigation ne peut donc pas chasser les satellites météo
 et les stations. La sélection mélangée est décrite plus bas.
- **Passage suivant.** `SatelliteStore.nextPass` balaie 48 heures par pas de 60 s, affine le
 lever et calcule le maximum. Si le satellite est déjà au-dessus de l'horizon, le passage
 retourné est le suivant après son coucher.
- **Couche monde.** `SatelliteLayer.swift` remplace le squelette WLD-1 sans toucher
 `WorldLayers.swift` ni `WorldLayerSection.swift` : `installed` passe à `true`. Les satellites
 sont des points avec leur nom, la trajectoire du satellite sélectionné est dessinée par
 `SatelliteOrbitLayer.swift`, et un appui sur un point ou sur une ligne de la feuille ouvre la
 carte.
- **Les deux projections.** Le dessin ne connaît que des latitudes et des longitudes, donc il est
 identique en Mercator et sur le globe de G-2 : la projection change la position à l'écran, pas
 la coordonnée. La trajectoire est coupée à l'antiméridien avant MapLibre, sinon une ligne de 179
 à -179 traverserait le monde. Aucune atmosphère n'est ajoutée : G-2 n'en porte pas.

## La carte de détail

La carte affiche :

- le nom du satellite et son numéro de catalogue dans la source ;
- l'altitude en kilomètres ;
- la vitesse orbitale en km/s ;
- la position dans le ciel : élévation et azimut en degrés ;
- le prochain passage : « Next pass in N min, max M deg », puis l'heure de lever et l'heure de
 coucher ;
- l'âge du TLE et la source (CelesTrak, cache ou fixture) ;
- une ligne de débogage `sat_debug` : `sat_count`, `sat_groups`, `sat_gps`, `sat_projection`,
 `sat_next_pass_min`, `sat_source`, `sat_alt_km`, `sat_speed_km_s`, `sat_tle_age_h`.

Aucun passage n'est inventé : sans TLE, sans passage dans les 48 heures ou pour un objet refusé,
la carte le dit (« No pass in the next 48 hours »).

## Précision SDP4 mesurée

`Sdp4Test` utilise trois TLE de vérification de l'espace lointain publiés dans `SGP4-VER.TLE`
(AIAA 2006-6753) : deux Molniya en résonance 12 h (`08195`, `09880`) et un géostationnaire en
résonance 24 h (`24208`), à leur époque et 120 minutes après. Les états TEME de référence sont
ceux de `tcppver.out`, la sortie de l'implémentation de référence. L'écart mesuré est inférieur à
10^-7 km en position et à 10^-9 km/s en vitesse sur les six états, très en dessous de
l'acceptation (1 km et 0,01 km/s). Le test vérifie aussi qu'un géostationnaire reste à son altitude
et dérive de moins de 5 degrés de longitude en un jour sidéral, et qu'un TLE proche de la Terre
reste sur SGP4.

## Précision SGP4 mesurée

`Sgp4Test` utilise trois TLE de vérification publiés dans `SGP4-VER.TLE` (AIAA 2006-6753) :
Vanguard 1 (`00005`), Delta 1 Deb (`06251`) et `28057`, à leur époque et 120 minutes après. Les
états TEME de référence viennent de l'implémentation de référence distribuée avec l'article. Le
test vérifie :

- un écart de position inférieur à 1 km, l'acceptation du lot, et un écart de vitesse inférieur à
 0,01 km/s ;
- un écart de position inférieur à 0,1 km et un écart de vitesse inférieur à 0,001 km/s, la borne
 plus stricte que le test mesure ;
- la cohérence ECEF : la rotation conserve le rayon, la latitude reste sous l'inclinaison, et le
 point géodésique de l'ISS tombe à moins de 0,2 degré de la référence indépendante.

L'écart mesuré reste sous 0,1 km, et l'essentiel de cet écart vient de l'arrondi de l'époque TLE
au milliseconde ; la propagation elle-même reproduit la référence à la précision de l'arrondi des
valeurs publiées.

## Preuves

- JVM : `Sgp4Test` (six états TEME, ECEF, époque périmée, aiguillage de l'espace lointain vers
 SDP4, décadence, TLE invalide), `Sdp4Test` (six états TEME de l'espace lointain, dérive d'un
 géostationnaire, TLE proche resté sur SGP4) et `SatelliteStoreTest` (cache disque frais sans
 requête, un cycle par deux heures et une requête par groupe, arrêt sur non 200 avec cache
 conservé, filtre d'horizon, filtre de vue, passage suivant avec lever et maximum, TLE invalide et
 TLE périmé refusés, géostationnaire et Molniya dessinés par SDP4, fixture à instant fixe, liste
 des quatre groupes et quatrième requête `gnss`, arrêt du cycle sur un échec de `gnss` avec les
 trois groupes d'origine conservés, sélection mélangée sous le plafond de 120 avec 200 candidats
 de navigation, GPS `gnss` dessiné).
- Simulateur : `SatelliteUITests.testSatellitesOverGlobe` lance la carte à `0,0,1` avec
 `-VelaSatelliteFixture YES`, allume le globe, allume Satellites, déplace la caméra, vérifie les
 lignes de la feuille, ouvre la carte de HST, puis écrit `sat_count`, `sat_groups`, `sat_gps`,
 `sat_projection=globe` et `sat_next_pass_min` au résumé. Captures : `satellites.png` (les points
 sur le globe), `satellite-pass.png` (la carte avec le passage suivant) et `satellite-orbit.png`
 (la trajectoire).
- La fixture est un instant fixe, `2026-10-29T00:33:00Z`, avec l'observateur fixé à `(0,0)` pour
 que le scénario ne dépende pas de la caméra. Elle porte deux objets de l'espace lointain,
 METEOSAT-9 (géostationnaire) et MOLNIYA 1-36 (résonance 12 h, époque redatée au jour de la
 fixture), et les 32 TLE `gps-ops` ajoutés par CELESTRAK-GPS. Le scénario écrit `sat_deep=1` au
 résumé et vérifie la ligne du géostationnaire dans la feuille. HST est à 6,5 degrés d'élévation
 et son passage suivant commence 97 minutes plus tard, avec un maximum de 48 degrés. La fixture
 n'est jamais déclarée live.
- Linux : `:core-common:jvmTest`, `:ios-shared:jvmTest` et
 `:ios-shared:compileKotlinIosSimulatorArm64` sont verts.
- Run Mac SDP4 : `sdp4-20261030-061629-9706`, `STATUS ok`, commit Vela `ea11ee9f`. Le résumé
 rend `sat_count=6`, `sat_deep=1`, `sat_projection=globe` et `sat_next_pass_min=97` ; les 656
 tests JVM, les 545 tests simulateur, les 188 tests Xcode et le scénario
 `SatelliteUITests.testSatellitesOverGlobe` passent. Les trois PNG sont dans
 `results/sdp4-20261030-061629-9706/` du builder.
- Run Mac G-3 : `g3-satellites-20261029-224144-1973`, `STATUS ok`, commit Vela `a2671e2f` (snapshot
 builder `3448739a`). Le build
 simulateur, les 188 tests unitaires et le scénario `SatelliteUITests.testSatellitesOverGlobe`
 passent en 180 s. Le résumé rend `sat_count=5`, `sat_projection=globe` et
 `sat_next_pass_min=97`. Les trois PNG sont dans `results/g3-satellites-20261029-224144-1973/`
 du builder : `satellites.png` montre les cinq points sur le globe à z1, `satellite-pass.png` la
 carte de HST (466 km, 7,64 km/s, passage dans 97 min, maximum 48 degrés) et
 `satellite-orbit.png` la trajectoire et le marqueur du satellite sélectionné, après le recentrage
 de la carte sur HST.

## Limites et risques

- **Groupes de navigation.** Le groupe `gnss` est un agrégat : il remplace plusieurs appels par
 constellation par un seul appel et couvre GPS, GLONASS, Galileo, BeiDou et SBAS. Il ne remplace
 pas les groupes d'origine et ne les précède jamais dans le cycle.
- **TLE des objets récents.** Le format TLE ne porte que cinq chiffres de numéro de catalogue,
 donc un objet de navigation lancé après le 2026-07-11, numéroté à six chiffres, n'apparaît pas.
  Il n'entre pas dans le cache et n'est pas dessiné, sans erreur visible.
- **Stabilité numérique de SDP4.** L'intégrateur de résonance avance par pas de 720 minutes depuis
 l'époque ; un écart d'époque de 30 jours reste dans le domaine validé par les cas AIAA, mais un
 TLE très ancien ou une excentricité proche de 1 restent hors du domaine de confiance. La
 résonance 12 h est la plus sensible : les cas 08195 et 09880 la couvrent à 0 et 120 minutes,
 pas au-delà de plusieurs mois.
- **TLE périmés.** La propagation reste juste quelques jours ; au-delà de 30 jours l'objet
 disparaît. Le cache de deux heures ne rajeunit pas un TLE que CelesTrak n'a pas mis à jour.
- **Hors ligne.** Aucun nouveau TLE n'arrive hors ligne : seuls les TLE déjà en cache sont
 propagés. La couche ne dessine rien quand le réseau est coupé par le réglage hors ligne, comme
 les autres calques du monde.
- **Position de l'utilisateur.** Sans autorisation de localisation, le passage suivant est calculé
 depuis le centre de la vue ; la carte ne le dit pas encore explicitement. La fixture, elle, fixe
 l'observateur à `(0,0)`.
- **Politesse.** La politique CelesTrak est respectée à la lettre du lot, mais un cycle de quatre
 requêtes reste quatre requêtes : le compteur de la feuille ne montre que les tentatives de
 rafraîchissement, pas les quatre appels internes.
- **Test iPhone.** La passe sur un iPhone réel reste humaine : densité des points à z1, lisibilité
 des noms, chauffe pendant un cycle de propagation, et intérêt réel du calque. Le simulateur ne
 prouve pas les fps.
- **Pas d'atmosphère.** La couche ne dessine ni ciel, ni halo, ni étoiles : G-2 n'en porte pas et
 G-3 n'en invente pas.

## Groupes de navigation (CELESTRAK-GPS)

SDP4 savait dessiner les GPS, mais aucun groupe interrogé ne les fournissait. Le quatrième groupe
corrige cela sans changer la fréquence des cycles.

- **Liste des groupes.** `stations`, `weather`, `science`, `gnss`. Le groupe `gnss` de CelesTrak
 est l'agrégat des constellations de navigation : GPS opérationnels, GLONASS opérationnels,
 Galileo, BeiDou et SBAS. Un seul appel couvre donc toutes les constellations, au lieu d'un appel
 par constellation (`gps-ops`, `glo-ops`, `galileo`, `beidou`, `sbas`), et le nombre de requêtes
 reste petit. L'ordre place `gnss` en dernier : si ce groupe échoue, les trois groupes d'origine
 ont déjà été rafraîchis ; si un groupe antérieur échoue, `gnss` n'est pas demandé et son ancien
 cache reste en place.
- **Requêtes et octets par cycle.** Un cycle fait quatre requêtes HTTP, une par groupe. Mesure du
 2026-10-30 en `FORMAT=tle` : `stations` 2 688 octets, `weather` 12 264, `science` 7 728, `gnss`
 28 224, soit 50 904 octets par cycle, environ 50 Ko. À douze cycles par jour au plus, cela fait
 environ 611 Ko par jour. La fréquence ne change pas : un cycle au plus toutes les deux heures,
 avec l'heure de tentative enregistrée même en cas d'échec.
- **Cache et échec.** Chaque groupe a sa clé de texte et sa clé d'heure. Une réponse 2xx réécrit
 seulement la clé de son groupe ; une réponse non 2xx arrête le cycle et laisse toutes les clés
 existantes intactes. Un cycle raté sur `gnss` conserve donc les TLE de navigation précédents et
 les trois groupes d'origine frais. Le plafond d'âge de 30 jours et le refus d'un TLE à plus d'un
 jour dans le futur restent inchangés pour tous les groupes.
- **Sélection mélangée sous le plafond de 120.** Les candidats sont triés par élévation
 décroissante. Au-delà de 120 candidats, chaque bande d'orbite réserve 40 places aux satellites
 les plus hauts de sa bande : basse sous 2 000 km, moyenne de 2 000 à 30 000 km, haute au-delà de
 30 000 km. Les places non utilisées par une bande passent au remplissage final, qui reprend les
 candidats restants par élévation. GPS, GLONASS et Galileo sont en orbite moyenne, BeiDou et SBAS
 en orbite haute ou moyenne, tandis que les stations, les satellites météo polaires et la science
 sont en orbite basse et les météosat géostationnaires en orbite haute. Une constellation de
 navigation ne peut donc pas vider la bande basse : `SatelliteStoreTest` le prouve avec 200
 candidats de navigation en orbite moyenne, un METOP en orbite basse et un METEOSAT en orbite
 haute ; les 120 places gardent les deux satellites météo et le satellite de navigation le plus
 haut reste en tête. Le résultat final est encore trié par élévation, donc l'ordre visible ne
 change pas.
- **Fixture et rapport.** La fixture de débogage porte maintenant les 32 TLE `gps-ops` du
 2026-10-30, en plus des groupes d'origine. À l'instant fixe `2026-10-29T00:33:00Z` et pour
 l'observateur `(0,0)`, dix GPS sont au-dessus de l'horizon et le total visible est de seize
 satellites. `SatelliteUITests.testSatellitesOverGlobe` lit `sat_groups` et `sat_gps` dans la
 ligne `sat_debug` et les écrit au résumé, avec `sat_count`, `sat_projection` et
 `sat_next_pass_min`. La ligne de statut de la feuille liste aussi les quatre groupes.

## Preuves CELESTRAK-GPS

- Linux : la commande du lot passe `:core-common:jvmTest`, `:ios-shared:jvmTest` et
 `:ios-shared:compileKotlinIosSimulatorArm64`. `SatelliteStoreTest` couvre la liste exacte
 `stations`, `weather`, `science`, `gnss`, quatre requêtes par cycle, la réouverture à deux
 heures, l'arrêt sur un échec de `gnss` avec les trois groupes d'origine conservés, la sélection
 mélangée sous le plafond et le GPS de `gnss` dessiné par SDP4.
- Run Mac CELESTRAK-GPS : `celestrak-gps-20261030-122838-9961`, `STATUS ok`, commit Vela
 `a2e0849c`. Le build simulateur, les 189 tests Xcode et le scénario
 `SatelliteUITests.testSatellitesOverGlobe` passent. Le résumé rend `sat_count=16`,
 `sat_groups=4`, `sat_gps=10`, `sat_deep=1`, `sat_projection=globe` et `sat_next_pass_min=97`.
 Les PNG sont dans `results/celestrak-gps-20261030-122838-9961/` du builder.
- **Risque de quota.** CelesTrak limite les téléchargements et le format TLE ne porte que cinq
 chiffres de numéro de catalogue. Un cycle qui tombe avant la mise à jour du groupe peut recevoir
 un 403 ; comme `gnss` est le dernier groupe, l'échec ne coûte que le rafraîchissement de
 navigation, et l'ancien cache reste. Le plafond de 30 jours finit par retirer un TLE que le
 groupe ne met plus à jour.
- **Risque de charge.** 50 904 octets par cycle, soit environ 611 Ko par jour, restent très en
 dessous de la limite de 100 Mo par jour. La charge vient des 168 objets de `gnss`, pas du nombre
 de requêtes, qui reste à quatre.
