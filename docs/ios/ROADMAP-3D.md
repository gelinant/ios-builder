# Feuille de route 3D, atmosphere et monde vivant

## Decision

La 3D « vraie » dans la carte principale se fera par un **renderer custom** (voie a du spike
`docs/ios/TERRAIN-SPIKE.md`), pas en attendant une API terrain de MapLibre Native. Ce chantier
commence **apres** la parite et apres la phase 8, pas avant.

Le spike a montre que la voie est techniquement ouverte : `MLNCustomStyleLayer` heberge un maillage
Metal dans la passe de la carte, partage la profondeur, suit la camera a 3,2e-9 pixel d'erreur et
tient 55 images par seconde a 2 097 152 triangles. Il a aussi montre ce qui manque : routes et
batiments non drapes, compositing d'overlay non resolu, LOD, ombrage et eau a faire. C'est pour cela
que le chantier est planifie, pas improvise.

## Perimetre vise

| Element | Contenu | Depend de |
|---|---|---|
| Terrain | maillage DEM drape, routes et batiments poses sur le relief, LOD par tuile | base du renderer |
| Atmosphere | ciel physique simple, brume de distance, halo solaire, nuit | terrain |
| Arbres | houppiers en volume la ou OSM donne `natural=tree`, forets en canopee texturee | terrain |
| Mer | surface animee, reflets, cote et bathymetrie grossiere | atmosphere |
| Meteo temps reel | precipitations, nuages, vent, temperature depuis un fournisseur a declarer | atmosphere |

Chaque element suit les memes regles que le reste du projet : aucune donnee inventee, une notice et
une attribution par source, un etat « indisponible » explicite quand la source manque, et le
hors-ligne traite separement du temps reel.

## Ordre de travail

1. **Base du renderer** : drapage des routes et des batiments (le defaut constate au spike), LOD et
   streaming des tuiles DEM, passage iPhone avec mesure de fps et de batterie. 8 a 11 sessions.
2. **Atmosphere** : ciel et brume, une seule passe, sans nouveau serveur. 2 a 3 sessions.
3. **Arbres** : houppiers en volume, reutilise le calque `TREES-LAYER` deja livre en 2D. 2 sessions.
4. **Mer** : surface et cote. 3 a 4 sessions.
5. **Meteo temps reel** : fournisseur a choisir et a declarer (licence et quota), cache, et une
   couche qui ne pretend jamais etre en direct sans horodatage. 3 sessions.

Total estime : **18 a 23 sessions**, apres la fin de la phase 8.

## Ce qui ne change pas

- Aucune couche du renderer custom ne remplace la carte MapLibre : elle s'y ajoute, et la carte
  reste utilisable si le renderer echoue ou si l'appareil ne le supporte pas.
- Le hors-ligne reste une exigence : un relief telecharge doit s'afficher sans reseau.
- Les tests de non-regression de la carte, des itineraires et du guidage restent la condition de
  merge de chaque etape.
- Pas de moteur « maison » complet : on ajoute des passes Metal a MapLibre, on ne reecrit pas le
  moteur de rendu, et on garde la possibilite de revenir a la carte seule.

## Etat

- Spike : fait, `docs/ios/TERRAIN-SPIKE.md`.
- Chantier : **planifie apres la phase 8**, non commence.
- Prealable immediat quand on y arrivera : relire le spike, refaire un build du renderer de test sur
  la version MapLibre du moment, puis seulement ouvrir le lot de drapage.
