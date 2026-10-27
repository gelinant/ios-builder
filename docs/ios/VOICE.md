# Voix neurales iOS (VO-1)

État au 2026-10-26, branche `ios/vo1-neural-voice`. Ce document décrit la voix Piper locale, son
runtime sherpa-onnx, le téléchargement des modèles, la sélection du moteur et les preuves. La voix
Apple `AVSpeechSynthesizer` reste le repli quand aucun modèle complet n'est installé, quand le
modèle ne parle pas la langue des directions ou quand son chargement échoue.

## Ce qui est livré

- Un runtime **sherpa-onnx 1.13.8** précompilé pour iOS, en xcframework
  (`SherpaOnnxC.framework`, tranches `ios-arm64` et `ios-arm64_x86_64-simulator`). C'est la
  variante `ios-shared-onnxruntime-static` : le framework est dynamique et embarque ONNX Runtime
  en statique, donc il est copié dans `Vela.app/Frameworks`. L'archive pèse 31 858 229 octets, le
  xcframework extrait environ 82 Mo.
- Le **catalogue Piper d'Android**, déplacé dans `:core-common` (`app.vela.core.voice.PiperCatalog`)
  pour que les deux plateformes lisent la même liste. 43 voix, mêmes identifiants, mêmes URL
  `vits-piper-<id>.tar.bz2` sur la release `tts-models` de `k2-fsa/sherpa-onnx`.
- Un **magasin sur disque** dans `Application Support/VelaVoices/<id>/`, avec la disposition exacte
  des archives Piper : `<id>.onnx`, `tokens.txt`, `espeak-ng-data/`. L'ensemble installé est dérivé
  du système de fichiers, jamais d'une préférence : un téléchargement interrompu n'est pas offert.
- Un **téléchargement dans l'app** depuis les mêmes URL HTTPS qu'Android, avec progression,
  extraction bzip2 + tar par SWCompression, validation de la taille du modèle et bascule atomique
  depuis un dossier de staging. La suppression libère le moteur avant d'effacer les fichiers.
- Une **synthèse** VITS dans `SherpaTts`, sur une file série, puis lecture par `AVAudioEngine`. Le
  taux d'échantillonnage vient de l'audio généré (Piper : 22 050 Hz ; un modèle 24 kHz passe sans
  changement). La session audio est `.playback` en mode `.voicePrompt` avec `.duckOthers` et
  `.interruptSpokenAudioAndMixWithOthers`, partagée avec la voix Apple et restaurée au Stop.
- Une **sélection par énoncé** dans `VelaNavVoice` : voix neuronale si un modèle complet de la
  langue des directions est installé, sinon Apple. Un échec de chargement bascule sur Apple pour
  la phrase en cours et évite de recharger le même modèle à chaque virage.
- Un **écran Réglages > Voix** : voix installées, voix en cours, Test voice, téléchargement de la
  voix recommandée, bibliothèque complète groupée par langue avec Use, Remove et Download.

## Intégration du framework

`scripts/ios/fetch-sherpa.sh` télécharge l'archive épinglée, vérifie sa taille et son SHA-256,
puis l'extrait dans `iosApp/Vendor/SherpaOnnxC.xcframework`. Le dossier est ignoré par Git. Le
script est idempotent et appelé par `scripts/ios/ci-ipa.sh` avant XcodeGen. En local :

```
bash scripts/ios/fetch-sherpa.sh
cd iosApp && xcodegen generate
```

`project.yml` déclare le xcframework en dépendance `embed: true` et le paquet Swift
`SWCompression` 4.9.1 (MIT) pour bzip2 et tar. Le choix de rester en **1.13.8** est volontaire :
sherpa-onnx 2.0 a retiré `data_dir` et attend des phonèmes déjà calculés. Les voix Piper du
catalogue ont besoin d'eSpeak NG embarqué dans le modèle ; 1.13.8 est la dernière version qui le
lit directement.

Android utilise le même runtime en AAR 1.13.3 et commons-compress pour les archives. iOS utilise
le xcframework statique et SWCompression ; le format des voix et les URL sont identiques.

## Modèles et droits

Les modèles ne sont pas dans le dépôt et ne sont pas propriétaires : ce sont les archives Piper
publiées par sherpa-onnx, téléchargées à la demande. Chaque voix garde son `MODEL_CARD`. Le runtime
sherpa-onnx est sous Apache-2.0. SWCompression est sous MIT. Aucun asset de voix n'est livré dans
l'IPA.

