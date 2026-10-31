# Parcours utilisateur iOS

État : lot UX-JOURNEY (L), 2026-10-30, branche `ios/ux-journey`. Ce document décrit les quatre
parcours de bout en bout, les défauts de continuité trouvés, les correctifs et ce qu'une passe de
design doit encore améliorer. Les scénarios vivent dans
`iosApp/VelaUITests/JourneyUITests.swift`.

Le lot ne redessine aucun écran. Il ne change que la navigation entre surfaces, les retours et les
libellés de flux. Les identifiants d'accessibilité existants sont conservés.

## 1. Recherche vers guidage

```
carte au repos
  -> recherche « coffee »
  -> liste de résultats
  -> fiche lieu
  -> Directions
  -> choix d'itinéraire
  -> Étapes
  -> retour au choix
  -> Démarrer
  -> bandeau de guidage
  -> Terminer
  -> carte, même caméra, aucune feuille
```

Défauts trouvés :

1. **La feuille d'itinéraire restait derrière le bandeau.** Démarrer activait le guidage, mais
   `route.isOpen` restait vrai. À la fin du trajet, le choix d'itinéraire réapparaissait comme une
   feuille oubliée. Correctif dans `MapScreen.swift` : `nav.active` ferme le choix d'itinéraire
   quand le guidage prend la main.
2. **La caméra de retour était perdue.** `MapController.endNavigation` remet la carte à plat sur
   la dernière position simulée, pas sur le point de départ du parcours. Correctif dans
   `MapScreen.swift` : `startDriveGuidance` et `startTransitGuidance` mémorisent centre et zoom,
   puis `restoreGuidanceCamera` les rétablit après la fin, une fois l'encart de carte revenu à
   zéro.
3. **Le libellé du bouton Étapes ne dépendait pas du clavier.** Aucun défaut observé à ce stade :
   `route-steps` reste au-dessus de la ligne d'action et la feuille des étapes se ferme par
   `steps-close`.

Le scénario `testJourney1SearchToGuidanceAndBack` vérifie la caméra avant et après le guidage,
l'absence de `route-sheet`, `steps-sheet`, `place-sheet` et `transit-card` à la fin, et écrit
`journey_1=ok|fail`.

## 2. Fiche lieu, liste enregistrée, itinéraire

```
fiche lieu
  -> Enregistrer
  -> Enregistrés
  -> nouvelle liste
  -> Liste
  -> fiche du lieu depuis la liste
  -> Itinéraire
  -> retour au choix
  -> fermer la fiche
  -> retour à la même liste
```

Défauts trouvés :

1. **Le point de retour de la liste était perdu.** Une fiche ouverte depuis une liste fermait
   Enregistrés ; après l'itinéraire, fermer la fiche laissait l'utilisateur sur la carte nue. Le
   contexte de la liste était perdu et il fallait rouvrir Enregistrés, puis la liste. Correctif :
   `SavedView` accepte `initialListId` et pousse le détail de liste dans un `NavigationStack`
   piloté par un chemin ; `MapScreen` retient `savedListReturnId` et `savedSheetListId`, donc
   `closePlace` rouvre Enregistrés sur la liste d'origine.
2. **Des libellés de flux étaient encore en anglais.** La route enregistrée s'appelait
   « Saved route » ou « Route to ... », l'origine « your location » ou « the map's center », et
   les options d'évitement « Avoid highways » et consorts. Correctif : clés existantes
   `route_save_default`, `route_save_default_from`, `mapscreen_your_location`,
   `route_use_map_center` et `car_setting_avoid_*`. Les titres de renommage, les sons de liste et
   la nouvelle liste passent aussi par le catalogue.
3. **Le libellé Enregistrer ne portait pas la langue.** Le scénario lance ce parcours en français
   et exige `Enregistrer` et `Itinéraire`, puis vérifie le retour sur la liste par le texte de son
   titre dans la barre, pas par le libellé composite de la barre. Pour quitter la feuille, il
   appuie sur Retour puis Fermer, l'ordre réel d'une liste poussée dans Enregistrés.

