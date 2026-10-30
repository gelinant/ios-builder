import SwiftUI

/// The detents a map sheet can rest on, as fractions of the window height. The values come from
/// `Design.Sheet`, so a screen never carries its own sheet height.
enum SheetDetent: String, CaseIterable, Hashable {
    case peek
    case compact
    case half
    case tall
    case expanded
    case full

    var fraction: CGFloat {
        switch self {
        case .peek: return Design.Sheet.peek
        case .compact: return Design.Sheet.compact
        case .half: return Design.Sheet.half
        case .tall: return Design.Sheet.tall
        case .expanded: return Design.Sheet.expanded
        case .full: return Design.Sheet.full
        }
    }

    /// The detent as the UI scenarios print it: `detent=0.42`.
    var debugValue: String {
        String(format: "%.2f", fraction)
    }

    /// The detent one step taller in an allowed list, clamped at the last one.
    func taller(in detents: [SheetDetent]) -> SheetDetent {
        guard let index = detents.firstIndex(of: self) else { return detents.last ?? self }
        return detents[min(index + 1, detents.count - 1)]
    }

    /// The detent one step shorter in an allowed list, clamped at the first one.
    func shorter(in detents: [SheetDetent]) -> SheetDetent {
        guard let index = detents.firstIndex(of: self) else { return detents.first ?? self }
        return detents[max(index - 1, 0)]
    }
}

/// The detent the surrounding `SheetSurface` currently rests on. Wave 3 sheets read it to adapt
/// their own header without owning the host binding.
private struct SheetDetentEnvironmentKey: EnvironmentKey {
    static let defaultValue: SheetDetent = .compact
}

extension EnvironmentValues {
    var sheetDetent: SheetDetent {
        get { self[SheetDetentEnvironmentKey.self] }
        set { self[SheetDetentEnvironmentKey.self] = newValue }
    }
}

/// Reports the laid-out height of a sheet, so the map moves its bottom inset to the exact height
/// the surface occupies instead of guessing from a fraction.
struct SheetHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The single sheet surface used over the map (DESIGN.md 3.7 and 4): full width, 20 pt top
/// corners, one high shadow, a 32 x 4 grabber and a stable content order. The host constrains the
/// height to a `SheetDetent`; this view only draws the surface and owns the grabber.
///
/// The drag gesture lives on the grabber, never on the content, so an inner `ScrollView` keeps
/// its own scroll. A tap on the grabber also moves one detent, which gives VoiceOver and the UI
/// scenarios a path that does not need a swipe.
struct SheetSurface<Content: View>: View {
    @Binding var detent: SheetDetent
    /// The detents this sheet is allowed to rest on, shortest first.
    let detents: [SheetDetent]
    /// A sheet whose content draws its own grabber (the place sheet until wave 3) hides the
    /// capsule but keeps an invisible drag strip over it.
    var showsGrabber = true
    var elevation: Design.Elevation = .level3
    /// Called with the measured height whenever the surface changes detent or layout.
    var onHeightChange: ((CGFloat) -> Void)?
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(detent: Binding<SheetDetent>, detents: [SheetDetent], showsGrabber: Bool = true,
         elevation: Design.Elevation = .level3,
         onHeightChange: ((CGFloat) -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        _detent = detent
        self.detents = detents
        self.showsGrabber = showsGrabber
        self.elevation = elevation
        self.onHeightChange = onHeightChange
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsGrabber {
                grabber
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .environment(\.sheetDetent, detent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.surface)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: Design.Sheet.cornerRadius,
            topTrailingRadius: Design.Sheet.cornerRadius))
        .shadow(color: elevation.color, radius: elevation.radius, y: -elevation.y)
        .overlay(alignment: .top) {
            if !showsGrabber {
                dragStrip
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SheetHeightPreferenceKey.self, value: proxy.size.height)
            })
        .onPreferenceChange(SheetHeightPreferenceKey.self) { height in
            onHeightChange?(height)
        }
        .accessibilityElement(children: .contain)
    }

    /// The standard 32 x 4 grabber: 8 pt from the top edge, 44 pt to the touch.
    private var grabber: some View {
        Button {
            advance()
        } label: {
            Capsule()
                .fill(Color(uiColor: .tertiaryLabel))
                .frame(width: Design.Chrome.grabberWidth, height: Design.Chrome.grabberHeight)
                .padding(.top, Design.Padding.sheetTop)
                .frame(maxWidth: .infinity)
                .frame(height: Design.Padding.sheetTop + Design.Chrome.grabberHeight + Design.Padding.sheetTop)
                .contentShape(Rectangle().inset(by: -Design.Spacing.m))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(dragGesture)
        .accessibilityLabel(detent == detents.last
            ? VelaL10n.text("settings_collapse") : VelaL10n.text("settings_expand"))
        .accessibilityValue(detent.debugValue)
        .accessibilityIdentifier("sheet-grabber")
    }

    /// The invisible drag strip for a sheet that draws its own capsule (the place sheet). It stays
    /// 44 pt tall and 140 pt wide, clear of the close button at the trailing edge.
    private var dragStrip: some View {
        Button {
            advance()
        } label: {
            Color.clear
                .frame(width: 140, height: Design.Size.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(dragGesture)
        .accessibilityLabel(detent == detents.last
            ? VelaL10n.text("settings_collapse") : VelaL10n.text("settings_expand"))
        .accessibilityValue(detent.debugValue)
        .accessibilityIdentifier("sheet-grabber")
    }

    /// A vertical drag of more than 40 pt moves one detent, in the direction of the drag.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: Design.Size.hitTarget)
            .onEnded { value in
                let height = value.translation.height
                guard abs(height) > Design.Size.hitTarget else { return }
                let target = height < 0 ? detent.taller(in: detents) : detent.shorter(in: detents)
                setDetent(target)
            }
    }

    /// The tap path: the next detent, wrapping back to the shortest from the tallest.
    private func advance() {
        let target = detent == detents.last ? (detents.first ?? detent) : detent.taller(in: detents)
        setDetent(target)
    }

    private func setDetent(_ target: SheetDetent) {
        guard target != detent else { return }
        withAnimation(Design.Motion.animation(Design.Motion.sheetSpring, reduceMotion: reduceMotion)) {
            detent = target
        }
    }
}