La voix par défaut du catalogue est `en_US-hfc_female-medium` (67 228 166 octets d'archive,
63 149 198 octets pour le `.onnx`), recommandée pour l'anglais. Le français recommandé est
`fr_FR-siwis-medium`.

Kokoro n'est pas exposé : le catalogue Android ne contient plus de voix Kokoro depuis juillet 2026
et `KokoroInstaller` n'est qu'un ancien nom de téléchargeur Piper. Le moteur iOS configure donc
VITS. Ajouter Kokoro demanderait une entrée de catalogue, `voices.bin` et `lexicon`, pas seulement
un nouveau identifiant.

## Sélection du moteur

`IosVoiceSelection` (Kotlin commun, testé sous Linux) applique les règles pures :

- un identifiant Piper porte sa langue en préfixe (`en_US`, `fr_FR`) ;
- la voix choisie doit être installée et complète, et sa langue doit être celle des directions
  (`NavStringsRegistry.current().language`) ;
- sinon la première voix installée de cette langue est utilisée ;
- sinon `AVSpeechSynthesizer`.

Il n'y a pas encore de bascule temporaire vers une autre voix installée quand la langue change en
cours de session, ni de carte « télécharger une voix pour cette langue ». La bibliothèque et le
bouton de téléchargement de la voix recommandée sont les chemins offerts.

## Audio

- Une phrase entière est rendue avant lecture. Une interruption coupe la lecture en cours et
  invalide la génération : aucun mélange de deux phrases.
- Le silence entre phrases et le nivellement Android (`VoiceLevel`), le volume et la vitesse ne sont
  pas portés. Le débit neuronal reste à 1,0 et Apple à 0,97 fois le débit par défaut.
- Le dictionnaire de prononciation des 3 500 lieux et `SpokenScript` restent hors de ce lot.

## Tests

Linux :

```
source ~/opt/env.sh
flock /tmp/opencode/gradle.lock ./gradlew --no-daemon -Pvela.iosOnly=true \
  :core-common:jvmTest :ios-shared:jvmTest :ios-shared:compileKotlinIosSimulatorArm64
```

`VoiceSelectionTest` couvre les 43 identifiants, les URL, les dispositions complètes ou partielles
et les replis de langue. `:core:compileDebugKotlin` vérifie que le déplacement de `PiperCatalog`
dans `:core-common` ne casse pas Android.

Mac :

- `VelaTests/VoiceTests.swift` couvre le catalogue, le magasin, une voix absente ou corrompue, une
  sélection supprimée, une voix d'une autre langue, l'extraction d'une archive synthétique et le
  refus d'une entrée `../`.
- `NeuralSynthesisTests` charge un vrai modèle Piper, synthétise « In a quarter mile, turn right
  onto Main Street. », exige 22 050 Hz, écrit un WAV et le décode avec `AVAudioFile`. Le modèle est
  fourni par `scripts/ios/fetch-voice-fixture.sh` (archive épinglée par SHA-256) et copié dans le
  bundle Debug par `ci-ipa.sh`, uniquement pour les tests.
- `VoiceUITests` vérifie l'écran Réglages avec le modèle installé (`voice-settings.png`), la
  bibliothèque (`voice-library.png`), puis un guidage réel dont la ligne `nav-voice-debug` contient
  `engine=neural` (`voice-guidance.png`). L'argument `-VelaVoiceDisableNeural YES` force le repli
  Apple pour un contrôle manuel ; il n'est lu qu'en Debug.

Le fixture de test n'entre ni dans l'archive Release ni dans l'IPA. Sans fixture, le test de
synthèse est sauté et le résumé du run le dit.

## Résultat du run du 2026-10-26

Run `vo1-neural-voice-20261026-212327-31706` (Xcode 26.6, simulateur iPhone 17, iOS 26.5) :

