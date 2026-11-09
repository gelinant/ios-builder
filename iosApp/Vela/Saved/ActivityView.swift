import SwiftUI
import UIKit

/// One share item that also answers the activity sheet's subject (used by Mail and Messages).
/// The placeholder is the item itself, so the sheet's preview shows the same text or URL.
final class ShareItem: NSObject, UIActivityItemSource {
    private let item: Any
    private let subject: String?

    init(item: Any, subject: String?) {
        self.item = item
        self.subject = subject
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        item
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        item
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subject ?? ""
    }
}

/// The system share sheet for a place link, a route or an exported document. iOS only: Vela adds
/// no custom service, so every destination is the one the user already has installed.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    var subject: String? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let sources = items.map { ShareItem(item: $0, subject: subject) }
        return UIActivityViewController(activityItems: sources, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
