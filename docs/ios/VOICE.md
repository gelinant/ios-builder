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

# Réglages de la voix (VO-CONTROL)

État au 2026-10-27, branche `ios/vo-control`. Ce lot porte les réglages de volume, de vitesse et
de nivellement d'Android, et fait lire aux deux plateformes le même lexique de formes parlées. La
voix neuronale de VO-1 et la dictée de VO-2 ne changent pas de moteur : aucune voix, aucun modèle
et aucun son supplémentaire n'est livré.

## Volume d'aide

Réglages > Voix > Guidance volume propose les quatre crans d'Android, avec les mêmes clés de
chaînes : Softer 0,6, Normal 1,0, Louder 1,6, Loudest 2,2. La valeur est un gain **relatif** sur une
voix ramenée à un niveau de référence, pas un volume absolu.

- Voix neuronale : le gain s'applique aux échantillons PCM rendus par Piper, avant la lecture. Les
  crans au-dessus de 1 sont donc réels.
- Voix Apple : `AVSpeechUtterance.volume` est plafonné à 1,0 par iOS. Les crans Louder et Loudest
  sonnent comme Normal ; seuls Softer et Normal changent quelque chose. C'est la même limite
  qu'Android avec son `KEY_PARAM_VOLUME` borné à 1,0.
- La session reste `.playback` en mode `.voicePrompt`, avec `.duckOthers` et
  `.interruptSpokenAudioAndMixWithOthers`. iOS baisse les autres applications le temps de la
  phrase, puis rend leur volume. Le volume matériel de sortie reste commun à toutes les
  applications : aucun API iOS ne permet à Vela de régler la sortie indépendamment du volume
  média, ni d'augmenter celui-ci. Le réglage agit donc dans le mix de Vela et sur son propre PCM,
  ce qui est la seule indépendance que la plateforme autorise.

Le choix est enregistré dans `app.vela.ios.voice.volume` et relu au lancement. Il est visible dans
la ligne de diagnostic Debug `voice-control-debug`.

## Vitesse

Les préréglages Android sont repris tels quels : un multiplicateur de 0,5 à 2,0 par pas de 0,1,
valeur par défaut 0,8 (le défaut poussé par la calibration Android). Le même multiplicateur pilote
les deux moteurs :

- Apple : `AVSpeechUtteranceDefaultSpeechRate` (0,5) multiplié par le réglage, borné aux limites
  `AVSpeechUtteranceMinimumSpeechRate` et `AVSpeechUtteranceMaximumSpeechRate`. 1,00x correspond
  donc au débit Apple par défaut, 2,00x au maximum.
- Piper : le multiplicateur est passé à `SherpaOnnxOfflineTtsGenerate`, donc le débit et les
  pauses suivent le même réglage, comme le `voice_speed` d'Android.

Le choix est enregistré dans `app.vela.ios.voice.rate`. Les boutons − et + sont des cibles de
44 points et s'arrêtent aux bornes.

## Nivellement

`GuidanceLevel` reprend les constantes et la formule d'Android (`VoiceLevel`) : cible RMS 0,13,
relèvement maximal 4, coude 0,8, silence sous un pic de 0,02 ignoré. La moyenne quadratique de
chaque voix est mesurée sur l'audio brut, conservée par identifiant de voix dans
`app.vela.ios.voice.level.<id>`, puis un seul gain est appliqué à toute la phrase. Ce qui dépasse
0,8 est arrondi par une tangente hyperbolique au lieu d'être écrêté. Une voix déjà forte n'est
jamais baissée par le nivellement ; seul le cran de volume la baisse.

La voix Apple n'est pas nivelée : iOS n'expose pas son PCM, seulement `volume`. C'est une limite de
plateforme, pas un oubli.

## Lexique et normalisation

`SpeechText.forSpeech(text, language)` dans `:core-common` est désormais le seul point d'entrée des
formes parlées. Il applique, pour l'anglais uniquement :

- les abréviations de voirie (`St` → Street, `Ave` → Avenue, `Pkwy` → Parkway, directions) ;
- les références (`I-80` → Interstate 80, `CA-99` → State Route 99) et `take exit 186` →
  `take the 186 exit` ;
