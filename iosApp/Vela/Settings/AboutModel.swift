import Foundation

/// One row of the bundled notices file. The JSON is checked by
/// `scripts/ios/check_notices.py`, which also proves that every Swift package, vendor framework
/// and shared Kotlin library has an entry.
struct NoticeEntry: Identifiable, Hashable, Decodable {
    let id: String
    let title: String
    let kind: String
    let license: String
    let url: String
    let note: String
    let hosts: [String]?

    var link: URL? { URL(string: url) }
}

private struct NoticeFile: Decodable {
    let entries: [NoticeEntry]
}

enum NoticesCatalog {
    /// The JSON lives beside this file in the source tree and is copied into the app bundle.
    static func load(bundle: Bundle = .main) -> [NoticeEntry] {
        let url = bundle.url(forResource: "Notices", withExtension: "json")
            ?? bundle.url(forResource: "Notices", withExtension: "json", subdirectory: "Settings")
        guard let url,
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(NoticeFile.self, from: data) else { return [] }
        return file.entries
    }

    static func grouped(_ entries: [NoticeEntry], kind: String) -> [NoticeEntry] {
        entries.filter { $0.kind == kind }
    }
}

struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let paragraphs: [String]
    let keywords: String
}

/// Help written for iOS. Every claim here is backed by the code and the porting documents; see
/// docs/ios/SETTINGS.md for the mapping.
enum HelpCatalog {
    static let topics: [HelpTopic] = [
        HelpTopic(
            id: "blank-map",
            title: "Why is my map blank?",
            summary: "The basemap is OpenStreetMap vector tiles from OpenFreeMap. Vela ships the style document, not the tiles.",
            paragraphs: [
                "Online, streets, labels and place icons are downloaded from OpenFreeMap. If the phone is offline, behind a captive portal, or OpenFreeMap cannot be reached, the map keeps its background and any route but shows no new streets or labels. Pan or zoom to make MapLibre retry; restart Vela when a tile request stalled.",
                "A downloaded region replaces the online basemap with local PMTiles while the map center is inside that region. With no connection, moving outside the downloaded area leaves no local data, so the map can be empty there. Open Offline to see what is installed; deleting the region returns that area to the online basemap.",
                "Use Vela without Google does not blank the basemap. OpenFreeMap is not Google. Traffic and satellite are separate raster layers from Google and Esri, and leaving them off changes nothing else.",
                "The first launch asks how Google may be used. The map behind that sheet is already the local Liberty style and does not wait for an answer.",
                "If only labels or icons are missing, glyphs and sprites are remote too, so the same connection problem applies. If the whole map is black or frozen, export diagnostics from Support and report it. That is a renderer problem this screen cannot repair."
            ],
            keywords: "blank empty white black grey gray background tiles offline openfreemap network captive portal map missing labels icons"),

        HelpTopic(
            id: "no-live-traffic",
            title: "Why is there no live traffic?",
            summary: "Live traffic is a Google overlay and Google arrival times. The open routers return a route without congestion.",
            paragraphs: [
                "Open Layers and turn on Traffic. The overlay is a Google raster drawn over the vector map. It is off by default and works only online. A downloaded region deliberately keeps every Google raster out, so offline maps have no live traffic.",
                "With Use Vela without Google, Vela's own requests to Google are blocked. The Traffic and Satellite switches are still in Layers, and MapLibre loads those tiles itself. If you want no Google traffic data at all, leave both off. This is the same limit the privacy page describes.",
                "Routes from OSRM and Valhalla have no live congestion. A traffic-aware arrival time, a faster-route offer and the red, amber and green line on a route come from Google directions. Without Google the route still works, but its time is the router's own estimate.",
                "Google's traffic is not available on every road or in every country, and it can lag behind the road. Vela does not invent congestion where Google has none.",
                "During navigation, live re-checks ask Google from the current position every few minutes when Google is allowed. That is what updates the arrival time."
            ],
            keywords: "traffic congestion jam red amber green overlay live eta arrival faster route google offline nogoogle"),

        HelpTopic(
            id: "place-details",
            title: "Why is a place missing reviews or photos?",
            summary: "Place pages, reviews, photos, opening hours and popular times come from Google's public pages, not from OpenStreetMap.",
            paragraphs: [
                "Vela reads Google's logged-out pages, with no account and no API key. Not every place has reviews, photos, hours or popular times, and Google sometimes gives a logged-out session a limited view: fewer photos, no popular times, and More reviews loads nothing. That usually lifts on its own, and starting a new session rarely helps.",
                "Place content Tiles only keeps the search row for the place (name, address, point) and asks Google for nothing more. Show reviews and Load photos off remove those loads. Load all photos and reviews raises the cap to 50 reviews. Photo quality, the photo cache size and Load photos only on Wi-Fi change images only.",
                "Hide website and external links removes the website row. It does not hide Street View, Book, Reserve or Order.",
                "With Use Vela without Google, a place page keeps the search row and sends no Google request. Places drawn on the map still come from OpenStreetMap, and a downloaded region can still find its own places.",
                "Street View is separate from the place page and also needs Google. Without Google there is no Street View."
            ],
            keywords: "reviews photos hours opening popular times place details missing google tiles only street view nogoogle"),

        HelpTopic(
            id: "offline-regions",
            title: "How do offline regions work?",
            summary: "A download stores a region's basemap, places and addresses on the phone. Inside that region the map and search work without a network.",
            paragraphs: [
                "Open Offline, search for a region and download it. The app fetches the region's place pack, its places archive, a basemap PMTiles archive and, once, the shared glyph pack. The download runs in a background URLSession, so it can finish while Vela is in the background, and it resumes after a relaunch when iOS kept the transfer.",
                "Inside a downloaded region the map is built from local PMTiles and contains no remote style URL. Search reads the installed places, addresses and street names. The region polygons decide coverage, so a downloaded country does not silently cover its neighbours.",
                "Offline means no live traffic, no Street View and no place details from Google. Routing also needs a network on iOS: the downloaded packs contain no on-device routing graph. Use the online map for those.",
                "The Offline screen shows the storage used by places, the map and the shared glyphs. Deleting a region removes its own packs. Downloaded regions stay on this phone and are not uploaded."
            ],
            keywords: "offline download region map places addresses storage background resume pmtiles glyphs nogoogle"),

        HelpTopic(
            id: "search-sources",
            title: "Where do search results come from?",
            summary: "Google when it is allowed, Photon for open and address search, and the places installed with a downloaded region.",
            paragraphs: [
                "With Google allowed, search asks Google and, in parallel, Photon for a query that reads like an address. Google results win when they answer, and Photon fills a missing address. The search window widens to about 40 km for an address.",
                "With Use Vela without Google, Vela asks Photon twice: one ranked request and one around the current area for partial addresses. Rows from a downloaded region are merged in and come first when they carry the query. Vela never falls back to Google in that mode.",
                "Without a network, only the installed region rows answer. That is why a search can be thin in an area that was never downloaded.",
                "Suggestions appear after a short pause while typing. Choosing one runs the full search. A missing place can simply be absent from all three sources, or lack the words you typed; try its street address or a nearby landmark."
            ],
            keywords: "search results source google photon address suggestions missing place offline region"),

        HelpTopic(
            id: "voice-downloads",
            title: "Why do I need to download a voice?",
            summary: "Spoken guidance uses downloadable Piper voices that run on the phone. Without one, Vela uses the iPhone's own voice.",
            paragraphs: [
                "Open Settings, Voice and pick a voice. A Piper voice is a 60 to 115 MB model, unpacked into Application Support and run by sherpa-onnx on the device. Nothing you say or hear is sent anywhere. You can remove a voice at any time.",
                "Without a downloaded voice, or for a language with no Piper voice (Japanese is the one), Vela uses the iPhone's AVSpeech voice. It works, but it can mispronounce local street names and may not match the language of the directions.",
                "English Piper voices read from Vela's own dictionary of about 3,500 place names, built from English Wikipedia. The Apple voice does not use that dictionary.",
                "The volume and speed controls in Settings, Voice affect the spoken directions. Voice search is different: it uses an on-device Whisper model when installed, otherwise the iPhone's speech recognizer, and it does not use a Piper voice."
            ],
            keywords: "voice piper download speech spoken navigation audio volume speed language japanese avspeech whisper offline"),

        HelpTopic(
            id: "privacy-google",
            title: "What does Vela send to Google?",
            summary: "With Google allowed, searches, place pages, routes, Street View and the Google rasters go to Google's public servers, without an account.",
            paragraphs: [
                "Google sees the phone's IP address, the words you search, the map area or the route endpoints, and its own logged-out session cookie. It never sees a Google account, a name or an API key that identifies Vela.",
                "Use Vela without Google blocks every Google host in Vela's HTTP client. Two exceptions stay under your control: opening a maps.app.goo.gl short link asks Google's shortener once without cookies, and the Traffic and Satellite layers load their tiles directly through MapLibre. Leave those switches off for no Google requests.",
                "Map tiles, OpenFreeMap, Photon, Overpass, Transitous, OSRM and Valhalla do not go to Google. A downloaded region keeps its map and places on the phone.",
                "The Privacy page counts requests made by Vela's HTTP client and the refusals while Google is off. The count is a floor, not a total: map tiles and hidden WebView traffic do not pass through that client. The same page can clear the counter or delete recent searches, recent places, parking history and recorded trips."
            ],
            keywords: "privacy google send account ip cookie nogoogle counter requests clear history telemetry short link"),

        HelpTopic(
            id: "report-problem",
            title: "How do I report a problem?",
            summary: "Export diagnostics, copy the version and build number, and describe what you did. Everything is a file you choose to share.",
            paragraphs: [
                "Export diagnostics here or in Settings, Privacy. Vela writes a plain text file with the app version and build number, the calibration version, the privacy switches and at most 200 recent lines from the Web, Calibration and Privacy logs, with places redacted. The iOS share sheet then asks where to send it. The Kotlin search, route and parsing logs are not included.",
                "The version row on this page can be copied. It contains the marketing version and the build number, which is what a bug report needs.",
                "Recorded trips are a separate file. When they are on, Vela stores the GPS trace of a navigation on this phone so a drive can be replayed. A trip is more revealing than diagnostics. It is never uploaded unless you share it, and Recorded trips can delete everything or raise the redaction radius for exports.",
                "Problems with a map tile, a place page or a route are often on the other side: OpenFreeMap, Google or a transit operator. The diagnostic file and the exact time help tell those apart. Source code, bug reports and discussions are in the Vela repository."
            ],
            keywords: "report bug diagnostics export log version build crash trip recorded trace github share")
    ]

