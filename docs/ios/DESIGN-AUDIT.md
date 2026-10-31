# Audit design et plan de migration (UX-GOOGLE-MAPS)

État : 2026-10-28, branche `ios/ux-google`, depuis `ios/main` (`f1320d6a`). Compagnon de
[DESIGN.md](DESIGN.md), qui porte les principes, les jetons et les règles d'accessibilité. Ce
document-ci porte l'état réel des écrans, les écarts avec la cible, le coût et l'ordre des
vagues. Il ne modifie aucun fichier de vue.

Méthode : lecture du code SwiftUI, des documents `MAP-LAYERS.md`, `PLACE.md`, `SEARCH.md`,
`SETTINGS.md`, et des captures existantes (Q-2, Q-3, MAP-STYLE, RTE-SHEET). Chaque constat cite
le fichier et la ligne où le comportement vit aujourd'hui.

Échelle de coût : **S** = 1 session, **M** = 2 à 3 sessions, **L** = 4 sessions ou plus. Une
session est une unité de travail d'un agent, build et vérification compris. Les totaux incluent
la revue et les captures, pas les allers-retours de coordinateur.

## 1. Synthèse

| Surface | Fichier principal | État actuel | Cible | Coût | Vague |
|---|---|---|---|---|---|
| Chrome de carte | `MapScreen.swift` | 2 boutons persistants, feuille d'actions courte | 2 boutons au repos, le reste dans une feuille, chrome qui suit la feuille | L (4) | 2, livré |
| Champ de recherche | `SearchViews.swift` | pilule 48 dans une rangée de 12 | pilule 56, marge 16, menu et micro hiérarchisés | S (1) | 1 |
| Liste de résultats | `SearchViews.swift` | carte flottante de 340 de haut | feuille bord à bord, 0,42 et 0,85 | M (2) | 1 et 2 |
| Fiche lieu, en-tête | `PlaceSheet.swift` | titre puis texte, pas de photo | photo 152, titre, note, 3 actions | L (4) | 3, livré |
| Fiche lieu, onglets | `PlaceSheet.swift` | pastilles de 44 teintées | texte et soulignement de 3 | S (inclus) | 3, livré |
| Fiche lieu, actions | `PlaceSheet.swift` | 6 à 7 boutons de même poids | 1 plein, 2 contour, le reste défilant | S (inclus) | 3, livré |
| Avis | `PlaceSheet.swift` | liste plate, sans en-tête collant | résumé, barres, tri, lignes 17 | M (2) | 3, livré |
| Choix d'itinéraire | `RouteSheets.swift` | 0,50 / 0,85, modes blancs sur accent | détents, modes lisibles, actions fixes | M (3) | 3 |
| Transports | `TransitBoardSheet.swift`, `TransitTripScreen.swift` | 3 chromes différents, plafond AX3 | une feuille, une échelle, pas de plafond | M (3) | 3 |
| Réglages | `SettingsScreen.swift` | `Form` natif, titre maison | `Form` gardé, rythme et en-tête aux jetons | M (2) | 1, livré |
| À propos | `SettingsAboutView.swift` | `Form` de recherche | hub gardé, sections et lignes aux jetons | S (1) | 1, livré |
| Hors ligne | `OfflineSheet.swift` | `List` de feuille système | feuille haute, cartes de région, stockage | M (2) | 1, livré |
| États vides et chargement | transverse | longues phrases en anglais | une ligne calme, localisée, à 24 | S (inclus) | 1 à 3 |

Total : 28 sessions, dont 1 pour ce lot, 8 en vague 1, 4 en vague 2, 12 en vague 3 et 3 en
validation.

## 2. Audit écran par écran

### 2.1 Chrome de carte

**Ce qui existe.** `MapScreen.swift` empile la pilule, le debug, les boutons, le panneau
bas et l'attribution dans une `VStack`. La pilule a 48 de haut, 16 d'encart interne et une capsule
en matériau avec une ombre noire à 20 % (`SearchViews.swift:41-64`). Le signet Enregistrés reste
l'accessoire de fin de pilule, sans pastille ronde. La colonne de droite ne garde que deux
contrôles persistants : la feuille d'actions (`square.grid.2x2`, `map-actions-open`) et localiser
(`locate-button`). La boussole et la paire de zoom n'apparaissent que si la carte est tournée ou si
« préférer les boutons » est actif. Les anciens boutons ronds (couches, transports, conduite libre,
parking, trajets, trace, terrain, réglages) vivent dans `MapActionsSheet`, avec leurs identifiants
d'origine. La rangée de puces fait 44 de haut (`SearchPanels.swift:67-118`). Les résultats sont
dessinés avec un encart fixe de 140 / 40 / 420 / 40 (`MapScreen.swift:333`).

**Ce que fait Google Maps.** Une seule pilule de recherche en haut, avec un contrôle à gauche et
le micro à droite ; une rangée de puces sous la pilule ; deux ou trois contrôles ronds sur le bord
droit (couches, boussole, localiser), le reste contextuel ; l'attribution en bas à gauche. La
carte reste nue : le chrome ne dessine pas une colonne de huit boutons.

**À changer.** Le chrome converge, les points restants portent sur la pilule et les détents.

- Passer la pilule à `Chrome.searchHeight` 56, marge 16, écart 8 avec le bouton rond voisin.
- Remplacer les ombres littérales restantes par `Elevation.level2`.
- Aligner la puce sur 40 visuels et 44 tactiles, écart 8, marge 16.
- Faire suivre l'encart bas au détent réel de la feuille, au lieu de `sheetInset` fixé à 0,5
  (`MapScreen.swift:1119-1122`) et du `420` de `showResults`.
