# Satellites sur le globe (G-3)

État au 2026-10-29, branche `ios/g3-satellites`, depuis `ios/main` après G-2. Ce document décrit le
calque satellites : la propagation SGP4 côté Kotlin, la source CelesTrak et sa politesse, le cache
disque, les filtres, le passage suivant, le dessin sur le globe et en Mercator, et la carte de
détail.

## Ce qui est branché

- **Propagation locale.** `core-common/src/commonMain/kotlin/app/vela/core/sat/Sgp4.kt` porte SGP4
 pour les orbites proches de la Terre (Vallado, Crawford, Hujsak et Kelso, AIAA 2006-6753,
 constantes WGS-72). Il produit l'état TEME, le tourne en ECEF avec le temps sidéral de
 Greenwich et la vitesse de rotation terrestre, puis donne latitude, longitude et altitude
 géodésiques WGS-84.
- **Refus explicites, jamais d'approximation.** Un TLE de plus de 30 jours est refusé, ainsi qu'un
 TLE de plus d'un jour dans le futur, un objet dont l'orbite est retombée au sol (rayon SGP4 sous un rayon terrestre), une
 excentricité hors bornes, un jeu de deux lignes invalide (somme de contrôle, champs, longueur)
 et une orbite de l'espace lointain (période de 225 min ou plus). SDP4 n'est pas dans ce lot :
 les GPS, Molniya et géostationnaires ne sont donc pas dessinés, ils sont comptés comme refusés.
- **Source.** `SatelliteStore` interroge CelesTrak GP (`celestrak.org`) par groupe : `stations`,
 `weather`, `science`. Le texte TLE et l'heure de récupération sont écrits dans le magasin
 `vela_satellites`, que `UserDefaultsKeyValueStores` persiste sur disque. Un nouveau processus
 relit le cache et ne redemande rien tant que la fenêtre de deux heures n'est pas finie.
- **Politesse CelesTrak, appliquée comme l'acceptation l'exige :**
 - un cycle de rafraîchissement au plus toutes les deux heures, qu'il réussisse ou non ; un
  déplacement de caméra ne déclenche donc jamais de requête ;
 - dans un cycle, une requête par groupe, dans l'ordre `stations`, `weather`, `science` ;
 - la première réponse qui n'est pas 2xx arrête le cycle immédiatement : les groupes suivants ne
  sont pas demandés, l'ancien cache reste et la couche dit son âge ;
 - l'heure de la tentative est enregistrée même en cas d'échec, pour qu'aucune caméra ne
  transforme une panne en rafale de requêtes.
- **Filtres.** Les satellites sont propagés à l'instant courant, puis gardés seulement s'ils sont
 au-dessus de l'horizon de l'observateur (position de l'utilisateur quand la carte en a une,
 sinon le centre de la vue) et dans la vue. Sous un zoom 2, la vue est la planète entière et le
 cadre ne coupe rien, ce qui est le cas du globe à z1. Les plus hauts dans le ciel passent en
 premier, avec un plafond de 120.
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
- une ligne de débogage `sat_debug` : `sat_count`, `sat_projection`, `sat_next_pass_min`,
 `sat_source`, `sat_alt_km`, `sat_speed_km_s`, `sat_tle_age_h`.

Aucun passage n'est inventé : sans TLE, sans passage dans les 48 heures ou pour un objet refusé,
la carte le dit (« No pass in the next 48 hours »).

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

- JVM : `Sgp4Test` (six états TEME, ECEF, époque périmée, espace lointain, décadence, TLE
 invalide) et `SatelliteStoreTest` (cache disque frais sans requête, un cycle par deux heures et
 une requête par groupe, arrêt sur non 200 avec cache conservé, filtre d'horizon, filtre de vue,
 passage suivant avec lever et maximum, TLE invalide, espace lointain et TLE périmé refusés,
 fixture à instant fixe).
- Simulateur : `SatelliteUITests.testSatellitesOverGlobe` lance la carte à `0,0,1` avec
 `-VelaSatelliteFixture YES`, allume le globe, allume Satellites, déplace la caméra, vérifie les
 lignes de la feuille, ouvre la carte de HST, puis écrit `sat_count`, `sat_projection=globe` et
 `sat_next_pass_min` au résumé. Captures : `satellites.png` (les points sur le globe),
 `satellite-pass.png` (la carte avec le passage suivant) et `satellite-orbit.png` (la
 trajectoire).
- La fixture est un instant fixe, `2026-10-29T00:33:00Z`, avec l'observateur fixé à `(0,0)` pour
 que le scénario ne dépende pas de la caméra. Cinq satellites sont alors au-dessus de l'horizon ;
 HST est à 6,5 degrés d'élévation et son passage suivant commence 97 minutes plus tard, avec un
 maximum de 48 degrés. La fixture n'est jamais déclarée live.
- Linux : `:core-common:jvmTest`, `:ios-shared:jvmTest` et
 `:ios-shared:compileKotlinIosSimulatorArm64` sont verts.
- Run Mac : `g3-satellites-20261029-224144-1973`, `STATUS ok`, commit Vela `a2671e2f` (snapshot
 builder `3448739a`). Le build
 simulateur, les 188 tests unitaires et le scénario `SatelliteUITests.testSatellitesOverGlobe`
 passent en 180 s. Le résumé rend `sat_count=5`, `sat_projection=globe` et
 `sat_next_pass_min=97`. Les trois PNG sont dans `results/g3-satellites-20261029-224144-1973/`
 du builder : `satellites.png` montre les cinq points sur le globe à z1, `satellite-pass.png` la
 carte de HST (466 km, 7,64 km/s, passage dans 97 min, maximum 48 degrés) et
 `satellite-orbit.png` la trajectoire et le marqueur du satellite sélectionné, après le recentrage
 de la carte sur HST.

## Limites et risques

- **Pas de SDP4.** Les GPS, Molniya et géostationnaires ne sont pas dessinés. Un utilisateur qui
 cherche un GPS dans la feuille ne le trouvera pas ; la couche ne promet pas le contraire.
- **TLE périmés.** La propagation reste juste quelques jours ; au-delà de 30 jours l'objet
 disparaît. Le cache de deux heures ne rajeunit pas un TLE que CelesTrak n'a pas mis à jour.
- **Hors ligne.** Aucun nouveau TLE n'arrive hors ligne : seuls les TLE déjà en cache sont
 propagés. La couche ne dessine rien quand le réseau est coupé par le réglage hors ligne, comme
 les autres calques du monde.
- **Position de l'utilisateur.** Sans autorisation de localisation, le passage suivant est calculé
 depuis le centre de la vue ; la carte ne le dit pas encore explicitement. La fixture, elle, fixe
 l'observateur à `(0,0)`.
- **Politesse.** La politique CelesTrak est respectée à la lettre du lot, mais un cycle de trois
 requêtes reste trois requêtes : le compteur de la feuille ne montre que les tentatives de
 rafraîchissement, pas les trois appels internes.
- **Test iPhone.** La passe sur un iPhone réel reste humaine : densité des points à z1, lisibilité
 des noms, chauffe pendant un cycle de propagation, et intérêt réel du calque. Le simulateur ne
 prouve pas les fps.
- **Pas d'atmosphère.** La couche ne dessine ni ciel, ni halo, ni étoiles : G-2 n'en porte pas et
 G-3 n'en invente pas.
