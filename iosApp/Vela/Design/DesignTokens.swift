import SwiftUI
import UIKit

/// The Vela iOS design system.
///
/// The layout and interaction patterns follow Google Maps: the map is the hero, one primary
/// surface at a time, and sheets grow through detents. Colors, type, iconography and map
/// styles stay Vela's own, and no Google asset is used. `docs/ios/DESIGN.md` holds the rules
/// and the audit lives in `docs/ios/DESIGN-AUDIT.md`.
///
/// No screen reads these tokens yet (wave 0 of the migration). Wave 1 moves one screen group
/// at a time, so a value changes here once instead of drifting per file.
///
/// Rules of thumb:
/// - spacing uses the 4 pt grid, never a literal;
/// - a tappable element is at least 44 by 44 pt;
/// - a sheet is full width, has 20 pt top corners and exposes at most three detents;
/// - every font is a semantic style, so Dynamic Type scales it.
enum Design {

    /// The 4 pt spacing grid. Use these names instead of literals.
    enum Spacing {
        /// Hairline gap inside a label (icon and text).
        static let xxs: CGFloat = 2
        /// Tight pair (rating number and star).
        static let xs: CGFloat = 4
        /// Icon and text, adjacent chips, stacked map buttons.
        static let s: CGFloat = 8
        /// Rows, small blocks.
        static let m: CGFloat = 12
        /// Page margin, sheet content inset, standard block gap.
        static let l: CGFloat = 16
        /// Gap between the sheet header and its first section.
        static let xl: CGFloat = 20
        /// Gap between two sections.
        static let xxl: CGFloat = 24
        /// Gap above a new chapter (About, Settings group).
        static let xxxl: CGFloat = 32
        /// Empty state vertical breathing room.
        static let huge: CGFloat = 40
    }

    /// Corner radii, from the smallest badge to a capsule.
    enum Radius {
        /// Attribution chip, lane badge.
        static let xs: CGFloat = 4
        /// Thumbnail, street view preview, review photo.
        static let s: CGFloat = 8
        /// Card inside a sheet, category tile, related place card.
        static let m: CGFloat = 12
        /// Legacy floating card. Kept for the screens wave 1 has not migrated yet.
        static let l: CGFloat = 16
        /// Sheet top corners, large surface.
        static let xl: CGFloat = 20
        /// A value large enough that SwiftUI clamps to a capsule.
        static let pill: CGFloat = 999
    }

    /// Content insets. Horizontal values are symmetric and stay correct in RTL because layout
    /// uses leading and trailing, never left and right.
    enum Padding {
        /// Horizontal page margin on the map and inside a sheet.
        static let page: CGFloat = 16
        /// Content inset of a sheet below its grabber.
        static let sheet: CGFloat = 16
        /// Gap between the grabber and the title.
        static let sheetTop: CGFloat = 8
        /// Last content row above the home indicator; the system adds the safe area.
        static let sheetBottom: CGFloat = 24
        /// List row insets. A row is 44 pt minimum, 56 pt for two lines.
        static let rowH: CGFloat = 16
        static let rowV: CGFloat = 12
        /// Filled and outlined button insets.
        static let buttonH: CGFloat = 20
        static let buttonV: CGFloat = 12
        /// Chip insets. The chip is 40 pt tall visually, 44 pt to the touch.
        static let chipH: CGFloat = 12
        static let chipV: CGFloat = 8
    }

    /// Fixed sizes of reusable controls.
    enum Size {
        /// Minimum touch target on every platform. Never go below it.
        static let hitTarget: CGFloat = 44
        /// Map chrome icon.
        static let icon: CGFloat = 20
        /// Inline icon paired with a caption.
        static let iconSmall: CGFloat = 16
        /// Review author avatar.
        static let avatar: CGFloat = 32
        /// Result row thumbnail.
        static let resultThumb: CGFloat = 84
        /// Review photo thumbnail.
        static let reviewThumb: CGFloat = 104
        /// Place sheet photo header.
        static let photoHeader: CGFloat = 152
    }

    /// Sizes and insets of the floating map chrome. These are what make the map stay the hero:
    /// the chrome floats over it and never reserves a bar.
    enum Chrome {
        /// The search pill. 56 pt is tall enough for a 44 pt field and reads as the primary
        /// control without becoming a navigation bar.
        static let searchHeight: CGFloat = 56
        /// Horizontal page margin of the search row and the chip row.
        static let sideInset: CGFloat = 16
        /// Distance from the safe area top to the search row.
        static let topInset: CGFloat = 8
        /// Gap between the search pill and the round button beside it.
        static let searchGap: CGFloat = 8
        /// Round map button (locate, layers, more). Visual size equals the touch size.
        static let actionSize: CGFloat = 48
        /// Vertical and horizontal gap between two round map buttons.
        static let actionSpacing: CGFloat = 8
        /// Distance from the bottom safe area to the attribution row.
        static let bottomInset: CGFloat = 8
        /// Category chip. 40 pt visual, 44 pt touch through contentShape.
        static let chipHeight: CGFloat = 40
        /// Horizontal gap between chips.
        static let chipSpacing: CGFloat = 8
        /// Sheet grabber, the only part that signals draggability.
        static let grabberWidth: CGFloat = 32
        static let grabberHeight: CGFloat = 4
    }