- Faire passer le panneau de résultats au détent 0,42 (`Sheet.compact`) et le debug sous la
  feuille en production, jamais dans la zone du chrome.

**Livré par CHROME-CONVERGE.** Deux contrôles persistants, une feuille d'actions à deux paliers
(`.medium`, `.large`), les identifiants d'origine dans la feuille, la boussole et le zoom
conditionnels. Les actions qui ont besoin d'une carte dégagée (conduite libre, trace) restent
listées et expliquent leur indisponibilité au lieu de disparaître. `MapChromeUITests` imprime
`chrome_controls=2` et `actions_sheet=1`, avec les captures `chrome-converged.png` et
`actions-sheet.png`.

**Coût.** L, 4 sessions. Fichier sérialisé, voir 4.1.

### 2.2 Champ de recherche et liste de résultats

**Ce qui existe.** `SearchBar` (`SearchViews.swift:4-65`) est une capsule de 48 avec loupe 17,
champ, progression, effacer, menu « plus ». Le menu contient Hors ligne et Réglages
(`SearchViews.swift:37-56`). Les suggestions forment une carte de 320 de haut
(`SearchPanels.swift:5-63`), les récents une carte de 300 (`SearchViews.swift:67-125`). La liste
de résultats est une carte de 340 de haut à coins 16, marge 8, ombre 15 %
(`SearchViews.swift:147-266`, `246-253`). L'en-tête dit « Search », « Searching » ou
« N results » et porte un bouton de filtre 44 (`SearchViews.swift:158-186`). Chaque ligne a une
vignette 84, un titre 17 semibold, la note, le statut coloré, l'adresse et trois pilules d'action
(`SearchViews.swift:404-512`). Les filtres s'ouvrent dans une feuille système à deux détents
(`SearchViews.swift:255-258`).

**Ce que fait Google Maps.** La pilule est le seul point d'entrée ; les suggestions tombent dans
un panneau collé sous la pilule, sans flotter au milieu de la carte. La liste de résultats est une
feuille du bas pleine largeur, avec un en-tête de 56, des lignes de 100 à 110 et des actions en
petites pilules. La feuille a deux paliers ; le titre et les filtres restent visibles quand elle
monte.

**À changer.**

- Pilule 56, texte `.body`, loupe 20, effacer 44, menu 44. La pilule ne bouge jamais quand une
  feuille s'ouvre.
- Panneau de suggestions : pleine largeur sous la pilule, coins bas 20, ombre `level3`, lignes 56,
  maximum 60 % de la hauteur, fermeture au premier défilement de la carte.
- Résultats : feuille bord à bord, `Sheet.compact` et `Sheet.expanded`, en-tête 56 avec titre
  `.headline` et filtre 44, lignes de 108, vignette 84 avec rayon 12, actions visuelles 36 et
  tactiles 44.
- Le résumé de filtres actifs devient une rangée de puces de 32, pas une ligne de texte
  (`SearchViews.swift:203-213`).
- La ligne « More results » garde 44 et devient un bouton pleine largeur avec un chevron, pas
  une ligne de texte au milieu de la liste.
- Les états vides et l'erreur Photon passent à `.detail`, une à deux lignes, avec une action
  « Réessayer » de 44.

**Coût.** Champ S (1), liste M (2). Le champ et la liste vivent dans le même fichier : une seule
branche à la fois.

### 2.3 Fiche lieu : en-tête, onglets, actions, avis

**Ce qui existe.** `PlaceSheet` ouvre sur une poignée décorative (`PlaceSheet.swift:70-73`),
puis le nom en `.title2` et une croix de 44 (`74-91`). Il n'y a **aucune photo d'en-tête** : le
contenu commence par la note, la catégorie, le statut et les horaires (`153-214`). Les actions
sont une rangée horizontale de boutons `bordered` / `borderedProminent` de 44, avec un lien
d'action en orange (`267-332`, `327-329`). Les onglets sont des pastilles de 44 avec un fond
d'accent à 12 % (`365-388`). Les avis sont une liste plate avec avatar 32, étoiles 13 et texte
17 (`985-1046`). La feuille est une carte flottante de 8 de marge, coins 16, hauteur fixée à
0,55 de la fenêtre (`MapScreen.swift:616-626`), sans détent ni glissement. L'encart bas de la
carte est pourtant calculé sur 0,5 (`MapScreen.swift:1120-1122`), donc la carte se centre sur
5 % de hauteur de trop, dans un sens.

**Ce que fait Google Maps.** Une feuille bord à bord qui s'ouvre à environ 40 % avec une photo
en bandeau, le nom, la note, trois actions (Itinéraire plein, Enregistrer, Partager), puis les
onglets en texte souligné. Elle monte à 90 % par la poignée et garde les actions visibles. Les
avis ont un résumé avec la répartition en barres et un tri.

**À changer.**

- En-tête photo de 152, pager de 1 à 5 photos, pastille « N photos » de 36 en bas à droite,
  fermer 44 en haut à droite, coins hauts 20. Sans photo, bloc de 96 avec l'icône de catégorie,
  jamais un vide.
- Titre 22 semibold, 2 lignes, puis la ligne note / étoiles / compte / prix / catégorie en 15.
- Actions : Itinéraire en `accentFill` (label `onAccent`), Enregistrer et Partager en contour.
  Appeler, Site, Réserver, Commander passent dans une rangée défilante secondaire.
- Onglets : texte 15 semibold, 44 de haut, indicateur de 3 sous l'actif, fond transparent. Le
  `isSelected` reste exposé.
- Poignée réelle : bouton de 44 qui bascule 0,42 / 0,85, glissement sur l'en-tête, actions
  VoiceOver « Étendre » et « Réduire ».