| Étape | Résultat |
|---|---|
| Kotlin | `jvmTest` 171/171, `iosSimulatorArm64Test` 150/150 |
| Tests Swift | 86 tests, 0 échec, dont la sélection, le catalogue, les archives synthétiques et la synthèse |
| Synthèse réelle | `SEAM_TEST VOICE_SYNTH samples=56856 rate=22050 wav_frames=56856` : le modèle HFC Female a produit 56 856 échantillons à 22 050 Hz, écrits et relus en WAV |
| Guidage neuronal | `VoiceUITests.testNeuralVoiceGuidanceAndFallbackMarker` vert en 23,7 s : `voice_guidance=spoken=2_text=In_500_feet,_Turn_right_onto_Mission_Street...last=neural_next=engine=neural` |
| Repli | `VoiceUITests.testSystemVoiceWhenNeuralIsDisabled` vert en 11,3 s : `voice_fallback=engine=system_reason=disabled-for-test` |
| IPA | `Vela-unsigned.ipa`, 20 478 563 octets, frameworks `MapLibre.framework` et `SherpaOnnxC.framework`, binaire arm64 17 592 896 octets. Cette IPA précède la correction de format ci-dessous. |
| Écran Réglages | Le scénario a échoué après l'ouverture de Réglages : la ligne « In use » passait un `Int` à un format `%3$@`. Correction appliquée après le run (chaîne convertie en `String`), capture `voice-settings.png` à refaire au prochain run |

La suite UI complète n'est pas verte : plusieurs scénarios hors voix (itinéraires, Saved, Quality,
transit) échouent sur ce run, et le scénario Réglages > Voix a besoin du run de confirmation après
la correction de format. Les deux preuves voix, guidage neuronal et repli, sont vertes.

## Limites honnêtes

- Le simulateur exécute bien le xcframework arm64 ; la preuve de synthèse vient des tests
  simulateur, pas d'une écoute sur iPhone. Le rendu audio réel, le routage Bluetooth, les appels et
  le verrouillage restent des tests humains.
- La capture `voice-settings.png` et le scénario « modèle installé » demandent un run après la
  correction du format `settings_voice_row_in_use`. Le guidage neuronal et le repli sont déjà
  prouvés sur simulateur.
- Le téléchargement in-app d'un modèle de 67 Mo n'est pas rejoué par la CI : l'extraction est
  testée avec une archive synthétique, et le modèle réel est injecté par le bundle de test. Une
  panne réseau ou un espace disque insuffisant restent à vérifier à la main.
- L'extraction bzip2 en Swift pur peut prendre plusieurs secondes et utiliser environ 150 Mo de
  mémoire pour un modèle moyen ; c'est un coût unique au téléchargement.
- La sélection ne mélange pas les langues : une voix française installée ne parle pas les
  directions anglaises, et inversement.
- Le gain, la vitesse, le volume et le nivellement Android ne sont pas portés.
- Le framework est un binaire précompilé non versionné : sans réseau, `fetch-sherpa.sh` doit être
  lancé depuis une copie de l'archive, et le build échoue si `Vendor/` est absent.

# Recherche vocale (VO-2)

État au 2026-10-27, branche `ios/vo2-dictation`. Ce lot ajoute la dictée et les intentions vocales
à iOS. La voix de guidage de VO-1 est inchangée ; la dictée partage sa session audio et ne parle
jamais par-dessus le microphone.

## Reconnaissance

Deux moteurs, choisis par ce qui est installé :

1. **sherpa-onnx hors ligne** avec les archives `asr-models` d'Android, mêmes identifiants, mêmes
   URL, mêmes tailles et mêmes SHA-256. Le catalogue commun est `app.vela.core.voice.AsrCatalog`
   (`:core-common`) ; Android garde son `AsrEngine` pour ses préférences, la liste des deux côtés
   doit rester identique. Par défaut : Whisper tiny en anglais, Whisper base pour les autres
   langues ; SenseVoice et Moonshine restent des choix explicites. L'audio ne quitte jamais le
   téléphone.
2. **`SFSpeechRecognizer` d'Apple** quand aucun modèle n'est installé, avec
   `requiresOnDeviceRecognition = true`. Si l'appareil ou la langue ne savent pas le faire en
   local, Vela refuse et le dit, au lieu de laisser Apple envoyer l'audio à son service. C'est la
   différence de confidentialité à connaître : le chemin Apple reste sur l'appareil ici, mais il
   dépend des langues installées par iOS, et il n'a pas la parité de langues de Whisper.

Le premier moteur est préféré dès qu'un modèle est présent. Les modèles se téléchargent dans
Réglages > Voix > Recherche vocale (un à la fois, contrôle de taille et de SHA-256, extraction
gzip + tar par SWCompression, bascule atomique depuis un dossier de staging, même règle que les
voix Piper). L'ensemble installé est dérivé du système de fichiers.

