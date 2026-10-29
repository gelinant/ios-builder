# W-2 : spike WKWebView (scrapes cachés de Vela sous iOS)

> Question : un WKWebView (moteur Safari) peut-il exécuter les scrapes en WebView cachée de Vela
> et obtenir les mêmes données qu'Android ? Réponse : **oui, go pour I-3**, avec deux réserves
> (WebGL de la carte Google, course au chargement), décrites au §5.

## 1. Méthode

- **JS identique à l'octet.** `tools/ios-spike-web/gen_js.py` lit les sources Kotlin (en lecture
  seule) et évalue les raw strings comme Kotlin : `${'$'}`, `$nom`, `${expr}`, puis
  `trimIndent()`. Il en tire `js/reviews.js` (`WebReviewsFetcher.extractScript`, cap 50, mots de
  `ReviewWords`, `STRIP_PLACE_NAME_JS`, sélecteurs par défaut), `js/photos.js`
  (`WebPhotoFetcher.extractScript`, cap 80, walk complet) et `js/popular.js`
  (`WebPopularTimesFetcher.script`, URL de détails construite comme `SearchPb.build` +
  `BrowserViewport.apply` 1920x945 + `URLEncoder`). L'app embarque ces octets en base64 avec leur
  SHA-256 et le vérifie au lancement (`matchesGenerator: true` sur les trois runs). L'id de
  requête (`@@ID@@`) et les noms de pont (`VelaBridge`, `VelaPanel`) sont substitués à
  l'exécution, comme `JsNames.of`, par des noms aléatoires de 11 caractères.
- **Pont émulé.** Un `WKUserScript` au début du document (cadre principal) définit
  `window.<nom aléatoire>` (non énumérable) avec `onResult`, `onProgress`, `onInfo`,
  `onHistogram`, `onPartial`, `onDates`. Chaque méthode poste `{m, a:[...]}` vers un
  `WKScriptMessageHandler` au nom lui aussi aléatoire. Les scripts sont lancés par
  `evaluateJavaScript` dans le monde de la page, comme `evaluateJavascript` sur Android.
- **Séquence Android rejouée.** Avis et photos : `load(/maps?cid=75778018372833520&hl=en&gl=us)`,
  injection une seule fois au premier des deux : fin de page + 150 ms (photos 1,2 s) ou plafond
  de 7 s. Affluence : `google.com/?hl=en&gl=us`, puis `sessionWarmUrl` 500 ms après, fin + 1,2 s ou
  plafond 9 s, puis le `fetch` same-origin. Navigation du cadre principal limitée à http(s) et,
  pour avis et photos, à `google.com`.
- **Identité.** `customUserAgent` Safari 26 macOS, `preferredContentMode = .desktop`, cookies
  `SOCS=CAESHAgBEhIaAB` et `CONSENT=YES+` sur `.google.com` via `WKHTTPCookieStore`, magasin
  `nonPersistent()` partagé par les scrapes d'une variante (comme le `CookieManager` Android).
  `BlockedHosts` en `WKContentRuleList` (12 règles, compilées sans erreur).
- **Taille.** Avis 1200x1000 pt (= CSS px), photos 1200x3200 pt, comme Android.
- **Où.** Simulateur iPhone 17, iOS 26.5, runner `macos-latest` du builder (Xcode 26.6), sortie par
  une IP de datacenter Microsoft. Fixture : Davis Food Co-op,
  `0x8085299fd6f41a23:0x10d37b4cae550f0`.
- **Lancement.** `scripts/ios/ci-webspike.sh [lettres de variantes]` : XcodeGen, build simulateur,
  boot, install, `simctl launch --console`, récupération du conteneur (`spike-result.json`,
  `spike-log.txt`, réponses brutes, snapshots), captures d'écran, extrait du log WebKit.

## 2. Runs (branche `results` du builder)

| Run | Tag | Variantes |
|---|---|---|
| 1 | `w2-webview-spike-20261024-205758-21667` | A visible, B offscreen magasin par défaut, C détaché, D UA mobile |
| 2 | `w2-webview-spike-20261024-211548-1987` | A offscreen, B offscreen après warm, V visible |
| 3 | `w2-webview-spike-20261024-213209-27315` | W offscreen sans WebGL (diagnostic), A offscreen |