- Encart de carte calculé sur le détent courant, avec la même animation de 320 ms.
- Avis : en-tête collant (note, compte, barres, tri), lignes avec avatar 32, étoiles 13,
  auteur 17, texte 17, photos 104, séparateur à 16.
- Les cartes « People also search for » passent à 140 de large, rayon 12, photo ou icône, note
  13, et gardent le défilement horizontal.

**Coût.** En-tête, onglets et actions L (4), avis M (2), dans la même branche `PlaceSheet.swift`.

### 2.4 Choix d'itinéraire

**Ce qui existe.** `RoutePickerSheet` est une carte flottante de 16 de rayon, marge 8, ombre
15 % (`RouteSheets.swift:11-96`). La poignée est un bouton de 44 qui bascule 0,50 / 0,85 avec
`easeInOut(duration: 0.2)` (`100-124`, `MapScreen.swift:441-454`). Les modes sont quatre
segments de 44, sélection en `Color.accentColor` avec texte blanc (`314-335`) : le blanc sur le
teal à 3,78:1 ne passe pas 4,5:1. Les actions Démarrer et Étapes sont deux boutons de 44 côte à
côte (`385-407`). L'en-tête porte destination, origine, échange, partage et fermer
(`248-296`). La feuille étendue affiche les options, les variantes et les horaires.

**Ce que fait Google Maps.** Une feuille du bas avec l'origine et la destination en haut, les
modes en segments, une durée et une distance dominantes, un bouton Démarrer plein et un bouton
Étapes secondaire. Les variantes sont des lignes, pas des cartes teintées. La feuille grandit
sans déplacer les actions.

**À changer.**

- Modes : sélection `accentFill` + `onAccent`, non sélection `surfaceRaised`, rayon 12, icône 20
  et durée 13. Le libellé reste lisible à AX3.
- En-tête : destination 22 semibold, origine 15 secondaire, trois boutons 44.
- Résumé : durée 20 tabulaire, distance et arrivée 15, « par » 15. Même ordre dans les deux
  paliers.
- Actions : Démarrer plein, Étapes contour, 48 de haut, 8 d'écart, toujours visibles.
- Variantes : ligne de 72, trait d'accent de 3 à gauche quand sélectionnée, fond neutre.
- Animation de palier à 320 ms (`Motion.sheetSpring`), et encart de carte synchronisé.
- `StepsSheet` garde 0,62 et reçoit le même en-tête, la même poignée et les mêmes actions.

**Coût.** M, 3 sessions, fichier `RouteSheets.swift` sérialisé.

### 2.5 Transports

**Ce qui existe.** Trois chromes coexistent : `TransitBoardSheet` est une feuille système avec
`NavigationStack`, `ScrollView`, titre 22 et lignes de carte (`TransitBoardSheet.swift:35-110`,
`140-183`) ; `TransitTripScreen` est un écran plein avec `NavigationStack`, deux onglets et un
plafond `.dynamicTypeSize(.xSmall ... .accessibility3)` (`TransitTripScreen.swift:22-67`) ;
`TransitDetailSheet` est une feuille de 0,62 montée par `MapScreen.swift:594-600`. Les pastilles
de ligne ont un rayon 6 (`TransitBoardSheet.swift:211-224`), les cartes de trajet un rayon 12.

**Ce que fait Google Maps.** Une feuille de départs avec le nom de l'arrêt, les lignes en
pastilles, les prochains passages et un état temps réel ; un écran de trajet avec une timeline
de segments et des cartes de marche, attente et correspondance. Le tout dans la même famille de
surfaces et la même échelle de texte.

**À changer.**

- Une seule surface : la fiche d'arrêt reste une feuille de carte, détent 0,42 puis 0,85 ; le
  trajet est une feuille plein écran (0,85 / 1,0) et non un `NavigationStack` unrelated.
- Retirer le plafond AX3 : il contredit A1 et empêche AX5. Passer en colonne unique avec le
  motif `needsUnifiedScroll`.
- Pastilles de ligne : rayon 6, 12 semibold, couleur de ligne avec texte contrasté (le
  `TransitActivityPalette` décide déjà du texte, garder ce calcul).
- Lignes de départ : heure 20 tabulaire à gauche, direction 17, minutes 15, temps réel 13 avec
  un point et un libellé, pas seulement une couleur.
- Cartes de segment : rayon 12, 12 d'encart, icône 20, durée 15, une seule bordure d'accent
  pour le segment actif.
- Les états hors ligne et périmé deviennent une rangée de 32 avec icône, pas un paragraphe
  orange.

