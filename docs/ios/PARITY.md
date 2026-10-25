# Parité iOS / Android : état et reste

État au 2026-10-25, après les merges I-3 à I-7. Ce document distingue le code présent, la preuve
sur simulateur et la validation sur iPhone. Une case « fait sur simulateur » ne vaut pas validation
en conduite.

## Mesures

- `:core` comptait 172 fichiers et 31,9 k lignes. Il en reste 59 et 6,1 k lignes dans `:core` :
  **113 fichiers déplacés** dans `:core-common` (66 % des fichiers, environ 81 % des lignes).
  Une partie du reste est volontairement Android : Hilt, les implémentations des coutures, Cronet,
  OsmAnd, capteurs et synthèse Android.
- Fonctions principales de la V1 : recherche, fiche lieu, itinéraires, navigation guidée, lieux
  enregistrés et régions hors ligne ont du code et des scénarios sur simulateur. Seule la carte et
  la recherche ont été validées par l'humain sur iPhone pour l'instant.
- La parité complète de `FEATURES.md` n'est pas atteinte. Les pourcentages ci-dessous sont des
  ordres de grandeur de travail, pas une mesure ligne par ligne :
  socle technique partagé environ 85 %, V1 utilisable environ 55 à 65 %, parité complète environ
  25 à 35 %.

## V1 : ce qui reste avant de dire « utilisable tous les jours »

| Domaine | Présent | Reste |
|---|---|---|
| Carte | MapLibre, style Liberty, épingles, itinéraires, hors ligne | Toucher les POI de la carte, couches et réglages essentiels, clusters et densité, noms de rues depuis les fonds téléchargés, performance |
| Recherche | Recherche Google, 3 pages, recherche hors ligne | Suggestions pendant la frappe, catégories, recherche d'adresses complète, fusion et déduplication en ligne + hors ligne |
| Fiche lieu | Détails, horaires, galerie paginée avec catégories et visionneuse, panneau d'avis avec photos et tri, repli d'affluence, vignette Street View, appel et site | Mesures du repli et des avatars sur le runner, validation sur iPhone et sur IP résidentielle, réponses du propriétaire si le parseur commun les expose un jour |
| Itinéraires | Alternatives, voiture/marche/vélo, étapes hybrides, Transitous | Évitement complet, étapes intermédiaires, départ choisi, page Google Transit, marche/vélo avec les mêmes choix qu'Android, itinéraire enregistré avec sa géométrie |
| Navigation | Guidage, voix, caméra, recalcul, arrière-plan déclaré | Validation en conduite réelle, alertes radars et limitations, trafic et détours, arrêts, reprise après interruption, Bluetooth, écran verrouillé |
| Lieux enregistrés | Listes, récents, parking, imports, partage | Ouverture Maison/Travail en un geste, partage de liens courts, import Takeout complet et testé sur device |
| Hors ligne | Régions, carte et recherche locale, NoGoogle | Téléchargement en arrière-plan, reprise, mises à jour incrémentielles, cellules et petit zoom monde, stockage et erreurs d'espace |
| Réglages et langues | Lot I-8 en cours | Toutes les chaînes des nouvelles vues, langues RTL, confidentialité, rotation de session, blocage de télémétrie |
| Qualité | Scénarios XCUITest sur chaque fonction principale | Tests sur iPhone, mémoire, batterie, GPU de la page cachée, accessibilité, grands textes, paysage, petits écrans |

Ordre de grandeur : **10 à 15 lots** de travail, puis une passe de validation sur iPhone. À la
cadence actuelle, viser **1 à 2 semaines** pour une V1 stabilisée, sans garantir les délais de test
en conduite.

## Parité Android : gros blocs encore absents

1. **Carte et couches** : trafic Google, satellite, bâtiments 3D, topographie, routes peintes,
   feux et passages, caméras DeFlock et OSM, carburant, ponts NDW, overlays d'adresses, cellules,
   faible zoom monde, choix des couches et des icônes.
