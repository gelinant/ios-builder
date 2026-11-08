# Système de design Vela iOS

État : lot UX-GOOGLE-MAPS, 2026-10-28, branche `ios/ux-google`. Ce document est la source de
vérité du langage visuel et interactif de l'app. Les valeurs sont implémentées dans
`iosApp/Vela/Design/DesignTokens.swift` (espace `Design`). L'audit écran par écran, le plan de
migration et les preuves attendues sont dans [DESIGN-AUDIT.md](DESIGN-AUDIT.md).

Le lot ne modifie aucun écran. Les tokens existent, aucun fichier de vue ne les importe encore :
la première vague les applique groupe par groupe, sans conflit avec les lots en cours.

## 1. Ce que Vela emprunte à Google Maps, et ce qu'il ne copie jamais

La cible est le **langage d'interaction** de Google Maps : la carte plein écran, une pilule de
recherche flottante, une rangée de puces, une feuille qui grandit par paliers, une fiche lieu
avec photo, note et actions, un accent unique, beaucoup d'air, une hiérarchie de texte nette,
une élévation discrète et un mouvement rapide et calme.

La règle qui décide ce qui est repris : **un motif est repris seulement s'il peut se décrire en
géométrie, en mouvement et en hiérarchie**. S'il faut l'asset de Google pour le reconnaître, Vela
invente le sien.

| Motif repris | Traduction Vela | Ce qui n'est jamais copié |
|---|---|---|
| Carte plein écran, chrome flottant | MapLibre et les styles Liberty Vela, chrome en surimpression | Fond de carte, tuiles, icônes POI, palette Google |
| Une seule surface primaire | Une feuille ou un panneau à la fois, jamais deux | Barre d'onglets, tiroir latéral permanent |
| Paliers de feuille | Trois détents maximum, contenu dans un ordre fixe | Animation et courbes propriétaires |
| Accent unique | Teal Vela de la marque, pas le bleu Google | Le bleu Google et toutes ses variantes |
| Grille 4/8 et cibles 44 | Tokens `Design.Spacing` et `Design.Size.hitTarget` | Icônes Material, rayons et ombres Google |
| Hiérarchie de texte | Styles sémantiques SF, Dynamic Type jusqu'à AX5 | Google Sans, Roboto, échelle figée |
| Photo d'en-tête de fiche | Photos Google déjà chargées, galerie Vela | Photos, avatars et visuels de marque Google |
| Mouvement rapide et calme | Durées et courbes du tableau 3.6, Reduce Motion respecté | Transitions partagées entre activités |
| Avis avec note et photos | Flux `qv9Egd`, avatars colorés Vela | Étoiles, extraits et libellés Google |

Deux interdits absolus : aucune valeur hexadécimale reprise de Google (le teal Vela est `#149387`
dans le catalogue d'assets), et aucun texte de Google dans l'interface. Les libellés passent par
`VelaL10n`, dans les 24 langues.

## 2. Les principes

### P1. La carte est le héros

Au repos, le chrome flottant occupe moins de 30 % de la hauteur de l'écran. Il n'y a pas de barre
de navigation opaque en haut : la pilule de recherche flotte, la rangée de puces flotte, les
boutons ronds flottent. Une feuille ne prend jamais la totalité de l'écran si elle décrit un
objet de la carte : la carte doit rester visible au-dessus d'elle.

Conséquence mesurable : une fiche lieu au détent compact laisse au moins 50 % de carte visible,
et le cadrage d'un itinéraire utilise cette surface restante, pas la fenêtre entière.

### P2. Une seule surface primaire à la fois

La pile de `MapScreen` n'affiche qu'un panneau de contenu : résultats, fiche lieu, fiche
POI, choix d'itinéraire, étapes, transports. Une feuille système (Réglages, Enregistrés, Couches,
Hors ligne) est modale et recouvre le tout. Deux feuilles de contenu ne se superposent jamais.

Ordre d'empilement de la carte, du fond vers l'avant :

1. tuiles et couches de la carte ;
2. lignes d'itinéraire et épingles de résultats ;
3. boutons ronds de la carte et attribution ;
4. feuille de contenu (résultats, fiche, itinéraire) ;
5. pilule de recherche et rangée de puces, qui restent au-dessus de la feuille ;
6. panneau de suggestions, qui se ferme dès qu'une autre surface prend la main ;
7. alertes et feuilles système.