    static func topic(id: String) -> HelpTopic? {
        topics.first { $0.id == id }
    }
}

struct SettingsIndexEntry: Identifiable, Hashable {
    let anchor: String
    let label: String
    let section: String
    let keywords: String

    var id: String { anchor }
}

/// The search index behind the About hub. Anchors are SwiftUI `.id` values on the Settings form
/// rows, so a hit closes About and scrolls the form to the real control.
enum SettingsIndex {
    static let entries: [SettingsIndexEntry] = [
        SettingsIndexEntry(anchor: "settings-appearance", label: "Appearance", section: "Appearance", keywords: "appearance theme language units clock map look chrome"),
        SettingsIndexEntry(anchor: "settings-navigation", label: "Navigation", section: "Navigation", keywords: "navigation camera gestures bike map buttons start view zoom tilt"),
        SettingsIndexEntry(anchor: "settings-voice", label: "Voice", section: "Voice", keywords: "voice piper download spoken directions volume speed language navigation audio"),
        SettingsIndexEntry(anchor: "settings-data-content", label: "Data and content", section: "Data and content", keywords: "data content places photos reviews cache quick chips"),
        SettingsIndexEntry(anchor: "settings-quick-chips", label: "Quick search buttons", section: "Data and content", keywords: "quick chips shortcuts search buttons"),
        SettingsIndexEntry(anchor: "settings-trips", label: "Saved and trips", section: "Saved and trips", keywords: "saved trips recorded storage redact delete"),
        SettingsIndexEntry(anchor: "settings-offline", label: "Offline maps", section: "Offline", keywords: "offline download region map storage"),
        SettingsIndexEntry(anchor: "settings-about", label: "About", section: "About", keywords: "about version build help notices licenses support diagnostics"),
        SettingsIndexEntry(anchor: "settings-language", label: "Language", section: "Appearance", keywords: "language locale system"),
        SettingsIndexEntry(anchor: "settings-units", label: "Units", section: "Appearance", keywords: "units metric imperial distance speed"),
        SettingsIndexEntry(anchor: "settings-clock", label: "Clock", section: "Appearance", keywords: "clock 12 24 hour time"),
        SettingsIndexEntry(anchor: "settings-no-google", label: "Use Vela without Google", section: "Privacy", keywords: "google free nogoogle privacy block"),
        SettingsIndexEntry(anchor: "settings-resolve-links", label: "Open shared Google Maps links", section: "Privacy", keywords: "short link maps.app.goo.gl google free"),
        SettingsIndexEntry(anchor: "settings-lookup-tapped", label: "Look up tapped places on Google", section: "Privacy", keywords: "poi maps places lookup google"),
        SettingsIndexEntry(anchor: "settings-telemetry", label: "Block Google page telemetry", section: "Privacy", keywords: "telemetry gen_204 ogads tracking"),
        SettingsIndexEntry(anchor: "settings-session-mode", label: "Google session rotation", section: "Privacy", keywords: "session cookie week day launch"),
        SettingsIndexEntry(anchor: "settings-session-new", label: "Start a new Google session now", section: "Privacy", keywords: "session cookies new reset"),
        SettingsIndexEntry(anchor: "settings-privacy-page", label: "Privacy page", section: "Privacy", keywords: "privacy page google requests counter history"),
        SettingsIndexEntry(anchor: "settings-export-diagnostics", label: "Export diagnostics", section: "Privacy", keywords: "diagnostics export log bug report support"),
        SettingsIndexEntry(anchor: "settings-place-content", label: "Place content", section: "Data and content", keywords: "place content full tiles only google"),
        SettingsIndexEntry(anchor: "settings-show-reviews", label: "Show reviews", section: "Data and content", keywords: "reviews place details google"),
        SettingsIndexEntry(anchor: "settings-load-photos", label: "Load photos", section: "Data and content", keywords: "photos images place google"),
        SettingsIndexEntry(anchor: "settings-photos-wifi", label: "Load photos only on Wi-Fi", section: "Data and content", keywords: "photos wifi mobile data expensive"),
        SettingsIndexEntry(anchor: "settings-photo-quality", label: "Photo quality", section: "Data and content", keywords: "photo quality high standard low"),
        SettingsIndexEntry(anchor: "settings-photo-cache-size", label: "Photo cache size", section: "Data and content", keywords: "photo cache memory size megabytes"),
        SettingsIndexEntry(anchor: "settings-photo-cache-clear", label: "Clear photo cache", section: "Data and content", keywords: "photo cache clear purge memory"),
        SettingsIndexEntry(anchor: "settings-full-place-load", label: "Load all photos and reviews", section: "Data and content", keywords: "photos reviews full load cap 50"),
        SettingsIndexEntry(anchor: "settings-details-retry", label: "Wait for popular times", section: "Data and content", keywords: "popular times details retry busy"),
        SettingsIndexEntry(anchor: "settings-hide-adult", label: "Hide adult categories", section: "Data and content", keywords: "adult categories search poi"),
        SettingsIndexEntry(anchor: "settings-hide-external", label: "Hide website and external links", section: "Data and content", keywords: "website external links book reserve order"),
        SettingsIndexEntry(anchor: "settings-low-data", label: "Low data mode", section: "Data and content", keywords: "low data LowDataMode photos traffic"),
        SettingsIndexEntry(anchor: "settings-low-ram", label: "Low RAM mode", section: "Data and content", keywords: "low ram LowRamMode memory performance"),
        SettingsIndexEntry(anchor: "settings-redact-exports", label: "Redact places in exports", section: "Recorded trips", keywords: "redact trips exports privacy radius"),
        SettingsIndexEntry(anchor: "settings-trips-size", label: "Recorded trips size", section: "Recorded trips", keywords: "trips recorded size storage files"),
        SettingsIndexEntry(anchor: "settings-trips-delete", label: "Delete all recorded trips", section: "Recorded trips", keywords: "trips delete recorded trace purge")
    ]
}