- les ordinaux de rue sur trois chiffres (`128th` → `one twenty eighth`) ;
- les horloges (`5:49 PM` → `five forty nine PM`) ;
- les unités des chaînes de transport (`10 min` → `10 minutes`, `0.4 mi` → `0.4 miles`).

La table des abréviations était privée dans `EnNavStrings` ; elle vit maintenant dans `SpeechText`
et `EnNavStrings.expandForSpeech` y délègue. Android garde donc exactement les mêmes sorties, ce
que `SpeechTextTest` et `NavStringsSnapshotTest` vérifient, et iOS lit la même table avant de
parler. La bannière et les étapes gardent la forme compacte (`Main St`) : c'est la même source,
transformée seulement pour la voix, comme sur Android.

Le dictionnaire de prononciation des 3 500 noms de lieux est maintenant embarqué côté iOS
(`iosApp/Vela/Voice/PlaceDictionary/vela-en_dict`, construit par `scripts/build-espeak-dict.sh`).
`PlaceDictionary` l'installe dans le `espeak-ng-data` de chaque voix anglaise complète, garde le
fichier d'origine en `en_dict.stock` et une version en `en_dict.vela`, donc l'opération est
idempotente et refaite quand le dictionnaire change. Il ne s'applique qu'aux voix Piper anglaises ;
la voix Apple a ses propres prononciations et ne lit pas ce fichier. Aucun modèle ni aucun son
n'est ajouté : le fichier pèse 228 Ko.

## Tests

Linux :

```
source ~/opt/env.sh
flock /tmp/opencode/gradle.lock ./gradlew --no-daemon -Pvela.iosOnly=true \
  :core-common:jvmTest :ios-shared:jvmTest :ios-shared:compileKotlinIosSimulatorArm64
```

`SpeechTextTest` couvre le lexique anglais, les unités, les références, les nombres et l'absence de
transformation dans une autre langue. Les attentes sont recopiées à l'identique dans
`GuidanceSpeechTests` côté Swift, pour que les deux plateformes soient comparées sur la même liste.

`VoiceTests` ajoute, côté Mac :

- `VoiceControlTests` : correspondance des préréglages de vitesse vers les débits Apple, bornes,
  persistance du volume et de la vitesse, plafond du volume Apple, gain et limiteur du
  nivellement, moyenne conservée par voix ;
- `GuidanceSpeechTests` : les mêmes phrases que la fixture Kotlin ;
- `PlaceDictionaryTests` : installation, sauvegarde du dictionnaire d'origine, idempotence par
  version, refus d'une voix non anglaise.

## Limites honnêtes

- Aucun API iOS ne règle le volume de sortie de l'application indépendamment du volume média. Le
  réglage est un gain logiciel relatif ; les crans forts ne dépassent pas le volume matériel.
- La voix Apple ne peut pas être nivelée et ne peut pas être amplifiée au-delà de son plein
  niveau. Seule la voix Piper profite du nivellement et des crans au-dessus de Normal.
- Le dictionnaire de noms de lieux est un binaire eSpeak compilé pour les voix Piper anglaises du
  catalogue. Une voix d'une autre langue, ou la voix Apple, ne l'utilise pas.
- Le rendu réel, le routage Bluetooth, les appels et le verrouillage restent des tests humains sur
  iPhone ; le simulateur ne prouve que la logique et la compilation.

## Résultat du run du 2026-10-27

Le Mac du LAN a redémarré pendant une mise à jour (Xcode 27.1, réseau coupé, puis refus de la
clé SSH) ; le run ciblé a donc été rejoué sur le runner GitHub, resté en Xcode 26.6 et iOS 26.5.

Run `vo-control-20261027-185957-12567` (commit source `eefdd946`) :

