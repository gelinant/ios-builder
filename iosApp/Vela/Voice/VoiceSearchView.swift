import SwiftUI
import VelaCore

/// The microphone entry point, its listening card and the error message. The panel is an overlay
/// inside the map chrome rather than a second `.sheet`: MapScreen already owns the one-sheet slot,
/// and a card can show the loudness ring without competing for presentation.
struct VoiceSearchOverlay: ViewModifier {
    @ObservedObject var model: VoiceSearchModel

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                Button {
                    model.open()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                }
                .padding(.top, 66)
                .padding(.trailing, 12)
                .accessibilityLabel("Voice search")
                .accessibilityIdentifier("voice-search")
                .opacity(model.isOpen ? 0 : 1)
                .allowsHitTesting(!model.isOpen)
            }
            .overlay {
                if model.isOpen {
                    VoiceSearchPanel(model: model)
                }
            }
    }
}

extension View {
    /// The single hook MapScreen needs for VO-2: `.voiceSearchOverlay(search:route:saved:)` on the
    /// browser chrome, with the models the map already owns.
    func voiceSearchOverlay(search: SearchModel, route: RouteModel, saved: SavedModel) -> some View {
        modifier(VoiceSearchHost(search: search, route: route, saved: saved))
    }
}

/// Owns the model for the lifetime of the screen (a ViewModifier cannot hold a StateObject).
struct VoiceSearchHost: ViewModifier {
    @StateObject private var model: VoiceSearchModel

    init(search: SearchModel, route: RouteModel, saved: SavedModel) {
        _model = StateObject(wrappedValue: VoiceSearchModel(
            session: AppGraph.session, search: search, route: route, saved: saved))
    }

    func body(content: Content) -> some View {
        content.modifier(VoiceSearchOverlay(model: model))
    }
}

/// The listening card: loudness ring, status, the spoken examples, Stop and Cancel. A failed
/// attempt keeps the same card and replaces the ring with the reason and a retry.
private struct VoiceSearchPanel: View {
    @ObservedObject var model: VoiceSearchModel
    @ObservedObject private var asr = AsrStore.shared

    private var examples: [String] {
        let lang = NavStringsRegistry.shared.current().language
        return IosVoiceExamples.shared.phrases(lang: lang.isEmpty ? "en" : lang)
    }

    private var failure: String? {
        if case .failed(let message) = model.phase { return message }
        return nil
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
                .onTapGesture { model.cancel() }
            VStack(spacing: 16) {
                Text(failure == nil ? "Voice search" : "Voice search failed")
                    .font(.title3.weight(.semibold))
                if let failure {
                    Text(failure)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("voice-search-error")
                } else {
                    ring
                    Text(model.status.isEmpty ? "Listening" : model.status)
                        .font(.headline)
                    if !model.heard.isEmpty {
                        Text("“\(model.heard)”")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("voice-search-heard")
                    }
                    Text("Try saying")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(examples, id: \.self) { phrase in
                        Text(phrase)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    if failure != nil {
                        Button("Try again") { model.open() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("voice-search-retry")
                        Button("Close") { model.dismissError() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("voice-search-close")
                    } else {
                        Button("Stop") { model.finish() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("voice-search-stop")
                        Button("Cancel") { model.cancel() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("voice-search-cancel")
                    }
                }
                Text(model.debugLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("voice-search-debug")
                Text(engineNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("voice-search-privacy")
            }
            .padding(22)
            .frame(maxWidth: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .accessibilityIdentifier("voice-search-panel")
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 84, height: 84)
                .scaleEffect(1 + CGFloat(min(model.level, 1)) * 1.6)
                .animation(.easeOut(duration: 0.08), value: model.level)
            Circle()
                .fill(Color.accentColor)
                .frame(width: 58, height: 58)
                .overlay(Image(systemName: "mic.fill").foregroundStyle(.white))
        }
        .accessibilityHidden(true)
    }

    /// Says plainly where the audio goes: the downloaded model never leaves the phone, Apple's
    /// recognizer is on-device only here, and a missing model offers the download.
    private var engineNote: String {
        if model.debugLine.contains("engine=sherpa") {
            return "On this device. The downloaded model never sends audio anywhere."
        }
        if asr.installed.isEmpty {
            return "On-device Apple speech. Download a Vela voice search model for offline languages."
        }
        return "On-device speech recognition."
    }
}