### P3. Divulgation progressive par paliers

Une feuille expose au plus trois paliers, et le contenu ne change jamais d'ordre entre eux : seule
la quantité visible change. Le palier compact montre le titre et une action, le palier médian
montre la fiche utile, le palier étendu montre le contenu secondaire et les listes longues.

Le glissement est possible par la poignée, par un geste de glissement sur l'en-tête et par
VoiceOver (action « Étendre » / « Réduire »). L'appui sur la poignée reste permis, mais n'est
jamais le seul chemin. La carte ajuste son encart bas à chaque palier, avec la même animation que
la feuille.

### P4. Un seul accent

Le teal Vela est la seule couleur saturée d'action et de sélection. Le vert, le rouge et l'orange
sont réservés au statut (ouvert, fermé, fermeture prochaine) et ne servent jamais de décoration.
Les étoiles sont ambre, jamais un signal unique : le nombre de la note est toujours écrit à côté.

Le teal de marque ne porte pas de label blanc : sur blanc il ne donne que 3,78:1. Les boutons
pleins utilisent `Design.Colors.accentFill` (7,75:1 avec un label blanc en clair, 8,33:1 avec un
label noir en sombre).

### P5. Grille 4/8

Tout espacement vient de `Design.Spacing`. Les valeurs hors grille de 4 sont interdites pour
un espacement, sauf une correction optique documentée (un chevron, une étoile). Un filet de
1 point et un indicateur de 3 points ne sont pas des espacements. Les marges de page sont 16, les écarts
entre sections 24, les écarts entre blocs 16, les écarts entre puces 8.

### P6. Cibles de 44 points

Toute cible tactile fait au moins 44 par 44 points, même quand le dessin est plus petit : une
puce de 40 points de haut ajoute 2 points de `contentShape` en haut et en bas. Deux cibles
adjacentes gardent au moins 8 points d'écart. Les icônes seules portent toujours un libellé
VoiceOver.

### P7. Mouvement rapide et calme

Rien ne rebondit. Une feuille se pose en 320 ms, une sélection change en 200 ms, un bouton répond
en 100 ms. La caméra de la carte est le seul mouvement long (450 ms) et elle appartient à
MapLibre. Reduce Motion coupe les translations et garde un fondu de 120 ms.

### P8. L'honnêteté avant la densité

Vela ne remplit pas un vide avec une donnée inventée. Une section sans données dit pourquoi, une
note absente ne devient pas zéro, une affluence typique ne devient pas « en direct ». Ce principe
est déjà dans le portage ; le design doit lui laisser la place : un état vide est une ligne
calme, pas une grande illustration qui pousse la carte hors de l'écran.

### P9. Le texte est traduit, jamais dessiné

Aucun libellé dans une image, aucun texte en dur, aucun caractère ajouté pour la décoration. Une
icône est un SF Symbol avec un label ; un chiffre est formaté par `VelaL10n` ou `FormatStyle`.
Une capture d'écran n'est jamais un asset d'interface.

## 3. Les jetons

Tous les noms ci-dessous existent dans `DesignTokens.swift`. Les valeurs sont en points, sauf
mention contraire.

### 3.1 Espacement

| Jeton | Valeur | Usage |
|---|---:|---|
| `Spacing.xxs` | 2 | écart interne d'un label (icône et texte) |
| `Spacing.xs` | 4 | note et étoile, paire serrée |
| `Spacing.s` | 8 | icône et texte, puces adjacentes, boutons de carte empilés |
| `Spacing.m` | 12 | ligne de liste, petit bloc |
| `Spacing.l` | 16 | marge de page, encart de feuille, écart de bloc standard |
| `Spacing.xl` | 20 | en-tête de feuille et première section |
| `Spacing.xxl` | 24 | entre deux sections |
| `Spacing.xxxl` | 32 | nouveau chapitre (Réglages, À propos) |
| `Spacing.huge` | 40 | respiration d'un état vide |

### 3.2 Rayons