2. **Street View** : rendu des panoramas, navigation dans la photo et vignette de la fiche lieu.
3. **Navigation avancée** : alertes radars et excès de vitesse, recalculs de trafic, arrêts,
   partage et rejeu de trajets, statistiques et diagnostics de conduite.
4. **Hors ligne avancé** : deltas, paquets d'overlays, stockage déplaçable, et routage `.obf`
   OsmAnd, actuellement hors V1 car il faut une autre implémentation iOS.
5. **Voix** : voix neurales Piper/Kokoro via sherpa-onnx iOS, installation et catalogue des voix,
   dictée ASR et commandes vocales.
6. **Réglages et confidentialité** : les nombreux réglages Android, rotation et vieillissement des
   sessions, télémétrie, diagnostics et export.
7. **CarPlay** : équivalent d'Android Auto. Il faut l'entitlement CarPlay navigation d'Apple, et le
   cycle de vie de l'app est différent du sideload simple.
8. **Divers** : D-pad et téléphones sans écran (pas d'équivalent iOS direct), updater, anciennes
   versions d'OS et appareils spécifiques.

Ordre de grandeur pour 90 à 95 % de parité : **30 à 50 lots**, soit **4 à 8 semaines** avec
plusieurs agents, plus la validation humaine. Une parité strictement 100 % est une cible mouvante :
Android évolue chaque semaine et certaines fonctions n'ont pas d'équivalent direct sur iOS.

## Fonctions spécifiques iOS proposées

| Fonction | Contenu | Prérequis et limites | Estimation |
|---|---|---|---|
| **Live Activity conduite et marche** | Prochaine manœuvre, distance, ETA, progression sur écran verrouillé et Dynamic Island | ActivityKit, `NSSupportsLiveActivities`. L'activité affiche l'état, elle ne fait pas tourner le GPS : la navigation doit vivre en arrière-plan avec la localisation | 2 à 4 jours après stabilisation de I-5 |
| **Live Activity transports** | Prochaine ligne, direction, arrêt de descente, heures prévues et retard, marche jusqu'à l'arrêt | Modèle d'étape transport dans `NavStore` ou un `TransitSession`. Sans serveur de push Vela, les mises à jour ne sont pas garanties minute par minute app tuée : rafraîchissement quand l'app est active, tâches d'arrière-plan limitées, ou push à ajouter plus tard | 4 à 7 jours pour une V1 honnête, plus si push temps réel |
| **App Intents / Siri / raccourcis** | « Itinéraire vers Maison », « où est ma voiture », recherche Vela | App Intents et raccourcis enregistrés, tests en français et anglais | 1 à 3 jours |
| **Spotlight** | Lieux enregistrés et récents retrouvés depuis la recherche iOS | CSSearchableIndex, ouverture directe de la fiche | 2 à 3 jours |
| **Widgets** | Maison/Travail, parking, prochain départ transport | Timeline limitée : les horaires ne sont pas du temps réel garanti | 2 à 4 jours par widget |
| **CarPlay** | Carte, recherche, guidage | Entitlement Apple navigation, plus gros travail qu'une Live Activity | 1 à 2 semaines après V1 |
| **Apple Watch** | Manœuvre et ETA | Optionnel, pas dans la V1 | À cadrer plus tard |

Priorité recommandée après la V1 stabilisée : Live Activity conduite/marche, App Intents, Spotlight,
puis Live Activity transports. CarPlay et les voix neurales viennent ensuite.

## Règle de suivi

Chaque ligne de `FEATURES.md` sera reprise ici avec : ✅ validé sur iPhone, 🟡 présent et testé sur
simulateur, ⚠️ partiel, ❌ absent, ➖ sans équivalent iOS. Les écarts deviennent des lots. La matrice
détaillée est le prochain lot de stabilisation, pas une affirmation de parité déjà acquise.
