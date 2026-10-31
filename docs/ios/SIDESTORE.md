# Mises à jour Vela iOS dans SideStore

## Ajouter la source

Dans SideStore : Sources, puis `+`, et coller :

```
https://raw.githubusercontent.com/gelinant/ios-builder/dist/apps.json
```

Ou ouvrir ce lien sur l'iPhone avec SideStore installé :

```
sidestore://source?url=https%3A%2F%2Fraw.githubusercontent.com%2Fgelinant%2Fios-builder%2Fdist%2Fapps.json
```

La source `Vela iOS` contient la dernière IPA validée par le coordinateur. SideStore propose les
mises à jour quand `CFBundleShortVersionString` augmente. Le manifeste contient aussi les champs
pour AltStore Classic. La même source fonctionne dans AltStore.

Le dépôt GitHub `gelinant/ios-builder` est public : SideStore télécharge le JSON et l'IPA sans compte
et sans jeton. Le JSON n'est pas signé ; la confiance vient du HTTPS de `git.alt144.net` et du profil
de développeur avec lequel l'utilisateur signe l'IPA.

## Publier une version

Après un build Mac vert, depuis la racine du checkout :

```
scripts/ios/publish-sidestore.sh /chemin/Vela-unsigned.ipa "Navigation, recherche et hors ligne" /chemin/capture.png
```

Le script :

1. lit dans l'IPA le bundle id, la version et le build ;
2. génère `apps.json` avec la taille, la date, les permissions et l'URL de téléchargement ;
3. copie l'IPA, l'icône et la capture sur la branche `dist` de `gelinant/ios-builder` ;
4. force-pousse cette branche en un seul commit, pour ne pas garder les anciennes IPA dans
   l'historique git.

Le script ne remplace pas les tests : ne publier que le build d'un merge validé. Le build local de
l'IPA sur `~/gmaps/ios-builder` (branche `ipa`) reste disponible comme méthode manuelle.

## Versions

Les anciennes IPA portent `0.1.0`. Les prochains builds CI prennent une version de développement
croissante `0.1.<UTC>` et un numéro de build croissant. SideStore ne doit jamais recevoir deux IPA
différentes avec la même version : la comparaison des mises à jour se fait sur cette chaîne.

## Limites

- Une IPA non signée doit être signée par SideStore/AltStore/Sideloadly. L'app et l'extension de
  Live Activity doivent être signées ensemble.
- Avec un compte Apple gratuit, le profil expire au bout de 7 jours. SideStore peut le renouveler
  quand l'iPhone et l'ordinateur/serveur de refresh sont disponibles ; une source ne change pas
  cette limite.
- La branche `dist` ne garde que la dernière version. Pas d'historique de versions ni de retour
  arrière proposé par la source.

## Build publie le 28 octobre 2026 (02 h)

- Source : `https://raw.githubusercontent.com/gelinant/ios-builder/dist/apps.json`
- Version `0.1.202610280149`, `Vela.ipa` de 21 817 800 octets, commit `41f9f6ae`
- Run de reference : `checkpoint-ipa-20261028-013853-11233` (`STATUS ok`, archive reelle,
  `NSSupportsLiveActivities: true`, scenario de lancement vert)
- Contenu : carte (styles, trafic Google, satellite Esri/Google, numeros de maison et de sortie,
  trois sources de lieux), recherche (cartes de resultats, priorite, filtres, cette zone,
  succursales, raccourcis), fiches (onglets, avis, photos, affluence, carburant UK, fermeture),
  itineraires (deux presentations, trafic a la demande, cameras, velo), navigation (bandeau,
  voies, ecussons, ETA par arret, reprise, alertes seules), favoris (edition, export, import,
  Find my car), confidentialite (consentement, compteur), transports (ecran type Citymapper),
  a propos avec notices verifiees.
- Ce build n'est pas une suite complete verte : il prouve la compilation, l'archive et un
  scenario de lancement. La suite complete reste le gate de la version de parite.

## Build publie le 29 octobre 2026 (10 h)

- Source : `https://raw.githubusercontent.com/gelinant/ios-builder/dist/apps.json`
- Version `0.1.202610291017`, `Vela.ipa` de 24 322 590 octets
- Run de reference : `ipa-29-20261029-101626-20383` (`STATUS ok`, archive reelle, deux scenarios
  de lancement verts)
- Nouveautes par rapport au build du 28 : carte cliquable partout (contrat dessine = cliquable),
  transports cliquables avec fiche de ligne et ruban dans la couleur de la ligne, rames
  interpolees depuis les heures reelles, mode GO facon Citymapper, arbres et couvert, marquages au
  sol (bandes cyclables, sens uniques, voies de bus), ouverture sur la position de l'utilisateur,
  themes clair/sombre et contraste corrige, feuille d'itineraire depliable.
- Ce build n'est pas une suite complete verte : la passe de bug hunt est en cours. La parite
  prouvee est de 32,4 pour cent des lignes en « teste sur simulateur ».

## Build publie le 29 octobre 2026 (18 h)

