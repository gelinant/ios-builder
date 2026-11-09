import ActivityKit
import Foundation
import OSLog
import VelaCore

/// Owns the one local Live Activity for the current drive or walk. ActivityKit never owns location
/// or navigation execution; NavModel only publishes snapshots to this controller on the main thread.
final class NavActivityController {
    private typealias NavActivity = Activity<NavActivityAttributes>

    private enum Operation {
        case update(NavActivity, NavActivityAttributes.ContentState)
        case end(NavActivity, NavActivityAttributes.ContentState?, dismissalDate: Date?)
    }

    private let log = Logger(subsystem: OSLogLog.subsystem, category: "LiveActivity")
    private var reducer = NavActivityReducer()
    private var activity: NavActivity?
    private var started = false
    private var arrivalEnded = false
    private var staleTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    private var operations: [Operation] = []

    private(set) var activitiesEnabled = false
    private(set) var requestFailed = false
    private(set) var requestCount = 0
    private(set) var updateCount = 0
    private(set) var endCount = 0

    var hasActivity: Bool { activity != nil && !arrivalEnded }

    /// Adopts one fresh activity after relaunch, ends duplicates immediately and gives a fresh but
    /// unmatched activity until its stale deadline to receive navigation state again.
    func start(now: Date = Date()) {
        guard !started else { return }
        started = true
        activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let existing = NavActivity.activities.filter { $0.activityState == .active }
        let fresh = activitiesEnabled
            ? existing.filter { NavActivityStalePolicy.shouldAdopt($0.content.state, now: now) }
            : []
        activity = fresh.max {
            $0.content.state.updatedAt < $1.content.state.updatedAt
        }
        for candidate in existing where candidate.id != activity?.id {
            endCount += 1
            enqueue(.end(candidate, nil, dismissalDate: nil))
        }
        if let activity {
            scheduleStaleExpiration(of: activity)
        }
    }

    func publish(_ state: NavUiState, now: Date = Date()) {
        publish(NavActivityStateMapper.map(state, now: now), now: now)
    }

    func publish(_ input: NavActivityInput, now: Date = Date()) {
        publish(NavActivityStateMapper.map(input, now: now), now: now)
    }

    private func publish(_ sample: NavActivityStateMapper.Sample?, now: Date) {
        activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        guard let action = reducer.publish(sample, now: now) else { return }
        switch action {
        case .start(let sample):
            staleTask?.cancel()
            arrivalEnded = false
            if let activity {
                updateCount += 1
                enqueue(.update(activity, sample.content))
            } else {
                request(sample)
            }
        case .update(let sample):
            guard let activity else { return }
            updateCount += 1
            enqueue(.update(activity, sample.content))
        case .arrive(let sample, let dismissalDate):
            staleTask?.cancel()
            if activity == nil { request(sample) }
            guard let activity else { return }
            arrivalEnded = true
            endCount += 1
            enqueue(.end(activity, sample.content, dismissalDate: dismissalDate))
        case .end:
            staleTask?.cancel()
            arrivalEnded = false
            guard let ending = activity else { return }
            activity = nil
            endCount += 1
            enqueue(.end(ending, nil, dismissalDate: nil))
        }
    }

    private func request(_ sample: NavActivityStateMapper.Sample) {
        guard activitiesEnabled else { return }
        let attributes = NavActivityAttributes(destinationName: sample.destinationName)
        do {
            let requested = try NavActivity.request(
                attributes: attributes,
                content: ActivityContent(state: sample.content, staleDate: nil),
                pushType: nil)
            activity = requested
            requestFailed = false
            requestCount += 1
        } catch {
            requestFailed = true
            log.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleStaleExpiration(of adopted: NavActivity) {
        staleTask?.cancel()
        let deadline = NavActivityStalePolicy.expiration(of: adopted.content.state)
        let delay = max(0, deadline.timeIntervalSinceNow)
        staleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.reducer.phase == .idle,
                  self.activity?.id == adopted.id else { return }
            self.activity = nil
            self.endCount += 1
            self.enqueue(.end(adopted, nil, dismissalDate: nil))
        }
    }

    /// Serializes ActivityKit calls and coalesces only consecutive updates for the same activity.
    /// End operations stay in FIFO order, so a late update cannot resurrect an ended presentation.
    private func enqueue(_ operation: Operation) {
        if case .update(let newActivity, _) = operation,
           let last = operations.last,
           case .update(let oldActivity, _) = last,
           newActivity.id == oldActivity.id {
            operations[operations.count - 1] = operation
        } else {
            operations.append(operation)
        }
        guard drainTask == nil else { return }
        drainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !self.operations.isEmpty {
                let next = self.operations.removeFirst()
                switch next {
                case .update(let activity, let state):
                    await activity.update(ActivityContent(state: state, staleDate: nil))
                case .end(let activity, let state, let dismissalDate):
                    let content = state.map { ActivityContent(state: $0, staleDate: nil) }
                    if let dismissalDate {
                        await activity.end(content, dismissalPolicy: .after(dismissalDate))
                    } else {
                        await activity.end(content, dismissalPolicy: .immediate)
                    }
                }
            }
            self.drainTask = nil
        }
    }
}
