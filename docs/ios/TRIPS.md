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
- Pas de copie de la trace complète dans un dossier choisi, ni de réglage global « Redact places
  in exports »; le rayon se choisit au partage.
- Un trajet plus court que deux fois le rayon choisi ne garde aucun point partageable : le détail
  l'annonce et refuse l'export plutôt que d'envoyer une trace brute.
- Pas de lignes `S` (texte prononcé), `J` (images) ni `B` (batterie) dans les trajets iOS. Les
  notes `K` et les blocs de route sont enregistrés.
- Pas de rendu de démonstration « Simulate driving » dans l'interface utilisateur; le rejeu
  `sf-market` reste un outil de test.