- Source : `https://raw.githubusercontent.com/gelinant/ios-builder/dist/apps.json`
- Version `0.1.202610291812`, `Vela.ipa` de 24 980 205 octets
- Run de reference : `ipa-29b-20261029-182107-30871` (`STATUS ok`, archive reelle, deux scenarios
  de lancement verts)
- Nouveautes par rapport au build du matin : carte 3D (batiments extrudes et relief ombre AWS),
  711 chaines localisees en 22 langues, controle d'heure unique dans six surfaces, import Google
  avec franchissement du consentement, tap carte repare (geste et chrome), fiche OpenStreetMap de
  repli quand Google ne correspond pas, panneau d'avis qui repond en 0,9 s au lieu de 60 s,
  rames interpolees et mode GO, arbres et marquages au sol.
- Ce build n'est pas une suite complete verte : la stabilisation du harnais est en cours, et les
  deux scenarios hors ligne longs restent a rejouer ensemble.

## Build publie le 30 octobre 2026 (03 h)

- Source : `https://raw.githubusercontent.com/gelinant/ios-builder/dist/apps.json`
- Version `0.1.202610300242`, `Vela.ipa` de 27 132 010 octets
- Run de reference : `ipa-30a-20261030-024236-*` (`STATUS ok`, archive reelle, deux scenarios de
  lancement verts)
- Contenu nouveau : globe natif (plafond z1, fond sombre), batiments 3D et relief ombre natif,
  ecran Relief GL JS avec ciel et atmosphere, satellites SGP4 avec prochain passage, widgets
  ecran d'accueil, fiche lieu avec en-tete photo et onglets soulignes, paliers de feuille et inset
  mesure, hors ligne repare (montage de l'archive, delta reel), demarrage a froid 430 ms plus
  rapide, controle d'heure unique, import Google avec consentement.
- Deuxieme build prevu en fin de matinee avec A11Y-W4, DRIVE-SEARCH, QUALITY-REG et REVIEWS-REG.

## Build publie le 30 octobre 2026 (08 h)

- Source : `https://raw.githubusercontent.com/gelinant/ios-builder/dist/apps.json`
- Version `0.1.202610300758`, `Vela.ipa` de 27 257 099 octets
- Run de reference : `ipa-30b` (`STATUS ok`, archive reelle, deux scenarios de lancement verts)
- Nouveautes par rapport au build de 03 h : satellites GPS, Molniya et geostationnaires (SDP4,
  precision mesuree a 1e-8 km), recherche et ajout d'arret pendant la conduite, ecran "atteignable
  en N minutes" avec enveloppe, budgets de performance relatifs, correctifs de gel des avis,
  defilement de la feuille d'itineraire et onglets qui replient en tres grands caracteres.
- Les lots A11Y-W4, I18N-4, PLACE-HARNESS et SCROLL-AX3 sont arrives apres ce build : ils seront
  dans la publication suivante.

## Build publie le 30 octobre 2026 (10 h)

- Source : `https://raw.githubusercontent.com/gelinant/ios-builder/dist/apps.json`
- Version `0.1.202610301001`, `Vela.ipa` de 27 269 305 octets
- Run de reference : `ipa-30c` (`STATUS ok`, archive reelle, deux scenarios de lancement verts)
- Nouveautes par rapport au build de 08 h : defilement unifie de la feuille d'itineraire corrige
  en AX XXXL (le ScrollView portait l'identifiant de la feuille et perdait le sien), "partir plus
  tard" ancre sur le depart reel a l'arret dans GO avec repli annonce, et fiche lieu sur fixture
  enregistree (photos, avis et histogramme deterministes).
- Les lots A11Y-W4 et I18N-4 restent a verifier et partiront dans la publication suivante.

## Build publie le 30 octobre 2026 (12 h)

- Source : `https://raw.githubusercontent.com/gelinant/ios-builder/dist/apps.json`
- Version `0.1.202610301130`, `Vela.ipa` de 27 273 596 octets
- Run de reference : `ipa-30d` (`STATUS ok`, deux scenarios de lancement verts)
- Contenu : interface francaise complete, pluriaux compris (`60 resultats`, `2 correspondances`),
  plus tout le build de 10 h. C'est le build de reference de la journee.
- Reste sans verdict : A11Y-W4 (balayage 20 cas, file du runner) et la fragilite du statut de
  l'ecran Relief sous fixture.

## Build publie le 30 octobre 2026 (23 h)

- Source : `https://raw.githubusercontent.com/gelinant/ios-builder/dist/apps.json`
- Version `0.1.202610302311`, `Vela.ipa` de 27 334 926 octets
- Run de reference : `ipa-30e` (`STATUS ok`, deux scenarios de lancement verts)
- Nouveautes par rapport au build de 12 h : instruction de manoeuvre visible en AX (elle etait
  absente), options transport accessibles depuis le choix d'itineraire, vue d'ensemble qui
  s'aplatit et restaure exactement la camera de conduite, zone hors ligne installee et durable,
  recherche le long de la route depuis la voiture, entree de zone a 49 pt, reset des couches
  monde dans les tests, quatre parcours utilisateur verts.
- C'est le build le plus complet de la journee (cinq publications : 03 h, 08 h, 10 h, 12 h, 23 h).
