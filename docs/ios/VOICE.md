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