/// The version and build come from the bundle, so a CI build shows the numbers Xcode was given.
enum AboutInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    static var versionLine: String { "Vela \(version) (build \(build))" }

    static func debugLine(notices: [NoticeEntry]) -> String {
        "version=\(version) build=\(build) notices=\(notices.count) "
            + "help=\(HelpCatalog.topics.count) settings=\(SettingsIndex.entries.count)"
    }
}

/// Search across Settings rows, help topics, notices and the Support entries. A query is a plain
/// case-insensitive substring match, like the Android settings hub.
enum AboutSearch {
    struct Hit: Identifiable, Hashable {
        enum Kind: String {
            case setting
            case help
            case notice
            case support
        }

        let id: String
        let kind: Kind
        let title: String
        let subtitle: String
        let target: String
    }

    private static let supportRows: [(target: String, title: String, subtitle: String, keywords: String)] = [
        ("version", "Version and build number", "Support", "version build number copy report"),
        ("installer", "Installer name", "Support", "installer testflight sidestore xcode sideload"),
        ("diagnostics", "Export diagnostics", "Support", "diagnostics export log bug report support"),
        ("donate", "Support Vela", "Support", "donate donation support payment buy me a coffee"),
        ("project", "Project website and source code", "Support", "website github repo source issue"),
        ("notices", "Notices and licenses", "Support", "notices licenses licenses attribution dependencies")
    ]

