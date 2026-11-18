import WidgetKit

/// One Home Screen entry. The entry date drives the countdowns and the age labels; the snapshot is
/// the last payload the app wrote, never a fresh network answer.
struct VelaWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Reads the App Group on each timeline build. No network request is made here, and WidgetKit
/// timelines are best effort: when a timeline stops being rebuilt the widget keeps the same
/// snapshot and labels its age instead of pretending it is live.
struct VelaWidgetProvider: TimelineProvider {
    /// The departures widget gets one entry per minute so "in 4 min" stays true without waking
    /// the extension. The parking widget needs neither: its age text is relative and its distance
    /// carries the fix time.
    let liveMinutes: Int

    init(liveMinutes: Int = 0) {
        self.liveMinutes = liveMinutes
    }

    func placeholder(in context: Context) -> VelaWidgetEntry {
        VelaWidgetEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (VelaWidgetEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.preview : WidgetSnapshotStore.shared?.load()
        completion(VelaWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VelaWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.shared?.load()
        if liveMinutes > 0, snapshot?.board != nil {
            let entries = (0..<liveMinutes).map { minute in
                VelaWidgetEntry(
                    date: now.addingTimeInterval(TimeInterval(minute * 60)),
                    snapshot: snapshot)
            }
            completion(Timeline(
                entries: entries,
                policy: .after(now.addingTimeInterval(TimeInterval(liveMinutes * 60)))))
        } else {
            completion(Timeline(entries: [VelaWidgetEntry(date: now, snapshot: snapshot)], policy: .never))
        }
    }
}
