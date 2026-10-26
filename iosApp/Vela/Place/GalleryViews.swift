import SwiftUI
import UIKit

struct GalleryRequest: Identifiable, Hashable {
    let id = UUID()
    let urls: [String]
    let captions: [String?]
    let start: Int
}

/// The complete gallery grid. RPC cursors add pages, and a separate user action runs the category
/// walk. Cells and their requests are lazy; every image uses the Safari image headers.
struct PhotoGridView: View {
    @ObservedObject var model: PlaceModel
    let onClose: () -> Void

    @State private var category: String?
    @State private var viewer: GalleryRequest?

    private var card: PlaceCard? { model.card }
    private var categories: [String] {
        guard let card else { return [] }
        return Array(Set(card.photoCategories.compactMap { $0 })).sorted()
    }
    private var indices: [Int] {
        guard let card else { return [] }
        return card.photos.indices.filter { index in
            guard let category else { return true }
            return index < card.photoCategories.count && card.photoCategories[index] == category
        }
    }

    var body: some View {
        ZStack {
            NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    #if DEBUG
                    Text("count=\(card?.photos.count ?? 0) filtered=\(indices.count) loading=\(model.photosLoading ? 1 : 0) walk=\(model.canWalkPhotos ? 1 : 0) categories=\(categories.count) viewer=\(viewer == nil ? 0 : 1)")
                        .font(.caption2.monospaced())
                        .accessibilityIdentifier("place-gallery-debug")
                    #endif
                    if !categories.isEmpty || model.canWalkPhotos {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if !categories.isEmpty {
                                    categoryButton(nil, title: "All")
                                    ForEach(categories, id: \.self) { name in
                                        categoryButton(name, title: name)
                                    }
                                }
                            }
                        }
                    }
                    if let card {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                            ForEach(indices, id: \.self) { index in
                                Button { viewer = makeRequest(card, index: index) } label: {
                                    RemoteImage(url: card.photos[index], headers: model.photoHeaders())
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 110)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .accessibilityIdentifier("place-grid-photo-\(index)")
                            }
                        }
                    }
                    if model.photosLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("place-gallery-loading")
                    } else if model.canLoadMorePhotos {
                        Button("More photos") { model.loadMorePhotos() }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("place-grid-more-photos")
                    }
                    if indices.isEmpty && !model.photosLoading {
                        Text("No photos in this category")
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                }
                .padding(12)
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: onClose)
                        .accessibilityIdentifier("place-gallery-close")
                }
                if model.canWalkPhotos {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(categories.isEmpty ? "Load categories" : "More photos") {
                            model.loadPhotoCategories()
                        }
                        .accessibilityIdentifier("place-photo-categories")
                    }
                }
            }
            }
            if let viewer {
                PhotoViewer(request: viewer, headers: model.photoHeaders(), onClose: { self.viewer = nil })
            }
        }
        .onChange(of: card?.key ?? "") { _, _ in category = nil }
    }

    private func categoryButton(_ value: String?, title: String) -> some View {
        Button(title) { category = value }
            .buttonStyle(.bordered)
            .tint(category == value ? .accentColor : .secondary)
            .accessibilityIdentifier(value == nil ? "place-photo-category-all" : "place-photo-category-\(title)")
    }

    private func makeRequest(_ card: PlaceCard, index: Int) -> GalleryRequest {
        GalleryRequest(urls: card.photos, captions: captions(card), start: index)
    }

    private func captions(_ card: PlaceCard) -> [String?] {
        card.photos.indices.map { index in
            let date = index < card.photoDates.count ? card.photoDates[index] : nil
            let category = index < card.photoCategories.count ? card.photoCategories[index] : nil
            let parts = [category, date].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }
}

/// A full-screen pager with independent pinch zoom and pan on each photo.
struct PhotoViewer: View {
    let request: GalleryRequest
    let headers: [String: String]
    let onClose: () -> Void
    var usesNavigationDismiss = false
    @Environment(\.dismiss) private var dismiss

    @State private var index: Int

    init(request: GalleryRequest, headers: [String: String], onClose: @escaping () -> Void, usesNavigationDismiss: Bool = false) {
        self.request = request
        self.headers = headers
        self.onClose = onClose
        self.usesNavigationDismiss = usesNavigationDismiss
        _index = State(initialValue: min(max(0, request.start), max(0, request.urls.count - 1)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(request.urls.indices, id: \.self) { photo in
                    ZoomableRemoteImage(url: PhotoURL.sized(request.urls[photo]), headers: headers)
                        .tag(photo)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityIdentifier("place-photo-viewer")
            VStack {
                HStack {
                    Button {
                        if usesNavigationDismiss { dismiss() } else { onClose() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .zIndex(3)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("place-viewer-close")
                    Spacer()
                    Text("\(index + 1) / \(request.urls.count)")
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("place-gallery-counter")
                }
                .padding()
                .background(LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom))
                Spacer()
                if index < request.captions.count, let caption = request.captions[index], !caption.isEmpty {
                    Text(caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.65), in: Capsule())
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("place-photo-attribution")
                }
            }
            .zIndex(2)
        }
        .ignoresSafeArea()
        .background(.black)
    }
}

private struct ZoomableRemoteImage: View {
    let url: String
    let headers: [String: String]

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            RemoteImage(url: url, headers: headers, contentMode: .fit)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .clipped()
                .contentShape(Rectangle())
                .gesture(pan, including: scale > 1 ? .all : .none)
                .simultaneousGesture(magnification)
                .onTapGesture(count: 2) {
                    withAnimation {
                        scale = scale > 1 ? 1 : 2.5
                        lastScale = scale
                        if scale == 1 { offset = .zero; lastOffset = .zero }
                    }
                }
                .accessibilityIdentifier("place-viewer-image")
                .accessibilityValue(Text(String(format: "scale=%.1f", scale)))
        }
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(5, max(1, lastScale * value.magnification))
            }
            .onEnded { _ in
                lastScale = scale
                if scale == 1 { offset = .zero; lastOffset = .zero }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
}

private enum PhotoURL {
    /// Google's FIFE URLs take a size directive after the final slash.
    static func sized(_ url: String, pixels: Int = 1600) -> String {
        guard let slash = url.lastIndex(of: "/"), let equals = url.lastIndex(of: "="), equals > slash else { return url }
        return String(url[..<equals]) + "=s\(pixels)"
    }
}
