# Matrice détaillée de parité iOS

Cette matrice reprend chaque puce de `FEATURES.md`, dans le même ordre et avec ses lignes sources.
Elle décrit la branche de travail issue de `3439792e`. Les lots N-2, O-2 et X-2 encore parallèles ne
sont pas comptés comme livrés. Un parseur ou un moteur en `:core-common` sans chemin utilisateur ne
vaut pas fonction terminée.

## Légende et méthode

- ✅ : fonction validée sur iPhone, avec une preuve humaine datée et le code correspondant.
- 🟡 : fonction présente et son chemin principal testé sur simulateur. Des variantes ou une
  validation iPhone peuvent rester à faire sans rendre la ligne partielle.
- ⚠️ : sous-ensemble utilisable, réglage manquant, ou preuve trop étroite pour le statut supérieur.
- ❌ : aucun chemin utilisateur iOS pour cette fonction, même si une brique de moteur existe déjà.
- ➖ : mécanisme propre à Android sans équivalent iOS retenu, ou fonction volontairement hors Vela.

Les lots cités sont des propositions de découpage après Q-1, sauf N-2 et O-2 déjà en cours. « Aucun »
signifie qu'aucun portage n'est proposé pour ce mécanisme Android.

## Repères de preuve

| Repère | Preuve conservée |
|---|---|
| M1 | `docs/ios/HIVE.md`, F-3a : sideload, carte, déplacement, zoom et localisation validés sur iPhone le 2026-10-24 |
| M2 | `docs/ios/HIVE.md`, V-2 : recherche « coffee », 60 résultats, liste et épingles validées sur iPhone |
| C5 | Run `c5-nav-20261025-013642-2384` et tests `core-common/src/commonTest` du moteur de navigation |
| M4 | Run `i4b-routes-polish-20261025-174403-1828`, `DirectionsUITests.testDirectionsToTheFirstCoffeeResult` |
| M5 | Run `n1-map-search-20261025-201545-28900`, `NavUITests.testGuidedDriveAndEnd` |
| I6 | Run `m5final-20261025-183757-4411`, `SavedUITests.testSavedPlaceListAndRecentsPersist` |
| I7 | Run `n1-map-search-20261025-201545-28900`, `OfflineUITests.testMonacoDownloadOfflineMapAndSearch` |
| I8 | Run `i8-l10n-20261025-205100-6342`, trois `LocalizationUITests` et tests Swift de localisation |
| N1 | Run `n1-map-search-20261025-201545-28900`, recherche, suggestions, catégories et POI verts |
| P1 | Runs `p1-place-complete-20261025-205542-12434` (20 photos, échec à la visionneuse) et `q1-parity-quality-20261025-221617-24690` (échec au bouton de catégories) ; aucun scénario complet vert |
| X1 | Run `x1-live-activity-20261025-193904-23245` et `docs/ios/LIVE-ACTIVITY.md` |
| X3 | Run `x3-transit-activity-20261026-010530-6408` et `docs/ios/TRANSIT-ACTIVITY.md` |
| W2 | `docs/ios/spike-webview-ios.md`, trois runs W-2 et mesures de la page cachée |
| Q1 | `docs/ios/QUALITY.md` et `QualityUITests.swift`, complétés par les runs Q-1 cités dans ce document |
| SRC | Lecture des fichiers indiqués sur la branche mesurée, sans déduire un test de la seule présence du code |

<!-- BEGIN GENERATED: parity-summary -->
## Synthèse chiffrée

Cette table est régénérée par `python3 scripts/ios/parity_check.py --md`. Les pourcentages
comptent des lignes de fonctions, pas leur complexité ni leur importance quotidienne.

| Statut | Lignes | Part du total |
|---|---:|---:|
| ✅ validé sur iPhone | 2 | 1,0 % |
| 🟡 testé sur simulateur | 13 | 6,4 % |
| ⚠️ partiel | 84 | 41,2 % |
| ❌ absent | 86 | 42,2 % |
| ➖ sans équivalent iOS | 19 | 9,3 % |
| **Total** | **204** | **100,0 %** |
<!-- END GENERATED: parity-summary -->

