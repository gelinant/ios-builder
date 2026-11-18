import SwiftUI
import VelaCore

/// The place sheet's "Learn more" section (W-1): Wikidata facts and a Wikivoyage extract, with the
/// source page, its licence and the exact attribution. It is the only part of the sheet that asks
/// Wikidata or Wikivoyage, and it asks nothing while the wiki layer is off or the place names no
/// Wikidata item.
///
/// No Wikimedia image is shown in this lot: the section links to the source page instead.
struct PlaceKnowledgeSection: View {
    let place: PlaceCard
    @ObservedObject private var world = WorldLayersHub.shared
    @State private var knowledge: KnowledgeViewData?
    @State private var loading = false
    @State private var loadedSource: String?
    @Environment(\.openURL) private var openURL

    private var wikidataId: String? { place.wikidataId }

    private var loadKey: String {
        "\(place.sourceId)|\(world.isOn(WikiLayerId))"
    }

    /// The section exists only for a place the sources can name and while its layer is on. A place
    /// with a Google or OpenStreetMap id alone shows nothing rather than an empty promise.
    @ViewBuilder
    var body: some View {
        if let wikidataId, world.isOn(WikiLayerId) {
            VStack(alignment: .leading, spacing: 8) {
                Text(VelaL10n.text("settings_places_source_more"))
                    .font(.headline)
                    .accessibilityIdentifier("place-knowledge")
                if let knowledge {
                    fieldRows(knowledge)
                    if let extract = knowledge.extract, !extract.isEmpty {
                        article(extract, url: knowledge.articleURL)
                    }
                    attribution(knowledge)
                } else if loading {
                    ProgressView()
                        .accessibilityIdentifier("wiki-loading")
                }
                #if DEBUG
                Text("wiki_fields=\(knowledge?.fieldCount ?? 0) wiki_image=none wiki_language=\(knowledge?.language ?? "-") wiki_id=\(wikidataId)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("wiki-debug")
                #endif
            }
            .task(id: loadKey) { await load() }
        } else {
            #if DEBUG
            Text("wiki_state=" + (wikidataId == nil ? "no_id" : "layer_off"))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("wiki-state-debug")
            #endif
        }
    }

    @ViewBuilder
    private func fieldRows(_ knowledge: KnowledgeViewData) -> some View {
        if let population = knowledge.population {
            row(VelaL10n.text("place_wiki_population"), population, id: "wiki-field-population")
        }
        if let opened = knowledge.opened {
            row(VelaL10n.text("place_wiki_opened"), opened, id: "wiki-field-opened")
        }
        if let website = knowledge.website, let url = URL(string: website) {
            Button {
                openURL(url)
            } label: {
                HStack(spacing: 4) {
                    Text(VelaL10n.text("place_website"))
                        .foregroundStyle(.secondary)
                    Text(PlaceSheet.shortHost(website))
                        .foregroundStyle(Color.accentColor)
                }
                .font(.subheadline)
                .frame(minHeight: 36)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wiki-field-website")
        }
        Button {
            if let url = URL(string: "https://www.wikidata.org/wiki/\(knowledge.wikidataId)") {
                openURL(url)
            }
        } label: {
            HStack(spacing: 4) {
                Text("Wikidata")
                    .foregroundStyle(.secondary)
                Text(knowledge.wikidataId)
                    .foregroundStyle(Color.accentColor)
            }
            .font(.subheadline)
            .frame(minHeight: 36)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wiki-field-id")
    }

    private func row(_ label: String, _ value: String, id: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
        }
        .font(.subheadline)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private func article(_ extract: String, url: URL?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(extract)
                .font(.subheadline)
                .accessibilityIdentifier("wiki-extract")
            if let url {
                Button {
                    openURL(url)
                } label: {
                    Label(VelaL10n.text("place_read_the_full_article_on_wikivoyage"), systemImage: "safari")
                        .font(.subheadline)
                        .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("wiki-source-link")
            }
        }
    }

    private func attribution(_ knowledge: KnowledgeViewData) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(VelaL10n.text("place_wikivoyage_contributors_cc_by_sa_4"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("wiki-attribution")
            Text(VelaL10n.text("place_wikidata_cc0_1_0"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("wiki-wikidata-attribution")
            if let title = knowledge.articleTitle {
                Text(VelaL10n.text("place_source_on_wikivoyage", String(describing: (title))))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        if loadedSource == place.sourceId, knowledge != nil { return }
        loading = true
        defer { loading = false }
        guard let core = IosGraph.shared.core else { return }
        let store = WikiResources.shared.forCore(core: core)
        do {
            let result = try await store.knowledge(placeId: place.sourceId, layerOn: true, language: nil)
            knowledge = result.flatMap { KnowledgeViewData($0) }
            loadedSource = place.sourceId
        } catch {
            knowledge = nil
        }
    }
}

/// The row shape the section draws, copied out of the Kotlin payload so SwiftUI holds plain values.
private struct KnowledgeViewData {
    let wikidataId: String
    let language: String
    let population: String?
    let opened: String?
    let website: String?
    let extract: String?
    let articleTitle: String?
    let articleURL: URL?

    var fieldCount: Int {
        [population != nil, opened != nil, website != nil, !wikidataId.isEmpty].filter { $0 }.count
    }

    init?(_ knowledge: WikiKnowledge) {
        guard let facts = knowledge.facts else { return nil }
        wikidataId = facts.wikidataId
        language = facts.language
        population = facts.population.map { "\($0)" }
        opened = facts.opened
        website = facts.website
        let article = knowledge.article
        extract = article?.extract
        articleTitle = article?.title
        articleURL = article.flatMap { URL(string: $0.url) }
    }
}

/// The wiki layer's catalogue id, repeated here so the section and the layer cannot drift.
let WikiLayerId = "wiki"

#if DEBUG
extension PlaceCard {
    /// The W-1 UI scenario's place: a named city whose identifier is a Wikidata item, with no
    /// Google field, so the section is the only content the test reads.
    static func wikiFixture(wikidataId: String) -> PlaceCard {
        PlaceCard(
            key: "wiki:\(wikidataId)",
            name: "Paris",
            category: "Capital city",
            rating: nil,
            reviewCount: nil,
            priceText: nil,
            statusText: nil,
            openNow: nil,
            hours: [],
            address: "Paris, France",
            phone: nil,
            website: nil,
            summary: nil,
            ownerDescription: nil,
            about: [],
            updates: [],
            similarPlaces: [],
            departments: [],
            actionLabel: nil,
            actionUrl: nil,
            permanentlyClosed: false,
            temporarilyClosed: false,
            fuelPrice: nil,
            fuelPriceAt: nil,
            fuelBrand: nil,
            fuelGrade: nil,
            fuelNearby: nil,
            featuredReview: nil,
            photos: [],
            photoDates: [],
            photoCategories: [],
            streetViewThumbnail: nil,
            streetViewPanoId: nil,
            streetViewYawDeg: nil,
            busyDays: [],
            ratingHistogram: nil,
            latitude: 48.8566,
            longitude: 2.3522,
            featureId: nil,
            sourceId: "wikidata:\(wikidataId)")
    }
}
#endif