## 3. Résultats

| Scrape (variante, run) | Résultat | Temps | Notes |
|---|---|---|---|
| Avis, W sans WebGL, run 3 | **5 avis**, `onResult` final | page 1,6 s, résultat 36,0 s | 5/5 : auteur, note, date, texte, avatar, id ; 3 avec photos (12 URL) ; histogramme `[783,215,58,17,21]` |
| Avis, W, 2e scrape même session | 5 avis | 40,5 s | identique |
| Avis, offscreen avec WebGL (runs 1 à 3) | 5 avis en partiels, pas de `onResult` | onglet ouvert vers 6 s | page figée par le plantage du processus GPU (§4) |
| Avis, détaché (C) | 0 | 2 ticks en 50 s | `visibilityState: hidden`, minuteries bridées |
| Avis, UA mobile (D) | 0 | 37 s | page mobile sans onglets ni cartes `.jJc9Ad` |
| Affluence, offscreen (runs 1 et 2) | réponse 52 Ko, nœud focalisé = la fixture | 10,9 à 26,8 s | note 4,6, 1094 avis, adresse, horaires, téléphone ; **pas de `[84]`** |
| Affluence, UA mobile (D) | 48 Ko, même contenu | 3,9 s | pas de `[84]` |
| Affluence, A run 3 | réponse vide | 9,8 s | plafond de warm atteint en pleine navigation, le `fetch` meurt avec le document |
| Photos, offscreen (A run 2) | 17 photos | 13,0 s | histogramme reçu |
| Photos, W sans WebGL | **27 photos** | 25,9 s | pas d'onglets de catégorie, 0 date (`APP_INITIALIZATION_STATE` sans photo) |

Ce que montre la capture du panneau (`snap-B-reviews.jpg`, run 2) : la mise en page **desktop**
complète (onglets Overview / Reviews / About, carte vectorielle, cartes d'avis), le bandeau
« You're seeing a limited view of Google Maps », un bouton « See more reviews (1,089) » et une
fenêtre « Sign-in to get the best of Google Maps ».

Lecture :

- **Le chemin complet marche** : chargement, injection, clic sur l'onglet Avis (`aria-selected`),
  défilement, déduplication, partiels, histogramme, résultat final, et tous les champs que lit
  `ReviewsWebParser`. Le script n'a pas eu à changer.
- **5 avis, c'est la vue limitée de Google**, pas une limite de WKWebView : SPEC (§3.7, « The feed
  stays off ») dit qu'une session anonyme neuve est limitée à cinq avis, et la page affiche le
  bandeau. Sur une IP de datacenter, Android n'obtient pas mieux. Le script tourne alors jusqu'à
  son arrêt dur (130 ticks, environ 34 s), comme sur Android.
- **L'affluence manque pour la même raison** : réponse « slim » des IP de datacenter (voir
  `GoogleHealthProbeTest`), sans `[84]`. Le reste des détails (note, nombre d'avis, horaires,
  adresse, téléphone) arrive bien, et le nœud `[0][1][0][14]` est celui de la fixture.
- Les nombres complets (avis au-delà de 5, affluence) ne peuvent se mesurer que depuis un iPhone
  sur IP résidentielle ou mobile.

## 4. Le plantage GPU du simulateur

Le log WebKit (`webkit-log.txt`) montre `GPUProcessProxy::gpuProcessExited: reason=Crash` en
boucle (10 fois au run 3), puis `RemoteRenderingBackendProxy::didBecomeUnresponsive`, et parfois
`web content process terminated`. Côté page : `The rendering context was not restored after 25
rendering frames` et le détecteur de tâches longues de Google (`qf for 10s`). La carte WebGL de
Google Maps fait tomber le processus GPU du simulateur du runner (GPU paravirtualisé) ; le fil
principal de la page reste bloqué des dizaines de secondes et le script n'atteint pas son
`onResult`. Sans WebGL (variante W, `getContext('webgl')` renvoie `null`), Maps dessine sans
et les trois scrapes vont au bout.

