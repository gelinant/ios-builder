import AVFoundation
import SwiftUI
import VelaCore

/// One short result in the drive's search overlay: the place, its distance from the car and the
/// drive off the line and back. The detour stays nil outside a line, so no number is invented.
struct DriveSearchHit: Identifiable {
    let row: SearchRow
    let distanceMeters: Double?
    let detourMeters: Double?
    var id: Int { row.id }
}

/// DRIVE-SEARCH: the driving chrome's search entry. The field is an overlay above the banner,
/// never a sheet, so the map, the camera, the step and the Live Activity keep running behind it.
/// The field never takes focus on its own; only a tap opens the keyboard. The same
/// `SearchCommands` parser as the map and the microphone reads the sentence, and "directions to X"
/// asks whether to add a stop or replace the destination before anything changes.
struct DriveSearchOverlay: View {
    @ObservedObject var model: NavModel
    @ObservedObject var search: SearchModel
    /// True only when the driver tapped the voice button, never on the search button.
    var startVoice = false
    let onClose: () -> Void

    @State private var text = ""
    @State private var localKind = ""
    @State private var choiceQuery = ""
    @State private var choiceText = ""
    @State private var notice: String?
    @StateObject private var voice = DriveDictation()

    private var language: String {
        let tag = DirectionsLanguage.shared.appLanguage(tag: DevicePlatformLocale.effectiveTag())
        return tag.isEmpty ? "en" : tag
    }

    private var commandKind: String {
        localKind.isEmpty ? search.commandKind : localKind
    }