    /// Sheet detents as fractions of the window height, plus the surface geometry shared by
    /// every custom sheet. Native `.presentationDetents` uses the same values for system sheets.
    enum Sheet {
        /// A place or result peek: the grabber, the title and one action row.
        static let peek: CGFloat = 0.18
        /// Default results and place detent: half the map stays visible.
        static let compact: CGFloat = 0.42
        /// Legacy half screen, kept while wave 1 migrates the map host.
        static let half: CGFloat = 0.5
        /// Route steps and transit detail.
        static let tall: CGFloat = 0.62
        /// Expanded route chooser. Leaves the status bar and the search row visible.
        static let expanded: CGFloat = 0.85
        /// Full height for a modal that is no longer a map companion (About, Settings).
        static let full: CGFloat = 1.0
        /// Top corners of the sheet surface.
        static let cornerRadius: CGFloat = 20
        /// A sheet is edge to edge. Zero is a token: the surface must not look like a card
        /// floating in the map, which was the old look.
        static let sideInset: CGFloat = 0
    }

    /// Elevation levels. Kept subtle: the map must remain lighter than the chrome.
    struct Elevation {
        let color: Color
        let radius: CGFloat
        let y: CGFloat

        /// Chips and inline cards. Barely visible on purpose.
        static let level1 = Elevation(color: .black.opacity(0.08), radius: 2, y: 1)
        /// Search pill and round map buttons.
        static let level2 = Elevation(color: .black.opacity(0.12), radius: 8, y: 2)
        /// Sheets and panels over the map.
        static let level3 = Elevation(color: .black.opacity(0.16), radius: 16, y: 4)
        /// Only for a modal alert or a sheet dragged to full height.
        static let level4 = Elevation(color: .black.opacity(0.20), radius: 24, y: 8)
    }

    /// Motion durations in seconds and the curves they belong to. Fast and calm: nothing on
    /// the map takes longer than the camera, and no bounce overshoots a sheet detent.
    enum Motion {
        /// Press feedback on a chip or a pill.
        static let press: Double = 0.10
        /// A control appears or leaves (clear button, selection ring).
        static let quick: Double = 0.12
        /// Standard state change (tab, filter, chip selection).
        static let base: Double = 0.20
        /// Sheet detent and route chooser expansion.
        static let sheet: Double = 0.32
        /// Attention: a new route offer, an error card.
        static let emphasis: Double = 0.42
        /// Map camera animation. Owned by MapLibre, not by SwiftUI.
        static let camera: Double = 0.45

        /// Content entering: decelerate, no overshoot.
        static let enter = Animation.easeOut(duration: base)
        /// Content leaving: accelerate out of the way.
        static let exit = Animation.easeIn(duration: quick)
        /// State change in place.
        static let move = Animation.easeInOut(duration: base)
        /// Sheet detent. Damping 0.86 keeps a hint of physics without the bounce.
        static let sheetSpring = Animation.spring(response: 0.34, dampingFraction: 0.86)
        /// Short snap (selection, chip strip settling).
        static let snap = Animation.spring(response: 0.28, dampingFraction: 0.9)
        /// Reduce Motion fallback: a crossfade, never a slide.
        static let fade = Animation.easeInOut(duration: 0.12)