| Jeton | Valeur | Usage |
|---|---:|---|
| `Radius.xs` | 4 | badge d'attribution, voie |
| `Radius.s` | 8 | vignette, aperçu Street View, photo d'avis |
| `Radius.m` | 12 | carte interne, tuile, lieu lié |
| `Radius.l` | 16 | ancienne carte flottante, encore en place avant la vague 1 |
| `Radius.xl` | 20 | coins hauts de feuille, grande surface |
| `Radius.pill` | 999 | capsule (pilule de recherche, puce, bouton d'action) |

### 3.3 Encarts et tailles

| Jeton | Valeur | Usage |
|---|---:|---|
| `Padding.page` | 16 | marge horizontale de la carte et de la feuille |
| `Padding.sheet` | 16 | contenu sous la poignée |
| `Padding.sheetTop` | 8 | poignée vers titre |
| `Padding.sheetBottom` | 24 | dernière ligne avant l'indicateur d'accueil |
| `Padding.rowH` / `rowV` | 16 / 12 | ligne de liste |
| `Padding.buttonH` / `buttonV` | 20 / 12 | bouton plein ou contour |
| `Padding.chipH` / `chipV` | 12 / 8 | puce de catégorie |
| `Size.hitTarget` | 44 | cible tactile minimale |
| `Size.icon` / `iconSmall` | 20 / 16 | icône de chrome / icône en ligne |
| `Size.avatar` | 32 | avatar d'avis |
| `Size.resultThumb` | 84 | vignette de résultat |
| `Size.reviewThumb` | 104 | photo d'avis |
| `Size.photoHeader` | 152 | en-tête photo de fiche lieu |

### 3.4 Élévation

| Jeton | Ombre | Usage |
|---|---|---|
| `Elevation.level1` | noir 8 %, rayon 2, y 1 | puces, carte en ligne |
| `Elevation.level2` | noir 12 %, rayon 8, y 2 | pilule de recherche, boutons ronds |
| `Elevation.level3` | noir 16 %, rayon 16, y 4 | feuille et panneau |
| `Elevation.level4` | noir 20 %, rayon 24, y 8 | alerte, feuille plein écran |

L'ombre est un signal de couche, pas un décor. Une feuille edge to edge ne porte que son ombre
haute (`y` négatif) ; les flancs ne sont pas ombrés puisqu'ils touchent les bords.

### 3.5 Typographie

Toutes les tailles sont des styles sémantiques SwiftUI : Dynamic Type, Bold Text et les tailles
d'accessibilité suivent sans code. Aucune taille fixe en points pour du texte d'interface.

| Rôle | Style SwiftUI | Base | Graisse | Usage |
|---|---|---:|---|---|
| `Typography.display` | `.title` | 28 | semibold | À propos, titre d'état vide |
| `Typography.sheetTitle` | `.title2` | 22 | semibold | nom de lieu, titre de feuille |
| `Typography.section` | `.title3` | 20 | semibold | Avis, À propos, Photos |
| `Typography.rowTitle` | `.body` | 17 | semibold | résultat, auteur, ligne de réglage |
| `Typography.body` | `.body` | 17 | regular | description, avis |
| `Typography.detail` | `.subheadline` | 15 | regular | adresse, horaires, métadonnée |
| `Typography.caption` | `.footnote` | 13 | regular | statut, compte, ligne tertiaire |
| `Typography.micro` | `.caption2` | 11 | regular | debug uniquement |
| `Typography.badge` | `.caption2` | 11 | semibold | pastille de compte |
| `Typography.button` | `.subheadline` | 15 | semibold | bouton plein ou contour |
| `Typography.tab` | `.subheadline` | 15 | semibold | onglet, puce |
| `Typography.rating` | `.subheadline` | 15 | semibold, chiffres tabulaires | note |
| `Typography.nav` | `.headline` | 17 | semibold | barre de feuille système |
| `Typography.metric` | `.title3` | 20 | semibold, chiffres tabulaires | durée, distance, arrivée |

Comportement Dynamic Type :

- jusqu'à AX3, toutes les mises en page du système gardent leur géométrie ;
- à partir de AX4, les écrans passent en colonne unique (le motif `needsUnifiedScroll` déjà
  utilisé par `PlaceSheet` et `RoutePickerSheet`) et les rangées horizontales deviennent
  verticales ou défilent ;
- à AX5, aucun texte n'est tronqué, aucune cible ne passe sous 44 points, et la carte garde au
  moins un tiers de l'écran ;
- la seule limite autorisée est `.dynamicTypeSize(... .accessibility3)` sur une rangée de puces
  horizontale, jamais sur un texte de contenu ;
- `.minimumScaleFactor` est interdit sur un libellé traduit. Il ne reste que sur la ligne de
  debug.

### 3.6 Mouvement

| Jeton | Valeur | Courbe | Usage |
|---|---:|---|---|
| `Motion.press` | 0,10 s | easeOut | enfoncement d'une puce ou d'un bouton |
| `Motion.quick` | 0,12 s | easeIn | un contrôle qui part |
| `Motion.base` | 0,20 s | easeOut / easeInOut | changement d'état, onglet, filtre |
| `Motion.sheet` | 0,32 s | spring réponse 0,34, amorti 0,86 | palier de feuille |
| `Motion.emphasis` | 0,42 s | easeOut | offre d'itinéraire, carte d'erreur |
| `Motion.camera` | 0,45 s | easeInOut (MapLibre) | caméra |
| `Motion.snap` | 0,28 s | spring 0,28 / 0,90 | sélection, rangée de puces |
| `Motion.fade` | 0,12 s | easeInOut | repli Reduce Motion |

`Motion.animation(_:reduceMotion:)` renvoie `nil` quand Reduce Motion est actif. L'appelant
change alors l'état sans animation et laisse le fondu terminer.

### 3.7 Paliers de feuille

| Jeton | Fraction | Usage |
|---|---:|---|
| `Sheet.peek` | 0,18 | aperçu d'un lieu, titre et une action |
| `Sheet.compact` | 0,42 | résultats, fiche lieu par défaut |
| `Sheet.half` | 0,50 | ancien palier, encore en place avant la vague 2 |
| `Sheet.tall` | 0,62 | étapes, détail transports |
| `Sheet.expanded` | 0,85 | choix d'itinéraire étendu |
| `Sheet.full` | 1,00 | À propos, Réglages, modale hors carte |

Géométrie de la surface : largeur de la fenêtre, coins hauts 20, aucun retrait latéral, poignée
32 x 4 à 8 points du bord, contenu à 16, dernière ligne à 24 de l'indicateur d'accueil. L'ancien
aspect « carte qui flotte » (retrait de 8 sur les côtés, coins de 16 partout) disparaît en vague
2. La feuille est bord à bord, comme une feuille iOS native, et c'est la carte qui reste un objet
distinct.

Un seul palier est actif à la fois. Le passage de l'un à l'autre ne change pas l'ordre du
contenu, ne remonte pas la pilule de recherche et ne déplace pas les boutons ronds.

### 3.8 Couleurs

| Rôle | Jeton | Valeur | Contraste | Usage |
|---|---|---|---:|---|
| Accent | `Colors.accent` | `#149387` (asset) | 3,78:1 sur blanc | icône, sélection, texte large seulement |
| Fond de bouton | `Colors.accentFill` | `#0B5D55` clair, `#4FB3A6` sombre | 7,75:1 / 8,33:1 | label blanc en clair, noir en sombre |
| Label sur accent | `Colors.onAccent` | blanc / noir | idem | texte d'un bouton plein |
| Surface | `Colors.surface` | `systemBackground` | système | feuille et panneau, opaque |
| Surface élevée | `Colors.surfaceRaised` | `secondarySystemBackground` | système | vignette, carte interne |
| Surface creuse | `Colors.surfaceSunken` | `tertiarySystemBackground` | système | champ, ligne groupée |
| Séparateur | `Colors.separator` | `separator` | système | filet de 1 point |
| Texte | `Colors.label` | `label` | système | texte principal |
| Texte secondaire | `Colors.secondaryLabel` | `secondaryLabel` | 4,5:1 minimum | métadonnée |
| Voile | `Colors.scrim` | noir 28 % | | arrière d'une modale |
| Succès | `Colors.success` | `systemGreen` | | ouvert, installé |
| Danger | `Colors.danger` | `systemRed` | | fermé, échec |
| Alerte | `Colors.warning` | `systemOrange` | | fermeture proche |
| Étoile | `Colors.star` | `#F2A65A` | 2,02:1 sur blanc, décoratif | étoile, toujours avec le nombre |

Deux valeurs de teal coexistent aujourd'hui : le catalogue d'assets donne `#149387`, le thème
Android `#14857A`. Le système iOS utilise l'asset. L'écart est volontairement laissé à un lot de
marque dédié, pas à une vague de design.

### 3.9 Chrome de carte

| Jeton | Valeur | Usage |
|---|---:|---|
| `Chrome.searchHeight` | 56 | hauteur de la pilule |
| `Chrome.sideInset` | 16 | marge de la pilule et des puces |
| `Chrome.topInset` | 8 | zone sûre vers la pilule |
| `Chrome.searchGap` | 8 | pilule et bouton rond voisin |
| `Chrome.actionSize` | 48 | bouton rond, visuel et tactile |
| `Chrome.actionSpacing` | 8 | entre deux boutons ronds |
| `Chrome.chipHeight` | 40 | puce, 44 avec le `contentShape` |
| `Chrome.chipSpacing` | 8 | entre deux puces |
| `Chrome.bottomInset` | 8 | attribution au-dessus de la zone sûre |
| `Chrome.grabberWidth` / `Height` | 32 / 4 | poignée de feuille |

## 4. API dans le code

```swift
// Une feuille bord à bord, sans carte flottante.
VStack(spacing: 0) {
    Capsule()
        .fill(Color(uiColor: .tertiaryLabel))
        .frame(width: Design.Chrome.grabberWidth, height: Design.Chrome.grabberHeight)
        .padding(.top, Design.Padding.sheetTop)
    content
        .padding(.horizontal, Design.Padding.sheet)
        .padding(.bottom, Design.Padding.sheetBottom)
}
.background(Design.Colors.surface)
.clipShape(UnevenRoundedRectangle(
    topLeadingRadius: Design.Sheet.cornerRadius,
    topTrailingRadius: Design.Sheet.cornerRadius))
.shadow(color: Design.Elevation.level3.color, radius: Design.Elevation.level3.radius,
        y: -Design.Elevation.level3.y)

// Une puce de 40 points visuels, 44 au toucher.
Text(label)
    .font(Design.Typography.tab)
    .padding(.horizontal, Design.Padding.chipH)
    .frame(height: Design.Chrome.chipHeight)
    .background(.regularMaterial, in: Capsule())
    .contentShape(Rectangle().inset(by: -2))

// Un bouton plein lisible.
Text(title)
    .font(Design.Typography.button)
    .foregroundStyle(Design.Colors.onAccent)
    .padding(.horizontal, Design.Padding.buttonH)
    .padding(.vertical, Design.Padding.buttonV)
    .background(Design.Colors.accentFill, in: Capsule())
    .frame(minHeight: Design.Size.hitTarget)
```

Les vues ne lisent pas encore ces jetons. La première vague les applique sans changer la
structure des fichiers, la deuxième change la surface elle-même.

## 5. Ce que Vela fait différemment, et pourquoi

1. **Un accent teal, pas le bleu de Google.** Le teal est déjà l'identité Android (`VelaTeal`)
   et il se distingue des routes, de l'eau et des icônes de la carte. Le bleu appartient à
   Google et disparaîtrait dans les tuiles Liberty.
2. **Aucun asset Google.** Pas de logo, pas de punaise, pas de pegman, pas de Google Sans. Les
   icônes sont des SF Symbols, les photos viennent des données déjà chargées. Raison juridique
   et raison de cohérence : une app qui emprunte les assets de Google devient une copie.
3. **Les styles de carte Liberty Vela.** La carte a cinq looks (Vela, Bright, Positron, Fiord,
   Black) et un mode clair ou sombre. Google Maps n'a pas cette palette et le design ne doit pas
   la contredire : le chrome reste neutre pour ne pas teinter la carte.
4. **Pas de barre d'onglets ni de tiroir permanent.** Vela est une carte, pas un hub à cinq
   destinations. Les lieux enregistrés, les trajets et les couches sont des feuilles, pas des
   tabs. La carte garde son rôle de héros.
5. **Pas de personnalisation, pas d'avatar Google, pas de « Contribuer ».** Vela est sans compte.
   La pilule de recherche n'a donc ni avatar ni photo de profil, et les résultats ne sont pas
   classés par un historique personnel.
6. **Les puces sont éditables.** L'utilisateur choisit ses raccourcis (`QuickChipsEditor`), au
   lieu de recevoir une rangée figée. Le design doit laisser la rangée défiler et garder une
   puce « Plus » accessible en fin de rangée.
7. **Des états vides honnêtes.** Une section sans données le dit en une ligne. C'est un choix
   produit qui se voit dans le design : pas de squelette infini, pas de fausse note, pas de
   « populaire maintenant » inventé.
8. **La note est ambre et toujours accompagnée du nombre.** Google utilise jaune et bleu ; Vela
   garde l'ambre de sa palette et ne fait jamais porter l'information par la couleur seule.
9. **Des feuilles bord à bord, pas des cartes flottantes.** L'ancien style Vela posait une carte
   de 8 points de marge au-dessus de la carte. La cible est une feuille iOS pleine largeur,
   parce que le contenu est long, que le geste natif est mieux compris et que l'ombre latérale
   n'a plus de sens.
10. **Un seul niveau de profondeur.** Google empile volontiers une fiche, un aperçu et une carte
    de lieu lié. Vela limite à une surface primaire et une modale système, pour rester lisible
    sur un petit écran et pour VoiceOver.
11. **Le mouvement est plus court.** 320 ms au lieu des transitions longues de Google. Sur un
    téléphone, une feuille qui se pose vite donne une impression de stabilité, et la carte n'est
    jamais masquée par une animation.
12. **Le texte est le même dans 24 langues.** Les libellés courts de Google (« Open now »,
    « Results ») ne sont pas repris tels quels : chaque clé est traduite, et l'allemand ou le
    tchèque ont le droit d'être 30 % plus longs sans casser une puce.

## 6. Gabarits de trois écrans

Ces gabarits décrivent la cible assez précisément pour être implémentés sans avoir vu Google
Maps. Les valeurs viennent des jetons ; les écrans sont cités dans leur état actuel.

### 6.1 Recherche et résultats (portrait 390 x 844)

Repères : zone sûre haute 59, basse 34, hauteur utile 751.

```
y=0     carte plein écran, sous la zone sûre
y=59    [16] ┌────────────────────────────── 358 ───────────────────────────┐ [8] (48) sauvegardé
             │ loupe 16   « Rechercher ici » 17       micro 20   effacer  │
             └────────────────────────────── 56 ────────────────────────────┘
y=127   [16] (Café)(Restaurant)(Courses)(Essence)(Plus)   puces 40, écart 8
y=...   carte visible
y=...   boutons ronds à droite, 48, écart 8, marge 16
y=720   attribution à 8 de la zone sûre
```

- **Z-order** : carte, épingles, boutons ronds, feuille de résultats, pilule et puces, suggestions.
- **Pilule** : 56 de haut, rayon 28, fond `surface` opaque ou `regularMaterial` selon Reduce
  Transparency, ombre `level2`, marge 16, 8 entre la pilule et le bouton rond de 48. Icône 20,
  texte `.body` 17, placeholder localisé.
- **Puces** : 40 visuels, 44 au toucher, 8 d'écart, 16 de marge, défilement horizontal sans
  indicateur, dernière puce « Plus » dans le flux.
- **Boutons ronds** : 48, `level2`, 8 d'écart, colonne à droite. Trois au maximum au repos
  (localiser, couches, plus). Les autres (conduite libre, trajets, parking) passent dans le
  menu « plus ».
- **Résultats** : feuille bord à bord, détent 0,42, en-tête 56 (titre `.headline` 17, filtre
  44 x 44), lignes de 108 (vignette 84 carrée, rayon 12, 12 d'écart, titre `.body` semibold,
  note 15, statut 15, adresse 15 sur deux lignes), actions en pilules de 36 visuels et 44 au
  toucher, séparateur à 16 du bord.
- **Mouvement** : la liste apparaît en 200 ms, la feuille se pose en 320 ms. Un appui sur une
  ligne ne fait pas disparaître la pilule ; la fiche lieu remplace la feuille dans le même détent.

### 6.2 Fiche lieu (portrait 390 x 844)

```
┌──────────────────────────────────────────────────────────────┐  coins 20
│ [photo 152, pleine largeur, pager de 1 à 5 photos]  (x) 44   │
│                                              (N photos) 36   │
│ 16  Nom du lieu                              22 semibold, 2l │
│ 16  4,6  ★★★★☆  (189)    ·    Restaurant  ·  €€              │
│ 16  [Itinéraire]  [Enregistrer]  [Partager]   44 de haut     │
│ 16  Ouvert · ferme à 22 h                    15, vert        │
│ 16  Adresse                                  15              │
│ 16  Téléphone                                15              │
│ 16  ─────────────────────────────────────────────────────    │
│     Aperçu   Avis   À propos   Photos   Menu                 │
│     ───────                                                  │
│ 16  [contenu de l'onglet, sections à 24]                     │
└──────────────────────────────────────────────────────────────┘
```

- **Z-order** : la photo est dans la feuille, pas derrière. La poignée est au-dessus de la photo
  (ou flottante sur un fond noir 25 %), le bouton fermer est un cercle de 36 (44 tactile) en
  haut à droite, la pastille « N photos » est en bas à droite de la photo.
- **En-tête** : 152 de haut, coins hauts 20, image en `scaledToFill` et `clipped`. Sans photo,
  un bloc `surfaceRaised` de 96 avec l'icône de catégorie, pas un trou. La pastille « N photos »
  est en bas à droite, le bouton fermer en haut à droite.
- **Titre** : 16 de marge, 12 sous la photo, `.title2` semibold, 2 lignes.
- **Note** : 15, étoiles ambre 13, compte. Prix et catégorie sur la même ligne, séparés par un
  point médian localisé.
- **Actions** : trois pilules de 44 : Itinéraire plein (`accentFill`, label blanc), Enregistrer
  et Partager en contour. Les actions secondaires (Appeler, Site, Réserver) passent dans une
  rangée défilante, jamais dans une grille de quatre.
- **Onglets** : texte 15 semibold, 44 de haut, indicateur de 3 points sous l'onglet actif, pas
  de pastille de fond. L'onglet actif est aussi signalé par `isSelected` pour VoiceOver.
- **Avis** : avatar 32, auteur 17 semibold, étoiles 13, âge 13, texte 17, photos 104, écart 8,
  ligne de séparation à 16. Le résumé affiche la répartition en cinq barres ambre et le nombre
  réel ; sans histogramme, pas de barres.
- **Paliers** : 0,42 puis 0,85 puis 1,0. Le détent courant décide de l'encart bas de la carte,
  avec la même animation. La carte reste visible à 0,42 (au moins 50 % de l'écran).

### 6.3 Choix d'itinéraire (portrait 390 x 844)

```
┌──────────────────────────────────────────────────────────────┐
│                         ▬ 32 x 4                             │
│ 16  Destination                            22 semibold       │
│     depuis Départ                         15 secondaire     │
│     (voiture) (transport) (marche) (vélo)  44, écart 6       │
│ 16  24 min · 8,4 km · 18:42                20 tabulaire      │
│     par Market Street                      15 secondaire     │
│                                                              │
│ 16  [        Démarrer        ]  [   Étapes   ]   48          │
└──────────────────────────────────────────────────────────────┘
```

- **Z-order** : les lignes d'itinéraire restent sous la feuille, la feuille à 0,50 en compact
  et 0,85 en étendu, la pilule de recherche reste au-dessus mais ne bouge pas.
- **Poignée** : 32 x 4, bouton de 44 qui bascule compact et étendu, libellé VoiceOver
  « Afficher tous les itinéraires » / « Réduire ».
- **En-tête** : destination 22 semibold, origine 15 secondaire avec chevron, échange 44,
  partager 44, fermer 44.
- **Modes** : quatre segments de 44, écart 6, icône 20 et durée 13, sélection en `accentFill`
  (pas `accent` : le label blanc doit rester lisible), non sélection en `surfaceRaised`.
- **Résumé** : durée 20 tabulaire, distance 15, arrivée 15, « par » 15. Rien ne bouge entre les
  paliers, seule la liste apparaît.
- **Actions** : Démarrer plein 48, Étapes contour 48, côte à côte à 8 d'écart, marge 16,
  12 sous le dernier contenu.
- **Étendu** : options (heure, arrêts, éviter), puis les variantes. Chaque variante est une
  ligne de 72 avec un trait d'accent de 3 sur le bord gauche pour la sélection, pas un bloc
  entièrement teinté.
- **Mouvement** : 320 ms pour le palier, la carte ajuste son encart avec la même animation. Le
  bouton Démarrer ne se déplace jamais entre compact et étendu.

## 7. Accessibilité et l10n : les règles

### A1. Dynamic Type

Les rôles de `Design.Typography` sont obligatoires. Le texte va jusqu'à AX5 sans troncature ;
la géométrie est garantie jusqu'à AX3, et à partir de AX4 les écrans passent en colonne unique.
Aucune hauteur de feuille n'est fixée en points pour du texte : un palier est une fraction, le
contenu défile.

### A2. Ordre VoiceOver

L'ordre de lecture est : carte, pilule de recherche, rangée de puces, boutons ronds, puis feuille
(poignée, titre, fermer, note, actions, onglets, contenu). Une feuille de contenu masque le
chrome de carte qu'elle recouvre (`.accessibilityHidden(true)`), et une feuille système bloque
le reste par nature.

Règle de la ruche : un `accessibilityIdentifier` posé sur un conteneur s'accompagne toujours de
`.accessibilityElement(children: .contain)`, sinon SwiftUI avale les enfants. C'est la cause de
quatre régressions déjà documentées dans `HIVE.md`.

### A3. Cibles et gestes

44 x 44 minimum, 8 points entre deux cibles. Un geste de glissement n'est jamais le seul chemin :
la poignée est un bouton, et VoiceOver expose « Étendre » et « Réduire ». Un appui long a
toujours un équivalent visible (bouton, menu) ou est une commodité, jamais une nécessité.

### A4. Contraste

4,5:1 pour le texte courant, 3:1 pour le texte large et les composants d'interface. Le teal sur
blanc (3,78:1) ne porte donc pas de texte de 15 points : il sert d'icône, de sélection ou de
texte large, et les boutons pleins utilisent `accentFill`. Le statut n'est jamais porté par la
seule couleur : « Ouvert » est écrit, pas seulement vert.

### A5. RTL

`leading` et `trailing` uniquement, jamais `left` ou `right`. Les chevrons et les flèches de
navigation se retournent avec `.flipsForRightToLeftLayoutDirection(true)`. Les nombres, les
coordonnées et les horaires restent en LTR dans un sous-arbre `.environment(\.layoutDirection,
.leftToRight)`. La géométrie de la carte n'est pas retournée : une rue ne change pas de côté.

### A6. Vingt-quatre langues

Aucun libellé en dur. Toute nouvelle chaîne entre dans le catalogue avec ses 24 traductions.
Les pluriels passent par le catalogue, jamais par une concaténation. Les gabarits de nombre
utilisent `%ld` pour les entiers 64 bits. Les libellés de bouton peuvent aller à deux lignes et
la feuille grandit ; une puce peut s'élargir de 30 % avant de défiler.

### A7. Pas de texte dans les images

Une image d'interface ne contient aucun mot. Les captures et les tuiles de carte sont des
données, pas des libellés. Une icône qui porte un sens a un label VoiceOver ; une icône
purement décorative est `accessibilityHidden(true)`.

### A8. Reduce Motion et Reduce Transparency

Reduce Motion : `Motion.animation(_:reduceMotion:)` renvoie `nil`, les paliers changent sans
translation, un fondu de 120 ms peut rester. Reduce Transparency : les surfaces qui utilisent
`regularMaterial` (pilule, puces, boutons ronds) passent en `Colors.surface` opaque avec un
séparateur de 1 point.

### A9. Clavier, focus et saisie

Le champ de recherche est le seul premier répondant à l'ouverture, avec `submitLabel(.search)`.
Le clavier ne compresse jamais le chrome : `ignoresSafeArea(.keyboard)` sur la pile de chrome,
comme aujourd'hui dans `MapScreen`. Une feuille ne prend pas le focus à l'ouverture.

### A10. Preuve obligatoire

Chaque vague livre : captures en clair et en sombre, AX3 et AX5, hébreu (RTL), allemand (texte
long), paysage sur petit écran, et un contrôle VoiceOver de l'ordre. Les noms de captures et les
tests qui doivent rester verts sont dans le plan de vague de DESIGN-AUDIT.md.
