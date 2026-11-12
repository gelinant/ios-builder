import Foundation
import VelaCore

/// The accessibility identifiers of one time control. Every surface keeps its existing identifiers
/// so the scenarios written for R-1 and T-3 keep reading the same buttons, while the shared
/// `time-choice` container and the query label stay stable everywhere.
struct TimeChoiceIDs {
    var now = "time-choice-now"
    var depart = "time-choice-depart"
    var arrive = "time-choice-arrive"
    var date = "time-choice-date"
    var plus = "time-choice-plus"
    var apply = "time-choice-apply"
    var label = "time-choice-label"

    static let route = TimeChoiceIDs(
        now: "route-time-NOW",
        depart: "route-time-DEPART",
        arrive: "route-time-ARRIVE",
        date: "route-time-date",
        plus: "route-time-plus",
        apply: "route-time-apply",
        label: "route-time-query")

    static let transitOptions = TimeChoiceIDs(
        now: "transit-option-now",
        depart: "transit-option-depart",
        arrive: "transit-option-arrive",
        date: "transit-option-date",
        plus: "transit-option-plus15",
        apply: "transit-option-apply",
        label: "transit-option-query")

    static let trip = TimeChoiceIDs(
        now: "transit-trip-time-now",
        depart: "transit-trip-time-depart",
        arrive: "transit-trip-time-arrive",
        date: "transit-trip-time-date",
        plus: "transit-trip-time-plus",
        apply: "transit-trip-time-apply",
        label: "transit-trip-time-query")

    static let board = TimeChoiceIDs(
        now: "transit-board-time-now",
        depart: "transit-board-time-depart",
        arrive: "transit-board-time-arrive",
        date: "transit-board-time-date",
        plus: "transit-board-time-plus",
        apply: "transit-board-time-apply",
        label: "transit-board-time-query")

    static let detail = TimeChoiceIDs(
        now: "transit-detail-time-now",
        depart: "transit-detail-time-depart",
        arrive: "transit-detail-time-arrive",
        date: "transit-detail-time-date",
        plus: "transit-detail-time-plus",
        apply: "transit-detail-time-apply",
        label: "transit-detail-time-query")

    static let savedRoute = TimeChoiceIDs(
        now: "saved-route-time-now",
        depart: "saved-route-time-depart",
        arrive: "saved-route-time-arrive",
        date: "saved-route-time-date",
        plus: "saved-route-time-plus",
        apply: "saved-route-time-apply",
        label: "saved-route-time-query")
}

/// The state behind one time control. The three modes and the next five minute slot come from the
/// shared Kotlin `TimeChoice`, so Swift never re-implements the grid or the labels. Editing is local
/// until Apply: a date picker cannot send a request for every intermediate value.
///
/// [status] names the mode, the chosen clock time and the device zone it belongs to, then the time
/// the query was sent. A reader can therefore tell a fresh answer from the one before it.
final class TimeChoiceModel: ObservableObject {
    /// The planner numbers, mirrored from the Kotlin `TimeChoice` object so Swift reads no
    /// Kotlin constant through the framework.
    static let now: Int32 = 0
    static let depart: Int32 = 1
    static let arrive: Int32 = 2
    static let stepSeconds: TimeInterval = 900

    @Published private(set) var mode: Int32
    @Published private(set) var epochSec: Int64
    @Published var draft: Date
    @Published private(set) var editing: Int32?
    @Published private(set) var status: String
    @Published private(set) var queriedAt: Date?

    let ids: TimeChoiceIDs
    let zone: TimeZone

    private let onApply: (Int32, Int64) -> Void
    private let clock: () -> Date