    static func hits(query: String, notices: [NoticeEntry], limit: Int = 24) -> [Hit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        var found: [Hit] = []

        for entry in SettingsIndex.entries where matches(
            needle, entry.label, entry.section, entry.keywords) {
            found.append(Hit(
                id: "setting-\(entry.anchor)",
                kind: .setting,
                title: entry.label,
                subtitle: "Settings > \(entry.section)",
                target: entry.anchor))
        }

        for topic in HelpCatalog.topics where matches(
            needle, topic.title, topic.summary, topic.keywords, topic.paragraphs.joined(separator: " ")) {
            found.append(Hit(
                id: "help-\(topic.id)",
                kind: .help,
                title: topic.title,
                subtitle: "Help",
                target: topic.id))
        }

        for notice in notices where matches(
            needle, notice.title, notice.license, notice.note, notice.kind) {
            found.append(Hit(
                id: "notice-\(notice.id)",
                kind: .notice,
                title: notice.title,
                subtitle: notice.license,
                target: notice.id))
        }

        for row in supportRows where matches(needle, row.title, row.subtitle, row.keywords) {
            found.append(Hit(
                id: "support-\(row.target)",
                kind: .support,
                title: row.title,
                subtitle: row.subtitle,
                target: row.target))
        }

        return Array(found.prefix(limit))
    }

    private static func matches(_ needle: String, _ values: String...) -> Bool {
        values.contains { $0.lowercased().contains(needle) }
    }
}