| Étape | Résultat |
|---|---|
| Kotlin JVM | 249 tests, 0 échec (dont `SpeechTextTest` et ses 5 nouvelles attentes) |
| Kotlin simulateur | 212 tests, 0 échec |
| Compilation app et tests | verte, `VelaCore.framework` produit |
| Tests Swift | 122 tests, 5 échecs, tous dans `IncomingLinksTests.testMoreStopsThanTheCapKeepTheFirstOnes`, hors voix et déjà présent sur cette base |
| Tests voix | `VoiceControlTests` (9), `GuidanceSpeechTests` (4), `PlaceDictionaryTests` (3), `VoiceSelectionTests` (8) et `VoiceSearchTests` (4) verts |
| Réglages > Voix | `VoiceUITests.testVoiceSettingsShowInstalledModel` vert en 29,0 s, `voice_engine=engine=neural_voice=en_US-hfc_female-medium`, capture `voice-settings.png` |
| Repli Apple | `VoiceUITests.testSystemVoiceWhenNeuralIsDisabled` vert en 27,5 s, `voice_fallback=engine=system_reason=disabled-for-test`, capture `voice-fallback.png` |
| Recherche vocale | les deux scénarios VO-2 verts, captures `voice-search.png` et `voice-search-intent.png` |
| Guidage neuronal | `testNeuralVoiceGuidanceAndFallbackMarker` rouge sur « no driving route » : le choix d'itinéraire n'a pas abouti dans les 90 s du scénario, avant toute phrase. Le guidage neuronal lui-même reste couvert par les runs VO-1 (`vo1-fix3-20261026-235926-7079`) et par `VOICE_SYNTH` (55 105 échantillons à 22 050 Hz sur ce run) |
| Synthèse | `VOICE_SYNTH samples=55105 rate=22050 wav_frames=55105` |

Le dictionnaire de noms de lieux n'est pas prouvé à l'oreille : `PlaceDictionaryTests` couvre
l'installation, la sauvegarde et l'idempotence, et la fixture Piper du run lit bien un modèle
anglais, mais aucune écoute automatique ne vérifie la prononciation d'un nom.

# Réglages de la voix (SET-VOICE)

État au 2026-10-28, branche `ios/set-voice`, depuis `ios/main` au commit `58f80fd5`. Ce lot
rassemble dans Réglages > Voix tout ce qui décide de la voix, y compris les deux clés que NAV-LIFE
écrit déjà. Aucun second magasin n'est créé : le mode parle à `NavStore`, la langue écrit la clé
Android `directions_language`, et l'ensemble installé reste dérivé du système de fichiers.

## Ce que la section montre

- **Spoken directions** : les trois états Android, On, Alerts only et Off. La ligne appelle
  `NavStore.setVoiceMode`, donc le bouton haut-parleur du bandeau et Réglages montrent le même
  état et écrivent les mêmes clés `spoken_directions` et `spoken_alerts_only`.
- **Directions language** : « Same as app language » ou l'une des 18 langues que les tables de
  navigation partagent réellement. Le choix est distinct de la langue des menus.
- **La voix qui parle** : « Voice: HFC Female (Vela) » quand un modèle complet de la langue des
  directions est installé, sinon « Voice: iPhone (system) ».
- **L'état sans voix** : un message explicite, le bouton de téléchargement de la voix recommandée
  avec sa taille, puis la bibliothèque. Une langue sans voix Piper, le japonais et l'hébreu, le dit
  et renvoie à la voix système au lieu d'offrir un téléchargement qui n'existe pas.
- **Les voix installées** : nom, taille, « In use », Use et Remove. Une voix d'une autre langue
  affiche « Directions are spoken in X. To hear this voice, set the directions language to Y. » et
  n'offre pas un Use sans effet.
- **La bibliothèque** : les 43 voix du catalogue Android, groupées par langue, avec la langue des
  directions en premier, la taille de chaque archive, le téléchargement, la progression en pour
  cent et la suppression.
- **Guidance volume** et **Voice speed** : les crans et les préréglages de VO-CONTROL, avec les
  mêmes clés `app.vela.ios.voice.volume` et `app.vela.ios.voice.rate`.
- **Voice search** : la sous-section VO-2 reste en dessous, inchangée.

## Langue des directions et langue de l'application

Une seule table `NavStringsRegistry` existe dans le processus. `SettingsStore.applyNavLanguage`
applique la langue de l'application au démarrage et à chaque changement ; `SettingsModel` applique
ensuite le choix explicite, dans cet ordre, pour ne pas être écrasé. La règle pure vit dans
`DirectionsLanguage` (`:ios-shared`) :