        /// Returns nil under Reduce Motion so the caller can change state without animating.
        static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }
    }

    /// Text roles. Every role is a semantic SwiftUI style, so Dynamic Type and Bold Text
    /// apply without extra work. Fixed point sizes are forbidden for UI text.
    enum Typography {
        /// About and empty state headline.
        static let display = Font.title.weight(.semibold)
        /// Place name, sheet title: two lines maximum.
        static let sheetTitle = Font.title2.weight(.semibold)
        /// Section title inside a sheet (Reviews, About, Photos).
        static let section = Font.title3.weight(.semibold)
        /// Result name, review author, settings row.
        static let rowTitle = Font.body.weight(.semibold)
        /// Long form text and place description.
        static let body = Font.body
        /// Address, hours, metadata, supporting sentence.
        static let detail = Font.subheadline
        /// Tertiary line, status, count.
        static let caption = Font.footnote
        /// Debug and the smallest badge. Never a control label.
        static let micro = Font.caption2
        /// A count or a short state inside a pill.
        static let badge = Font.caption2.weight(.semibold)
        /// Filled and outlined button label.
        static let button = Font.subheadline.weight(.semibold)
        /// Tab row and chip label.
        static let tab = Font.subheadline.weight(.semibold)
        /// Rating number and review count, kept tabular.
        static let rating = Font.subheadline.weight(.semibold).monospacedDigit()
        /// Sheet header title in a compact form (settings, about).
        static let nav = Font.headline
        /// Travel time, distance and arrival, tabular so they do not dance.
        static let metric = Font.title3.weight(.semibold).monospacedDigit()
    }

    /// Semantic colors. Only the accent is Vela's brand; the rest are system roles so dark
    /// mode, Increase Contrast and Reduce Transparency keep working.
    enum Colors {
        /// Vela teal from the asset catalog. Use for selection, icons and text at 3:1 or
        /// better, never for a white label on a light background.
        static let accent = Color.accentColor

        /// Fill for a primary button. Darker than the accent in light mode because white on
        /// the brand teal is only 3.8:1; this pair reaches 7.7:1. In dark mode it lightens and
        /// takes a black label.
        static let accentFill = dynamic(
            light: UIColor(red: 11 / 255, green: 93 / 255, blue: 85 / 255, alpha: 1),
            dark: UIColor(red: 79 / 255, green: 179 / 255, blue: 166 / 255, alpha: 1))

        /// Label color on top of `accentFill`.
        static let onAccent = dynamic(light: .white, dark: .black)

        /// Selected route-mode chip. It uses `accentFill`, not the brand teal: white on `#149387`
        /// is only 3.78:1, while this pair reaches 7.75:1 in light and 8.33:1 in dark.
        static let routeChipFill = accentFill
        /// Label on a selected route-mode chip.
        static let routeChipLabel = onAccent

        /// Sheet and panel background. Opaque, not a material: secondary text and dividers
        /// vanished over material on iOS 26.
        static let surface = Color(uiColor: .systemBackground)
        /// Thumbnail background and inline card.
        static let surfaceRaised = Color(uiColor: .secondarySystemBackground)
        /// Input and grouped row background.
        static let surfaceSunken = Color(uiColor: .tertiarySystemBackground)
        /// Hairline divider.
        static let separator = Color(uiColor: .separator)
        /// Primary text.
        static let label = Color(uiColor: .label)
        /// Metadata text. Must reach 4.5:1 on `surface`.
        static let secondaryLabel = Color(uiColor: .secondaryLabel)
        /// Behind a modal that must not be touched.
        static let scrim = Color.black.opacity(0.28)

        /// Open status and a successful install.
        static let success = Color(uiColor: .systemGreen)
        /// Closed permanently, failed download.
        static let danger = Color(uiColor: .systemRed)
        /// Closing soon, a degraded layer.
        static let warning = Color(uiColor: .systemOrange)

        /// Star glyphs. Decorative only: the numeric rating always sits beside them, so the
        /// amber never has to carry the meaning alone at 2:1.
        static let star = Color(red: 242 / 255, green: 166 / 255, blue: 90 / 255)

        /// Builds a color that follows the system appearance.
        private static func dynamic(light: UIColor, dark: UIColor) -> Color {
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            })
        }
    }

    /// The exact sRGB components behind the contrast claims above. Kept as numbers as well as
    /// colors so a unit test can compute the ratio instead of trusting a comment.
    enum Palette {
        /// Vela teal, the asset catalog's `#149387`.
        static let accent = (red: 20.0 / 255, green: 147.0 / 255, blue: 135.0 / 255)
        /// Light-mode primary fill, `#0B5D55`.
        static let accentFillLight = (red: 11.0 / 255, green: 93.0 / 255, blue: 85.0 / 255)
        /// Dark-mode primary fill, `#4FB3A6`.
        static let accentFillDark = (red: 79.0 / 255, green: 179.0 / 255, blue: 166.0 / 255)
        static let white = (red: 1.0, green: 1.0, blue: 1.0)
        static let black = (red: 0.0, green: 0.0, blue: 0.0)
        static let star = (red: 242.0 / 255, green: 166.0 / 255, blue: 90.0 / 255)
    }

    /// WCAG 2.1 relative luminance and contrast ratio. Text needs 4.5:1, large text and interface
    /// components 3:1. The values are computed, never copied from a design comment.
    enum Contrast {
        static func relativeLuminance(_ color: (red: Double, green: Double, blue: Double)) -> Double {
            func channel(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(color.red) + 0.7152 * channel(color.green)
                + 0.0722 * channel(color.blue)
        }

        static func ratio(_ first: (red: Double, green: Double, blue: Double),
                          _ second: (red: Double, green: Double, blue: Double)) -> Double {
            let a = relativeLuminance(first)
            let b = relativeLuminance(second)
            let lighter = max(a, b)
            let darker = min(a, b)
            return (lighter + 0.05) / (darker + 0.05)
        }
    }
}
