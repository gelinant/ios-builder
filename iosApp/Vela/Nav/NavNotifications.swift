import Foundation
import UserNotifications

/// The local notification that says guidance is still running once the app goes to the
/// background. iOS has no push server here and does not let a suspended process schedule new
/// work, so this is one notification posted at the transition, not a live update: the Live
/// Activity remains the continuous surface. The tap opens the app and re-attaches the camera to
/// the live drive, or lets the persisted drive resume when the process had been killed.
final class NavNotificationController: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NavNotificationController()
    private static let identifier = "vela.nav.background"

    private(set) var authorization = "unknown"
    private(set) var requested = 0
    private(set) var posted = 0
    private(set) var opens = 0
    private(set) var failed = false
    var onOpen: (() -> Void)?

    private var started = false

    /// Installs the delegate once, so a tap that launches the app is delivered. Reading the
    /// current authorization does not prompt.
    func start() {
        guard !started else { return }
        started = true
        UNUserNotificationCenter.current().delegate = self
        refreshAuthorization()
    }

    /// Asks only while the choice is undetermined. The caller decides when that context makes
    /// sense (the first drive, not the map at launch).
    func requestIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self else { return }
            if settings.authorizationStatus == .notDetermined {
                DispatchQueue.main.async {
                    self.requested += 1
                    UNUserNotificationCenter.current().requestAuthorization(
                        options: [.alert, .sound]
                    ) { _, _ in
                        self.refreshAuthorization()
                    }
                }
            } else {
                self.refreshAuthorization()
            }
        }
    }

    /// One notification when a live, unpaused drive enters the background. Posting is attempted
    /// even after a refusal: the system drops it, and the authorization field says why.
    func notifyGuidance(destination: String, remainingSeconds: Double, step: String, paused: Bool) {
        guard !paused else { return }
        let content = UNMutableNotificationContent()
        content.title = "Vela navigation"
        let place = destination.isEmpty ? "your destination" : destination
        let minutes = max(1, Int((remainingSeconds / 60).rounded()))
        if step.isEmpty {
            content.body = "Guiding to \(place), \(minutes) min left. Tap to return."
        } else {
            content.body = "Guiding to \(place), \(minutes) min left. Next: \(step) Tap to return."
        }
        content.sound = .default
        content.threadIdentifier = "vela.navigation"
        let request = UNNotificationRequest(
            identifier: Self.identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error == nil {
                    self.posted += 1
                } else {
                    self.failed = true
                }
            }
        }
    }

    /// Coming back to the foreground or ending the drive removes what this controller posted.
    func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }

    /// The lifecycle scenario's tap, through the same handler as the real delegate callback.
    func simulateTap() {
        opens += 1
        onOpen?()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == Self.identifier {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.opens += 1
                self.onOpen?()
            }
        }
        completionHandler()
    }

    /// A notification posted while the app is still in the foreground is only useful when the
    /// system has not yet completed the background transition. Show it as a banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let value: String
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                value = "granted"
            case .denied:
                value = "denied"
            case .notDetermined:
                value = "undetermined"
            @unknown default:
                value = "unknown"
            }
            DispatchQueue.main.async { self?.authorization = value }
        }
    }
}