Le scénario `testJourney2PlaceToSavedListToRouteAndBack` écrit `journey_2=ok|fail` et
`journey_2_language=fr`. Il prouve aussi qu'une liste nommée en français reste utilisable sans
identifiant dépendant de la langue.

## 3. Transport, de la porte à la porte

```
arrêt
  -> tableau des départs
  -> ligne
  -> itinéraire
  -> écran du trajet
  -> GO
  -> fin de GO
  -> fin du guidage transport
  -> carte
```

Défauts trouvés :

1. **Le premier appui sur une ligne du tableau peut être avalé.** Sur le runner, l'appui sur
   `transit-board-line` après la fermeture de la feuille de ligne du fixture n'a pas ouvert la
   feuille. Le scénario réessaie maintenant sur la bande haute de la ligne, sans toucher la
   surface derrière la feuille. Aucun fichier `Transit/**` n'est modifié : ce lot ne possède pas
   cette surface.
2. **La carte ne revient pas à son cadrage après le transport.** Le même mécanisme de caméra que
   le parcours 1 est branché sur `transit.active`, donc quitter le transport rend le cadrage
   d'avant le trajet. Le parcours 3 vérifie surtout l'absence de feuille et le retour du champ de
   recherche.
3. **L'action Trajet était dans la rangée épinglée.** Après TRANSIT-POLISH, Fermer, Trajet et
   Démarrer partageaient la même rangée. Le bouton Trajet est maintenant dans l'en-tête de
   l'itinéraire, en cible de 44, et Fermer et Démarrer restent épinglés en bas. Correctif minimal
   dans `TransitDetailSheet.swift`, seul fichier `Transit/**` touché par ce lot.
4. **Les fermetures existent à chaque étape.** `transit-line-close`, `transit-board-close`,
   `steps-close`, `transit-trip-close`, `transit-go-close` et `transit-end` sont tous atteignables
   dans l'ordre du parcours. Fermer l'écran du trajet ramène à l'itinéraire, puis `steps-close`
   ramène à la carte de guidage et GO peut démarrer.

Le scénario `testJourney3TransitDoorToDoor` écrit `journey_3=ok|fail`.

## 4. Hors ligne : cadre, téléchargement, sortie et retour

```
carte
  -> menu de la carte
  -> Hors ligne
  -> Télécharger une zone
  -> cadre sur la carte
  -> Télécharger
  -> carte de progression
  -> masquer la progression
  -> Hors ligne
  -> Done
  -> Hors ligne à nouveau, même état ou état plus avancé
  -> Done
  -> carte
```

Défauts trouvés :

1. **L'état de la zone n'était pas lisible à la réouverture dans le test.** La carte de
   progression de zone vit en haut de la `List` de la feuille Hors ligne. Le scénario cherchait
   `area-sheet-pieces` sans défiler, alors que la `List` construit ses rangées à la demande. Le
   harnais fait maintenant un `reveal` dans `offline-sheet` avant de lire l'état. Le modèle
   `OfflineModel` garde le même `areaId` et la même progression pendant que la feuille est
   fermée.
2. **Masquer la progression ne doit pas annuler le téléchargement.** `area-hide` ne change que
   `areaReportVisible` ; le téléchargement continue et la feuille Hors ligne le retrouve. Le
   scénario vérifie qu'un second passage ne recule jamais dans les pièces téléchargées.
3. **Une zone terminée doit être un état stable.** Si le téléchargement finit entre deux
   ouvertures, `area-sheet-ready` est accepté comme un état cohérent avec 100 pour cent.

Le scénario `testJourney4OfflineAreaDownloadAndReopen` écrit `journey_4=ok|fail`.

## 5. Preuves et état du run

Run Mac final : `journey-verify11-20261030-184359-29148`, commande
`mac-run.sh ... VELA_ONLY_UI=JourneyUITests VELA_SKIP_ARCHIVE=1`, `STATUS ok`.