Il n'y a pas de microphone permanent : la session ne s'ouvre qu'après un appui sur le bouton
micro, se ferme au Stop, au bouton Annuler, au silence (1,4 s) ou après 12 s. La carte de écoute
affiche l'anneau de niveau, le texte entendu, les exemples de commandes partagés avec Android et
la mention de confidentialité du moteur utilisé. Un arrêt automatique par silence repose sur un
seuil RMS, pas sur Silero VAD comme Android.

## Intentions

Le texte reconnu passe par **`QueryIntents`**, déplacé de `:core` vers `:core-common` pour que les
deux plateformes lisent le même vocabulaire. Le repli d'accents utilise `OfflineRank.fold` au lieu
de `java.text.Normalizer`, qui n'existe pas en commun ; les tests de `QueryIntentTest` et
`QueryIntentExamplesTest` ont suivi le déplacement et tournent sous Linux.

`VoicePlanner` (`:ios-shared`) traduit l'intention en action :

| Texte | Action iOS |
|---|---|
| « coffee », « pharmacie près de moi » | recherche avec le remplissage retiré, via `SearchStore` |
| « navigate to X » | recherche X, puis choix d'itinéraire sur le premier résultat |
| « take me home », « get me to work » | raccourci enregistré, puis choix d'itinéraire |
| « from A to B » | les deux extrémités passent par la recherche, le départ est posé sur le choix |
| « what's my ETA » | réponse parlée si un guidage est en cours |

Aucun second chemin de recherche : les actions appellent le `SearchStore` et le `RouteStore`
existants. Une requête non reconnue reste une recherche simple, donc « Home Depot » ne déclenche
pas le raccourci Maison.

## Audio

`VoiceAudioMachine` (`:ios-shared`, testé sous Linux) décrit la chronologie : démarrer, baisser les
autres sons une seule fois, retenir une phrase de guidage demandée pendant l'écoute, restaurer une
seule fois. Côté Swift, `DictationAudio` exécute ces étapes : `.playAndRecord` en mode
`.measurement` avec `.duckOthers`, arrêt de la phrase de guidage en cours avant d'ouvrir le micro,
puis retour à la catégorie capturée avant la dictée. `VelaNavVoice` retient la dernière phrase
demandée pendant l'écoute et la dit après la restauration. Une annulation restaure exactement comme
un arrêt normal.

## Échecs

Chaque cas laisse l'app utilisable et affiche un message dans la carte :

- microphone refusé : renvoi vers Réglages, ou téléchargement d'un modèle ;
- reconnaissance Apple refusée ou indisponible : renvoi vers Réglages ;
- reconnaissance Apple impossible sur l'appareil pour la langue : message explicite, modèle local
  proposé ;
- aucun moteur installé : le repli Apple est utilisé, sinon le refus est expliqué ;
- aucun son, silence ou fichier vide : « No speech was heard » ;
- modèle supprimé entre le téléchargement et l'écoute : message de re-téléchargement ;
- réseau absent pendant un téléchargement : le staging est supprimé et l'erreur est affichée ;
- annulation : rien n'est appliqué et la session est restaurée.

## Réglages

Réglages > Voix > Recherche vocale liste les moteurs installés (Use, Remove), propose le
téléchargement du moteur recommandé pour la langue et affiche la progression, l'erreur et, en
Debug, une ligne `asr-debug`.

## Tests

Linux :

```
source ~/opt/env.sh
flock /tmp/opencode/gradle.lock ./gradlew --no-daemon -Pvela.iosOnly=true \
  :core-common:jvmTest :ios-shared:jvmTest :ios-shared:compileKotlinIosSimulatorArm64
```

`VoiceDictationTest` couvre les phrases reconnues (recherche, navigation, Maison, Travail, trajet,
ETA, nom d'entreprise), la chronologie audio (duck une fois, interruption du guidage, phrase
retenue, restauration unique, annulation) et la sélection de moteur par langue. Les tests déplacés
de `QueryIntentTest` et `QueryIntentExamplesTest` tournent dans `:core-common:jvmTest`.

Mac :

