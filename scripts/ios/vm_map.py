#!/usr/bin/env python3
"""Presentation-logic map of MapViewModel, NavController and the ui/ holders (lot P-0).

Reads a Kotlin class (default: app/.../ui/map/MapViewModel.kt), lexes it with the lexer of
core_deps.py (comments and string text blanked, templates kept), lists the members declared
at the class body's top level (fun, val, var, init, nested types) with their line ranges,
and for each member measures:

  - which MapUiState fields it writes (named arguments of a `.copy(` call),
  - which constructor collaborators it touches (dataSource, savedStore, webReviews...),
  - which app / core classes it names (fully qualified `app.vela.x.Y` or imported names),
  - Android exposure: qualified `android.*` / `androidx.*` names, `appContext`, `R.string`,
    and the core_deps.py blocker rules (Math, String.format, SystemClock...),
  - which other members it calls (call graph inside the class).

Members are put in a feature by name rules (FEATURE_RULES, first match wins, then
OVERRIDES), then a member left unclassified inherits the feature its callers or callees
mostly have. The result is a measure, not a design: the doc says where the rules guess.

Usage:
  python3 scripts/ios/vm_map.py                       # per-feature summary of MapViewModel
  python3 scripts/ios/vm_map.py --members             # every member, one line each
  python3 scripts/ios/vm_map.py --state               # MapUiState fields by feature and writers
  python3 scripts/ios/vm_map.py --file ui/map/NavController.kt --members
  python3 scripts/ios/vm_map.py --holders             # stateful objects/classes in ui/
  python3 scripts/ios/vm_map.py --json /tmp/opencode/vm.json
  python3 scripts/ios/vm_map.py --churn <rev>            # lines changed since <rev>, per feature
  python3 scripts/ios/vm_map.py --fingerprint runSearch  # logic hash of members
  python3 scripts/ios/vm_map.py --md docs/ios/PRESENTATION-MAP.md     # rewrite the watch block
  python3 scripts/ios/vm_map.py --check docs/ios/PRESENTATION-MAP.md  # what changed upstream since

Members are found at the class body's top level only: a local function inside a member counts
with that member. Line counts are declaration lines; "code lines" leave out blank and
comment-only lines.
"""

import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from core_deps import COMPILED_RULES, lex  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
APP = "app/src/main/java/app/vela"
VM = "ui/map/MapViewModel.kt"

MODS = r"(?:(?:public|internal|private|protected|override|open|abstract|final|suspend|inline|" \
       r"inner|data|sealed|enum|value|lateinit|const|operator|infix|tailrec|external|crossinline|" \
       r"@[\w.]+(?:\([^)]*\))?)\s+)*"
MEMBER_RE = re.compile(r"^[ \t]*(" + MODS + r")(fun|val|var|class|interface|object|init|companion\s+object)\b"
                       r"\s*(?:<[^>]*>\s*)?([\w.`]*)")

# (feature, regex on member name). First match wins.
FEATURES = [
    "init", "search", "place", "route", "nav", "transit", "saved", "offline", "layers",
    "streetview", "voice", "location", "links", "network", "status", "replay", "update", "misc",
]
FEATURE_LABEL = {
    "init": "construction et collecteurs",
    "search": "recherche et suggestions",
    "place": "fiche lieu (détails, photos, avis)",
    "route": "itinéraires et choix d'itinéraire",
    "nav": "navigation (start/stop/recalcul, alertes)",
    "transit": "transport en commun",
    "saved": "lieux enregistrés, listes, raccourcis, parking",
    "offline": "hors ligne (régions, paquets, tuiles)",
    "layers": "couches carte et réglages",
    "streetview": "Street View",
    "voice": "voix et dictée (moteurs, téléchargements)",
    "location": "position, vitesse, limite",
    "links": "liens entrants (geo:, Google Maps, partage)",
    "network": "connectivité (hors ligne, données limitées)",
    "status": "bandeaux d'état et notices",
    "replay": "trajets enregistrés, replay, diagnostic",
    "update": "mise à jour de l'APK",
    "misc": "divers",
}
FEATURE_RULES = [
    ("streetview", r"(?i)streetview|pano"),
    ("update", r"(?i)selfupdate|^update(Apk|Info|Download|Check)|checkForUpdate|installUpdate|dismissUpdate|apkPending|keepApk"),
    ("replay", r"(?i)replay|trip(?!Shortcut)|diag|demo|export|flightRec|frameJank"),
    ("transit", r"(?i)transit|stopDeparture|departure|routeDetail|board"),
    ("voice", r"(?i)voice|piper|kokoro|asr|speech|tts|engine(?!Route)|speaker|neural|synth|speak|phrase"),
    ("offline", r"(?i)offline|region|routing(?!Pref)|poiPack|cell|basemap|pmtiles|archive|download|storage|obf|pack|areaPick|areaPlan|patch|bake|overlayStore|catalog"),
    ("saved", r"(?i)saved|list(?!en)|shortcut|parking|parked|home|work|favorite|import|takeout|myMap|shape|draw|rename|note|label|pinTrip|share"),
    ("streetview", r"(?i)look ?around"),
    ("nav", r"(?i)nav|drive|reroute|faster|arriv|camera|flock|alpr|speedCam|pause|resume|maneuver|corridor|routeBar|passAlert|detour|recenter|overview|northUp|tapCandidate"),
    ("route", r"(?i)route|direction|waypoint|stop(?!Dep)|origin|dest|travelMode|avoid|pickOnMap|eta|reverse|swap|step|chooser|modeEta|linkTrip|depart"),
    ("search", r"(?i)search|suggest|query|recent|result|categor|branch|chain|more(Results)?|nearby|openNow|filter|sort|contact|intent|command|geocode|photon"),
    ("place", r"(?i)place|select|review|photo|detail|popular|hours|tap|open(?!Now)|sheet|alias|fuel|menu|update(s)?Tab|website|call"),
    ("location", r"(?i)location|fix|speed|limit|heading|compass|gps|stale|psds|sane|kalman|bearing|accuracy|still"),
    ("layers", r"(?i)style|layer|poi|ambient|building|address(Overlay)|traffic|overlay|tile|satellite|imagery|terrain|maxspeed|viewport|controls|declutter|mapCenter|camera|zoom|theme|unit|setting|pref"),
    ("status", r"(?i)status|notice|flash|toast|message|tip|banner"),
]
COMPILED_FEATURE_RULES = [(f, re.compile(r)) for f, r in FEATURE_RULES]