    init(
        mode: Int32 = 0,
        epochSec: Int64 = 0,
        ids: TimeChoiceIDs = TimeChoiceIDs(),
        zone: TimeZone = .current,
        clock: @escaping () -> Date = Date.init,
        onApply: @escaping (Int32, Int64) -> Void
    ) {
        self.ids = ids
        self.zone = zone
        self.clock = clock
        self.onApply = onApply
        let nowSec = Int64(clock().timeIntervalSince1970)
        let normalisedMode = TimeChoice.shared.normalizedMode(mode: mode)
        let normalisedEpoch = TimeChoice.shared.normalizedEpoch(
            mode: normalisedMode, epochSec: epochSec, nowSec: nowSec)
        self.mode = normalisedMode
        self.epochSec = normalisedEpoch
        self.draft = Self.date(normalisedEpoch > 0 ? normalisedEpoch : Self.nextSlot(nowSec))
        self.status = Self.describe(normalisedMode, normalisedEpoch, zone: zone)
    }

    /// Mirrors a choice the surface restored from its store (a route reopened on a past query).
    /// It does not call the apply hook and does not claim a query time it never sent.
    func sync(mode: Int32, epochSec: Int64) {
        let next = TimeChoice.shared.normalizedMode(mode: mode)
        let normalised = TimeChoice.shared.normalizedEpoch(
            mode: next, epochSec: epochSec, nowSec: Int64(clock().timeIntervalSince1970))
        guard next != self.mode || normalised != self.epochSec else { return }
        self.mode = next
        self.epochSec = normalised
        if editing == nil {
            draft = Self.date(normalised > 0 ? normalised : Self.nextSlot(Int64(clock().timeIntervalSince1970)))
        }
        status = Self.describe(next, normalised, zone: zone)
        queriedAt = nil
    }

    /// Leave now sends at once; the two future modes open the date editor first.
    func choose(_ choice: Int32) {
        let next = TimeChoice.shared.normalizedMode(mode: choice)
        if next == Self.now {
            editing = nil
            mode = next
            epochSec = 0
            draft = Self.date(Self.nextSlot(Int64(clock().timeIntervalSince1970)))
            send()
            return
        }
        editing = next
        if mode == next && epochSec > 0 {
            draft = Self.date(epochSec)
        } else {
            draft = Self.date(Self.nextSlot(Int64(clock().timeIntervalSince1970)))
        }
    }

    func addFifteenMinutes() {
        draft = draft.addingTimeInterval(Self.stepSeconds)
    }

    func apply() {
        guard let editing else { return }
        let nowSec = Int64(clock().timeIntervalSince1970)
        let epoch = TimeChoice.shared.normalizedEpoch(
            mode: editing, epochSec: Int64(draft.timeIntervalSince1970.rounded(.down)), nowSec: nowSec)
        mode = editing
        epochSec = epoch
        draft = Self.date(epoch)
        self.editing = nil
        send()
    }

    private func send() {
        queriedAt = clock()
        status = Self.applied(mode, epochSec, zone: zone, at: queriedAt ?? clock())
        onApply(mode, epochSec)
    }

    private static func nextSlot(_ nowSec: Int64) -> Int64 {
        TimeChoice.shared.nextFiveMinuteSlot(nowSec: nowSec)
    }

    private static func date(_ epochSec: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(epochSec))
    }

    private static func describe(_ mode: Int32, _ epochSec: Int64, zone: TimeZone) -> String {
        let raw = TimeChoice.shared.label(
            mode: mode, epochSec: epochSec, zoneId: zone.identifier)
        let label = raw
            .replacingOccurrences(of: "Leave now", with: VelaL10n.text("place_leave_now"))
            .replacingOccurrences(of: "Depart at", with: VelaL10n.text("place_depart_at"))
            .replacingOccurrences(of: "Arrive by", with: VelaL10n.text("place_arrive_by"))
        guard mode != Self.now else { return label }
        return "\(label) · \(zone.identifier)"
    }

    private static func applied(_ mode: Int32, _ epochSec: Int64, zone: TimeZone, at: Date) -> String {
        "\(describe(mode, epochSec, zone: zone)) · \(VelaL10n.text("time_asked", clockText(at)))"
    }

    private static func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
