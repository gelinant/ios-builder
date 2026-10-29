# Trajets enregistrés et diagnostics (DG-1)

Ce lot ajoute deux écrans iOS : les trajets enregistrés, accessibles par le bouton « Recorded
trips » de la carte, et Diagnostics, ouvert depuis l'écran Trajets. Aucun envoi n'est automatique.

## Enregistrement

- Le réglage « Save my trips » est **désactivé par défaut**. Il vit dans l'écran Trajets, pas dans
  Réglages.
- Quand il est actif, chaque navigation lancée depuis l'écran d'itinéraire démarre un fichier. Le
  format est le CSV de `TripLog` en common, identique à Android : `META`, `RP`, `RD`, `M`, les
  fixes horodatés et les notes `K` des décisions de navigation.
- Les fixes sont écrits toutes les cinq secondes environ, par `PlatformFiles.writeTextAtomic` sous
  `Application Support/trips`. Le fichier actif s'appelle `trip_<début>.csv.recording`.
- Une arrivée ou « End » appelle `finishTrip`. Un trajet de moins de cinq fixes est supprimé.
  `discard` existe pour jeter volontairement une capture.
- Une fermeture forcée laisse le fichier `.recording`. Il reste lisible, la liste le marque
  « Partial », et le détail offre « Keep partial trip » pour le convertir en trajet normal. Rien
  n'est jamais réécrit dans un fichier d'un autre trajet.

## Liste et détail

- La liste affiche le libellé, la date, la distance, la durée, l'heure de début et de fin, et le
  nombre de fixes. Aucune coordonnée n'est affichée.
- Le détail montre la ligne enregistrée sur une carte MapLibre statique, avec départ vert et
  arrivée rouge, le profil de vitesse, la vitesse moyenne et maximale, et les arrêts de plus de
  20 s sous 0,6 m/s.
- Renommer passe par `TripLog.renameHeader`, puis une écriture atomique. Supprimer retire les deux
  formes du fichier. Le glissement dans la liste supprime aussi.

## Partage

- Deux sorties seulement : GPX et CSV Vela. Les deux passent d'abord par `TripScrub`, avec un
  rayon de 200, 400 ou 800 m choisi dans le détail. Les extrémités, la destination et l'étiquette
  disparaissent; les notes `K` restent pour tout le trajet.
- Le GPX ne contient que les points nettoyés. Il n'a ni nom de lieu, ni heure absolue : les
  horodatages du fichier nettoyé sont rebasés sur zéro.
- Le nom du fichier partagé vient de la date de départ, jamais du libellé.
- `UIActivityViewController` fait le partage. Aucun envoi automatique, aucun compte, aucun serveur.

## Diagnostics

L'écran Diagnostics affiche en texte monospace :

- version de l'app et du framework VelaCore, version de calibration;
- drapeaux : enregistrement des trajets, NoGoogle, unités, horloge, langue, calibration rafraîchie;
- nombre de requêtes Google au total et le jour même, par type;
- régions et pièces hors ligne installées;
- nombre de sessions de navigation, nombre de trajets enregistrés;
- les dix dernières alertes techniques.

« Export text » écrit le même texte dans un fichier temporaire et le partage. Le texte ne contient
aucune coordonnée, aucun texte saisi, aucun nom de lieu : `VelaDiag.warn` n'accepte que des lignes
techniques, et `DiagnosticsStore` ne lit que des compteurs. Le journal OSLog existant reste
distinct.

## Tests

- JVM (`:ios-shared:jvmTest`) : `TripsStoreTest` couvre le cycle d'enregistrement, le trajet trop
  court, la reprise d'un fichier partiel, renommer et supprimer, le nettoyage des deux extrémités,
  la sortie GPX et l'export de diagnostics sans lieu.
- Simulateur : `TripsUITests` active l'enregistrement, rejoue `sf-market`, termine la navigation,
  ouvre le trajet, vérifie le profil de vitesse et le contrôle de nettoyage, puis ouvre
  Diagnostics. Run complet `dg1-trips-final-20261027-030521-11867` : `TripsUITests` vert en 73 s,
  `trip_fixes` renseigné et `trips_flow=recorded_opened`. Captures : `trips-list.png`,
  `trip-detail.png`, `diagnostics.png`. La suite complète garde des scénarios rouges hors de ce lot
  (Directions, Localisation, Saved, MapSearch, deux mesures Quality), et l'IPA mesure 20 657 812
  octets.

## Limites

- Le compteur de requêtes lit `GoogleUsage`, alimenté côté Android par le client HTTP; sur iOS il
  peut rester à zéro. Les autres compteurs (régions, pièces, sessions, trajets) sont réels.
- Pas de sélection multiple pour partager ou supprimer plusieurs trajets à la fois.
- Le réglage global « Redact places in exports » n'existe pas encore sur iOS; le rayon se choisit
  au partage. TRIP-TRACE ajoute la copie de la trace complète dans un dossier choisi (voir plus
  bas).