    var body: some View {
        ZStack(alignment: .top) {
            // A light veil only: the drive stays visible and steers underneath. Tapping it closes
            // the field exactly like the close button.
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityIdentifier("drive-search-backdrop")
            card
                .padding(.horizontal, 12)
                .padding(.top, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drive-search")
        .onAppear {
            // Each opening starts from an empty field and an empty list, never a stale answer.
            search.clear()
            voice.onTranscript = { spoken in
                guard !spoken.isEmpty else { return }
                text = spoken
                submit()
            }
        }
        .task {
            if startVoice { voice.open(language: language) }
        }
        .onDisappear {
            // The drive keeps its search state: replacing the destination submits a command and
            // closes straight away, so clearing here would race that search.
            voice.cancel()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            searchRow
            if voice.isOpen {
                voiceCard
            }
            if !choiceQuery.isEmpty {
                choiceCard
            }
            results
            if let notice {
                Text(notice)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("drive-search-message")
            } else if let message = search.message, search.rows.isEmpty, !search.searching {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("drive-search-message")
            }
            debugLine
        }
        .padding(14)
        .frame(maxWidth: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(VelaL10n.text("place_search_along_route"))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("drive-search-title")
            Spacer(minLength: 0)
            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(VelaL10n.text("mapscreen_dismiss"))
            .accessibilityIdentifier("drive-search-close")
        }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            TextField(VelaL10n.text("route_search_for_a_place"), text: $text)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { submit() }
                .accessibilityIdentifier("drive-search-field")
            Button { voice.open(language: language) } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .background(.thinMaterial, in: Circle())
            .accessibilityLabel(VelaL10n.text("search_voice_cd"))
            .accessibilityIdentifier("drive-search-voice")
            Button { submit() } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .background(.thinMaterial, in: Circle())
            .accessibilityLabel(VelaL10n.text("settings_search"))
            .accessibilityIdentifier("drive-search-go")
        }
    }

    private var choiceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(choiceQuery)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .accessibilityIdentifier("drive-search-choice-title")
            Text(VelaL10n.text("mapscreen_pick_stop_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(VelaL10n.text("place_add_stop")) { choose(add: true) }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("drive-search-add-stop")
                Button(VelaL10n.text("place_change_destination")) { choose(add: false) }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("drive-search-replace")
                Button(VelaL10n.text("settings_cancel")) {
                    choiceQuery = ""
                    choiceText = ""
                }
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
                .accessibilityIdentifier("drive-search-choice-cancel")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drive-search-choice")
    }

    @ViewBuilder
    private var results: some View {
        if search.searching && search.rows.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(VelaL10n.text("settings_search"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !hits.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(hits) { hit in
                        Button { add(hit.row) } label: {
                            resultRow(hit)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("drive-search-result")
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 240)
            .accessibilityIdentifier("drive-search-results")
        }
    }

    private func resultRow(_ hit: DriveSearchHit) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.row.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(figures(hit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let address = hit.row.address, !address.isEmpty {
                    Text(address)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(Design.Colors.accentFill)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func figures(_ hit: DriveSearchHit) -> String {
        var parts: [String] = []
        if let distance = hit.distanceMeters {
            parts.append(SearchRow.distance(distance))
        }
        if let detour = hit.detourMeters {
            parts.append(VelaL10n.text("nav_stop_offer_detour", SearchRow.distance(detour)))
        }
        return parts.joined(separator: " · ")
    }

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(voice.failure == nil
                ? VelaL10n.text("search_voice_cd")
                : VelaL10n.text("voice_voice_search_failed"))
                .font(.subheadline.weight(.semibold))
            if let failure = voice.failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("drive-voice-error")
            } else {
                Text(voice.status.isEmpty ? VelaL10n.text("voice_capture_listening") : voice.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !voice.heard.isEmpty {
                    Text(voice.heard)
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                        .accessibilityIdentifier("drive-voice-heard")
                }
            }
            HStack(spacing: 8) {
                if voice.failure != nil {
                    Button(VelaL10n.text("voice_error_retry")) { voice.open(language: language) }
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("drive-voice-retry")
                    Button(VelaL10n.text("place_close")) { voice.dismissError() }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("drive-voice-close")
                } else {
                    Button(VelaL10n.text("steps_stop")) { voice.finish() }
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("drive-voice-stop")
                    Button(VelaL10n.text("settings_cancel")) { voice.cancel() }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("drive-voice-cancel")
                }
            }
            Text(voice.debugLine)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("drive-voice-debug")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drive-voice")
    }

    @ViewBuilder
    private var debugLine: some View {
        #if DEBUG
        Text(
            "open=1 cmd=\(commandKind.isEmpty ? "-" : commandKind)"
                + " results=\(hits.count) added=\(addedCount) nav=\(model.navigating ? 1 : 0)"
                + " activity=\(model.activityActive ? 1 : 0) step=\(model.stepIndex)")
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityIdentifier("drive-search-debug")
        #endif
    }

    /// The short list: at most four, closest detour first. The drive only ever keeps the few a
    /// driver can choose between without reading a page.
    private var hits: [DriveSearchHit] {
        let route = model.routeFlat
        let traveled = model.traveledMeters
        let origin = model.currentCoordinate
        let candidates = search.rows.prefix(12).map { row -> DriveSearchHit in
            let straight = origin.map {
                Self.distanceMeters(lat1: $0.latitude, lng1: $0.longitude,
                                    lat2: row.latitude, lng2: row.longitude)
            }
            return DriveSearchHit(
                row: row,
                distanceMeters: straight ?? row.distanceMeters,
                detourMeters: route.count >= 4
                    ? Self.detourMeters(row.latitude, row.longitude, route: route, traveled: traveled)
                    : nil)
        }
        return Array(candidates.sorted { left, right in
            switch (left.detourMeters, right.detourMeters) {
            case let (lhs?, rhs?): return lhs < rhs
            case (nil, _?): return false
            case (_?, nil): return true
            default: return (left.distanceMeters ?? .greatestFiniteMagnitude)
                < (right.distanceMeters ?? .greatestFiniteMagnitude)
            }
        }.prefix(4))
    }

    /// A debug counter so the line can prove the overlay added the stop before it closes.
    private var addedCount: Int {
        #if DEBUG
        DriveSearchDebug.adds
        #else
        0
        #endif
    }

    private func submit() {
        let committed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !committed.isEmpty else { return }
        notice = nil
        // The drive reads the same parser as the map. Only the directions command needs a
        // decision before it runs, because silently replacing the destination would end the
        // drive the driver is already following.
        if let plan = SearchCommands.shared.parse(text: committed, lang: language),
           plan.kind == "directions" {
            localKind = "directions"
            choiceQuery = plan.query
            choiceText = committed
            return
        }
        localKind = ""
        choiceQuery = ""
        choiceText = ""
        search.submit(text: committed, viewport: nil)
    }

    private func choose(add: Bool) {
        let query = choiceQuery
        let original = choiceText
        choiceQuery = ""
        choiceText = ""
        if add {
            guard !query.isEmpty else { return }
            Task { await addFirst(query) }
            return
        }
        // Replace reuses the ordinary directions path: the chooser names the new destination and
        // the live drive keeps going until the driver starts that route.
        search.submit(text: original, viewport: nil)
        close()
    }

    @MainActor
    private func addFirst(_ query: String) async {
        let baseline = search.submissions
        search.search(query, viewport: nil)
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            if search.submissions > baseline, !search.searching, let row = search.rows.first {
                add(row)
                return
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        notice = VelaL10n.text("mapvm_no_results", query)
    }

    private func add(_ row: SearchRow) {
        model.addStop(name: row.name, latitude: row.latitude, longitude: row.longitude)
        #if DEBUG
        DriveSearchDebug.adds += 1
        #endif
        close()
    }

    private func close() {
        voice.cancel()
        onClose()
    }

    private static func distanceMeters(
        lat1: Double, lng1: Double, lat2: Double, lng2: Double
    ) -> Double {
        let mid = (lat1 + lat2) / 2 * .pi / 180
        let dx = (lng2 - lng1) * 111_320 * cos(mid)
        let dy = (lat2 - lat1) * 111_320
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Twice the perpendicular distance to the live line, past the travelled part. A place behind
    /// the car has no detour and is not proposed. The numbers match `SearchCommandCorridor`.
    private static func detourMeters(
        _ latitude: Double, _ longitude: Double, route: [Double], traveled: Double
    ) -> Double? {
        let count = route.count / 2
        guard count >= 2 else { return nil }
        var cumulative = [Double](repeating: 0, count: count)
        for index in 1..<count {
            cumulative[index] = cumulative[index - 1] + distanceMeters(
                lat1: route[(index - 1) * 2], lng1: route[(index - 1) * 2 + 1],
                lat2: route[index * 2], lng2: route[index * 2 + 1])
        }
        var bestOff = Double.greatestFiniteMagnitude
        var bestAlong = 0.0
        for index in 0..<(count - 1) {
            let aLat = route[index * 2]
            let aLng = route[index * 2 + 1]
            let bLat = route[(index + 1) * 2]
            let bLng = route[(index + 1) * 2 + 1]
            let midLat = (aLat + bLat) / 2 * .pi / 180
            let bx = (bLng - aLng) * 111_320 * cos(midLat)
            let by = (bLat - aLat) * 111_320
            let px = (longitude - aLng) * 111_320 * cos(midLat)
            let py = (latitude - aLat) * 111_320
            let length2 = bx * bx + by * by
            let t = length2 == 0 ? 0 : min(1, max(0, (px * bx + py * by) / length2))
            let off = ((px - t * bx) * (px - t * bx) + (py - t * by) * (py - t * by)).squareRoot()
            if off < bestOff {
                bestOff = off
                bestAlong = cumulative[index]
                    + t * (cumulative[index + 1] - cumulative[index])
            }
        }
        if traveled > 0 && bestAlong < traveled { return nil }
        return bestOff * 2
    }
}

#if DEBUG
enum DriveSearchDebug {
    static var adds = 0
}
#endif

/// The drive's own dictation: the same on-device engines as VO-2, but the transcript lands in the
/// drive's field and goes through the same command parser instead of the map's voice dialog. The
/// microphone still opens only after an explicit tap.
@MainActor
final class DriveDictation: ObservableObject {
    enum Phase: Equatable {
        case idle
        case listening
        case recognising
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var heard = ""
    @Published private(set) var status = ""
    @Published private(set) var debugLine = "engine=none state=idle"

    var onTranscript: ((String) -> Void)?

    private let capture = VoiceCapture()
    private let sherpa = SherpaAsr()
    private let apple = AppleSpeech()
    private let asr = AsrStore.shared

    private var samples: [Float] = []
    private var engineId: String?
    private var language = "en"
    private var engineLabel = "none"
    private var busy = false
    private var injected = false

    var isOpen: Bool { phase != .idle }

    var failure: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    init() {
        capture.onBuffer = { [weak self] buffer in self?.collect(buffer) }
        capture.onRawBuffer = { [weak self] buffer in
            guard let self, self.engineLabel == "apple" else { return }
            self.apple.append(buffer)
        }
        capture.onLevel = { [weak self] value in
            DispatchQueue.main.async { self?.level = value }
        }
        capture.onAutoStop = { [weak self] in
            DispatchQueue.main.async { self?.finish() }
        }
    }

    func open(language: String) {
        guard !busy else { return }
        heard = ""
        level = 0
        samples = []
        self.language = language
        #if DEBUG
        if let text = LaunchOptionsAsr.injectedText {
            injected = true
            engineLabel = "injected"
            heard = text
            status = VelaL10n.text("settings_search")
            phase = .listening
            updateDebug(state: "injected")
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 450_000_000)
                self?.deliver(text)
            }
            return
        }
        #endif
        injected = false
        let chosen = asr.engineId(forLanguage: language)
        engineId = chosen
        if let chosen, let entry = asr.entry(chosen) {
            engineLabel = "sherpa"
            let model = SherpaAsr.Model(
                id: entry.id, modelType: entry.modelType, language: language,
                files: asr.files(for: entry))
            sherpa.warmUp(model)
            startCapture(language: language)
        } else {
            engineLabel = "apple"
            status = VelaL10n.text("voice_capture_listening")
            phase = .listening
            Task { await startApple(language: language) }
        }
        updateDebug(state: "opening")
    }

    private func startCapture(language: String) {
        Task {
            guard await requestMic() else {
                fail("Microphone access is off. Allow it for Vela in Settings, then try again.")
                return
            }
            guard DictationAudio.shared.begin() else {
                fail("The microphone could not start. Close other audio apps and try again.")
                return
            }
            do {
                try capture.start()
            } catch {
                DictationAudio.shared.end()
                fail(error.localizedDescription)
                return
            }
            phase = .listening
            status = VelaL10n.text("voice_capture_listening")
            updateDebug(state: "listening")
        }
    }

    private func startApple(language: String) async {
        let authorization = await AppleSpeech.requestAuthorization()
        guard authorization == .authorized else {
            fail("Speech recognition is not allowed. Enable it for Vela in Settings, or download a Vela voice search model.")
            return
        }
        guard await requestMic() else {
            fail("Microphone access is off. Allow it for Vela in Settings, then try again.")
            return
        }
        guard DictationAudio.shared.begin() else {
            fail("The microphone could not start. Close other audio apps and try again.")
            return
        }
        do {
            try apple.start(language: language) { [weak self] text in
                guard let self, !text.isEmpty else { return }
                self.heard = text
            }
            try capture.start()
        } catch {
            apple.cancel()
            DictationAudio.shared.end()
            fail(error.localizedDescription)
            return
        }
        phase = .listening
        status = VelaL10n.text("voice_capture_listening")
        updateDebug(state: "listening")
    }

    private func requestMic() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined: break
        @unknown default: return false
        }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func collect(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        samples.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }

    func finish() {
        guard phase == .listening, !busy, !injected else { return }
        busy = true
        capture.stop()
        DictationAudio.shared.end()
        let label = engineLabel
        phase = .recognising
        status = VelaL10n.text("settings_search")
        updateDebug(state: "recognising")
        Task {
            defer { busy = false }
            if label == "apple" {
                let text = await apple.finish()
                deliver(text)
                return
            }
            let collected = samples
            samples = []
            guard let id = engineId, let entry = asr.entry(id) else {
                fail("The speech model is no longer available. Download it again in Settings.")
                return
            }
            let model = SherpaAsr.Model(
                id: entry.id, modelType: entry.modelType, language: language,
                files: asr.files(for: entry))
            let recognizer = sherpa
            do {
                let text = try await Task.detached(priority: .userInitiated) {
                    try recognizer.transcribe(samples: collected, sampleRate: 16000, model: model)
                }.value
                deliver(text)
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    func cancel() {
        if phase == .listening { capture.stop() }
        apple.cancel()
        DictationAudio.shared.end()
        samples = []
        phase = .idle
        heard = ""
        level = 0
        updateDebug(state: "idle")
    }

    func dismissError() {
        phase = .idle
        status = ""
        heard = ""
        updateDebug(state: "idle")
    }

    private func deliver(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            fail("No speech was heard. Hold the phone closer and try again.")
            return
        }
        heard = text
        phase = .idle
        status = ""
        updateDebug(state: "delivered")
        onTranscript?(text)
    }

    private func fail(_ message: String) {
        phase = .failed(message)
        status = message
        updateDebug(state: "failed")
    }

    private func updateDebug(state: String) {
        var parts = ["engine=\(engineLabel)", "state=\(state)"]
        if !heard.isEmpty {
            parts.append("heard=\(heard.replacingOccurrences(of: " ", with: "_"))")
        }
        debugLine = parts.joined(separator: " ")
    }
}
