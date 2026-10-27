# Parité iOS / Android : état et reste

État au 2026-10-26, sur `ios/main` au commit `3c628f48`. La matrice couvre les lots mergés N-2,
O-2, X-2, I-2b, N-3, I-1b, DL-1, R-1, T-1, L-1, Q-2 et S-0. Ce document distingue la V1
quotidienne de la parité Android complète. Une case « fait sur simulateur » ne vaut pas validation
sur iPhone ou en conduite.

## Mesure ligne par ligne

La référence est désormais [FEATURES-IOS.md](FEATURES-IOS.md). Elle reprend chaque puce de
`FEATURES.md`, son statut, sa preuve et le lot qui doit fermer l'écart. Sa synthèse est calculée par
le script, jamais saisie à la main :

```
python3 scripts/ios/parity_check.py --md
python3 scripts/ios/parity_check.py --check
python3 scripts/ios/test_parity_check.py
```

Le contrôle refuse une ligne source manquante ou déplacée, un statut inconnu et une synthèse
périmée. Les pourcentages comptent des puces de fonctions, pas leur complexité ni leur importance.
Les anciennes estimations globales de 55 à 65 % pour V1 et 25 à 35 % pour la parité sont donc
retirées.

## V1 : périmètre et preuves actuels

La V1 reste celle de `PORTAGE_IOS.md` : carte, recherche, fiche lieu, itinéraires, navigation avec
voix, lieux enregistrés, régions hors ligne avec carte et recherche, réglages essentiels. Le routage
hors ligne `.obf`, CarPlay, Street View interactif, les voix neurales et la dictée restent hors V1.

| Domaine | Preuve actuelle | Reste avant de fermer la V1 |
|---|---|---|
| Carte et recherche | M1/M2 sur iPhone ; N1 : suggestions, catégories et toucher POI sur simulateur ; I-1b : panneau de couches, POI par catégorie, densité, marques peintes, caméras, contrôles, carburant UK et ponts NL (`MAP-LAYERS.md`) ; I-2b : adresse et déduplication au run `i2b-search-addresses-20261026-151138-5519` | Validation iPhone des adresses, de la fusion, des couches et de la densité. Les styles alternatifs, le trafic et le satellite Google restent hors build. |
| Fiche lieu | N1 pour détails, horaires, photos, avis, appel et site ; P1 pour 20 photos ; Q-2 pour les libellés de photos, d'avis et d'affluence et les cibles de 44 points | Rejouer le scénario complet au commit mergé, vérifier galerie et panneau d'avis, affluence sur IP résidentielle, captures manquantes et validation iPhone. Le scénario Q-2 échoue encore après le retour de la grille. |
| Itinéraires | M4 : alternatives, voiture, marche, étapes hybrides et Transitous ; R-1 au run `r1-route-options-20261026-155652-14395` : origine, jusqu'à 10 arrêts, départ et arrivée à une heure ; T-1 : options d'heure et de véhicule, tableau d'arrêt, détail avec alertes (`t1-transit-20261026-184331-24518`) ; L-1 : ligne enregistrée réutilisable | Vélo et NoGoogle de bout en bout, arrêts pendant le guidage, validation iPhone des options, du tableau, du détail et de la ligne enregistrée |
| Navigation | M5 : guidage, voix, caméra, recalcul, arrière-plan déclaré ; X1 pour ActivityKit ; N-2 : vitesse et limitation OSM, alertes Overpass et offre de route plus rapide, avec tests JVM et scénario UI à rejouer ; N-3 : pause et reprise, perte de GPS avec estimation de tunnel bornée, cycle de vie et audio | Conduite réelle, DeFlock et données routières précalculées, rejeu de `NavAlertsUITests`, preuves UI des alertes et des arrêts, tunnel, appel, Bluetooth et verrouillage sur iPhone |
| Lieux enregistrés | I6 : Save, listes, récents et persistance ; L-1 : raccourcis Maison/Travail, ligne enregistrée, partage de liste et Takeout (`l1-saved-polish-20261026-181057-20440`) ; S-0 : écriture synchrone des récents et test Spotlight qui vérifie l'émission des requêtes | Rejouer `SavedUITests` et `IntentsUITests` après S-0, import par le sélecteur et raccourcis sur iPhone, quick saves à exporter, parking Find my car |
| Hors ligne | I7 : Monaco, carte sans URL distante et 30 résultats NoGoogle ; O-2 : téléchargements en arrière-plan, reprise après relance et noms de rues PMTiles locaux, avec scénario de relance à rejouer | Deltas, cellules et petit zoom monde, erreurs d'espace, validation en mode avion et en arrière-plan sur iPhone |
| Réglages et langues | I8 : langue, unités, horloge et NoGoogle ; français et allemand sur simulateur ; Q-2 : hébreu RTL dans la recherche et les réglages, catégories rapides localisées, cibles de 44 points et Dynamic Type jusqu'à AX5, au run `q2-accessibility-20261026-183637-14215` | Traductions des nouvelles vues, CJK, trois corrections de harnais Q-2 à rejouer, consentement et réglages de confidentialité essentiels, validation iPhone |
| Qualité | Q-1 ajoute la matrice, l'audit Dynamic Type/RTL/paysage et les métriques XCTest ; Q-2 corrige les cibles, les libellés et les grands textes, avec les mesures dans `QUALITY.md` | Rejouer les trois corrections de harnais Q-2, petit écran, mémoire sur iPhone, batterie et GPU de la page cachée |