# Name -> feature, where the name rules guess wrong (checked by reading the body).
OVERRIDES = {
    "MapViewModel.kt": {
        "selectPlace": "place", "clearSelection": "place", "onMapTap": "place",
        "startNavigation": "nav", "stopNavigation": "nav",
        "route": "route", "routeBetween": "route",
        "onCleared": "init", "navHost": "nav", "nav": "nav", "ukFuel": "place",
        "voicePrefListener": "voice", "_state": "init", "state": "init",
        "settingsPrefs": "layers", "noticePrefs": "status", "http": "misc",
        "mapCenter": "layers", "destination": "route",
        # Read from the bodies (2026-10-24): the name rules put these in the wrong feature.
        "installPendingUpdate": "update", "dismissPendingUpdate": "update", "sharePendingUpdate": "update",
        "downloadUpdate": "update", "cancelUpdateDownload": "update", "updateCancel": "update",
        "toggleSave": "saved", "cancelAssign": "saved", "isAddressPick": "saved", "consumeAssign": "saved",
        "clearAllHistory": "search", "homeSuggestions": "search", "homeNameHits": "search",
        "fromHere": "search", "rankBias": "search", "plausibleBias": "search", "branchStripped": "search",
        "onCameraIdle": "layers", "webWarmScheduled": "place", "warmWebViewsWhenQuiet": "place",
        "lastDefaultNetwork": "network", "refreshConnectivity": "network", "observeConnectivity": "network",
        "offlineNow": "network", "isValidated": "network", "isOnline": "network", "systemOnline": "network",
        "recheckConnectivity": "network", "isConnectivityError": "network", "offlineLatchJob": "network",
        "lastValidated": "network", "googleOff": "network",
        "netTick": "replay", "stillHeld": "replay", "etaTick": "replay", "lastDataNote": "replay",
        "driveDataNote": "replay",
        "openSharedText": "links", "openDeepLink": "links", "openStreetViewLink": "links",
        "pickLinkHit": "links", "anchorLinkSearch": "links", "linkMode": "links", "LinkPlan": "links",
        "linkPlan": "links", "openDirectionsLink": "links", "linkPin": "links", "linkPlace": "links",
        "linkTripJob": "links", "linkPlaceWithin": "links", "linkStopSlots": "links",
        "linkFindSlot": "links", "findLinkStop": "links", "linkTripFor": "links",
        "clearLinkTrip": "links", "openTripLink": "links", "launchLink": "links",
        "listingsAtPoint": "place", "nearestLiveStop": "transit", "itineraryStep": "transit",
        "lineLabelMatches": "transit", "openRouteStop": "transit", "transitTrips": "transit",
        "backfillOfflineAddress": "place", "fetchPlaceDetails": "place", "mergeDetails": "place",
        "detailsCache": "place", "thumbPano": "place", "loadPhotoCategories": "place", "lru": "place",
        "loadMoreReviews": "place", "civicFiltered": "layers", "clearPreview": "route",
        "SETTLEMENT_KINDS": "place", "onOpenPlaceTap": "place", "offlineTwin": "place",
        "JUNCTION_CATEGORIES": "place", "crossScriptCandidates": "place", "onMapLongPress": "place",
        "onAddressLabelTap": "place", "startNavToSelected": "nav", "stepPickedInList": "route",
        "setPlaceIcon": "saved", "placeIcon": "saved", "routeRows": "saved", "shapeForRow": "saved",
        "openShapeTrip": "saved", "togglePendingLayer": "saved", "cancelChooseOnMap": "route",
        "navRemainingStopLabels": "nav", "tripPointsForEditor": "route", "applyTrip": "route",
        "pinTripShortcut": "route", "openTripShortcut": "route", "roadFeaturesJob": "nav",
        "defaultDrivenRouteName": "saved", "awaitRouteWork": "route", "setSpokenDirections": "voice",
        "liveRechecksOn": "nav", "setLiveRechecks": "nav", "velaLabel": "voice",
        "clearMapCache": "offline", "enterDrivingMode": "nav", "leaveDrivingMode": "nav",
        "stopSimulateLocation": "location", "recentlyViewed": "layers", "recentlyViewedAtMs": "layers",
        "withRecentlyViewed": "layers", "areaTileKb": "offline", "tileCount": "offline",
        "placesLookedUp": "layers", "refreshPlacesOverlays": "layers", "RoadCover": "nav",
        "roadFeaturesCover": "nav", "roadFeaturesCoverRoute": "nav", "roadCoverOf": "nav",
        "openStartView": "layers", "startDecided": "layers", "userPannedSinceLaunch": "layers",
        "onUserPanned": "layers", "startHadPermission": "location", "downloadLaunch": "offline",
        "rememberRecentPlace": "search", "selectSaved": "saved", "openShortcut": "saved",
        "recenter": "location", "dismissPsdsTip": "location", "refreshNotices": "status",
        "companion": "misc", "placeKey": "search", "clearViewedPlaces": "place", "showViewedCopy": "place",
        "placeCacheDir": "place", "openSimilar": "place",
    },
}

