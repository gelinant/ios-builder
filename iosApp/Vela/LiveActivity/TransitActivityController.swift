import ActivityKit
import Foundation
import OSLog
import VelaCore

/// Owns the local Live Activity for one transit session. ActivityKit only displays TransitSession
/// snapshots; CoreLocationPipeline supplies the fixes and the only legitimate background execution.
final class TransitActivityController {
    private typealias TransitActivity = Activity<TransitActivityAttributes>

    private enum Operation {
        case update(TransitActivity, TransitActivityAttributes.ContentState)
        case end(TransitActivity, TransitActivityAttributes.ContentState?, dismissalDate: Date?)
    }

    private let log = Logger(subsystem: OSLogLog.subsystem, category: "LiveActivity")
    private var reducer = TransitActivityReducer()
    private var activity: TransitActivity?
    private var activitySessionId: Int64?
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

    /// Adopts at most one fresh activity and removes duplicates or stale activities left by an
    /// earlier process. An adopted activity still expires if no transit session claims it.
    func start(now: Date = Date()) {
        guard !started else { return }
        started = true
        activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let existing = TransitActivity.activities.filter { $0.activityState == .active }
        let fresh = activitiesEnabled
            ? existing.filter { TransitActivityStalePolicy.shouldAdopt($0.content.state, now: now) }
            : []
        activity = fresh.max {
            $0.content.state.updatedAt < $1.content.state.updatedAt
        }
        activitySessionId = activity?.content.state.sessionId
        for candidate in existing where candidate.id != activity?.id {
            endCount += 1
            enqueue(.end(candidate, nil, dismissalDate: nil))
        }
        if let activity {
            scheduleStaleExpiration(of: activity)
        }
    }

    func publish(_ state: TransitState, now: Date = Date()) {
        publish(TransitActivityInput(state), now: now)
    }

    func publish(_ input: TransitActivityInput, now: Date = Date()) {
        activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let sample = TransitActivityStateMapper.map(input, now: now)
        guard let action = reducer.publish(sample, now: now) else { return }
        switch action {
        case .start(let sample):
            staleTask?.cancel()
            arrivalEnded = false
            if let activity, activitySessionId == sample.sessionId {
                updateCount += 1
                enqueue(.update(activity, sample.content))
            } else {
                if let ending = activity {
                    endCount += 1
                    enqueue(.end(ending, nil, dismissalDate: nil))
                    activity = nil
                    activitySessionId = nil
                }
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
            activitySessionId = nil
            endCount += 1
            enqueue(.end(ending, nil, dismissalDate: nil))
        }
    }

    private func request(_ sample: TransitActivityStateMapper.Sample) {
        guard activitiesEnabled else { return }
        let attributes = TransitActivityAttributes(destinationName: sample.destinationName)
        do {
            let requested = try TransitActivity.request(
                attributes: attributes,
                content: ActivityContent(state: sample.content, staleDate: nil),
                pushType: nil)
            activity = requested
            activitySessionId = sample.sessionId
            requestFailed = false
            requestCount += 1
        } catch {
            requestFailed = true
            log.error("Transit Live Activity request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleStaleExpiration(of adopted: TransitActivity) {
        staleTask?.cancel()
        let deadline = TransitActivityStalePolicy.expiration(of: adopted.content.state)
        let delay = max(0, deadline.timeIntervalSinceNow)
        staleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.reducer.phase == .idle,
                  self.activity?.id == adopted.id else { return }
            self.activity = nil
            self.activitySessionId = nil
            self.endCount += 1
            self.enqueue(.end(adopted, nil, dismissalDate: nil))
        }
    }

    /// ActivityKit calls are serialized. Only consecutive updates coalesce; End remains ordered so
    /// an old update cannot resurrect a presentation after the user ends transit guidance.
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