Le run L-1 `l1-saved-polish-20261026-181057-20440` réussit les trois scénarios du lot et 34 des 36
scénarios UI. Il ne constitue pas une suite verte : le fixture Spotlight ne s'indexe pas et le
scénario Saved existant ne retrouve pas les récents après relance. S-0 corrige ensuite l'écriture
des récents et fait vérifier au test Spotlight l'émission réelle des requêtes, le démon du
simulateur pouvant ne pas répondre. Aucun run de suite n'a été publié après S-0, donc ces deux
corrections restent à prouver par un run vert.

La V1 n'est pas encore déclarée stabilisée. Il faut au minimum un run vert de la fiche complète, un
run de suite après S-0, le rejeu des trois corrections de harnais Q-2 et de `NavAlertsUITests`, les
limites ci-dessous acceptées, et une passe humaine sur chaque fonction principale. Les durées et le
nombre de lots ne sont pas garantis par ces documents.

## Limites assumées de la V1

- Pas de backend de push Vela. La Live Activity transports se met à jour quand l'app est active;
  elle ne promet pas une actualisation minute par minute après une fermeture forcée.
- Pas d'entitlement CarPlay. La navigation voiture d'Android Auto n'a pas d'équivalent iOS dans ce
  build.
- Pas de routage hors ligne `.obf`. Les régions installées fournissent carte, lieux, adresses et
  recherche, pas un itinéraire calculé localement.
- Trafic et satellite Google absents. Leurs URL de tuiles vivent dans le module Android `:app`;
  `LayersView` affiche `Not in this build`. Seuls les tronçons de trafic d'un itinéraire sont
  dessinés, avec les données de Google Directions.
- Ferry non supporté par Transitous. `Transitous.plan` n'accepte que bus, subway, rail et tram, et
  « Last available » n'existe pas dans l'endpoint public.
- Arrêts pendant le guidage absents. R-1 planifie jusqu'à dix arrêts, mais leur ajout ou leur
  modification en conduite et le toucher d'un lieu pour l'ajouter restent hors build. Un lien
  d'itinéraire Google qui porte des arrêts est refusé explicitement.
- Liens `https` non interceptés. iOS ne permet pas à une app de s'inscrire pour `http` ou `https`
  sans Universal Links et fichier AASA hébergé par Google. Les chemins réels sont `vela://`,
  `geo:`, le collage d'une URL et une action Raccourcis; un lien court `maps.app.goo.gl` se résout
  quand il est ouvert par Vela, pas automatiquement depuis Safari ou Messages.


## Écarts encore suivis

- Q-2 : trois corrections de harnais attendent un cinquième run, soit l'assertion de position du
  toggle hébreu, la recherche de `route-scroll` parmi tous les types XCUI et la mesure de la photo
  avant l'ouverture de la grille. Le budget de quatre runs est atteint et ces trois scénarios
  restent rouges.
- S-0 : l'écriture des récents et le test Spotlight sont corrigés, mais aucun run de suite après
  S-0 n'est publié. `SavedUITests` et `IntentsUITests` doivent être rejoués avant de compter ces
  deux écarts comme fermés.
- Le run Q-1 `q1-parity-quality-20261025-221617-24690` a 100 tests JVM, 79 tests simulateur et 34
  tests Swift verts, mais `PlaceUITests.testCompleteFixturePlace` échoue après 69 s. Le bouton
  `place-photo-categories` reste non hittable à `PlaceUITests.swift:46`. Les 10 photos RPC arrivent,
  mais le scénario ne produit ni galerie complète ni panneau d'avis. P-1 reste donc non validé.
- Le run précédent `p1-place-complete-20261025-205542-12434` avait obtenu 10 puis 20 photos et
  `place-gallery-grid.png`, avec `place_gallery_categories=0`, avant un échec à la visionneuse. Le
  passage de 10 à 20 photos est une preuve conservée, pas une réussite du scénario complet.
- Le repli d'affluence est parsé, sans horaires fournies par Google sur l'IP du runner. Aucun
  graphique ne doit être fabriqué pour combler cette absence.
- Le run `p1-place-complete-20261025-194645-27708` mesure 5 avatars décodés dont 5 non noirs. Le test
  synthétique PNG sRGB passe aussi.
- Avant de marquer la galerie et le panneau 🟡, il faut un run complet vert au commit mergé, les
  captures de catégories, visionneuse et avis, puis une validation sur iPhone et IP résidentielle.

