# Parité iOS / Android : état et reste

État au 2026-10-25, sur la base `3439792e` et avant les merges des lots N-2, O-2 et X-2. Ce document
distingue la V1 quotidienne de la parité Android complète. Une case « fait sur simulateur » ne vaut
pas validation sur iPhone ou en conduite.

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
| Carte et recherche | M1/M2 sur iPhone ; N1 : suggestions, catégories et toucher POI sur simulateur | Adresses en ligne, fusion et déduplication en ligne/hors ligne, réglages de couches jugés essentiels, tests de densité et de cadence |
| Fiche lieu | N1 pour détails, horaires, photos, avis, appel et site ; P1 pour 20 photos | Rejouer le scénario complet au commit mergé, vérifier galerie et panneau d'avis, affluence sur IP résidentielle, captures manquantes et validation iPhone |
| Itinéraires | M4 : alternatives, voiture, marche, étapes hybrides et Transitous | Vélo et NoGoogle de bout en bout, choix d'origine et d'horaire, arrêts si retenus pour V1, itinéraire enregistré qui réutilise sa géométrie |
| Navigation | M5 : guidage, voix, caméra, recalcul, arrière-plan déclaré ; X1 pour ActivityKit | Conduite réelle, N-2 pour alertes/limitations/trafic, interruption et Bluetooth, écran verrouillé et reprise après arrêt |
| Lieux enregistrés | I6 : Save, listes, récents et persistance ; code pour parking, imports et partage | Maison/Travail en un geste, import Takeout complet sur iPhone, partage attendu et parking Find my car |
| Hors ligne | I7 : Monaco, carte sans URL distante et 30 résultats NoGoogle | O-2 pour arrière-plan, reprise et deltas, erreurs d'espace, variantes d'adresses et validation en mode avion sur iPhone |
| Réglages et langues | I8 : langue, unités, horloge et NoGoogle ; français et allemand sur simulateur | Application complète de l'horloge, traduction des nouvelles vues, hébreu RTL, consentement et réglages de confidentialité essentiels |
| Qualité | Q-1 ajoute la matrice, l'audit Dynamic Type/RTL/paysage et les métriques XCTest | Corriger ou accepter explicitement les défauts Q-1, petit écran, mémoire sur iPhone, batterie et GPU de la page cachée |

La V1 n'est pas encore déclarée stabilisée. Il faut au minimum un run vert de la fiche complète, les
limites N-2/O-2 acceptées, aucun défaut d'accessibilité bloquant et une passe humaine sur chaque
fonction principale. Les durées et le nombre de lots ne sont pas garantis par ces documents.

## Après la V1

Ordre proposé à partir des écarts de la matrice :

1. **Q-2 qualité** : cibles tactiles, libellés VoiceOver, grands textes, petit écran, RTL et
   navigation avec grand texte, puis mesures de mémoire et d'énergie sur iPhone.
2. **P-2, I-2b, R-1, L-1 et PR-1** : compléter les parcours existants avant d'ajouter des surfaces :
   fiche lieu, adresses/filtres, arrêts et options d'itinéraire, listes/import/export, confidentialité
   et réglages.
3. **N-3 et T-1** : navigation avancée, conduite libre, reprise et tunnel ; départs d'arrêts, options
   et guidage de transport.
4. **I-1b et O-3** : couches et habillages de carte, stockage et routage hors ligne. Le routage `.obf`
   demande une nouvelle implémentation iOS et ne doit pas être présenté comme un simple branchement.
5. **DL-1, SV-1, VO-1 et DG-1** : liens entrants, Street View interactif, voix neurales/dictée,
   trajets et diagnostics.
6. **CP-1** : CarPlay après validation des parcours iPhone. L'entitlement navigation et le cycle de
   vie en sideload sont des prérequis, pas des détails de finition.

## P-1 : limites des derniers runs mesurés

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
`x1-live-activity-20261025-193904-23245`. Le rendu de l'écran verrouillé et de la Dynamic Island
reste à valider sur iPhone selon [LIVE-ACTIVITY.md](LIVE-ACTIVITY.md). X-2 App Intents/Spotlight est
un lot parallèle non compté dans la base mesurée. Live Activity transports, widgets et CarPlay restent
ultérieurs ; aucun ne doit promettre un temps réel que l'absence de push ou l'entitlement ne permet
pas.

## Règle de suivi

Chaque lot qui change une fonction met à jour la ligne concernée de `FEATURES-IOS.md`, sa preuve et
le lot suivant dans le même commit. ✅ exige une preuve iPhone ; 🟡 exige un scénario simulateur ;
⚠️ décrit la limite fonctionnelle ou de preuve ; ❌ ne laisse pas croire qu'un parseur isolé est une
fonction accessible. Les défauts et mesures qualité sont conservés dans [QUALITY.md](QUALITY.md).
