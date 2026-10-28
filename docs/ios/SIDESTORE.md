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