## The map

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L8-L9](../../FEATURES.md#L8-L9) | Carte vectorielle OSM, bâtiments, numéros, frontières, écussons et sorties | ⚠️ | M1 et `LaunchUITests` pour Liberty. `liberty-roboto.json` contient bâtiments, frontières et écussons, mais pas de couche de numéros de maisons ni preuve des numéros de sortie. | I-1b habillage carte |
| [L10-L11](../../FEATURES.md#L10-L11) | Icônes de lieux Vela, Google ou les deux | ⚠️ | N1 prouve les POI Liberty et les épingles de recherche. Aucune source Vela/Google/Both sélectionnable dans `MapController` ou Settings. | I-1b sources de POI |
| [L12-L13](../../FEATURES.md#L12-L13) | Réglages Show places, lieux civiques, transports et taille des icônes | ❌ | SRC : `SettingsScreen` ne contient aucun de ces réglages et `MapController` n'applique pas de filtre de POI. | I-1b réglages de couches |
| [L14](../../FEATURES.md#L14) | Toucher lieu, numéro ou bâtiment, appui long pour une épingle | ⚠️ | `MapSearchUITests.testMapPoiTapOpensGooglePlace` et N1 pour un POI. `handleLongPress` existe, mais numéros, bâtiments et appui long n'ont pas de scénario. | I-1b toucher carte |
| [L15](../../FEATURES.md#L15) | Inclinaison et bâtiments 3D avec leurs interrupteurs | ⚠️ | Le style a une couche `building-3d` et MapLibre garde ses gestes par défaut. Les deux réglages et leur test sont absents. | I-1b gestes et 3D |
| [L16](../../FEATURES.md#L16) | Pincer-tourner et retour au nord après une petite rotation | ⚠️ | `MapView` ne désactive pas les gestes MapLibre. Aucun code de retour au nord ni test de rotation combinée. | I-1b gestes et 3D |
| [L17-L18](../../FEATURES.md#L17-L18) | Keep north up en consultation et en navigation | ⚠️ | `NavModel.toggleNorthUp` agit pendant une navigation. Pas de verrou global, pas de réglage et pas de mode voiture. | I-1b orientation carte |
| [L19-L23](../../FEATURES.md#L19-L23) | Panneau de couches, styles, satellite, trafic, transports, terrain et source de POI | ⚠️ | Les segments de trafic d'un itinéraire sont dessinés et mesurés par M4. Le panneau, l'affichage du trafic en consultation et les autres couches sont absents. | I-1b panneau de couches |
| [L24-L25](../../FEATURES.md#L24-L25) | Lignes de transport colorées et mises en cache | ⚠️ | M4 affiche les tronçons Transitous avec leurs couleurs. `TransitLineCache` est en common, sans rendu des lignes mémorisées sur la carte. | T-1 lignes et arrêts |
| [L26](../../FEATURES.md#L26) | Feux, stop, passages à niveau et ralentisseurs à fort zoom | ❌ | SRC : aucune couche correspondante dans le style et aucun overlay dans `MapController`. | I-1b alertes de carte |
| [L27-L28](../../FEATURES.md#L27-L28) | Zoom des numéros et complétion des bâtiments manquants | ❌ | SRC : ni préférences ni couches ou sources dédiées dans les ressources et `MapController`. | I-1b habillage carte |
| [L29](../../FEATURES.md#L29) | Point bleu, cône de cap et cercle de précision approximative | ⚠️ | M1 valide le bouton de localisation. `MapController.showUser` utilise le puck MapLibre, mais le cône et le cercle large n'ont pas de preuve dédiée. | Q-2 validation GPS iPhone |
| [L30](../../FEATURES.md#L30) | Conduite sans itinéraire, cap vers le haut, vitesse et limite | ❌ | `NavChrome` et la caméra ne sont actifs qu'avec `NavUiState.active`. `NavStore.speedLimitKmh` n'est jamais alimenté. | N-3 conduite libre |
| [L31-L34](../../FEATURES.md#L31-L34) | Mode conduite sans route et alertes associées | ❌ | Aucun mode de conduite libre dans `MapScreen` ni réglage de démarrage. | N-3 conduite libre |
| [L35-L37](../../FEATURES.md#L35-L37) | Noms dans la langue de l'app, romanisés ou en écriture locale | ⚠️ | Le style Liberty utilise ses propres règles de noms. Aucun réglage iOS de langue de carte dans `MapDefaults` ou `MapController`. | I-1b noms de carte |
| [L38](../../FEATURES.md#L38) | Boussole, échelle, localisation et boutons de zoom | ⚠️ | M1 couvre la localisation. `MapView` laisse la boussole MapLibre, mais n'installe ni échelle ni boutons de zoom ou leur préférence. | I-1b chrome de carte |
| [L39-L40](../../FEATURES.md#L39-L40) | Choix de la position de départ | ⚠️ | `LaunchOptions` permet une caméra de test et la caméra par défaut est San Francisco. Aucun choix utilisateur position actuelle, dernière vue, Maison ou vue enregistrée. | I-8b réglages de départ |

## Places

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L44-L45](../../FEATURES.md#L44-L45) | Fiche lieu avec identité, note, prix, contact et distance | ⚠️ | N1 et `PlaceSheet` couvrent les champs sauf la distance. `PlaceCard` n'a pas de distance et le téléphone/site dépendent des données. | P-2 détails lieu |
| [L46](../../FEATURES.md#L46) | Statut et horaires semaine, vacances et départements | ⚠️ | N1 mesure `place_hours=7`. Les horaires spéciaux et départements n'ont ni présentation distincte ni fixture iOS. | P-2 horaires |
| [L47-L48](../../FEATURES.md#L47-L48) | Onglets Overview, Reviews, Photos, Menu, Updates et About | ⚠️ | La fiche native contient un résumé, des photos et des avis. Menu, posts du propriétaire et attributs About ne sont pas exposés par `PlaceCard`. | P-2 onglets lieu |
| [L49-L50](../../FEATURES.md#L49-L50) | Avis avec photos, histogramme, tri, recherche et page Google complète | ⚠️ | `ReviewsPanel` fait photos, tri et recherche locale. P1 n'a pas atteint ce panneau au dernier run; pas d'histogramme ni ouverture de la page Google complète. | P-2 avis et revalidation P-1 |
| [L51](../../FEATURES.md#L51) | Galerie par catégorie, visionneuse et affluence | ⚠️ | P1 prouve 20 photos et la grille, puis Q-1 échoue au bouton de catégories. La visionneuse et les catégories restent à valider. Le repli d'affluence répond sans horaires sur l'IP du runner. | P-2 galerie et affluence iPhone |
| [L52](../../FEATURES.md#L52) | Directions, Start, Call, Website, Save, Share, Order et Reserve | ⚠️ | N1, M4, M5 et I6 couvrent les six premières actions selon les données. Order et Reserve sont absents de `PlaceSheet`. | P-2 actions commerciales |
| [L53](../../FEATURES.md#L53) | Partage lien, geo, coordonnées, adresse ou autre carte | ⚠️ | `SavedModel.shareSelectedUrl` et `ActivityView` partagent l'URL canonique dans la feuille système. `ShortLinks` résout seulement les liens entrants, donc aucun lien court sortant n'est annoncé; les autres contenus ne sont pas offerts. | DL-2 autres contenus de partage |
| [L54-L57](../../FEATURES.md#L54-L57) | Ouverture d'un lien d'itinéraire Google avec arrêts et points déplacés | ❌ | `MapLinkParser` est en common, mais `VelaApp` n'a ni `onOpenURL` ni déclaration de liens et `RouteStore` ne prend pas ce lien. | DL-1 liens Google |
| [L58-L59](../../FEATURES.md#L58-L59) | People also search, Also at this location et épingles enregistrées | ⚠️ | Les lieux enregistrés se rouvrent par I6. Les deux rangées de lieux liés ne sont pas dans `PlaceModel` ou `PlaceSheet`. | P-2 lieux liés |
| [L60](../../FEATURES.md#L60) | Ouverture immédiate d'un POI avec données ouvertes et source | ⚠️ | N1 ouvre un POI Liberty puis sa fiche Google. `MapPoiSheet` montre un état de résolution, sans nommer explicitement la source ouverte. | I-1b fiche POI |
| [L61-L64](../../FEATURES.md#L61-L64) | Fermetures et prix des carburants US/UK avec fraîcheur | ⚠️ | Le statut texte est affiché. `FuelGb` et `FuelGbStore` sont en common, mais `PlaceCard` ne porte ni prix ni fraîcheur. | P-2 fermetures et carburant |
| [L65-L66](../../FEATURES.md#L65-L66) | Street View interactive, historique et vignette | ⚠️ | `PlaceSheet.streetView` affiche seulement une vignette distante si `svPanoId` existe. Aucun panoramique interactif ou historique dans iOS. | SV-1 Street View |
| [L67-L68](../../FEATURES.md#L67-L68) | Réglages de chargement des avis et photos | ❌ | Le chargement paresseux des avis existe, mais aucun des quatre réglages de `SettingsScreen`. | PR-1 réglages de contenu |
| [L69-L70](../../FEATURES.md#L69-L70) | Attente de l'affluence et chargement complet photos/avis | ❌ | Les replis automatiques de P1 ne sont pas ces préférences. Aucun réglage correspondant. | PR-1 réglages de contenu |
| [L71-L72](../../FEATURES.md#L71-L72) | Masquage adulte et liens externes | ❌ | `CategoryFilter` est en common, sans réglage iOS ni application visible à la recherche ou à la fiche. | PR-1 réglages de contenu |

## Search

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L76](../../FEATURES.md#L76) | Recherche nom, catégorie ou adresse biaisée à la vue | ⚠️ | M2 valide nom/catégorie sur iPhone et N1 mesure 60 lignes. Le biais est envoyé à `SearchStore`; l'adresse en ligne et sa déduplication ne sont pas démontrées. | I-2b adresses et fusion |
| [L77](../../FEATURES.md#L77) | Suggestions, récents/enregistrés prioritaires et flèche de saisie | ⚠️ | `SearchUITests.testSuggestionsAppearAndFreezeAfterSelection` mesure 4 suggestions dans N1. Les récents sont séparés; priorité des enregistrés et flèche absentes. | I-2b suggestions |
| [L78](../../FEATURES.md#L78) | Résultats épingles et cartes avec note, statut, photos et actions | ⚠️ | M2 valide liste et épingles. `ResultRow` n'affiche que nom, note, nombre d'avis et adresse, sans photo, statut ou actions. | I-2b cartes de résultats |
| [L79](../../FEATURES.md#L79) | Requête Open now | ❌ | Aucun intent ou filtre Open now dans `SearchModel` et `SearchStore`. | I-2b filtres |
| [L80-L81](../../FEATURES.md#L80-L81) | Filtres ouverture, note, prix, accessibilité et tri | ❌ | `ResultsPanel` n'expose aucun filtre ou tri. | I-2b filtres |
| [L82](../../FEATURES.md#L82) | Search this area et More results | ⚠️ | La recherche charge plusieurs pages, comme le montrent les 60 résultats M2/N1. Ni bouton Search this area après déplacement ni bouton More results. | I-2b pagination et zone |
| [L83-L84](../../FEATURES.md#L83-L84) | Autres succursales et son interrupteur | ❌ | `OtherLocations` est en common, mais aucun appel depuis les stores iOS ni ligne de succursales dans `PlaceSheet`. | P-2 succursales |
| [L85](../../FEATURES.md#L85) | Raccourcis de catégories en rangée, bouton ou masqués | ⚠️ | `SearchUITests.testQuickCategoryRunsSearch` et N1 couvrent six catégories fixes en rangée. Recharge EV, mode bouton et masquage absents. | I-2b catégories |
| [L86-L87](../../FEATURES.md#L86-L87) | Choix et ordre des raccourcis, puce More, variantes route/voiture | ❌ | `QuickCategory.all` est fixe et `QuickCategoriesView` n'a ni More ni réglage. | I-2b catégories |
| [L88](../../FEATURES.md#L88) | Commandes texte ou vocales | ❌ | La soumission appelle seulement `SearchStore.submit`; aucun interpréteur de commandes dans iOS. | VO-1 commandes |
| [L89-L91](../../FEATURES.md#L89-L91) | Recherche vocale et cinq moteurs locaux | ❌ | Aucun micro, moteur ASR ou réglage dans `iosApp` et `ios-shared`. | VO-1 dictée |
| [L92](../../FEATURES.md#L92) | Recherche dans les contacts | ❌ | Aucun accès Contacts ni réglage associé. | I-2b contacts |
| [L93](../../FEATURES.md#L93) | Recherche le long de l'itinéraire | ❌ | `SearchModel` reçoit la vue et la position, jamais la géométrie active de `RouteStore` ou `NavStore`. | I-2b recherche sur route |
| [L94-L95](../../FEATURES.md#L94-L95) | Liens cartes externes et choix place/itinéraire/navigation/Street View | ❌ | Aucun enregistrement de domaine, type d'URL ou `onOpenURL` dans le projet iOS. | DL-1 liens Google |
| [L96](../../FEATURES.md#L96) | Recherche hors ligne et NoGoogle sur données ouvertes | 🟡 | I7 installe Monaco, bloque le réseau et trouve 30 résultats avec `offline=1`. Les variantes d'adresses restent à élargir. | Q-2 variantes de recherche hors ligne |

## Routes

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L100](../../FEATURES.md#L100) | Itinéraires voiture, marche, vélo, transit et départ libre | ⚠️ | M4 prouve voiture, marche et Transitous. Le vélo a une puce, mais pas de scénario; le départ libre se limite au secours du milieu de la carte. | R-1 origines et modes |
| [L101-L102](../../FEATURES.md#L101-L102) | Route Google, noms/voies/sorties ouverts et routeurs NoGoogle | ⚠️ | M4 mesure les étapes hybrides nommées et les voies. Le chemin NoGoogle n'a pas de scénario de bout en bout et les chemins agricoles ne sont pas vérifiés. | R-1 routage ouvert |
| [L103](../../FEATURES.md#L103) | Jusqu'à quatre alternatives, trafic et sélection sur la carte | 🟡 | M4 mesure 3 alternatives et une sélection; `MapController.onRouteTap` câble le toucher d'une ligne. Le plafond de quatre est celui du store commun. | Q-2 toucher des alternatives |
| [L104-L105](../../FEATURES.md#L104-L105) | Choix Google-style une route ou panneau classique | ❌ | `RoutePickerSheet` liste toujours les alternatives et n'a pas de réglage de présentation. | R-1 présentation du choix |
| [L106-L108](../../FEATURES.md#L106-L108) | Ajout et réorganisation d'arrêts, y compris en conduite | ❌ | `RouteStore` appelle `directions` avec `emptyList()` pour les arrêts et aucune feuille Stops n'existe. | R-1 arrêts |
| [L109](../../FEATURES.md#L109) | Évitements et heures de départ/arrivée | ⚠️ | `RoutePickerSheet` expose autoroutes, péages et ferries persistés. Caméras, Leave now, Depart at et Arrive by manquent; les toggles ne sont pas couverts par M4. | R-1 options et N-2 caméras |
| [L110-L111](../../FEATURES.md#L110-L111) | Routeur marche ouvert et préférence vélo | ⚠️ | M4 prouve la marche OSRM. Le vélo utilise le store, mais la préférence de voies calmes n'est pas exposée ni testée. | R-1 vélo |
| [L112](../../FEATURES.md#L112) | Étapes avant départ et focus d'une étape | ⚠️ | M4 ouvre et capture les étapes voiture, marche et transport. Aucun `onTap` sur `step-row` pour cadrer la carte. | R-1 étapes |
| [L113-L114](../../FEATURES.md#L113-L114) | Enregistrement et offre Your route pour le même trajet | ⚠️ | L-1 ajoute la géométrie enregistrée comme Saved line à côté des routes calculées, sans ETA, trafic ou étapes inventés. Le scénario de réouverture est ajouté, mais la ligne reste une prévisualisation sans guidage et les runs avec arrêts ne sont pas restaurés. | L-1 validation et runs avec arrêts |
| [L115](../../FEATURES.md#L115) | Raccourci d'accueil et partage texte du trajet | ❌ | Saved contient des lieux, pas de raccourci de trajet; aucune action de partage dans `RoutePickerSheet`. | R-1 partage de trajet |
| [L116](../../FEATURES.md#L116) | Alerte de fermeture à l'arrivée | ❌ | `ClosingTime` est en common, mais ni `RouteStore` ni `NavStore` ne publient cet avertissement. | R-1 alertes de destination |
| [L117](../../FEATURES.md#L117) | Trafic en direct seulement à la demande | ❌ | Aucun réglage ni bouton Show traffic; le choix du routeur ne change pas sur cette intention. | N-2 trafic et confidentialité |

## Navigation

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L121-L123](../../FEATURES.md#L121-L123) | Bandeau complet, anticipation, abréviations écran et voix longue | ⚠️ | M5 prouve flèche, distance, instruction et voix. `NavManeuver` n'expose pas écussons/voies et le bandeau n'a pas de balayage d'anticipation. | N-3 bandeau |
| [L124-L125](../../FEATURES.md#L124-L125) | Grands textes: carte tiers d'écran, flèche dégagée et cadrage | ⚠️ | `NavChrome` n'a aucune règle de tiers ou de Dynamic Type et `MapController` utilise seulement des insets fixes. Mesures Q-1 à consolider avant correction. | Q-2 accessibilité navigation |
| [L126-L129](../../FEATURES.md#L126-L129) | Zoom automatique vers la prochaine manœuvre | ❌ | `MapController.updateNavigation` applique seulement deux zooms selon la vitesse, sans position de la prochaine manœuvre ni réglage. | N-3 caméra |
| [L130](../../FEATURES.md#L130) | Voix avec rues et voies, option sans noms de rue | ⚠️ | M5 reçoit les phrases AVSpeechSynthesizer et les tests communs couvrent les voies. Aucun réglage Say street names. | I-8b réglages voix |
| [L131-L133](../../FEATURES.md#L131-L133) | Deux virages proches annoncés ensemble | 🟡 | `NavEngineChainTest` fixe les phrases complètes et raccourcies; C5 les exécute aussi sur simulateur, avec la même `NavSession` qu'iOS. | Q-2 replay vocal sur iPhone |
| [L134-L135](../../FEATURES.md#L134-L135) | Noms de rues complétés pendant la conduite | 🟡 | `RouteHealTest` et C5 couvrent la réparation par la `NavSession` commune; `NavStore` observe la même session. | N-3 preuve en conduite |
| [L136-L137](../../FEATURES.md#L136-L137) | Niveaux Everything, Brief et Highway exits only | ⚠️ | `SpokenDetail` est utilisé par le moteur commun, mais Settings ne propose pas ces modes et le bouton iOS ne fait que muet/actif. | I-8b réglages voix |
| [L138-L140](../../FEATURES.md#L138-L140) | Barre ETA, étapes, arrêts et informations au prochain arrêt | ⚠️ | M5 couvre durée, distance et arrivée. Pas de balayage vers les étapes ni chiffres par arrêt; X1 affiche l'état sans arrêts. | R-1 arrêts et N-3 barre |
| [L141](../../FEATURES.md#L141) | Recalcul avec carillon, vibration et bandeau | ⚠️ | M5 et X1 observent le recalcul; `AppleNavVoice` joue un carillon. `AppleNavHaptics.reroute` refuse explicitement le mode DRIVE. | N-2 recalcul et retour haptique |
| [L142-L143](../../FEATURES.md#L142-L143) | Offre d'itinéraire plus rapide et acceptation automatique | ❌ | Les méthodes du store existent, mais `NavUiState` ne publie aucune offre et `NavChrome` n'a pas de carte correspondante. | N-2 trafic et détours |
| [L144](../../FEATURES.md#L144) | Ligne colorée par congestion et route parcourue grise | ⚠️ | M4 prouve la congestion dans le choix. `NavModel.showRoute` reconstruit la ligne de navigation avec `traffic=[]`; rien ne grise le passé. | N-2 ligne de navigation |
| [L145-L146](../../FEATURES.md#L145-L146) | Ligne recentrée sur la chaussée | 🟡 | `RouteStore.lineOf` préfère `drawPolyline`, produite par le nommage commun, et M4 couvre le tracé hybride. | N-3 comparaison visuelle en conduite |
| [L147](../../FEATURES.md#L147) | Vitesse et limite affichées avec interrupteur | ⚠️ | `NavChrome` affiche la vitesse. `NavStore.speedLimitKmh` reste à sa valeur initiale et aucun réglage Show speed n'existe. | N-2 limitations |
| [L148-L149](../../FEATURES.md#L148-L149) | Limites conditionnelles selon l'heure | ❌ | `OsmMaxspeed` et ses tests sont en common, mais aucune source iOS n'alimente `speedLimitKmh`. | N-2 limitations |
| [L150-L151](../../FEATURES.md#L150-L151) | Barre Road ahead | ❌ | `RouteBar` est en common, sans état dans `NavUiState` ni vue iOS. | N-3 Road ahead |
| [L152-L153](../../FEATURES.md#L152-L153) | Flèches directionnelles le long de la route | ❌ | `RouteLayers` ne crée pas de couche de flèches de manœuvre et Settings n'a pas l'option. | N-3 rendu de route |
| [L154-L155](../../FEATURES.md#L154-L155) | Nom de rue actuelle et son placement | ❌ | `NavModel.streetName` est publié mais jamais lu par `NavChrome`; aucun réglage de placement. | N-3 chrome navigation |
| [L156-L157](../../FEATURES.md#L156-L157) | Priorité aux numéros de routes | ⚠️ | Les étapes et le bandeau peuvent utiliser `ref`. Aucun réglage Road numbers first ni propagation aux trois surfaces demandées. | N-3 noms de routes |
| [L158](../../FEATURES.md#L158) | Cartouches de rues croisées | ❌ | Aucune couche ou vue de carrefour dans `MapController` ou `NavChrome`. | N-3 rendu de route |
| [L159](../../FEATURES.md#L159) | Écusson de la route actuelle sur la ligne | ❌ | `RouteLayers` ne dessine pas d'écusson périodique. | N-3 rendu de route |
| [L160-L161](../../FEATURES.md#L160-L161) | Pause de la navigation et placement du bouton | ❌ | `NavStore.setPaused` et `NavModel.paused` existent, mais aucun bouton ou réglage ne les expose. | N-3 pause |
| [L162](../../FEATURES.md#L162) | Vue d'ensemble et Recentrer | ⚠️ | M5 couvre le suivi et `nav-recenter` existe après détachement. Aucun bouton Overview pour cadrer le reste du trajet. | N-3 caméra |
| [L163-L164](../../FEATURES.md#L163-L164) | Boussole cap/nord et préférences de départ | ⚠️ | Le bouton `nav-heading` appelle `toggleNorthUp`. Les préférences Start north-up et Keep north up sont absentes. | I-8b réglages navigation |
| [L165-L166](../../FEATURES.md#L165-L166) | Icône, taille et couleurs du véhicule | ❌ | Le puck MapLibre est utilisé sans sélecteur d'icône, taille ou palette. | I-8b apparence navigation |
| [L167](../../FEATURES.md#L167) | Vibration, écran actif et confirmation de fin | ⚠️ | M5 prouve écran actif et confirmation End. `AppleNavHaptics` couvre certains modes, mais pas les réglages Vibrate on turns ni la conduite par défaut. | I-8b retour haptique |
| [L168-L169](../../FEATURES.md#L168-L169) | Navigation en arrière-plan avec notification, mini-carte ou Live Activity | ⚠️ | M5 vérifie localisation arrière-plan et X1 crée/met à jour/termine une Live Activity. Pas de mini-carte; rendu écran verrouillé encore humain. | X-1 validation iPhone |
| [L170](../../FEATURES.md#L170) | Bandeau dans la mini-carte Android | ➖ | Aucune mini-carte Android Picture-in-Picture sur iOS. La Live Activity a sa propre présentation, couverte par la ligne précédente. | Aucun |
| [L171](../../FEATURES.md#L171) | Proposition de reprise après fermeture en navigation | ❌ | `docs/ios/LIVE-ACTIVITY.md` dit explicitement que la navigation n'est pas restaurée; aucun état de reprise dans `NavStore`. | N-3 reprise |
| [L172](../../FEATURES.md#L172) | Estimation de position en tunnel | ❌ | Le tunnel de `NavController` Android n'est pas porté. iOS publie `starved` et « Searching for GPS » après 10 s, sans boucle d'estimation. | N-3 tunnel |
| [L173-L175](../../FEATURES.md#L173-L175) | Annonce des arrêts et de l'arrivée avec totaux | ⚠️ | `NavEngineStopCueTest` couvre les annonces communes et `NavChrome.arrival` affiche les totaux. Sans arrêts iOS, seule l'arrivée finale a un chemin utilisateur. | R-1 arrêts et N-3 arrivée |
| [L176-L177](../../FEATURES.md#L176-L177) | Annonce du virage dans le parking de destination | 🟡 | `NavEngineStopCueTest` et `StopCueStringsTest` couvrent « Turn left into the parking lot » dans la `NavSession` commune exécutée par C5. | N-3 validation en conduite |
| [L178](../../FEATURES.md#L178) | Toucher un lieu en conduite pour en faire un arrêt | ❌ | Tous les callbacks de POI de `MapScreen` sont bloqués pendant `nav.active`. | R-1 arrêts |
| [L179-L180](../../FEATURES.md#L179-L180) | Simplification de la carte pendant la conduite et les virages | ❌ | `MapScreen` ne change ni sources ni couches quand `nav.active` devient vrai. | N-3 rendu de route |
| [L181-L182](../../FEATURES.md#L181-L182) | Guidage par les feux en anglais, désactivé par défaut | ⚠️ | `NavEngineLightCueTest` couvre les phrases communes et `lightLead` est appelé. Le réglage explicite et son état par défaut ne sont pas exposés sur iOS. | N-3 guidage par feux |

## Transit

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L186-L187](../../FEATURES.md#L186-L187) | Trajets, horaires, couleurs, marches, compte à rebours et retards | ⚠️ | M4 mesure les itinéraires et X3 conserve le retard réel du fixture avec heures planifiées et estimées distinctes. Pas de compte à rebours vivant ni validation sur iPhone. | T-1 fiches transport |
| [L188-L189](../../FEATURES.md#L188-L189) | Départ, arrivée, dernier trajet et préférences de transport | ❌ | `RouteStore.transitPlanner` ne reçoit que départ et destination; aucune puce temporelle ou préférence dans `RoutePickerSheet`. | T-1 options de recherche |
| [L190](../../FEATURES.md#L190) | Détail des arrêts, alertes, tarif et tracé réel | ⚠️ | M4 montre les tronçons et `RouteStore.transitLineOf` joint leur géométrie. Pas de liste d'arrêts, alertes ou tarif dans `TransitLegView`. | T-1 détail des trajets |
| [L191](../../FEATURES.md#L191) | Décomposition d'une marche en manœuvres | ❌ | `TransitLegView` affiche seulement « Walk » et sa durée, sans étapes de marche. | T-1 détail des trajets |
| [L192](../../FEATURES.md#L192) | Guidage transport étape par étape | 🟡 | X3 démarre l'itinéraire choisi, avance marches et arrêts par position ou hook Debug, affiche carte et Live Activity, puis End. Scénario simulateur et captures verts; progression réelle et rendus ActivityKit à valider sur iPhone. | X-3 validation iPhone |
| [L193-L194](../../FEATURES.md#L193-L194) | Tableau des départs d'un arrêt | ❌ | `StopDeparturesParser` est en common, mais le toucher d'un arrêt suit la fiche POI et aucune vue de départs n'existe. | T-1 arrêts |
| [L195](../../FEATURES.md#L195) | Dernier tableau d'arrêt hors ligne | ❌ | Aucun tableau en ligne à mettre en cache et aucun store iOS de départs consultés hors ligne. | T-1 arrêts hors ligne |
| [L196](../../FEATURES.md#L196) | Trajets Transitous avec Google désactivé | 🟡 | M4 mesure les itinéraires Transitous, seul planificateur transport de `RouteStore`, donc indépendant des pages Google Transit. | T-1 test explicite NoGoogle |

## Cameras and road alerts

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L200](../../FEATURES.md#L200) | Caméras de surveillance et orientation sur la carte | ❌ | `OverpassAlprCameras` est en common, mais aucune source, couche ou préférence dans `MapController`. | N-2 alertes et couches |
| [L201-L202](../../FEATURES.md#L201-L202) | Évitement des caméras avec comptage par itinéraire | ❌ | `CameraDetour` est en common; `RouteState` n'a ni option ni compte de caméras et `RoutePickerSheet` ne les affiche pas. | N-2 et R-1 évitement |
| [L203](../../FEATURES.md#L203) | Essai des rues latérales autour des caméras | ❌ | La brique `CameraDetour` ne suffit pas: aucune option ou requête de variantes depuis `RouteStore`. | N-2 et R-1 évitement |
| [L204](../../FEATURES.md#L204) | Carte et annonce d'une caméra de plaque | ❌ | Aucun état de caméra dans `NavUiState`, aucune carte dans `NavChrome` et aucune phrase branchée. | N-2 alertes |
| [L205-L206](../../FEATURES.md#L205-L206) | Radars fixes sur carte, carte d'alerte et annonce | ❌ | `OverpassSpeedCameras` est en common, sans couche ni état d'alerte iOS. | N-2 alertes |
| [L207](../../FEATURES.md#L207) | Alerte vocale de dépassement | ❌ | `SpeedingAlerts` est testé en common, mais vitesse limite non alimentée et aucun événement d'alerte exposé par `NavStore`. | N-2 limitations |
| [L208-L209](../../FEATURES.md#L208-L209) | Mode vocal Alerts only et sélecteur pendant la conduite | ❌ | `NavModel.toggleVoice` n'a que deux états et aucun état d'alerte n'est publié à `NavChrome`. | N-2 alertes |
| [L210-L211](../../FEATURES.md#L210-L211) | Ouvertures de ponts NDW | ❌ | `NdwBridgeOpenings` est en common, sans appel depuis les stores iOS ni carte d'alerte. | N-3 alertes de ponts |
| [L212](../../FEATURES.md#L212) | Données de caméras embarquées pour le hors ligne | ❌ | Aucun paquet de caméras dans `iosApp/Vela/Resources` ni lecture d'un tel paquet dans les stores iOS. | N-2 données hors ligne |

## Offline

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L216](../../FEATURES.md#L216) | Téléchargement d'une zone cadrée avec carte, lieux, adresses et routage | ⚠️ | I7 installe carte, lieux et adresses d'une région du catalogue. Pas de cadrage libre et aucun routeur `.obf` iOS, conforme à D7. | O-3 zone libre et routage |
| [L217-L218](../../FEATURES.md#L217-L218) | Catalogue États/pays et découpage des grandes régions | 🟡 | I7 charge le catalogue et installe Monaco. `OfflineStore` applique les archives parent/partie du `RegionCatalog` commun; les autres découpages restent des tests de données. | O-2 validation du catalogue |
| [L219-L221](../../FEATURES.md#L219-L221) | Carte, lieux et recherche hors ligne avec adresses et accents | 🟡 | I7 prouve carte locale sans URL distante et 30 résultats NoGoogle. `OfflineStore.search` fusionne POI et `OfflineAddressStore`; davantage de fixtures sont nécessaires. | Q-2 variantes hors ligne |
| [L222-L223](../../FEATURES.md#L222-L223) | Itinéraires hors ligne avec voix, limites et évitements | ❌ | D7 exclut le routeur `.obf` de V1 et aucun autre moteur local n'est branché dans `RouteStore`. | O-3 routage hors ligne |
| [L224-L226](../../FEATURES.md#L224-L226) | Mises à jour incrémentielles, Wi-Fi/données et Update all | ❌ | `PmtilesPatch` est en common, mais la feuille n'a ni politique ni bouton de mise à jour et `OfflineStore` ne lance pas de delta. | O-2 deltas |
| [L227](../../FEATURES.md#L227) | Déplacement des régions vers une carte SD | ➖ | iOS n'offre pas le modèle Android de stockage SD adoptable. Les fichiers sont dans Application Support via `FileManagerPlatformFiles`. | Aucun |
| [L228](../../FEATURES.md#L228) | Détail du stockage, purge du cache et suppression complète | ⚠️ | La feuille affiche un total et supprime une région; les tailles détaillées sont seulement en Debug. Pas de Clear map cache ou Delete all. | O-3 stockage |
| [L229-L230](../../FEATURES.md#L229-L230) | Options Include places et Keep viewed places | ⚠️ | I7 inclut toujours le paquet de lieux. `PlaceCache` existe en common, mais aucune préférence ou politique iOS de conservation visible. | O-3 conservation |
| [L231](../../FEATURES.md#L231) | Globe barré hors ligne et nouvelle vérification | ❌ | `SearchBar` n'a pas d'icône d'état réseau; `OfflineNetworkMonitor` ne pilote qu'`OfflineStore`. | O-3 état réseau |
| [L232](../../FEATURES.md#L232) | Téléchargements en arrière-plan avec Cancel | ⚠️ | I7 couvre progression et `OfflineStore.cancelDownload`. `RegionDownloader` est explicitement une URLSession de premier plan. | O-2 arrière-plan et reprise |
| [L233](../../FEATURES.md#L233) | Mode données réduites et photos limitées | ❌ | `LowDataMode` est en common, mais aucun réglage iOS ni adaptation des requêtes photos au type de connexion. | PR-1 données réduites |

## Voice and languages

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L237](../../FEATURES.md#L237) | Voix neuronale Vela téléchargée et locale | ❌ | `AppleNavVoice` utilise `AVSpeechSynthesizer`; aucun moteur Piper/Kokoro ou téléchargement de voix iOS. | VO-1 voix neurales |
| [L238](../../FEATURES.md#L238) | Bibliothèque d'environ 40 voix Piper et voix système | ⚠️ | Les voix système Apple sont utilisées par M5. Aucune bibliothèque ou voix neuronale installable. | VO-1 bibliothèque |
| [L239](../../FEATURES.md#L239) | Interrupteur Spoken directions identique au muet | ⚠️ | M5 prouve la voix et `NavModel.toggleVoice` appelle `setMuted`. L'interrupteur global de Settings est absent. | I-8b réglages voix |
| [L240-L241](../../FEATURES.md#L240-L241) | Volume, vitesse, test et nivellement de la voix | ❌ | `NavVoice` fixe seulement le débit à 0,97 et la session duckOthers. Aucun réglage, test vocal ou nivellement neuronal. | VO-1 réglages voix |
| [L242-L243](../../FEATURES.md#L242-L243) | Langue des directions et gestion des voix absentes | ⚠️ | `SettingsStore` pousse la langue dans `NavStringsRegistry` et Apple choisit une voix de repli. Aucun téléchargement proposé ni avertissement sur une ligne de voix. | VO-1 langues vocales |
| [L244-L245](../../FEATURES.md#L244-L245) | Prononciation locale de 3 500 noms et romanisation | ⚠️ | Les règles `NavStrings` et `SpeechText` sont partagées. Aucun lexique de 3 500 noms n'est livré dans les ressources iOS. | VO-1 prononciation |
| [L246-L247](../../FEATURES.md#L246-L247) | Langues, CJK, hébreu RTL et traductions partielles | ⚠️ | I8 mesure français et allemand et le catalogue offre 24 locales. Q-1 montre la recherche en RTL, mais `SettingsScreen` reste en LTR en hébreu et les catégories rapides en anglais. | I-8b traductions et Q-2 RTL |
| [L248](../../FEATURES.md#L248) | Langue système ou propre à Vela | 🟡 | I8 vérifie le lancement français, le choix persistant et le fonctionnement par défaut du catalogue système. | Q-2 autres langues sur iPhone |
| [L249-L250](../../FEATURES.md#L249-L250) | Langue des directions différente des menus | ⚠️ | La langue de l'app pilote aussi les directions. Aucun second réglage Directions language dans `SettingsStore`. | I-8b langue des directions |
| [L251](../../FEATURES.md#L251) | Unités et horloge 12/24 h | ⚠️ | I8 vérifie la persistance des deux choix et `RouteFormat.distance` lit les unités. `NavFormat.arrival` utilise directement `DateFormatter`, sans le choix Vela. | I-8b application de l'horloge |

## Saved places, lists and sharing

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L255](../../FEATURES.md#L255) | Save, Maison/Travail et Share | 🟡 | I6 vérifie Save et sa persistance. L-1 ouvre Maison/Travail depuis Saved et la carte par `SavedModel.openShortcut`, indépendamment des récents; Share ouvre la feuille système avec le lien canonique. | Validation iPhone des raccourcis |
| [L256-L258](../../FEATURES.md#L256-L258) | Gestes des listes et récents, ordre, multisélection et retour haptique | ⚠️ | `SavedViews` couvre swipes, renommage, déplacement par menu contextuel et Clear recents. Pas de poignée, multisélection ou retour haptique. | L-1 édition des listes |
| [L259-L260](../../FEATURES.md#L259-L260) | Nom, couleur, icône, notes et renommage | ⚠️ | I6 crée et renomme des listes; `SavedStore.setNote` existe en common. L'éditeur ne propose ni couleur, icône, emoji ni note. | L-1 édition des listes |
| [L261-L263](../../FEATURES.md#L261-L263) | Marqueurs enregistrés colorés, noms, zoom et épingles de recherche | ⚠️ | `MapController.annotationView` dessine des disques colorés de 14 points et Save devient rempli. Pas de taille selon zoom, nom ou épingle de recherche. | L-1 marqueurs |
| [L264](../../FEATURES.md#L264) | Forme ronde ou carrée des boutons de carte | ⚠️ | Les boutons Saved, parking et localisation sont ronds. Aucun réglage Map buttons ni variante carrée. | I-8b apparence carte |
| [L265-L268](../../FEATURES.md#L265-L268) | Export/import, GPX/KML/GeoJSON et listes Takeout | ⚠️ | L-1 partage une liste au JSON Android, gère la portée du document, l'annulation avec progrès partiel et les entrées périmées. Un fixture UI importe deux repères. L'export des quick saves et le sélecteur de documents restent à prouver sur iPhone. | L-1 exports restants et validation iPhone |
| [L269-L270](../../FEATURES.md#L269-L270) | Sélection multiple pour supprimer ou déplacer | ⚠️ | Le menu contextuel déplace un lieu à la fois. Aucun mode de sélection multiple dans `SavedView` ou `SavedListDetailView`. | L-1 sélection multiple |
| [L271-L272](../../FEATURES.md#L271-L272) | Son de liste et alerte au passage | ❌ | Aucun éditeur de son dans `SavedViews` et aucun abonnement de `NavStore` aux lieux enregistrés pour déclencher `PassAlerts`. | L-1 alertes de listes |
| [L273](../../FEATURES.md#L273) | Ouverture d'une liste Google partagée | ❌ | `ShortLinks` et la source commune ont des briques, mais aucun `onOpenURL` ni import de lien de liste dans iOS. | DL-1 listes partagées |
| [L274](../../FEATURES.md#L274) | Ouverture d'un lien Google My Maps | ❌ | `MyMapKml` est en common, sans gestion de lien ou chemin d'import My Maps dans `SavedStore`. | DL-1 My Maps |
| [L275](../../FEATURES.md#L275) | Dessin de lignes et zones | ❌ | Aucun outil de dessin ou modèle de forme dans `MapController` et `SavedViews`. | L-1 formes |
| [L276-L278](../../FEATURES.md#L276-L278) | Parking, Find my car, historique et proposition à l'arrivée | ⚠️ | I6 et `SavedViews` couvrent position actuelle et historique. Pas de distance/itinéraire Find my car ni proposition sur `NavChrome.arrival`. | L-1 parking |
| [L279](../../FEATURES.md#L279) | Suppression unitaire ou globale des récents | 🟡 | `RecentsPanel` et `SavedView` appellent `removeRecent` et `clearRecents`; I6 vérifie la création et la persistance des récents sur lesquelles ces méthodes agissent. | Q-2 suppression des récents |

## Privacy controls

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L283](../../FEATURES.md#L283) | Pas de compte, publicité, analytics ou serveur Vela | ✅ | M1/M2 utilisent l'app sans compte. SRC : `project.yml` ne lie aucun SDK publicitaire/analytics et les requêtes vont aux fournisseurs, sans backend Vela. | Q-2 revue réseau iPhone |
| [L284-L286](../../FEATURES.md#L284-L286) | Consentement initial Google et caméras | ❌ | `MapScreen.onAppear` démarre calibration et session sans feuille de premier lancement; aucun consentement caméra. | PR-1 premier lancement |
| [L287](../../FEATURES.md#L287) | Page Privacy regroupant tous les choix Google | ⚠️ | Settings a une section Privacy avec NoGoogle et un lien, mais pas les interrupteurs détaillés. | PR-1 confidentialité |
| [L288-L289](../../FEATURES.md#L288-L289) | NoGoogle stoppe Google et retire contenus en direct | ⚠️ | I7 prouve carte et recherche sans réseau. Le test ne couvre pas une fiche déjà chargée, avis, photos, trafic ou vignette Street View. | PR-1 audit NoGoogle |
| [L290](../../FEATURES.md#L290) | Résolution des liens courts autorisée avec Google off | ❌ | Aucune ouverture de lien externe ni préférence distincte pour `ShortLinks`. | DL-1 liens Google |
| [L291-L292](../../FEATURES.md#L291-L292) | Aucun envoi à Google au déplacement avec POI Vela | ❌ | La source de POI Vela n'existe pas encore sur iOS; seules les tuiles OpenFreeMap et recherches explicites sont mesurées. | I-1b sources de POI |
| [L293](../../FEATURES.md#L293) | Interrupteur Look up tapped places on Google | ❌ | Le toucher d'un POI suit toujours `MapPoiModel.tap`; aucune préférence indépendante de NoGoogle. | PR-1 confidentialité |
| [L294](../../FEATURES.md#L294) | Rotation de session hebdomadaire, quotidienne ou au lancement | ⚠️ | Chaque processus crée une nouvelle session WebView non persistante et `MapSession` réchauffe Google au lancement. Aucun choix hebdomadaire ou quotidien. | PR-1 sessions |
| [L295](../../FEATURES.md#L295) | Blocage de la télémétrie des pages Google | ⚠️ | W2 et `HiddenWebView.blockedHostsRules` bloquent publicité et télémétrie par défaut. L'interrupteur et la mesure sur iPhone manquent. | PR-1 confidentialité WebView |
| [L296](../../FEATURES.md#L296) | Compteur des requêtes Google par jour, semaine et motif | ❌ | `GoogleUsage` est en common, mais aucun compteur visible dans Settings ou les stores de présentation. | PR-1 diagnostics réseau |
| [L297](../../FEATURES.md#L297) | Désactivation des revérifications de trafic en navigation | ⚠️ | Cette version ne revérifie pas le trafic pendant la conduite, donc n'envoie pas la position pour ce motif. L'interrupteur devra accompagner l'arrivée du trafic vivant. | N-2 trafic et confidentialité |
| [L298](../../FEATURES.md#L298) | Clear history global | ⚠️ | Récents et historique parking ont des purges séparées. Aucune action unique et aucun trajet enregistré iOS à purger. | PR-1 historique |
| [L299](../../FEATURES.md#L299) | Localisation facultative, précise pour la navigation | ⚠️ | M1/M2 montrent carte et recherche; `LocationPermission` demande When In Use et le filtre de navigation exige 50 m. Pas de parcours dédié à la précision exacte. | Q-2 permissions iPhone |
| [L300](../../FEATURES.md#L300) | État des liens Google confiés par Android | ➖ | Ce réglage décrit le gestionnaire d'intents Android. Les Universal Links iOS relèvent de DL-1, pas d'un équivalent de cette ligne. | Aucun |

## Look and settings

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L304-L305](../../FEATURES.md#L304-L305) | Thèmes clair, sombre, AMOLED et jour/nuit | ⚠️ | SwiftUI suit le système par défaut. Aucun sélecteur de thème ou comportement jour/nuit dans `SettingsModel`. | I-8b thèmes |
| [L306-L309](../../FEATURES.md#L306-L309) | Apparence indépendante de la carte, styles et palettes | ⚠️ | `MapDefaults` fixe OpenFreeMap Liberty et deux ressources de sprites. Aucun réglage de style ou palette. | I-1b styles de carte |
| [L310-L311](../../FEATURES.md#L310-L311) | Couleurs Material You issues du fond d'écran | ➖ | Le fond d'écran dynamique et Material You sont propres à Android. iOS utilise AccentColor et les couleurs système. | Aucun |
| [L312-L313](../../FEATURES.md#L312-L313) | Police personnalisée et taille d'interface | ⚠️ | Les styles SwiftUI peuvent suivre Dynamic Type, audités par Q-1. Aucun choix Google Sans, fichier de police ou échelle propre à Vela. | Q-2 Dynamic Type et I-8b police |
| [L314](../../FEATURES.md#L314) | Désactivation des transitions et renommage du lanceur | ❌ | `VelaDeterministic` est réservé aux tests. Aucun réglage utilisateur de transitions ou de nom du lanceur. | I-8b apparence |
| [L315](../../FEATURES.md#L315) | Hub de réglages avec recherche | ⚠️ | `SettingsScreen` est un formulaire de langue, unités, horloge et NoGoogle. Pas de hub paginé ni champ de recherche. | PR-1 réglages |
| [L316-L317](../../FEATURES.md#L316-L317) | Chargement vocal au démarrage et rendu de compatibilité | ❌ | La recherche vocale n'existe pas. Le mode de compatibilité des téléphones Android n'a pas d'équivalent actuel sur MapLibre iOS. | VO-1 dictée; compatibilité non retenue |

## Android Auto

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L321-L322](../../FEATURES.md#L321-L322) | Présence dans le lanceur de la voiture | ❌ | Aucune cible CarPlay, scène ou entitlement dans `project.yml`. | CP-1 CarPlay |
| [L323-L324](../../FEATURES.md#L323-L324) | Accueil voiture avec raccourcis et proximité | ❌ | Aucune interface CarPlay; les modèles Saved/Search ne sont pas exposés à une scène voiture. | CP-1 CarPlay |
| [L325-L327](../../FEATURES.md#L325-L327) | Recherche voiture, aperçu et assistant | ❌ | Aucune cible CarPlay ou intent de navigation voiture. | CP-1 CarPlay |
| [L328-L330](../../FEATURES.md#L328-L330) | Écran de conduite voiture et caméra | ❌ | `NavChrome` ne vise que l'iPhone et `project.yml` ne déclare pas CarPlay. | CP-1 CarPlay |
| [L331-L332](../../FEATURES.md#L331-L332) | Conduite libre sur l'écran voiture | ❌ | Ni conduite libre iPhone ni cible CarPlay. | N-3 puis CP-1 |
| [L333-L334](../../FEATURES.md#L333-L334) | Habillages et trafic de la carte voiture | ❌ | Aucun renderer CarPlay et pas de couche trafic de consultation iOS. | I-1b puis CP-1 |
| [L335-L337](../../FEATURES.md#L335-L337) | Commandes vocales, fin, Recentrer, Overview et Pause en voiture | ❌ | Aucune surface CarPlay pour ces commandes. | CP-1 CarPlay |
| [L338](../../FEATURES.md#L338) | Feux et stop sur la carte voiture | ❌ | Ces alertes sont déjà absentes de la carte iPhone et il n'y a pas de cible CarPlay. | I-1b puis CP-1 |
| [L339](../../FEATURES.md#L339) | Alertes caméra, vitesse et fermeture dans la voiture | ❌ | Aucun état d'alerte CarPlay; les alertes correspondantes restent à livrer sur iPhone. | N-2 puis CP-1 |
| [L340-L341](../../FEATURES.md#L340-L341) | Réglages de la voiture | ❌ | Aucune interface ou persistance de réglages CarPlay. | CP-1 CarPlay |
| [L342](../../FEATURES.md#L342) | Trajet partagé entre téléphone et voiture | ❌ | Aucune session CarPlay à synchroniser avec `NavStore`. | CP-1 CarPlay |
| [L343](../../FEATURES.md#L343) | Affichage des virages au combiné d'instruments | ❌ | Aucune intégration CarPlay ou canal de manœuvres secondaire. | CP-1 CarPlay |
| [L344](../../FEATURES.md#L344) | Voiture fonctionnant elle-même sous Android | ➖ | Ce mécanisme Android Automotive n'a pas d'équivalent iOS direct. | Aucun |

## Phones without a touchscreen

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L348](../../FEATURES.md#L348) | D-pad, OK et anneaux de focus sur tous les écrans | ➖ | Le portage ne cible pas les téléphones à D-pad. VoiceOver, clavier complet et Switch Control relèvent d'un audit distinct. | Q-2 clavier et Switch Control |
| [L349-L350](../../FEATURES.md#L349-L350) | Croix directionnelle et raccourcis clavier sur la carte | ➖ | Aucun équivalent D-pad retenu; les gestes MapLibre restent tactiles. | Q-2 clavier et Switch Control |
| [L351](../../FEATURES.md#L351) | Affectation libre des touches de zoom | ➖ | Fonction propre aux appareils à clavier numérique Android, sans équivalent retenu. | Aucun |
| [L352](../../FEATURES.md#L352) | Chemin clavier pour chaque geste | ➖ | Aucune cible D-pad; une couverture Full Keyboard Access reste à mesurer séparément. | Q-2 clavier et Switch Control |
| [L353](../../FEATURES.md#L353) | Guide D-pad Android | ➖ | `docs/dpad.md` documente Android, pas une fonction à reproduire telle quelle sur iOS. | Aucun |

## Updates and install

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L357](../../FEATURES.md#L357) | Pas de Google Play services et localisation du téléphone | ✅ | M1 valide sideload et localisation sur iPhone; `CoreLocationPipeline` utilise Core Location et aucun SDK Google Play n'existe sur iOS. | Q-2 précision GPS iPhone |
| [L358](../../FEATURES.md#L358) | Installation F-Droid, Obtainium ou APK | ➖ | Ces canaux Android n'ont pas d'équivalent. M1 valide à la place une IPA sideloadée; `docs/ios/SIDESTORE.md` décrit la source iOS. | Aucun |
| [L359](../../FEATURES.md#L359) | Vérification quotidienne des releases dans l'app | ➖ | L'updater APK est explicitement hors portage iOS. SideStore gère les mises à jour de la source, sans vérification par Vela. | Aucun |
| [L360](../../FEATURES.md#L360) | Canaux Stable, Nightly et Canary de l'updater Android | ➖ | Aucun updater intégré iOS; les builds de développement sont publiés par le builder. | Aucun |
| [L361-L362](../../FEATURES.md#L361-L362) | Carte de mise à jour et notes après installation | ➖ | Cette interface appartient à l'updater APK non porté. | Aucun |
| [L363](../../FEATURES.md#L363) | About avec version et installateur | ⚠️ | L'IPA contient version et bundle id, vérifiés par `ci-ipa.sh`, mais aucun écran About dans l'app. | PR-1 About |
| [L364](../../FEATURES.md#L364) | Notices du projet sans mise à jour | ⚠️ | `Notice` et la calibration signée sont en common. `MapScreen` ne publie aucune notice visible. | PR-1 notices |
| [L365](../../FEATURES.md#L365) | Soutien et demande de don après une semaine | ❌ | Aucun lien de don ni planification de demande dans l'app iOS. | PR-1 About |

## Recorded trips and diagnostics

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L369-L370](../../FEATURES.md#L369-L370) | Enregistrement, replay, renommage et partage de trajets | ❌ | `TripLog` est en common, mais aucun enregistreur, écran de trajets ou sélection iOS. | DG-1 trajets |
| [L371-L372](../../FEATURES.md#L371-L372) | Partage de trajet nettoyé avec notes techniques | ❌ | `TripScrub` est en common, sans enregistrement ni partage de trajet utilisateur sur iOS. | DG-1 trajets |
| [L373-L374](../../FEATURES.md#L373-L374) | Journal local opt-in et Export debug session | ⚠️ | `OSLogLog` produit des journaux et `ci-ipa.sh` les collecte pour les tests. Aucun réglage Diagnostics ou export utilisateur. | DG-1 diagnostics |
| [L375-L376](../../FEATURES.md#L375-L376) | Sauvegarde de la trace complète dans un dossier choisi | ❌ | Aucun enregistrement de trace ni sélecteur de dossier dans iOS. | DG-1 trajets |
| [L377](../../FEATURES.md#L377) | Redact places in exports | ❌ | Aucun export de trajets ou diagnostics iOS auquel appliquer ce réglage. | DG-1 confidentialité exports |
| [L378](../../FEATURES.md#L378) | Export d'un rapport de plantage | ❌ | Aucun collecteur ou export de crash dans l'app iOS. | DG-1 diagnostics |
| [L379-L380](../../FEATURES.md#L379-L380) | Simulation de conduite et de position en démo | ⚠️ | `LaunchOptions` et les helpers simctl fournissent des fixtures de test et M5 rejoue `sf-market`. Aucun écran de démo utilisateur. | DG-1 démo |
| [L381](../../FEATURES.md#L381) | Trace de fluidité et debug des bâtiments | ❌ | Aucun instrument de navigation ou overlay de debug des bâtiments iOS; les lignes Debug actuelles ne mesurent pas les images. | Q-3 diagnostics performance |

## Not in Vela

Ces cinq lignes décrivent des exclusions communes aux deux plateformes. Elles restent dans la matrice
pour que le contrôle de couverture atteigne bien la fin de `FEATURES.md`; elles ne sont pas des écarts
à fermer.

| Source | Fonction ou groupe | iOS | Preuve et limite | Prochain lot |
|---|---|---|---|---|
| [L387](../../FEATURES.md#L387) | Contribution d'avis, photos ou modifications cartes | ➖ | Exclusion explicite de `FEATURES.md`, liée à l'absence de compte et de serveur. | Aucun |
| [L388](../../FEATURES.md#L388) | Partage de position et d'heures d'arrivée en direct | ➖ | Exclusion explicite de `FEATURES.md`; la Live Activity ne partage aucune position avec d'autres personnes. | Aucun |
| [L389](../../FEATURES.md#L389) | Chronologie des déplacements | ➖ | Exclusion explicite de `FEATURES.md`; aucune timeline iOS n'est prévue. | Aucun |
| [L390](../../FEATURES.md#L390) | Affluence en direct | ➖ | Exclusion explicite de `FEATURES.md`. Seule l'affluence hebdomadaire typique relève de P-2. | Aucun |
| [L391](../../FEATURES.md#L391) | Synchronisation des lieux par compte | ➖ | Exclusion explicite de `FEATURES.md`; l'import/export de fichiers reste le chemin sans compte. | Aucun |