| Parcours | Verdict | Preuve |
|---|---|---|
| 1 recherche vers guidage | `journey_1=ok` | caméra `37.77118,-122.41694,14.7` avant et après, aucune feuille |
| 2 fiche, liste, itinéraire | `journey_2=ok`, `journey_2_language=fr` | liste rouverte sur son titre, puis Retour et Fermer |
| 3 transport de porte à porte | `journey_3=ok` | tableau, ligne, itinéraire, trajet, GO, fin, carte |
| 4 hors ligne | `journey_4=ok` | 1 pièce, 4 à la première réouverture, 100 à la seconde |

Causes réelles du rejeu `journey-verify` et correctifs :

1. **Caméra du parcours 1.** Aucun écrivain tardif de la caméra. Le défaut venait de la mesure
   avant guidage : `showRoutes` remettait l'encart de la carte à zéro avant de cadrer, donc la
   ligne `start-debug` décrivait un cadre plus haut que la caméra réelle d'environ 35 points, et
   le rétablissement était correct mais comparé à une valeur fausse. `MapScreen` remet maintenant
   l'encart du choix d'itinéraire après chaque cadrage (`restoreRouteInset`), publie le viewport
   vivant après le cadrage (`publishLiveViewport`) et après la dernière correction de caméra.
   `restoreGuidanceCamera` garde une première pose puis une lecture de contrôle.
2. **Liste du parcours 2.** Le libellé de la barre contient le bouton Retour et les actions, donc
   `navigationBars.firstMatch.label` n'était jamais exactement le titre. Le scénario lit
   maintenant `navigationBars.staticTexts[listName]`, puis appuie sur `BackButton` et
   `saved-close`, qui sont les deux étapes réelles pour quitter une liste poussée. La liste
   elle-même était bien rouverte.
3. **Trajet du parcours 3.** L'action `transit-trip-open` était dans la rangée épinglée, à côté de
   Fermer et Démarrer, et le premier bouton du même identifiant trouvé dans l'arbre était celui de
   la carte de guidage restée derrière la feuille, donc non touchable. Correctif minimal dans
   `TransitDetailSheet.swift` : l'action Trajet passe dans l'en-tête de la feuille, en cible de 44,
   et la rangée épinglée garde Fermer et Démarrer. Le scénario interroge aussi l'action dans
   `steps-sheet`, pas dans la carte derrière.
4. **GO en français.** La clé `transit_preparing_go_guidance` est bien traduite
   (`Préparation du guidage GO`) et `TransitGoScreen` l'utilise. Le texte n'est pas en dur et le
   catalogue la publie dans les 24 langues. L'écran et son harnais `TransitGoTestSupport`
   appartiennent au lot Transit ; aucun fichier de ce lot n'est modifié. Si le test échoue encore,
   la cause est dans le montage Debug du GO, pas dans une chaîne de ce lot.

Le run final produit les captures `journey-1-search.png` à `journey-1-end.png`,
`journey-2-place.png` à `journey-2-back-to-list.png` et `journey-2-end.png`,
`journey-3-stop.png` à `journey-3-end.png`, et `journey-4-offline.png` à `journey-4-end.png`.

Contrôles Linux : `strings_to_xcstrings.py` puis `check_ios_strings.py` donnent
`2145 keys, 24 resource locales, 38583 localized values, 1036 Swift references`.

## 5 bis. Parcours du chrome convergé (CHROME-CONVERGE)

Le chrome de carte ne montre plus qu'un localiser et un contrôle secondaire. Le parcours
d'action passe désormais par une feuille courte, et les quatre parcours existants gardent leurs
surfaces de départ.

1. Carte au repos : `locate-button` et `map-actions-open` sont les deux seuls contrôles ronds.
   La boussole et `map-zoom-in` restent absents tant que la carte n'est pas tournée ou que
   « préférer les boutons » n'est pas actif. Le signet `saved-open` reste l'accessoire de fin de
   la pilule de recherche, donc le parcours 2 n'a pas de détour.