**Coût.** M, 3 sessions (1 pour l'arrêt, 2 pour le trajet).

### 2.6 Réglages

**Ce qui existe.** `SettingsScreen` est un `Form` dans un `NavigationStack`
(`SettingsScreen.swift:29-42`) avec un en-tête maison de 44 (`533-550`) et un composant
`SettingsMenu` qui réserve 44 (`552-597`). Les sections sont Apparence, Confidentialité, Contenu,
Trajets, Voix, À propos (`172`, `484-513`). Les aides sont en `.footnote` secondaire, souvent
sur deux lignes. La feuille s'ouvre en plein écran par `.sheet(item:)` (`MapScreen.swift:116-118`).

**Ce que fait Google Maps.** Une liste pleine hauteur, un champ de recherche, des groupes avec
un titre de section, des lignes de 56 à 72, la valeur à droite et un chevron. Les interrupteurs
sont à droite et la ligne entière est la cible.

**À changer.**

- Garder `Form` (le comportement natif est bon) mais imposer le rythme : titre de groupe
  `.caption` majuscule à 16, ligne 56, valeur 15 secondaire, chevron 13.
- L'en-tête devient `.nav` 17 avec Done 44, sans matériau qui tranche.
- Les aides passent à `.detail` secondaire, une ligne quand c'est possible, et se déplacent sous
  la ligne concernée avec 4 d'écart.
- Les lignes destructrices (purge des trajets, cache photo) prennent `Colors.danger` et une
  confirmation, jamais un simple bouton rouge.
- La recherche de réglages existante (`SettingsAboutView` côté À propos) reste le seul accès
  transverse.

**Coût.** M, 2 sessions.

### 2.7 À propos

**Ce qui existe.** `AboutScreen` est un hub cherchable dans un `Form`, avec un `TextField`
(`SettingsAboutView.swift:31-33`), des sections Aide, Notices, Support et Projet (`139`, `157`,
`177`), une navigation vers les sujets et les licences (`282`, `310`, `372`), et un Done de 44
(`54-58`). L'entrée depuis les Réglages est une ligne de 44 avec deux niveaux de texte
(`SettingsScreen.swift:484-513`).

**Ce que fait Google Maps.** Une page « À propos, conditions et confidentialité » avec la
version, les mentions légales, les licences et les liens. Vela va plus loin : le hub cherchable
est un avantage produit, pas une dette.

**À changer.**

- Garder le hub, l'aligner sur les jetons : titre `.display`, champ de recherche 44, sections
  `.section`, lignes 56 avec chevron 13.
- Les résultats de recherche deviennent des lignes de 56 avec un type (réglage, aide, licence)
  en `.caption`, au lieu de deux lignes de texte.
- Les notices longues passent en lecture pleine largeur, texte 17, marges 16, sans `Form` qui
  casse les paragraphes.
- La version reste `.caption` secondaire.

**Coût.** S, 1 session.

### 2.8 Hors ligne

**Ce qui existe.** `OfflineSheet` est un `List` dans un `NavigationStack`
(`OfflineSheet.swift:10-11`), avec des sections : région actuelle, données, monde, cadre sur la
carte, téléchargement, mise à jour, régions installées, régions disponibles, stockage
(`16-231`). La progression est une `ProgressView`, les notes sont en `.caption` secondaire. La
feuille est présentée par `MapScreen.swift:109-115` et se ferme en laissant le cadre prendre la
carte (`112-115`).

**Ce que fait Google Maps.** Un gestionnaire de cartes hors ligne plein écran : liste de
régions avec vignette, bouton de téléchargement, taille, barre de stockage, et une entrée
« Sélectionner ma carte ». La progression reste visible quand on quitte l'écran.

**À changer.**

- Feuille haute (0,85 / 1,0) au lieu d'une feuille système moyenne.
- Chaque région devient une carte de 72 : nom 17, taille 15, état 13, action 44 à droite.
- Une barre de stockage de 8 de haut avec trois catégories (carte, lieux, voix) et une légende.
- La progression devient une rangée persistante de 56 avec pourcentage 15 tabulaire, pas une
  section qui pousse le reste.
- Les notes passent à `.caption` sur une ligne, avec l'icône d'information, et les erreurs à
  `Colors.danger` avec une action.

**Coût.** M, 2 sessions.

### 2.9 États vides, chargement et erreurs

**Ce qui existe.** Des phrases longues en anglais dans plusieurs feuilles : « Google did not
provide ... » (`PlaceSheet.swift:499`, `542`, `647`, `704`), « No departures found here »
(`TransitBoardSheet.swift:130-134`), « Not enough free space » (`OfflineSheet.swift:67-72`).
Les chargements sont des `ProgressView` avec un texte `.footnote`.

**Ce que fait Google Maps.** Une ligne courte, une icône discrète et, quand c'est utile, une
action. L'état vide ne prend pas la place du contenu principal.

**À changer.**

- Un composant `EmptyState` : icône 20 secondaire, titre `.rowTitle`, une ligne `.detail`, une
  action 44 facultative, marges 24.
- Un composant `LoadingRow` : `ProgressView` 20, texte `.detail`, hauteur 56.
- Traduire les phrases existantes (elles sont déjà des clés pour certaines, en dur pour
  d'autres) avant la vague 3.
- Ne jamais afficher un état vide à la place d'un contenu qui arrive : afficher le contenu
  existant et la ligne de chargement en dessous.

**Coût.** Inclus dans les vagues 1 et 3, environ 1 session transverse.

## 3. Les dix deltas qui changent le plus pour l'utilisateur

Classés par impact perçu, pas par coût.

1. **La fiche lieu n'a pas de photo d'en-tête.** Elle ouvre sur du texte
   (`PlaceSheet.swift:68-153`). Une photo de 152 change la perception de toute la fiche et
   rapproche Vela du langage de Google Maps sans copier un asset.
2. **La feuille de contenu a une hauteur fixe.** `0.55` dans `MapScreen.swift:626`, sans
   détent ni glissement. L'utilisateur ne peut pas lire une fiche longue sans lutter contre le
   bord ; c'est le cœur de l'interaction Google Maps.
3. **Deux contrôles persistants sur la carte.** Livré par CHROME-CONVERGE : localiser et une
   feuille d'actions courte. La colonne de huit boutons a disparu, la boussole et le zoom ne
   reviennent qu'avec une carte tournée ou la préférence de boutons.
4. **L'encart de carte ne suit pas la feuille.** `sheetInset` vaut 0,5
   (`MapScreen.swift:1119-1122`) alors que la fiche vaut 0,55 : les épingles et le cadrage
   d'itinéraire sont légèrement faux, et le défaut s'aggrave quand les détents arrivent.
5. **Les onglets de fiche sont des pastilles teintées.** `PlaceSheet.swift:365-388` : cinq
   pastilles de 44 prennent la place d'une rangée de texte soulignée, et l'accent à 12 % se lit
   mal en sombre.
6. **Les actions de fiche ont toutes le même poids.** `PlaceSheet.swift:267-332` : Itinéraire,
   Enregistrer, Listes, Partager, Appeler, Site et une action commerciale orange. Il faut une
   action primaire, deux secondaires, le reste derrière un défilement.
7. **Les résultats sont une carte flottante de 340.** `SearchViews.swift:147-266` : la liste ne
   peut pas grandir, la carte est masquée par une carte blanche, et le geste de feuille iOS
   n'existe pas. Une feuille 0,42 / 0,85 règle les trois.
8. **Les modes d'itinéraire écrivent blanc sur le teal.** `RouteSheets.swift:314-335` :
   3,78:1 pour un libellé de 13 points, sous AA. `accentFill` corrige sans changer la marque.
9. **Le trajet transports plafonne le texte à AX3.** `TransitTripScreen.swift:63` : un
   utilisateur en AX5 ne peut pas agrandir l'écran, et les trois écrans transports n'ont pas la
   même surface. C'est une régression d'accessibilité, pas un détail visuel.
10. **Des libellés anglais en dur dans cinq feuilles.** Par exemple « Reviews », « More
    results », « Next departures » (`PlaceSheet.swift:511`, `SearchViews.swift:237`,
    `TransitBoardSheet.swift:117`). La promesse des 24 langues se voit dans l'interface ; un
    passage design qui ne les corrige pas fige la dette.

## 4. Plan de migration

### 4.1 Propriété des fichiers et sérialisation

Règles, valables pour toutes les vagues :

- Une branche ne touche que les fichiers de sa ligne. Un besoin transverse passe par un
  commit séparé sur `DesignTokens.swift` ou `Design/`, revu par le coordinateur.
- **`MapScreen.swift` est le point de sérialisation.** Un seul agent à la fois, une seule
  branche ouverte, jamais en parallèle d'une autre vague. C'est le fichier qui porte la carte,
  la pilule, les boutons, les encarts et toutes les feuilles ; un conflit y coûte plus cher que
  d'attendre.
- Une vague qui touche un fichier détenu par un lot ouvert attend son merge. Les lots ouverts
  au 2026-10-28 sont listés dans `HIVE.md` : SRCH-CARDS et SRCH-FILTER (`SearchViews.swift`),
  PLC-PAGE et PLC-REVIEW (`PlaceSheet.swift`, `ReviewsPanel.swift`), RTE-PICKER et RTE-SHEET
  (`RouteSheets.swift`, `MapScreen.swift`), SET-CONTENT (`SettingsScreen.swift`), SET-ABOUT
  (`SettingsAboutView.swift`), O-3 (`OfflineSheet.swift`), les lots transports (`Transit/*`).
- Chaque vague merge dans `ios/main` avant qu'une vague suivante ne touche les mêmes fichiers.
- Aucun jeton nouveau en cours de vague : une valeur manquante est ajoutée à
  `DesignTokens.swift` dans son propre commit, avec sa ligne dans DESIGN.md.

### 4.2 Vague 0 : le système (ce lot)

Périmètre : `docs/ios/DESIGN.md`, `docs/ios/DESIGN-AUDIT.md`,
`iosApp/Vela/Design/DesignTokens.swift`. Aucun écran, aucune navigation.

Preuve : `scripts/check-writing.sh $(git merge-base ios/main HEAD)..HEAD` et
`python3 scripts/ios/parity_check.py --check` verts ; `grep -R "Design\\." iosApp/Vela --include=*.swift`
ne montre aucun consommateur hors du fichier de jetons ; relecture du tableau des jetons par le
coordinateur.

Coût : 1 session.

### 4.3 Vague 1 : surfaces hors carte, en parallèle

Quatre flux sur des fichiers disjoints, 8 sessions. Ils peuvent tourner en parallèle, à
condition que les lots propriétaires soient mergés.

| Flux | Fichiers | Contenu | Sessions |
|---|---|---|---|
| Recherche | `SearchViews.swift`, `SearchPanels.swift` | pilule 56, suggestions, lignes de résultats, pilules, états | 3 |
| Réglages | `SettingsScreen.swift` | en-tête, lignes 56, aides, destructif | 2 |
| À propos | `SettingsAboutView.swift` | hub, résultats, notices | 1 |
| Hors ligne | `OfflineSheet.swift` | cartes de région, stockage, progression | 2 |

La géométrie de la feuille hôte ne change pas dans cette vague : la carte garde son encart de
0,5 jusqu'à la vague 2. Les flux changent l'intérieur, pas la surface.

### 4.3.1 État livré par DESIGN-W1 (Réglages, À propos, Hors ligne)

Le lot DESIGN-W1 applique la vague 1 sur les trois surfaces hors carte que les autres lots ne
détiennent pas, sans toucher `MapScreen.swift`, `SearchViews.swift` ni les feuilles de contenu.

- **Réglages** (`SettingsScreen.swift`) : en-tête `.nav` sur surface opaque avec un filet de
  1 point et un Done de 44 ; titres de groupe `.caption` semibold, secondaire et majuscule ;
  hauteur de ligne minimale de 44 ; lignes à deux niveaux (`rowTitle` et `caption`) avec chevron
  de 13 et retournement RTL ; aides en `.detail` secondaire collées sous leur contrôle ;
  accent réservé aux sélections et aux icônes, le Done en `accentFill` pour tenir 7,75:1 ; le
  commutateur Google reste dans les deux premiers écrans. Le composant `SettingsMenu` garde son
  identifiant et sa valeur d'accessibilité.
- **À propos** (`SettingsAboutView.swift`, `SettingsChrome.swift`) : hub cherchable aux mêmes
  jetons, champ de recherche de 44 sur `surfaceSunken` et `Radius.m`, résultats et sujets d'aide
  en lignes à deux niveaux, bloc version et support en `.caption` secondaire. Les notices passent
  en lecture pleine largeur, une carte `Radius.m` par famille de sources, chaque source nommant
  sa licence en texte.
- **Hors ligne** (`OfflineSheet.swift`, `OfflineAreaView.swift`) : contenu en cartes de
  `Radius.m` avec `Elevation.level1`, en-têtes de groupe aux jetons, lignes de région lisibles
  d'un coup (nom, taille, état, action de 44), carte de zone et carte de progression en
  `Radius.xl` avec `Elevation.level3`, barre de stockage de 8 avec légende nommée, deux
  commutateurs de la carte de zone avec leur sous-titre. Mouvement de feuille à 320 ms
  (`Motion.sheetSpring`) et repli en fondu de 120 ms sous Reduce Motion. À partir de AX4 les
  rangées de région et de catalogue passent en colonne.
- **Preuve** : scénario `SettingsUITests.testDesignTokensApplied` (`design_settings=1`),
  captures `design-settings.png`, `design-about.png`, `design-offline.png`, assertions de cible
  de 44 dans `SettingsUITests` et `OfflineUITests`. Les scénarios `SettingsUITests`,
  `OfflineUITests` et `LocalizationUITests` restent verts, et les identifiants existants sont
  conservés.

Preuve : `ux-v1-search-field.png`, `ux-v1-search-results.png`, `ux-v1-search-suggestions.png`,
`ux-v1-settings.png`, `ux-v1-about.png`, `ux-v1-offline.png`, leurs variantes `-dark`, plus
`ux-v1-de-long.png` et `ux-v1-he-rtl.png`.

Contrôle visuel : pilule à 56 et marge 16, suggestions sous la pilule et non au milieu, lignes de
résultat à 108, aucune cible sous 44, réglages à 56, aucun texte tronqué en allemand, ordre
correct en hébreu.

Tests qui doivent rester verts : `SearchUITests`, `SearchAreaUITests`, `SearchFiltersUITests`,
`SettingsUITests`, `SettingsAboutUITests`, `LocalizationUITests`, `PrivacyUITests`,
`OfflineUITests`, `OfflineAreaUITests`, `QualityUITests`, `LaunchUITests`. Linux :
`scripts/check-writing.sh` et `parity_check.py --check`.

### 4.4 Vague 2 : l'hôte de la carte, sérialisé

Périmètre : `MapScreen.swift` et un nouveau `iosApp/Vela/Design/SheetSurface.swift`. 4
sessions, un seul agent.

- Chrome : trois boutons au repos, pilule 56, puces 40 / 44, menu « plus ».
- Surface : composant `SheetSurface` bord à bord, coins 20, poignée 32 x 4, ombre haute.
- Hôte : un détent par feuille, encart de carte calculé sur le détent, animation 320 ms.
- Résultats : passage de la carte 340 à la feuille 0,42 / 0,85, avec la modification minimale
  de `SearchViews.swift` (surface seulement, le contenu a été fait en vague 1).
- Suppression des ombres et rayons littéraux de `MapScreen.swift` au profit des jetons.

Cette vague est le point de non-retour : l'hôte passe un `@Binding` de détent, et les feuilles
de la vague 3 le lisent au lieu de fixer leur hauteur.

Preuve : `ux-v2-map-rest.png`, `ux-v2-sheet-compact.png`, `ux-v2-sheet-expanded.png`,
`ux-v2-sheet-peek.png`, `ux-v2-map-landscape.png`, variantes `-dark`.

Contrôle visuel : carte visible à au moins 50 % au détent 0,42 ; trois boutons ronds au repos ;
une seule surface ; les épingles restent au-dessus de la feuille ; la pilule ne bouge pas entre
les paliers ; aucune feuille ne dépasse sous l'indicateur d'accueil.

Tests : `LaunchUITests`, `MapSearchUITests`, `MapPoiUITests`, `MapLayersUITests`,
`SavedMapUITests`, `DirectionsUITests`, `NavBannerUITests`, `QualityUITests`. Les scénarios de
`RTE-SHEET` (feuille dépliée, `route-add-stop` atteignable) restent la référence de non
régression.

### 4.4.1 État livré par DESIGN-W2 (hôte de la carte)

Le lot DESIGN-W2 applique la vague 2 sur l'hôte de la carte sans toucher les feuilles de contenu
de la vague 3. Les deltas 2, 3, 4 et 7 sont fermés.

- **Chrome** (`MapScreen.swift`, `SearchViews.swift`, `SearchPanels.swift`) : pilule de recherche
  à 56 (`Chrome.searchHeight`), marge 16, rayon capsule, ombre `Elevation.level2`, loupe 20 et
  boutons effacer et menu de 44. La rangée de puces passe à 40 visuels et 44 au toucher
  (`Chrome.chipHeight`, `contentShape` de 2), écart 8, marge 16, ombre `level1`.
- **Hiérarchie des boutons** : un seul contrôle primaire, localiser, en accent ; la boussole et
  le zoom MAP-GESTE sont conservés ; couches, conduite libre, enregistrement, trajets et parking
  sont regroupés dans une seule surface de matériau à lignes de 48. Tous les identifiants
  existants restent sur leur ligne, donc aucun scénario ne perd sa cible.
- **Surface** (`Common/SheetSurface.swift`) : composant unique bord à bord, coins hauts 20,
  poignée 32 x 4 à 8 du bord, ombre haute `level3` (`level2` pour les résultats), hauteur de
  contenu mesurée par une `PreferenceKey`. La poignée est un bouton de 44 qui expose « Étendre »
  et « Réduire » à VoiceOver et un glissement d'un palier.
- **Détents** : résultats 0,42 puis 0,85 ; fiche lieu 0,42, 0,85 puis 1,0 ; choix d'itinéraire
  0,50 puis 0,85 ; étapes et détail transports 0,62 ; hors ligne 0,85 puis 1,0. Le contenu ne
  change pas d'ordre et la pilule ne bouge pas entre les paliers.
- **Encart de carte** : l'encart bas vaut la hauteur mesurée de la feuille active, quel que soit
  le détent, et retombe à zéro quand la feuille se ferme. Le recentrage et la caméra de suivi
  lisent donc la même valeur. La ligne de debug `sheet-layout-debug` imprime
  `detent=<valeur> ... map_inset_matches_sheet=1` ; les épingles de résultats utilisent le même
  encart au lieu d'une bande fixe de 420.
- **Preuve** : scénario `MapChromeUITests.testDesignDetentsMatchMapInset` (`detent=0.42`,
  `detent_expanded=0.85`, `map_inset_matches_sheet=1`), captures `design-chrome.png`,
  `design-results-sheet.png`, `design-detents.png`. `SearchUITests`, `MapChromeUITests` et
  `MapTapUITests` restent verts sur le runner Mac.
- **Reste pour la vague 3** : la fiche lieu garde sa carte interne et sa poignée décorative,
  remplacées par l'en-tête photo et les onglets soulignés ; les modes d'itinéraire passent à
  `accentFill` ; les transports perdent le plafond AX3.

### 4.5 Vague 3 : feuilles de contenu, en parallèle

Trois flux sur des fichiers disjoints, après la vague 2, 12 sessions.

| Flux | Fichiers | Contenu | Sessions |
|---|---|---|---|
| Fiche lieu | `PlaceSheet.swift` | photo 152, titre, note, actions, onglets, avis | 6 |
| Itinéraire | `RouteSheets.swift` | modes, en-tête, résumé, variantes, étapes | 3 |
| Transports | `TransitBoardSheet.swift`, `TransitTripScreen.swift` | arrêt, trajet, pastilles, hors ligne | 3 |

La fiche lieu est un seul flux car les avis vivent dans `PlaceSheet.swift` : les deux sessions
d'avis sont sérialisées dans la même branche. `RouteSheets.swift` est également sérialisé en
interne. Les trois flux sont parallèles entre eux.

Preuve : `ux-v3-place-header.png`, `ux-v3-place-tabs.png`, `ux-v3-place-actions.png`,
`ux-v3-place-reviews.png`, `ux-v3-route-compact.png`, `ux-v3-route-expanded.png`,
`ux-v3-route-steps.png`, `ux-v3-transit-board.png`, `ux-v3-transit-trip.png`, variantes
`-dark`.

Contrôle visuel : photo 152 et pastille N photos, titre sur deux lignes, une action primaire,
onglets soulignés, avis avec résumé et barres réelles, modes lisibles, Démarrer immobile,
transports sans plafond de texte.

Tests : `PlaceUITests`, `PlaceReviewsUITests`, `PlaceFuelUITests`, `PlaceKnowledgeUITests`,
`DirectionsUITests`, `TransitCitymapperUITests`, `TransitAdvancedUITests`, `QualityUITests`.

### 4.5.1 État livré par DESIGN-W3 (fiche lieu)

Le lot DESIGN-W3 applique la vague 3 au flux fiche lieu. Les deltas 1, 5 et 6 sont fermés. Le
delta 10 recule sur les libellés touchés par ce flux. Le delta 9 et les flux itinéraire et
transports restent dans leurs branches.

- **En-tête** (`PlaceSheet.swift`) : la première photo de la galerie occupe 152 points, avec un
  dégradé, le nom en `sheetTitle`, la note et son compte, et deux contrôles de 44, favori et
  fermer. Sans photo, un bandeau de 120 points prend la teinte et l'icône de la catégorie, jamais
  une bande vide. Aux détents étendu et plein, la photo cède la place à une barre de titre
  compacte ; le détent est lu par l'environnement que `SheetSurface` expose.
- **Onglets** : texte `typography.tab`, soulignement de 3 points qui glisse entre les onglets avec
  `matchedGeometryEffect`, aucun fond de pastille, `isSelected` conservé. La rangée défile et
  centre l'onglet actif à chaque changement et à chaque taille de texte, donc à AX3.
- **Actions** : Itinéraire est la seule action pleine (`accentFill` et `onAccent`). Enregistrer,
  Listes, Partager, Appeler, Site et l'action commerciale sont des pilules secondaires dans une
  seule rangée défilante. À partir de AX4 la rangée passe en colonne. Tous les identifiants
  existants restent posés sur le même comportement.
- **Avis** : l'histogramme passe à l'ambre `Colors.star` sur une piste à 18 %, les tris et la
  recherche deviennent des puces `accentFill` ou `surfaceRaised`, la mention de traduction reste
  au niveau `caption`. Les lignes prennent l'avatar 32, l'auteur `rowTitle`, le texte `body`, les
  photos 104 et les espacements des jetons.
- **Preuve** : `PlaceUITests.testDetailsHoursTabsActionsAndRelated` reporte
  `place_header=photo|category`, `place_tabs=underlined` et `place_action_primary=directions`, et
  produit `design-place-header.png`, `design-place-tabs.png` et `design-place-actions.png`. Les
  scénarios `PlaceUITests`, `PlaceReviewsUITests` et `PlaceKnowledgeUITests` restent la référence
  de non-régression, avec `PlaceFuelUITests` pour la ligne de carburant.

Le run Mac `design-w3-20261030-003546-17109` compile l'app et exécute les trois suites.
`PlaceUITests.testCompleteFixturePlace`, `PlaceKnowledgeUITests.testWikidataAndWikivoyage` et
`PlaceReviewsUITests.testGalleryViewerSwipesWithCaptionAndSource` sont verts, et la capture
`design-place-header.png` montre l'en-tête photo. Trois points restent à confirmer sur un prochain
run : la fiche ouverte par la recherche live n'avait pas de statut Google, ce qui arrêtait
`testDetailsHoursTabsActionsAndRelated` avant les captures des onglets et des actions ;
`testReviewsHistogramAndControls` a subi le blocage de snapshot de simulateur déjà documenté dans
PLACE.md ; `testSwipeKeepsThePanelResponsive` a mesuré 1358 ms sur un runner qui répondait déjà en
911 ms avant le geste. Après ce run, le bouton All reviews suit la même condition que l'onglet
Reviews et le scénario tolère un statut absent ; ces deux corrections demandent une nouvelle
exécution Mac.

### 4.6 Vague 4 : validation et finitions

3 sessions, après la vague 3.

- AX3 et AX5 sur les quatre écrans clés, colonne unique à partir d'AX4.
- Hébreu (RTL), allemand (texte long), arabe si le catalogue le permet.
- Clair, sombre, Increase Contrast, Reduce Motion, Reduce Transparency.
- Paysage sur petit écran, encart de carte et feuille.
- Ordre VoiceOver relu dans la hiérarchie, pas seulement au doigt.

Preuve : `ux-v4-ax3.png`, `ux-v4-ax5.png`, `ux-v4-dark.png`, `ux-v4-he.png`,
`ux-v4-de.png`, `ux-v4-small-landscape.png`, `ux-v4-voiceover-order.txt`, et un passage
`QualityPerformanceUITests` pour vérifier que la feuille n'a pas ajouté de saccade.

Tests : toute la suite `VelaUITests` du périmètre, plus `QualityUITests` et
`LocalizationUITests`.

### 4.7 Total

| Vague | Parallélisme | Sessions |
|---|---|---:|
| 0 système | sérialisé | 1 |
| 1 surfaces hors carte | 4 flux | 8 |
| 2 hôte de carte | sérialisé | 4 |
| 3 feuilles de contenu | 3 flux | 12 |
| 4 validation | sérialisé | 3 |
| **Total** | | **28** |

## 5. Protocole de preuve

Une capture ne prouve rien sans une phrase qui dit ce qu'on regarde. Chaque vague livre :

1. les captures nommées ci-dessus, en clair et en sombre pour les écrans concernés ;
2. une ligne `UITEST` par invariant mesurable (par exemple `UITEST ux_pill_height=56`,
   `UITEST ux_sheet_visible_map=0.58`) lue par le scénario, pas une capture seule ;
3. un contrôle visuel écrit en trois points : géométrie, hiérarchie, mouvement ;
4. les tests listés dans la vague, verts sur simulateur, et les scripts Linux verts.

Invariants communs à toutes les vagues :

- aucune cible sous 44 par 44, mesurée dans la hiérarchie ;
- aucun texte tronqué à AX3 ni à AX5 ;
- la carte reste visible à au moins 50 % au détent compact ;
- aucun libellé en dur ajouté, et les libellés existants en dur diminuent ;
- une seule surface de contenu à la fois ;
- aucun identifiant d'accessibilité sur un conteneur sans
  `.accessibilityElement(children: .contain)` (le piège de `HIVE.md`).

## 6. Risques et points ouverts

1. **`MapScreen.swift` est le goulot.** 1 215 lignes, 27 scénarios UI, toutes les surfaces.
   La vague 2 est la plus risquée du plan ; elle doit être seule sur la branche et garder les
   identifiants existants un par un. Un renommage d'identifiant casse un scénario sans casser
   le build.
2. **Le design passe avant la fin des fonctionnalités.** Les lots hors ligne, transports,
   enregistrés et couches bougent encore. Une vague qui part trop tôt sur un fichier détenu
   sera rebasée ou refaite. Les portes de propriété de 4.1 ne sont pas une formalité.
3. **Accessibilité et l10n sont les vrais risques de régression.** Le teal sur blanc ne passe
   pas AA pour un label de 15 points, le trajet transports plafonne à AX3, et cinq feuilles
   portent de l'anglais en dur. Un passage purement visuel peut figer ces défauts au lieu de
   les corriger. Les règles A1 à A10 et les preuves de la vague 4 sont la garde.

Points ouverts à trancher par le coordinateur :

- l'écart de teal entre l'asset iOS (`#149387`) et le thème Android (`#14857A`) ;
- le sort du bouton « Enregistrés » à côté de la pilule : le garder comme second bouton rond, ou
  le déplacer dans le menu « plus » ;
- l'usage d'onglets soulignés pour la fiche lieu (Aperçu, Avis, Photos) ou d'un simple
  défilement avec ancres ;
- le niveau de détail de l'en-tête photo quand Google ne rend aucune photo : bloc de couleur,
  icône de catégorie, ou pas d'en-tête du tout ;
- la place de la recherche vocale dans la pilule, aujourd'hui une surcouche
  (`MapScreen.swift:455-456`).