- une valeur explicite reconnue gagne ;
- sinon la langue de l'application, avec ses codes hérités (`iw` vers `he`) et ses variantes
  (`pt-BR`, `zh-Hant`) ;
- sinon l'anglais, seule langue toujours présente dans les tables.

`pt-br` garde la région `BR` et `zh-tw` le script `Hant`, car la table de navigation diffère. La
recherche vocale et ses exemples ne suivent pas ce choix : elles utilisent la langue de
l'application, comme avant.

## Téléchargement et suppression

Les règles de bouton sont partagées dans `VoiceInstallRules` (`:ios-shared`) : un seul
téléchargement à la fois, pas de second téléchargement d'une voix installée, pas de suppression
pendant l'extraction, et la suppression de la voix choisie efface le choix. Les deux écrans,
la section et la bibliothèque, lisent le même statut. La progression et l'installation viennent de
`VoiceLibrary`, qui garde le dossier de staging et la bascule atomique de VO-1.

## Limites de plateforme affichées

- La voix Apple `AVSpeechSynthesizer` ne peut pas être nivelée : iOS n'expose pas son PCM. Elle ne
  peut pas non plus être amplifiée au-delà de son plein niveau. La section le dit dans la ligne de
  volume : avec elle, Louder et Loudest sonnent comme Normal.
- Une langue sans voix neuronale installée, ou sans voix Piper du tout, utilise la voix système.
  La section l'explique avant de proposer un téléchargement.
- Le volume reste un gain logiciel relatif dans le mix de Vela, jamais le volume média du
  téléphone.
- Aucune ligne ne promet un moteur TTS tiers installable : iOS n'a pas d'équivalent au choix
  d'engine Android.

## Ce qui n'est pas dans ce lot

- « Say street names » (L130) et « How much the voice says » ne sont pas exposés : le moteur commun
  iOS ne lit pas encore `spoken_road_names` ni `spoken_detail`, et une ligne qui n'écrirait rien
  serait mensongère. Le bandeau et la voix restent en mode Everything avec les noms de rue.
- Le téléchargement réel d'un modèle de 67 Mo n'est pas rejoué par la CI. Le scénario de capture
  utilise `-VelaVoiceDownloadFixture`, un état Debug statique à 42 pour cent qui ne lance aucun
  transfert ; l'extraction réelle reste couverte par `VoiceTests`.
- Le nivellement et l'écoute réelle restent des tests humains sur iPhone.

## Tests

Linux :

```
source ~/opt/env.sh
flock /tmp/opencode/gradle.lock ./gradlew --no-daemon -Pvela.iosOnly=true \
  :core-common:jvmTest :ios-shared:jvmTest :ios-shared:compileKotlinIosSimulatorArm64
```

`DirectionsLanguageTest` couvre la normalisation des codes, la priorité du choix explicite, le
repli sur la langue de l'application puis l'anglais, les parties `pt-br` et `zh-tw` envoyées au
registre, et la présence d'une voix Piper par langue. `VoiceInstallRulesTest` couvre les boutons
d'une voix installée, choisie, absente, en téléchargement et en installation, le refus d'un second
téléchargement et l'effacement du choix à la suppression. `VoiceSelectionTest` reste inchangé.

Mac :

`scripts/ios/ci-ipa.sh VELA_ONLY_UI=SettingsVoiceUITests VELA_SKIP_ARCHIVE=1` joue
`SettingsVoiceUITests.testVoiceAndLanguage` : la section avec le modèle injecté et l'état de
téléchargement Debug, le passage en Alerts only puis retour à On par les clés partagées, la voix
neuronale active, le choix du français qui affiche le repli système, puis la bibliothèque groupée
par langue. Captures : `settings-voice.png`, `settings-voice-alerts.png`,
`settings-voice-section.png`, `settings-voice-language.png`, `settings-voice-download.png`,
`voice-library.png`.

## Résultat du run

Run `RUN_TAG` sur le runner GitHub (Xcode 26.6, simulateur iPhone 17, iOS 26.5) : à compléter.