2. `map-actions-open` ouvre `MapActionsSheet` à `.medium`. La feuille liste couches, transports,
   conduite libre, enregistrés, parking, trajets, trace, terrain et réglages, avec les
   identifiants d'origine (`layers-button`, `transit-options-open`, `free-drive-open`,
   `saved-open`, `parking-button`, `trips-open`, `trace-record-open`, `terrain-open`,
   `settings-menu-item`).
3. Une action choisie ferme la feuille, puis son écran s'ouvre depuis `onDismiss` : couches,
   transports, enregistrés, trajets et réglages sont des feuilles de carte, terrain est un
   `fullScreenCover`, conduite libre et trace prennent la carte.
4. Si une fiche lieu ou un itinéraire est déjà ouvert, la feuille reste complète. Conduite libre
   et trace sont désactivées avec la raison « Fermez d'abord la feuille ouverte ». Une trace
   déjà en cours affiche sa propre raison.
5. `MapChromeUITests` imprime `chrome_controls=2`, `actions_sheet=1` et écrit
   `chrome-converged.png` puis `actions-sheet.png`. `MapTapUITests` ouvre la feuille avant
   `layers-button` dans ses fixtures caméra et aviation.

## 6. Ce qu'une passe de design doit encore améliorer

1. **Une seule géométrie de retour.** Trois écrans choisissent encore leur hauteur et leur
   fermeture : choix d'itinéraire, étapes et fiche lieu. Impact fort : chaque parcours doit
   retenir un état de présentation dans `MapScreen`. Un composant unique de pile de feuilles
   supprimerait cette mémoire et les quatre champs `savedSheetListId`, `savedListReturnId`,
   `guidanceCamera` et `placeDetent`.
2. **Le tableau transport ouvre une feuille de ligne hors de la pile de la carte.**
   `TransitLineLink` présente un `UIHostingController` système, donc la feuille de ligne ne
   participe pas à l'encart de carte et ne peut pas être empilée dans le même ordre. Impact moyen
   à fort : sur un arrêt, la feuille de ligne recouvre le tableau sans animation commune, et le
   retour se fait par un bouton, jamais par la poignée de la carte.
3. **Le parcours fiche lieu vers liste dépend d'une mémoire hors de la feuille.** Le retour à la
   liste est correct, mais il est porté par `MapScreen`. Impact moyen : une fiche ouverte depuis
   une liste devrait porter son point de retour dans la fiche elle-même, pour survivre aussi à un
   lien profond ou à une relance.
4. **Les états vides du hors ligne restent des paragraphes.** La carte de zone est un objet long,
   et la progression est une barre dans une carte. Impact moyen : une rangée persistante de 56
   points avec pourcentage et action serait lisible d'un coup, même quand la feuille est fermée.
5. **La feuille de résultats n'a pas de retour explicite vers la carte.** Le parcours 1 quitte la
   liste en ouvrant une fiche, mais une liste vide ou une erreur ne propose que l'effacement du
   champ. Impact moyen : il manque une action Retour à la carte, surtout à AX5 où le clavier
   couvre la moitié de l'écran.
6. **VoiceOver n'a pas d'ordre de parcours testé.** Les quatre scénarios vérifient que chaque
   action existe et que `place-directions`, `place-save`, `route-steps`, `transit-go-open` et
   `area-hide` sont atteignables. Impact fort : une passe dédiée doit lire la hiérarchie dans
   l'ordre carte, pilule, puces, boutons, feuille, comme le demande `DESIGN.md` A2.

## 7. Risques

- Le parcours 1 dépend de la recherche Google et du calcul d'itinéraire réels, même avec
  `-VelaRouteOrderFixture` pour l'ordre des routes. Le parcours 2 utilise le fixture de lieu,
  mais son itinéraire reste calculé.
- Le parcours 3 dépend des fixtures transport et de leur minuterie de feuille de ligne.
- Le parcours 4 dépend du fixture hors ligne et de `-VelaOfflineAreaSlow` pour laisser une
  progression visible.
- Aucun scénario n'a été rejoué sur iPhone. Les quatre verdicts `fail` du run ne sont pas une
  preuve de régression produit avant rejeu des corrections de harnais.