C'est très probablement un artefact du simulateur. Sur un iPhone, WebGL tourne sur un vrai GPU.
Mais une carte WebGL à 1200x1000 pt en @3x (3600x3000 px) cachée coûte mémoire et batterie (le
processus WebContent était à 319 Mo après chargement). À mesurer sur l'iPhone dans I-3.

## 5. Différences avec Android

| Sujet | Android | iOS (WKWebView) |
|---|---|---|
| Pont | `addJavascriptInterface`, nom de `JsNames` | `WKUserScript` + `WKScriptMessageHandler`, deux noms aléatoires (objet de page et handler) ; arguments convertis en chaînes |
| `X-Requested-With` | envoyé sur chaque requête, d'où `WebProxy` / `WebStreamProxy` / Cronet | **jamais envoyé** : pas de proxy ni d'interception |
| Client hints | métadonnées UA à forger | Safari n'en envoie pas : rien à faire |
| `BlockedHosts`, télémétrie | `shouldInterceptRequest` → réponse vide | `WKContentRuleList` (bloque au lieu de répondre vide ; la télémétrie optionnelle sera une seconde liste ajoutée ou retirée) |
| `allowNavigation` | `shouldOverrideUrlLoading` | `decidePolicyFor` sur le cadre principal |
| Vue cachée | `measure`/`layout` hors fenêtre, `onResume`/`resumeTimers` | doit être **dans la fenêtre** (hors écran suffit) : détachée, la page est `hidden` et bridée |
| Pause après fetch | `onPause` | pas d'équivalent public ; retirer la vue de la fenêtre (bridage) ou charger `about:blank` |
| Viewport | CSS px x densité | points = CSS px ; `innerWidth` 1200, `innerHeight` 904 hors écran (barres retirées), `devicePixelRatio` 3 |
| Empreinte JS | Chrome Windows | `navigator.platform` `MacIntel` mais `maxTouchPoints` 5 : un iPad en mode bureau, cohérent avec un Safari Apple ; aucun refus constaté |

## 6. Décision pour I-3

**Go.** La fiche lieu iOS garde les scrapes WebView, avec les scripts d'Android tels quels
(déplacés dans `:core-common`, `app.vela.core.web`, comme prévu, pour une seule source). Règles pour
le `HiddenWebView` Swift :

1. Le WKWebView est attaché à la fenêtre, hors écran, à la taille Android (avis 1200x1000, photos
   1200x3200). Jamais détaché.
2. UA Safari macOS + `.desktop` (D11). L'UA mobile sert une page sans onglets : non.
3. Pont par `WKScriptMessageHandler`, noms aléatoires par processus.
4. `WKContentRuleList` pour `BlockedHosts`. Aucune interception, aucun proxy.
5. `webViewWebContentProcessDidTerminate` traité : rendre les derniers partiels plutôt que rien.
6. À mesurer sur un iPhone avant de figer : le coût de la carte WebGL cachée (si elle pèse ou
   plante, refuser WebGL dans la vue cachée, ce qui a marché ici, au prix d'une modification de
   page détectable) ; le nombre d'avis et l'affluence sur IP résidentielle.

## 7. Risques et constats hors périmètre

- **Course au chargement** (aussi présente sur Android) : le plafond de 7 s (avis, photos) ou de
  9 s (warm de l'affluence) peut injecter dans un document qui va être remplacé. L'id est alors
  marqué injecté et l'injection de fin de page est refusée : le scrape expire sans rien (vu deux
  fois sur des chargements lents). Une injection devrait être autorisée à nouveau après un
  changement de document. À signaler pour `WebReviewsFetcher`, `WebPhotoFetcher` et
  `WebPopularTimesFetcher` (hors périmètre, non modifiés).
- Snapshots `takeSnapshot` peu fiables quand le processus GPU tombe (« unknown error »).
- Le premier boot du simulateur a pris 7 minutes au run 1 ; le script boote maintenant en tâche de
  fond pendant le build.