# Constructor collaborators of MapViewModel and what they are, for the doc.
COLLABORATOR_KIND = {
    "appContext": "Android Context",
    "dataSource": "core MapDataSource",
    "locationProvider": "core LocationProvider (STAYS)",
    "headingProvider": "core HeadingProvider (STAYS)",
    "voice": "core VoiceGuide",
    "voiceInstaller": "app voice/VoiceInstaller",
    "kokoroInstaller": "app voice/KokoroInstaller",
    "piperSynth": "app voice/PiperSynth",
    "navSession": "core NavSession",
    "recentStore": "core RecentSearchStore",
    "recentPlaceStore": "core RecentPlaceStore",
    "savedStore": "core SavedPlaceStore",
    "parkingStore": "core ParkingStore",
    "listStore": "core PlaceListStore",
    "savedRouteStore": "core SavedRouteStore",
    "shortcutStore": "core PlaceShortcutStore",
    "calibration": "core CalibrationStore",
    "offlinePoiStore": "core OfflinePoiStore",
    "addressStore": "core OfflineAddressStore",
    "webPhotos": "app web/WebPhotoFetcher",
    "webReviews": "app web/WebReviewsFetcher",
    "webDirections": "app web/WebDirectionsFetcher",
    "webStopDepartures": "app web/WebStopDeparturesFetcher",
    "diag": "core DiagLog",
    "diagExporter": "app diag/DiagExporter",
    "webPopularTimes": "app web/WebPopularTimesFetcher",
    "tripStore": "app replay/TripStore",
    "regionCatalog": "app offline/RegionCatalog",
    "poiPackStore": "app offline/PoiPackStore",
    "obfStore": "app offline/ObfStore",
    "overlayStore": "app offline/OverlayTileStore",
    "maxspeedStore": "app offline/MaxspeedOverlayStore",
    "placesStore": "app offline/PlacesTileStore",
    "basemapStore": "app offline/BasemapTileStore",
    "cellStore": "app offline/CellStore",
    "routeEngine": "core RouteEngine",
    "http": "OkHttpClient",
    "selfUpdater": "app update/SelfUpdater",
    "asrRecognizer": "app voice/AsrRecognizer",
}

ANDROID_RE = re.compile(r"(?<![\w.])(androidx?\.[a-z]\w*(?:\.\w+)*)")
FQ_APP_RE = re.compile(r"(?<![\w.])app\.vela\.((?:[a-z]\w*\.)*)([A-Z]\w*)")
APPCTX_RE = re.compile(r"\bappContext\b|\bcontext\b|\bctx\b")
RSTRING_RE = re.compile(r"(?<![\w.])R\.(?:string|plurals|drawable|raw|array)\.\w+")
COMPOSE_RE = re.compile(r"\bsnapshotFlow\b|\bmutableStateOf\b|androidx\.compose")


def read(rel):
    with open(os.path.join(REPO, APP, rel), encoding="utf-8") as fh:
        return fh.read()


def line_of(code, pos):
    return code.count("\n", 0, pos) + 1