## Fonctions spécifiques iOS

X-1 fournit une Live Activity conduite/marche, testée sur simulateur dans
`x1-live-activity-20261025-193904-23245`. X-3 ajoute le guidage Transitous et sa Live Activity dans
`x3-transit-activity-20261026-010530-6408`. T-1 ajoute les tableaux de départs, les options de
recherche transport et le détail d'itinéraire, documentés dans [TRANSIT.md](TRANSIT.md). X-2 ajoute
App Intents, Siri et Spotlight. S-0 rend l'écriture des récents synchrone et fait vérifier au test
Spotlight l'émission réelle des requêtes, sans dépendre du démon du simulateur. DG-1 ajoute les
trajets enregistrés et l'écran Diagnostics, documentés dans [TRIPS.md](TRIPS.md) : l'enregistrement
est opt-in, le partage passe toujours par `TripScrub`, et l'export de diagnostics ne contient ni
coordonnée, ni texte saisi, ni nom de lieu. Les rendus de l'écran verrouillé et de la Dynamic
Island, ainsi que Siri et les tuiles système, restent à valider sur iPhone. Widgets et CarPlay
restent ultérieurs ; aucune surface ne doit promettre un temps réel que l'absence de push ou
l'entitlement ne permet pas.

Le run complet `dg1-trips-final-20261027-030521-11867` fait passer `TripsUITests` (enregistrement
d'un rejeu `sf-market`, liste, détail avec profil de vitesse, Diagnostics) et conserve les
captures `trips-list.png`, `trip-detail.png` et `diagnostics.png`. Des scénarios hors du lot
restent rouges dans ce run : Directions, trois Localisation, deux Saved, deux SavedFinishing,
MapSearch et deux mesures Quality.

## Fonctions spécifiques iOS proposées

| Fonction | Contenu | Prérequis et limites | Estimation |
|---|---|---|---|
| 🟡 **Live Activity conduite et marche** | X-1 présent : prochaine manœuvre, rue, distances, ETA, recalcul et progression sur écran verrouillé et Dynamic Island | ActivityKit, `NSSupportsLiveActivities`. L'activité affiche l'état, elle ne fait pas tourner le GPS : la navigation doit vivre en arrière-plan avec la localisation. Rendu et sideload à valider sur iPhone, voir `LIVE-ACTIVITY.md` | Implémenté, validation iPhone requise |
| 🟡 **Live Activity transports** | X-3 présent : ligne, direction, arrêt de descente, heures prévues et retard, marche jusqu'à l'arrêt | `TransitSession`. Sans serveur de push Vela, pas de mises à jour minute par minute app tuée : rafraîchissement quand l'app est active, pas de force-quit. Voir `TRANSIT-ACTIVITY.md` | Implémenté, validation iPhone requise |
| 🟡 **App Intents / Siri / raccourcis** | X-2 présent : Maison, Travail, voiture, recherche libre et lieu enregistré, avec ouverture du choix d'itinéraire | Phrases anglaises et françaises dans `AppShortcuts.strings`, erreurs qui ouvrent Saved. Routeur et scénarios testés sur simulateur, mais Siri et les tuiles système restent à vérifier sur iPhone, voir `INTENTS.md` | Implémenté, validation iPhone requise |
| 🟡 **Spotlight** | X-2 présent : lieux enregistrés, éléments de listes, Maison, Travail et stationnement, ouverture par le routeur. S-0 vérifie que les requêtes d'ajout et de suppression sont réellement émises dans le même processus | CSSearchableIndex local synchronisé avec les stores. Les récents et l'historique sont exclus par confidentialité. Le démon Spotlight du simulateur peut différer ou perdre une requête; la présentation système reste à vérifier sur iPhone | Implémenté, validation iPhone requise |
| **Widgets** | Maison/Travail, parking, prochain départ transport | Timeline limitée : les horaires ne sont pas du temps réel garanti | 2 à 4 jours par widget |
| **CarPlay** | Carte, recherche, guidage | Entitlement Apple navigation, plus gros travail qu'une Live Activity | 1 à 2 semaines après V1 |
| **Apple Watch** | Manœuvre et ETA | Optionnel, pas dans la V1 | À cadrer plus tard |

Priorité recommandée après la V1 stabilisée : rejouer et valider sur iPhone les surfaces déjà
livrées (Live Activity, App Intents, Spotlight), puis les widgets et CarPlay. Les voix neurales et la
dictée viennent ensuite.

## Règle de suivi

Chaque lot qui change une fonction met à jour la ligne concernée de `FEATURES-IOS.md`, sa preuve et
le lot suivant dans le même commit. ✅ exige une preuve iPhone ; 🟡 exige un scénario simulateur ;
⚠️ décrit la limite fonctionnelle ou de preuve ; ❌ ne laisse pas croire qu'un parseur isolé est une
fonction accessible. Les défauts et mesures qualité sont conservés dans [QUALITY.md](QUALITY.md).
