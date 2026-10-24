# W-1 : spike de faisabilité du scraping Google depuis iOS

> But : répondre **AVANT toute migration KMP** si Google laisse passer le trafic
> iOS malgré la divergence de fingerprint réseau (Apple TLS / CFNetwork vs
> Chromium/Cronet d'Android). Sortie : un go/no-go documenté.
>
> Source des valeurs ci-dessous : `calibration.json` (version 27) +
> `core/data/google/BrowserHeaders.kt` + `core/data/google/GoogleSession.kt` +
> `core/di/CoreModule.kt` (cookies).

## 1. Ce que Vela prétend être (l'identité à rejouer)

Vela prétend être **Chrome 156 desktop sur Windows** :

| Header | Valeur |
|---|---|
| `User-Agent` | `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36` |
| `Sec-CH-UA` | `"Not:A-Brand";v="8", "Chromium";v="156", "Google Chrome";v="156"` |
| `Sec-CH-UA-Mobile` | `?0` |
| `Sec-CH-UA-Platform` | `"Windows"` |
| `Accept` | document : `text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8` · XHR : `*/*` |
| `Accept-Language` | `en-US,en;q=0.9` |
| `Sec-Fetch-Dest/Mode/Site` | document : `document/navigate/none` · XHR : `empty/cors/same-origin` |
| `Referer` | document (warm-up) : absent · XHR : page d'origine |
| `Downlink` / `RTT` | `10` / `50` (uniquement les XHR après warm-up) |

Cookies pré-semés (CoreModule `InMemoryCookieJar`) sur `google.com` / `www.google.com` /
`consent.google.com` : `SOCS=CAESHAgBEhIaAB`, `CONSENT=YES+`.

## 2. La séquence à rejouer (5 requêtes, dans l'ordre)

Une vraie session = un warm-up puis les RPC. Les `pb=…` sont des protobufs
encodés « `!…!` + hex » (les `{...}` sont des placeholders à substituer).

0. **Warm-up** (obligatoire, récupère les cookies NID/consent) :
   `GET https://www.google.com/maps?hl=en&gl=us`, headers document, **sans** Referer.
   Conserver les cookies de la réponse.

1. **Recherche** (`searchEndpoint` + `searchPb`) :
   `GET https://www.google.com/search?tbm=map&authuser=0&hl=en&gl=us&pb=<searchPb>` avec
   `{QUERY}`, `{LAT}`, `{LNG}` substitués (ex. `1451 W Covell Blvd, Davis, CA 95616`,
   `38.55`, `-121.74`). Headers XHR + Referer `https://www.google.com/maps`.

2. **Avis d'un lieu** (`reviewsEndpoint` + `reviewsPb`, keyless, pas de token) :
   `GET https://www.google.com/maps/preview/review/listentitiesreviews?authuser=0&hl=en&gl=us&pb=<reviewsPb>`
   avec `{HIGH}`/`{LOW}` = feature-id du lieu (ex. `0x808529a...`). Headers XHR + Referer maps.

3. **Itinéraire** (`directionsEndpoint` + `directionsPb`) :
   `GET https://www.google.com/maps/preview/directions?authuser=0&hl=en&gl=us&pb=<directionsPb>`
   avec `{OLAT}/{OLNG}/{DLAT}/{DLNG}` et `{MODE}` (ex. `0`=drive). Headers XHR + Referer maps.

4. **Photos** (`photosEndpoint` + `photosProto`, POST keyless) :
   `POST https://www.google.com/maps/_/MapsWizUi/data/batchexecute?rpcids=hspqX&source-path=/maps&hl=en&_reqid=1&rt=c`
   body = `f.req=<photosProto URL-encodé>` avec `{FID}`, `{COUNT}`. Headers XHR, `Content-Type: application/x-www-form-urlencoded`.

## 3. Le script : `tools/ios-spike.swift`

Sur un Mac (le stack réseau d'URLSession sur macOS est celui d'iOS, à la version d'OS près) :

```
swift tools/ios-spike.swift                 # les trois identités
swift tools/ios-spike.swift safari-mac      # une seule
```

Il rejoue warm-up, recherche, avis, photos (`hspqX`) et itinéraire, avec un magasin de cookies
neuf par identité, et un délai aléatoire de 1 à 2,5 s entre deux requêtes.

| Identité | UA | Client hints | Pourquoi |
|---|---|---|---|
| `chrome-win` | Chrome 156 Windows (celle d'Android) | oui | Référence. Incohérente sur Apple : la poignée de main TLS d'Apple ne ressemble pas à Chrome, et il n'existe plus de build Cronet iOS récent (le bucket `chromium-cronet/ios/` s'arrête vers la version 108). |
| `safari-mac` | Safari 26 macOS | non (Safari n'en envoie pas) | Identité **cohérente** avec le TLS d'Apple. Hypothèse principale pour iOS. |
| `safari-ios` | Safari 26 iPhone | non | Ce que présente un WKWebView par défaut. Peut faire servir à Google une forme mobile. |

Le lancer deux fois, à une heure d'écart, et une fois depuis le réseau mobile d'un téléphone en
partage de connexion (IP différente).

## 4. Ce qu'on lit

Pour chaque requête : code HTTP, URL finale (redirection vers `consent.google.com` ou `/sorry`),
taille, temps. Le verdict `THIN` du script est un seuil grossier : comparer les tailles avec
celles d'Android sur la même requête (`GoogleHealthProbeTest` côté JVM donne la référence).

- La recherche doit contenir un identifiant de lieu (`0x…:0x…`). Sans lui, avis et photos ne
  sont pas tentés.
- Avis : 20 attendus en session neuve, ou au moins 5 (Google limite les sessions neuves).
- Photos : une première page de 20 ou moins avec une suite = session « limitée »
  (`GoogleStanding`), 40 ou plus = pleine.

## 5. Décision

| Résultat | Décision |
|---|---|
| `safari-mac` OK partout | Go. L'identité iOS est Safari desktop (D11 de `PORTAGE_IOS.md`). |
| Seul `chrome-win` OK | Go, avec Chrome en identité, risque de détection à surveiller (`google-health`). |
| `safari-ios` seul OK | Go, mais les templates `pb` desktop sont peut-être à recalibrer pour la forme mobile. |
| Recherche OK, avis/photos limités | Go. Les avis passent de toute façon par WKWebView (spike W-2). |
| Rien ne passe, aucune identité | No-go. On s'arrête avant la phase 1. |

## 6. Livrable

La sortie brute du script (elle ne contient ni coordonnée hors fixture ni nom de lieu au-delà
de l'extrait de 100 caractères : le relire avant de coller), recopiée dans la PR W-1 avec la
ligne de décision du tableau ci-dessus.