def match_brace(code, i):
    """code[i] == '{' -> index of its matching '}'."""
    depth = 0
    n = len(code)
    while i < n:
        c = code[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return n - 1


def class_body(code, name):
    m = re.search(r"(?m)^(?:@\w+\s*)*(?:\w+\s+)*(?:class|object)\s+" + re.escape(name) + r"\b", code)
    if not m:
        return None
    # The body brace is the first '{' at paren depth 0 after the header.
    i = m.end()
    depth = 0
    while i < len(code):
        c = code[i]
        if c in "(<":
            depth += 1
        elif c in ")>":
            depth -= 1
        elif c == "{" and depth <= 0:
            break
        i += 1
    return m.start(), i, match_brace(code, i)


def members(code, src, start, end):
    """Top-level members of the class body code[start..end] (start at '{')."""
    out = []
    depth = 0
    i = start + 1
    line_start = i
    decls = []
    while i < end:
        c = code[i]
        if c == "\n":
            line_start = i + 1
        if c in "{([":
            depth += 1
        elif c in "})]":
            depth -= 1
        if depth == 0 and i == line_start:
            seg = code[i:code.find("\n", i)]
            m = MEMBER_RE.match(seg)
            if m and m.group(2):
                kind = re.sub(r"\s+", " ", m.group(2))
                name = m.group(3) or ""
                if kind == "fun" and "." in name:  # extension member: keep the function name
                    name = name.split(".")[-1]
                if kind == "init":
                    name = "init"
                decls.append((i, kind, name.strip("`"), m.group(1)))
        i += 1
    lines = src.split("\n")
    code_lines = code.split("\n")
    prev_end = line_of(code, start)
    for k, (pos, kind, name, mods) in enumerate(decls):
        nxt = decls[k + 1][0] if k + 1 < len(decls) else end
        a = line_of(code, pos)
        b = line_of(code, nxt) - 1
        # Trim trailing blank / comment-only lines (comments are blank in code).
        while b > a and not code_lines[b - 1].strip():
            b -= 1
        # The KDoc or comment block right above the member belongs to it.
        doc = a
        while doc - 1 > prev_end and not code_lines[doc - 2].strip() and lines[doc - 2].strip():
            doc -= 1
        prev_end = b
        body = "\n".join(code_lines[a - 1:b])
        out.append({
            "kind": kind, "name": name, "start": a, "end": b, "lines": b - a + 1,
            "doc_start": doc, "with_doc": b - doc + 1,
            "code_lines": sum(1 for ln in code_lines[a - 1:b] if ln.strip()),
            "private": "private" in mods, "suspend": "suspend" in mods,
            "code": body, "src": "\n".join(lines[a - 1:b]),
        })
    return out


def copy_fields(code):
    """Named arguments of every `.copy(` call."""
    out = Counter()
    for m in re.finditer(r"\.copy\s*\(", code):
        i = m.end()
        depth = 1
        argstart = i
        args = []
        while i < len(code) and depth:
            c = code[i]
            if c in "([{":
                depth += 1
            elif c in ")]}":
                depth -= 1
            elif c == "," and depth == 1:
                args.append(code[argstart:i])
                argstart = i + 1
            i += 1
        args.append(code[argstart:i - 1])
        for a in args:
            mm = re.match(r"\s*(\w+)\s*=(?!=)", a)
            if mm:
                out[mm.group(1)] += 1
    return out


def ui_state_fields(code):
    b = class_body_paren(code, "MapUiState")
    if not b:
        return []
    seg = code[b[0]:b[1]]
    names = []
    depth = 0
    for ln in seg.split("\n"):
        if depth == 0:
            m = re.match(r"\s*val\s+(\w+)\s*:", ln)
            if m:
                names.append((m.group(1), line_of(code, b[0]) + len(names)))
        depth += ln.count("(") + ln.count("{") - ln.count(")") - ln.count("}")
    return [n for n, _ in names]


def class_body_paren(code, name):
    m = re.search(r"data class\s+" + name + r"\s*\(", code)
    if not m:
        return None
    i = m.end() - 1
    depth = 0
    j = i
    while j < len(code):
        if code[j] == "(":
            depth += 1
        elif code[j] == ")":
            depth -= 1
            if depth == 0:
                return i + 1, j
        j += 1
    return None


def ui_state_field_lines(code, src):
    b = class_body_paren(code, "MapUiState")
    seg_start = line_of(code, b[0])
    out = {}
    depth = 0
    for k, ln in enumerate(code[b[0]:b[1]].split("\n")):
        if depth == 0:
            m = re.match(r"\s*val\s+(\w+)\s*:", ln)
            if m:
                out[m.group(1)] = seg_start + k
        depth += ln.count("(") + ln.count("{") + ln.count("<") - ln.count(")") - ln.count("}") - ln.count(">")
    return out


def classify(name, fname):
    ov = OVERRIDES.get(fname, {})
    if name in ov:
        return ov[name], "override"
    if name == "init":
        return "init", "rule"
    for f, rx in COMPILED_FEATURE_RULES:
        if rx.search(name):
            return f, "rule"
    return None, None


def analyze(rel, cls):
    src = read(rel)
    code, _ = lex(src)
    fname = os.path.basename(rel)
    cb = class_body(code, cls)
    if not cb:
        raise SystemExit(f"class {cls} not found in {rel}")
    hdr, s, e = cb
    mem = members(code, src, s, e)
    names = {m["name"] for m in mem if m["kind"] == "fun"}
    props = {m["name"] for m in mem if m["kind"] in ("val", "var")}
    imports = {}
    for im in re.finditer(r"(?m)^import\s+([\w.]+)", code):
        full = im.group(1)
        imports[full.split(".")[-1]] = full
    collab = [c for c in COLLABORATOR_KIND]
    for m in mem:
        c = m["code"]
        m["writes"] = dict(copy_fields(c))
        m["collab"] = sorted({k for k in collab if re.search(r"(?<![\w.])" + re.escape(k) + r"\b", c)})
        m["android"] = sorted(set(ANDROID_RE.findall(c)))
        m["rstrings"] = len(RSTRING_RE.findall(c))
        m["context"] = len(APPCTX_RE.findall(c))
        m["compose"] = len(COMPOSE_RE.findall(c))
        fq = set()
        for mm in FQ_APP_RE.finditer(c):
            fq.add((mm.group(1) + mm.group(2)))
        for simple, full in imports.items():
            if full.startswith("app.vela.") and re.search(r"(?<![\w.])" + re.escape(simple) + r"\b", c):
                fq.add(full[len("app.vela."):])
        m["names"] = sorted(fq)
        bl = {}
        for rid, rx in COMPILED_RULES:
            k = len(rx.findall(c))
            if k:
                bl[rid] = k
        m["blockers"] = bl
        calls = set()
        for mm in re.finditer(r"(?<![\w.])(\w+)\s*(?:\(|\{)|::(\w+)", c):
            nm = mm.group(1) or mm.group(2)
            if nm in names and nm != m["name"]:
                calls.add(nm)
        for p in props:
            if p != m["name"] and re.search(r"(?<![\w.])" + re.escape(p) + r"\b", c):
                calls.add(p)
        m["calls"] = sorted(calls)
        f, how = classify(m["name"], fname)
        m["feature"], m["how"] = f, how
    # Propagate a feature to the unclassified members from their neighbours.
    by = {m["name"]: m for m in mem}
    callers = defaultdict(set)
    for m in mem:
        for k in m["calls"]:
            callers[k].add(m["name"])
    for _ in range(4):
        for m in mem:
            if m["feature"]:
                continue
            votes = Counter()
            for k in list(m["calls"]) + list(callers[m["name"]]):
                f = by.get(k, {}).get("feature")
                if f and f != "init":
                    votes[f] += 1
            if votes:
                m["feature"], m["how"] = votes.most_common(1)[0][0], "graph"
    for m in mem:
        if not m["feature"]:
            m["feature"], m["how"] = "misc", "none"
    for m in mem:
        m["callers"] = sorted(callers[m["name"]])
    tiers(mem)
    return {"file": rel, "class": cls, "lines": src.count("\n") + 1,
            "class_start": line_of(code, hdr), "class_end": line_of(code, e),
            "members": mem, "code": code, "src": src}


APP_COLLAB = {k for k, v in COLLABORATOR_KIND.items() if v.startswith("app ") or k == "http"}
TIER_ORDER = ["PURE", "STATE", "CORE", "APP", "ANDROID"]
TIER_LABEL = {
    "PURE": "pur (aucun état, aucun collaborateur)",
    "STATE": "état seul (_state, scope), collaborateurs core au plus",
    "CORE": "collaborateurs :core",
    "APP": "classes :app (web/, offline/, voice/, replay/, OkHttp)",
    "ANDROID": "API Android, Context ou R.*",
}


def tiers(mem):
    """PURE < STATE < CORE < APP < ANDROID, the worst of the member and of what it calls."""
    by = {m["name"]: m for m in mem}
    for m in mem:
        c = m["code"]
        t = "PURE"
        if re.search(r"(?<![\w.])(?:_state|state|viewModelScope|nav|navHost|ukFuel)\b", c) and m["name"] not in ("_state", "state"):
            t = "STATE"
        if m["collab"]:
            t = "CORE"
        if set(m["collab"]) & APP_COLLAB or any(n.split(".")[0] in ("web", "offline", "voice", "replay", "diag", "update", "service", "streetview", "car") for n in m["names"]):
            t = "APP"
        if m["android"] or m["context"] or m["rstrings"] or m["compose"]:
            t = "ANDROID"
        m["own_tier"] = t
        m["tier"] = t
    for _ in range(12):
        changed = False
        for m in mem:
            for k in m["calls"]:
                o = by.get(k)
                if o and TIER_ORDER.index(o["tier"]) > TIER_ORDER.index(m["tier"]):
                    m["tier"] = o["tier"]
                    changed = True
        if not changed:
            break


def state_map(a, extra=()):
    """MapUiState fields, with the members that write them (MapViewModel and [extra] analyses,
    NavController by default: it writes the shared flow too)."""
    code = a["code"]
    lines = ui_state_field_lines(code, a["src"])
    writers = defaultdict(list)
    for src in (a,) + tuple(extra):
        tag = "" if src is a else src["class"] + "."
        for m in src["members"]:
            for f in m["writes"]:
                writers[f].append(dict(m, name=tag + m["name"]))
    out = []
    for f, ln in lines.items():
        feats = Counter(m["feature"] for m in writers.get(f, []))
        feat = feats.most_common(1)[0][0] if feats else (classify(f, "")[0] or "misc")
        out.append({"field": f, "line": ln, "feature": feat,
                    "writers": [m["name"] for m in writers.get(f, [])]})
    return out


def summary(a):
    agg = defaultdict(lambda: {"members": 0, "fun": 0, "public": 0, "lines": 0, "code": 0, "android": 0,
                               "rstrings": 0, "collab": Counter(), "names": Counter(),
                               "blockers": Counter()})
    for m in a["members"]:
        g = agg[m["feature"]]
        g["members"] += 1
        g["lines"] += m["lines"]
        g["code"] += m["code_lines"]
        if m["kind"] == "fun":
            g["fun"] += 1
            if not m["private"]:
                g["public"] += 1
        if m["android"] or m["context"]:
            g["android"] += 1
        g["rstrings"] += m["rstrings"]
        g["collab"].update(m["collab"])
        g["names"].update(m["names"])
        g["blockers"].update(m["blockers"])
    return agg


def ranges(ms):
    """Compact line ranges of members: 120-180, 300-310 ..."""
    spans = sorted((m["start"], m["end"]) for m in ms)
    out = []
    for s, e in spans:
        if out and s <= out[-1][1] + 3:
            out[-1][1] = max(out[-1][1], e)
        else:
            out.append([s, e])
    return out


def print_summary(a):
    agg = summary(a)
    total = sum(m["lines"] for m in a["members"])
    total_doc = sum(m["with_doc"] for m in a["members"])
    print(f"{a['file']}: {a['lines']} lines, class {a['class']} {a['class_start']}-{a['class_end']}, "
          f"{len(a['members'])} members ({total} lines of declarations, {total_doc} with their comments)")
    print("feature | members | fun (public) | lines | code lines | with Android | R.* | top collaborators | top blockers")
    for f in FEATURES:
        if f not in agg:
            continue
        g = agg[f]
        print(f"{f} | {g['members']} | {g['fun']} ({g['public']}) | {g['lines']} | {g['code']} | {g['android']} | {g['rstrings']} | "
              + ", ".join(f"{k}×{v}" for k, v in g["collab"].most_common(6)) + " | "
              + ", ".join(f"{k}×{v}" for k, v in g["blockers"].most_common(4)))
    how = Counter(m["how"] for m in a["members"])
    print("classification:", dict(how))
    print("tier | members | lines (own tier) | members | lines (with callees)")
    for t in TIER_ORDER:
        own = [m for m in a["members"] if m["own_tier"] == t]
        tr = [m for m in a["members"] if m["tier"] == t]
        print(f"{t} | {len(own)} | {sum(m['lines'] for m in own)} | {len(tr)} | {sum(m['lines'] for m in tr)}")
    print("feature x own tier (lines)")
    for f in FEATURES:
        row = [sum(m["lines"] for m in a["members"] if m["feature"] == f and m["own_tier"] == t) for t in TIER_ORDER]
        if sum(row):
            print(f, "|", " | ".join(str(x) for x in row))


def print_members(a, feature=None, tier=None):
    for m in a["members"]:
        if feature and m["feature"] != feature:
            continue
        if tier and m["own_tier"] != tier:
            continue
        vis = "-" if m["private"] else "+"
        print(f"{m['start']}-{m['end']} ({m['lines']}) {vis}{m['kind']} {m['name']} [{m['feature']}/{m['how']}] {m['own_tier']}/{m['tier']}"
              f" collab={','.join(m['collab'])} android={len(m['android'])}+ctx{m['context']} R={m['rstrings']}"
              f" writes={','.join(sorted(m['writes']))} names={','.join(m['names'][:8])}")


# ---------------------------------------------------------------------------
# Holders in ui/
# ---------------------------------------------------------------------------

HOLDER_DIRS = ["ui", "ui/place", "ui/search", "ui/nav", "ui/settings", "ui/map"]
TOP_RE = re.compile(r"(?m)^(?:@[\w.]+(?:\([^)]*\))?\s+)*(?:(?:private|internal|data|sealed|enum|abstract|open)\s+)*(object|class)\s+(\w+)")


def holders():
    out = []
    for d in HOLDER_DIRS:
        base = os.path.join(REPO, APP, d)
        for fn in sorted(os.listdir(base)):
            if not fn.endswith(".kt"):
                continue
            rel = f"{d}/{fn}"
            if rel in (VM, "ui/map/NavController.kt"):
                continue
            src = read(rel)
            code, _ = lex(src)
            composables = len(re.findall(r"@Composable", src))
            for m in TOP_RE.finditer(code):
                kind, name = m.group(1), m.group(2)
                hdr = code[m.start():m.end() + 200]
                if kind == "class" and re.search(r"\b(?:data|enum|sealed|annotation)\s+class\s+" + name, code[m.start():m.end()]):
                    continue
                cb = class_body(code, name)
                if not cb:
                    continue
                _, s, e = cb
                body = code[s:e]
                flows = len(re.findall(r"\bMutableStateFlow\b", body))
                states = len(re.findall(r"\bmutableStateOf\b|\bmutableIntStateOf\b|\bmutableFloatStateOf\b|\bmutableLongStateOf\b", body))
                vars_ = len(re.findall(r"(?m)^\s{4}(?:@Volatile\s+)?(?:private\s+|internal\s+)?var\s", body))
                prefs = len(re.findall(r"SharedPreferences|getSharedPreferences|\bprefs\b", body))
                funs = len(re.findall(r"(?m)^\s{4}(?:[a-z]+\s+)*fun\s", body))
                if not (flows or states or vars_):
                    continue
                android = sorted(set(ANDROID_RE.findall(body)))
                imp_android = re.findall(r"(?m)^import\s+(androidx?\.[\w.]+)", code)
                out.append({
                    "file": rel, "name": name, "kind": kind, "start": line_of(code, s),
                    "end": line_of(code, e), "lines": line_of(code, e) - line_of(code, s) + 1,
                    "flows": flows, "states": states, "vars": vars_, "prefs": prefs, "funs": funs,
                    "android": android, "file_android_imports": len(imp_android),
                    "file_composables": composables, "file_lines": src.count("\n") + 1,
                    "started_in_velaapp": False,
                })
    app_src = read("VelaApp.kt")
    for h in out:
        h["started_in_velaapp"] = bool(re.search(r"(?<![\w])" + h["name"] + r"\.(?:init|start|load|attach|bind)\w*\s*\(", app_src))
    return out


def changed_lines(rev, rel):
    """New-side line numbers touched since [rev] (git diff -U0 rev..HEAD)."""
    import subprocess
    out = subprocess.run(["git", "-C", REPO, "diff", "-U0", rev, "HEAD", "--", os.path.join(APP, rel)],
                         capture_output=True, text=True, check=True).stdout
    lines = set()
    for m in re.finditer(r"(?m)^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", out):
        start, count = int(m.group(1)), int(m.group(2) or "1")
        lines.update(range(start, start + count))
    return lines


def churn(a, rev):
    ch = changed_lines(rev, a["file"])
    per = Counter()
    tot = Counter()
    for m in a["members"]:
        k = sum(1 for ln in range(m["doc_start"], m["end"] + 1) if ln in ch)
        per[m["feature"]] += k
        tot[m["feature"]] += m["with_doc"]
        m["churn"] = k
    return ch, per, tot


def fingerprint(m):
    """Hash of a member's code with comments, strings' text and whitespace removed: changes when
    the logic changes, not when a comment does."""
    import hashlib
    return hashlib.sha1(re.sub(r"\s+", "", m["code"]).encode()).hexdigest()[:10]


# The members each :ios-shared store ports (PRESENTATION-MAP.md section 3). Their logic hash goes
# in the doc's "watch" block; `--check` says which ones changed upstream since, so the Kotlin
# copy in :ios-shared is re-read against the new body.
WATCH = {
    "SearchStore": {
        "MapViewModel": ["onQueryChange", "fillQuery", "localMatches", "placeKey", "nameLocKey",
                         "pickLocalSuggestion", "removeLocalSuggestion", "clearSearch", "searchRecent",
                         "search", "handleQueryIntent", "routeBetween", "rankBias", "homeSuggestions",
                         "homeNameHits", "searchOpenNow", "searchThisArea", "loadMoreResults",
                         "plausibleBias", "runSearch", "offlineSearch", "archivePlaces", "googleFreeLocal",
                         "addressFirst", "searchAlongRoute", "isConnectivityError", "quickSearch",
                         "rememberRecentPlace"],
    },
    "PlaceStore": {
        "MapViewModel": ["selectPlace", "clearSelection", "fetchPlaceDetails", "mergeDetails",
                         "fetchPhotos", "loadAllPhotos", "requestReviews", "fetchReviews",
                         "loadMoreReviews", "othersAt", "streetKey", "nameAgrees", "onPoiTap",
                         "onMapLongPress", "onAddressLabelTap", "backfillOfflineAddress", "thumbPano",
                         "placeCacheGet", "placeCachePut", "placeRetryWait", "placeTries", "isPlaceholder"],
    },
    "RouteStore": {
        "MapViewModel": ["route", "routeToSelected", "directionsTo", "selectRoute", "nameIfNeeded",
                         "setTravelMode", "setAvoidTolls", "setAvoidHighways", "setAvoidFerries",
                         "stickyAvoid", "stickyTravelMode", "syncRoutingAvoid", "setDirectionsTime",
                         "swapDirections", "setDirectionsOrigin", "setDirectionsDestination", "addStop",
                         "applyStops", "clearRoute", "modeEtaKeyOf", "beginModeEtas", "publishModeEta",
                         "prefetchModeEtas", "shownDuration", "routeTransit", "offerSavedRoutes"],
    },
    "NavStore": {
        "MapViewModel": ["startNav", "startLocation", "sanePosition", "gateMeasuredSpeed",
                         "bearingBetween", "restartStaleTimer", "updateSpeedLimit", "toggleNavPause",
                         "setVoiceMode", "toggleVoice", "addStopDuringNav"],
        "NavController": ["bind", "startNav", "launchNav", "stopNav", "maybeWarnClosingSoon",
                          "stopArrivals", "closingMessage", "tunnelDeadReckonLoop", "maybeOfferResume",
                          "resumeNav", "persistNav", "updateRouteBar", "refreshRouteSpeedCams",
                          "refreshRouteFlock", "maybeWarnFlock", "maybeWarnSpeeding", "maybeWarnCamera",
                          "lightCues", "onNavPanned", "recenterNav", "navOverview", "toggleNavNorthUp"],
    },
    "SavedStore": {
        "MapViewModel": ["toggleSave", "pinSavedAs", "removeSaved", "renamePlace", "selectSaved",
                         "createList", "updateList", "moveList", "deleteList", "addPlaceToList",
                         "removePlaceFromList", "saveParkingSpot", "clearParkingSpot", "showParkedCar",
                         "beginAssignShortcut", "consumeAssign", "openShortcut", "clearShortcut",
                         "importTakeoutRows", "saveActiveRoute", "openSavedRoute"],
    },
    "OfflineStore": {
        "MapViewModel": ["refreshRoutingRegions", "downloadPoiPack", "fetchRegionArchives",
                         "refreshRegionUpdates", "updateRegionNow", "pickBasemapArchive",
                         "refreshBasemapArchive", "downloadOfflinePois", "areaDownloadPlan",
                         "downloadPickedArea", "offlineStorageBreakdown", "deleteAllOfflineData"],
    },
}
WATCH_FILES = {"MapViewModel": VM, "NavController": "ui/map/NavController.kt"}


def watch_rows():
    rows = []
    cache = {}
    for store, by_cls in WATCH.items():
        for cls, names in by_cls.items():
            a = cache.get(cls) or cache.setdefault(cls, analyze(WATCH_FILES[cls], cls))
            byname = defaultdict(list)
            for m in a["members"]:
                if m["kind"] == "fun":
                    byname[m["name"]].append(m)
            for n in names:
                ms = byname.get(n)
                if not ms:
                    rows.append((store, cls, n, "-", "absent"))
                    continue
                for m in ms:  # overloads: one row each
                    rows.append((store, cls, n, f"{m['start']}-{m['end']}", fingerprint(m)))
    return rows


def watch_md():
    head = "| Store | Classe | Fonction | Lignes | Empreinte |\n|---|---|---|---|---|\n"
    return head + "\n".join(f"| {s} | {c} | `{n}` | {l} | `{h}` |" for s, c, n, l, h in watch_rows()) + "\n"


def write_watch(path):
    with open(path, encoding="utf-8") as fh:
        doc = fh.read()
    block = re.compile(r"(<!-- BEGIN GENERATED: watch -->\n)(.*?)(<!-- END GENERATED: watch -->)", re.S)
    if not block.search(doc):
        raise SystemExit(f"{path}: no watch block")
    doc = block.sub(lambda m: m.group(1) + watch_md() + m.group(3), doc)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(doc)


def check_watch(path):
    with open(path, encoding="utf-8") as fh:
        doc = fh.read()
    recorded = defaultdict(list)
    for m in re.finditer(r"^\| (\w+) \| (\w+) \| `(\w+)` \| ([\d-]+|-) \| `(\w+)` \|$", doc, re.M):
        recorded[(m.group(2), m.group(3))].append(m.group(5))
    drift = 0
    for store, cls, n, lines, h in watch_rows():
        if h not in recorded.get((cls, n), []):
            drift += 1
            print(f"changed: {store} <- {cls}.{n} ({lines}) now {h}, recorded {','.join(recorded.get((cls, n), ['none']))}")
    print(f"{drift} watched function(s) changed since the doc was generated")
    return drift


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default=VM)
    ap.add_argument("--cls")
    ap.add_argument("--members", action="store_true")
    ap.add_argument("--feature")
    ap.add_argument("--tier")
    ap.add_argument("--state", action="store_true")
    ap.add_argument("--holders", action="store_true")
    ap.add_argument("--json")
    ap.add_argument("--churn", metavar="REV", help="lines changed since REV, per feature")
    ap.add_argument("--md", metavar="DOC", help="rewrite the generated watch block of DOC")
    ap.add_argument("--check", metavar="DOC", help="list watched functions whose logic changed since DOC")
    ap.add_argument("--fingerprint", nargs="*", metavar="NAME",
                    help="logic hash of the named members (all functions without names)")
    args = ap.parse_args(argv)
    if args.md:
        write_watch(args.md)
        return
    if args.check:
        sys.exit(1 if check_watch(args.check) else 0)
    if args.holders:
        for h in holders():
            print(f"{h['file']}:{h['start']}-{h['end']} {h['kind']} {h['name']} ({h['lines']} l.) "
                  f"flows={h['flows']} states={h['states']} vars={h['vars']} prefs={h['prefs']} funs={h['funs']} "
                  f"android={len(h['android'])} composables_in_file={h['file_composables']} "
                  f"VelaApp={'yes' if h['started_in_velaapp'] else 'no'}")
        return
    cls = args.cls or os.path.basename(args.file)[:-3]
    a = analyze(args.file, cls)
    if args.json:
        slim = {k: v for k, v in a.items() if k not in ("code", "src")}
        slim["members"] = [{k: v for k, v in m.items() if k not in ("code", "src")} for m in a["members"]]
        if cls == "MapViewModel":
            slim["state"] = state_map(a, (analyze("ui/map/NavController.kt", "NavController"),))
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(slim, fh, indent=1)
    if args.churn:
        ch, per, tot = churn(a, args.churn)
        print(f"{len(ch)} new-side lines changed since {args.churn}")
        print("feature | changed lines | lines now | share")
        for f in FEATURES:
            if tot[f]:
                print(f"{f} | {per[f]} | {tot[f]} | {100 * per[f] // tot[f]} %")
        top = sorted(a["members"], key=lambda m: -m["churn"])[:15]
        print("most changed:", ", ".join(f"{m['name']}@{m['start']} {m['churn']}" for m in top))
    elif args.fingerprint is not None:
        want = set(args.fingerprint)
        for m in a["members"]:
            if (want and m["name"] in want) or (not want and m["kind"] == "fun"):
                print(f"{m['name']} {m['start']}-{m['end']} {fingerprint(m)}")
    elif args.members:
        print_members(a, args.feature, args.tier)
    elif args.state:
        extra = (analyze("ui/map/NavController.kt", "NavController"),) if cls == "MapViewModel" else ()
        for s in state_map(a, extra):
            print(f"{s['line']} {s['field']} [{s['feature']}] writers={len(s['writers'])}: {','.join(s['writers'][:6])}")
    else:
        print_summary(a)


if __name__ == "__main__":
    main()