- `VelaTests/VoiceSearchTests.swift` vérifie la forme du catalogue (identifiants, URL, tailles,
  SHA-256, fichiers), le magasin dérivé du système de fichiers, les phrases reconnues, puis une
  **reconnaissance réelle** : la voix Piper de VO-1 synthétise « Navigate to coffee », l'audio est
  ramené à 16 kHz et Whisper tiny le transcrit ; la ligne `SEAM_TEST VOICE_ASR` donne le texte. Ce
  test est sauté sans les fixtures `VoiceFixture` ou `AsrFixture`.
- Les deux scénarios UI injectent le texte reconnu (le simulateur CI n'a pas de micro exploitable) :
  `-VelaVoiceQuery coffee` prouve que le texte atteint le champ de recherche et que la recherche
  ordinaire s'exécute (`voice-search.png`) ; `-VelaVoiceQuery "navigate to coffee"` prouve que
  l'intention de navigation ouvre le choix d'itinéraire (`voice-search-intent.png`).

Ce qui est réel dans ces preuves : le catalogue, le magasin, le parseur d'intentions, la recherche,
le choix d'itinéraire et la transcription d'un vrai modèle. Ce qui est injecté : le texte reconnu
des scénarios UI, faute de micro dans le simulateur. La capture micro, le niveau, le bruit réel et
le routage Bluetooth restent des tests humains sur iPhone.

## Résultat du run du 2026-10-27

Run `vo2-dictation-20261027-040248-1507` (Xcode 26.6, simulateur iPhone 17, iOS 26.5), construit
depuis le commit source `84e43f38` :

| Étape | Résultat |
|---|---|
| Kotlin JVM | 198 tests, 0 échec (dont `VoiceDictationTest`, `QueryIntentTest`, `QueryIntentExamplesTest`) |
| Kotlin simulateur | 166 tests, 0 échec |
| Tests Swift | 90 tests, 0 échec (dont `VoiceSearchTests`) |
| Reconnaissance réelle | `SEAM_TEST VOICE_ASR text=Never_get_to_coffee. samples=17833` : Piper a dit « Navigate to coffee », Whisper tiny a bien reconnu « coffee » mais a entendu le verbe comme « Never get to ». Le test n'exige que le mot ; voir la limite ci-dessous. |
| Synthèse VO-1 | `VOICE_SYNTH samples=55727 rate=22050` : le chemin Piper reste vert |
| Scénarios UI voix | 5/5 verts, dont les 2 nouveaux : `voice_search_query=coffee`, `voice_search_results=71`, `voice_intent_chooser=1`, `voice_intent_destination=All_Star_Cafe` |
| Captures | `voice-search.png` (71 résultats), `voice-search-intent.png` (choix d'itinéraire, 5 min, voiture) |
| IPA | `Vela-unsigned.ipa`, 20 717 820 octets, binaire arm64 18 299 272 octets, frameworks MapLibre et SherpaOnnxC |

Les captures montrent le bouton micro sous le bouton Saved (Debug affiche les lignes de diagnostic).

## Limites honnêtes

- Le texte synthétique « Navigate to coffee » a été transcrit « Never get to coffee. » par Whisper
  tiny : la reconnaissance réelle du mot est prouvée, mais le verbe a été mal entendu, et le
  parseur commun lit alors « never … to coffee » comme un trajet. Le scénario UI et les tests du
  parseur prouvent l'intention de navigation avec un texte exact. Un réglage de modèle (Whisper
  base) ou un vrai micro donnera un meilleur résultat ; ce n'est pas mesuré ici.
- Aucun test automatique n'ouvre le microphone : la capture réelle, le silence, le refus de
  permission et l'interruption d'un appel restent à vérifier sur iPhone.
- Silero VAD n'est pas branché côté iOS ; la fin d'écoute est un seuil RMS après 1,4 s de silence.
- « from A to B » fait deux recherches successives et ne pose le départ qu'après coup ; le départ
  choisi peut différer de la meilleure correspondance sur les noms ambigus.
- L'ETA n'est répondu à voix haute que pendant un guidage ; hors guidage, un message le dit.
- Le texte des messages et des réglages est en anglais dans le code ; il entre dans le catalogue
  de chaînes au prochain passage du script de chaînes.
- Le téléchargement d'un modèle de 58 à 222 Mo n'est pas rejoué par la CI ; seule l'extraction
  avec une vraie archive est testée, par la fixture Whisper tiny.