- Un trajet plus court que deux fois le rayon choisi ne garde aucun point partageable : le détail
  l'annonce et refuse l'export plutôt que d'envoyer une trace brute.
- Pas de lignes `S` (texte prononcé), `J` (images) ni `B` (batterie) dans les trajets iOS. Les
  notes `K` et les blocs de route sont enregistrés.
- Le rejeu de démonstration est une trace enregistrée rejouée à l'écran, jamais une navigation
  simulée (voir plus bas); le rejeu `sf-market` reste un outil de test.

## TRIP-TRACE : trace complète, dossier et démonstration

### Enregistrement depuis la carte

- Le bouton « Record a drive trace » enregistre un trajet complet sans destination : position,
  vitesse, cap et horodatage de chaque fix, dans le même CSV `TripLog` que la navigation guidée.
  Il écrit sous `Application Support/trips` par `TripsStore`, donc le fichier survit à une
  relance et apparaît dans Trajets, avec la même reprise d'un fichier partiel.
- L'entrée est masquée pendant une navigation guidée, qui enregistre déjà son propre trajet. Si
  une navigation démarre pendant une capture libre, la capture est arrêtée avant que deux
  écrivains ne se disputent le même fichier.
- La carte affiche une pastille « Recording drive » avec la durée, le nombre de fixes, « Stop »
  et « Discard ». « Stop » ouvre la liste des trajets; un trajet de moins de cinq fixes est jeté,
  comme pour la navigation.

### Dossier de traces

- L'écran Trajets propose « Choose folder » et retient le dossier choisi. Chaque trajet terminé y
  est copié sous `vela-trip-<date>-full.csv`, et « Save full trace » refait la copie à la demande.
- Le fichier contient tous les fixes, sans fin ni début coupés, mais applique la règle
  d'expurgation des exports : le libellé du trajet et la destination disparaissent, les blocs de
  route, les noms de rue et les lignes prononcées sont retirés, et les horodatages sont rebasés
  sur le premier fix. Un fichier dans Fichiers peut être lu par n'importe quelle app ouverte par
  l'utilisateur; il ne doit donc nommer aucun lieu ni aucune heure de départ.
- **Ce qu'iOS ne permet pas de retenir.** iOS ne donne pas de chemin inscriptible à l'app : le
  sélecteur rend une URL à portée de sécurité, et seule une empreinte (bookmark) de cette URL
  survit à une relance. Vela ne peut écrire que dans le dossier choisi, pas créer un dossier
  ailleurs, pas choisir la racine d'un fournisseur, et pas écrire en arrière-plan. Si le dossier
  est déplacé ou supprimé, si le fournisseur iCloud se déconnecte, ou si l'autorisation est
  révoquée, l'empreinte devient invalide : la copie échoue et l'écran demande de choisir le
  dossier à nouveau. Le texte sous le sélecteur le dit dans l'app.
- Sans dossier choisi, rien ne sort de Vela : le trajet reste dans la liste et se partage par GPX
  ou CSV expurgé, comme avant.

### Démonstration

- « Replay (demo) » sur un trajet, ou le drapeau de lancement `-VelaDemoReplay latest|<id>`,
  ouvre un écran plein avec la trace, une pastille orange qui avance et un bandeau « Demo replay ».
- Le rejeu suit la chronologie pure de `DemoReplay` (Kotlin, testé sur JVM), à quatre fois la
  vitesse réelle, avec interpolation de la position, de la vitesse, de la distance et du cap.
- Ce n'est jamais du guidage : aucun son, aucun itinéraire, aucune heure d'arrivée, aucune Live
  Activity, aucun appel à `NavStore`. Le bandeau le dit et le bouton « Close » ramène à l'app.

### Tests

- JVM (`:ios-shared:jvmTest`) : `DemoReplayTest` couvre les deux extrémités, l'interpolation, le
  facteur de vitesse, le cap, le clamp et une trace vide. `TripsStoreTest` couvre la copie
  complète expurgée (tous les fixes, aucun lieu, aucun nom de rue), l'annonce unique d'un trajet
  gardé et la purge.
- Simulateur : `TripsUITests.testFullTraceAndDemoMode` enregistre `sf-market`, ouvre la trace sur
  la carte, vérifie le texte des limites du dossier, lance le rejeu de démonstration, prouve que
  la pastille avance et prend `trip-trace-map.png` et `trip-demo-replay.png`.
- Run Mac `trip-trace-20261028-141500-14306` : `STATUS ok`, 487 tests JVM et 391 tests Kotlin
  simulateur sans échec, 151 tests Xcode sans échec, `TripsUITests.testFullTraceAndDemoMode` vert
  en 129,8 s et `TripsUITests.testRecordDriveAndOpenTrip` vert en 122,2 s. Les deux captures sont
  dans les résultats du run; le résumé affiche `trips_flow=full_trace_map_demo_replay`.
