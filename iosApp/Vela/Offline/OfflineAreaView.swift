import SwiftUI
import VelaCore

/// The framed-area picker (OFF-AREA): the map dimmed outside a fixed frame, a hint above it and a
/// card below with the live estimate, what the download includes and the confirmation. The frame's
/// insets match the Kotlin estimator (`OfflineArea`), so the rectangle the user sees is the one the
/// store plans for. Pan and pinch reach the map; only the card takes taps.
struct OfflineAreaOverlay: View {
    @ObservedObject var model: OfflineModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let left = 0.07
    private let right = 0.07
    private let top = 0.18
    private let bottom = 0.34

    var body: some View {
        GeometryReader { geometry in
            let frame = CGRect(
                x: geometry.size.width * left,
                y: geometry.size.height * top,
                width: geometry.size.width * (1 - left - right),
                height: geometry.size.height * (1 - top - bottom))
            ZStack(alignment: .top) {
                AreaScrim(frame: frame, size: geometry.size, corner: Design.Radius.m)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Area frame")
                    .accessibilityIdentifier("offline-area-frame")
                Text("Pan and pinch to choose the area to save")
                    .font(Design.Typography.tab)
                    .foregroundStyle(Design.Colors.label)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Design.Padding.sheet)
                    .padding(.vertical, Design.Spacing.s)
                    .background(Design.Colors.surface, in: RoundedRectangle(cornerRadius: Design.Radius.l))
                    .shadow(
                        color: Design.Elevation.level2.color,
                        radius: Design.Elevation.level2.radius,
                        y: Design.Elevation.level2.y)
                    .padding(.top, Design.Chrome.topInset)
                    .accessibilityIdentifier("offline-area-hint")
                VStack {
                    Spacer()
                    card
                        .padding(.horizontal, Design.Spacing.m)
                        .padding(.bottom, Design.Spacing.m)
                }
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.s) {
                Text("Download this area")
                    .font(Design.Typography.sheetTitle)
                Spacer(minLength: Design.Spacing.s)
                Button {
                    withAnimation(cardAnimation) { model.cancelAreaPick() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Design.Typography.section)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Cancel area picker")
                .accessibilityIdentifier("area-close")
            }

            estimate

            if let plan = model.areaPlan {
                Text(plan.regionName.isEmpty
                     ? "No offline map covers this frame"
                     : "Whole region: \(plan.regionName)")
                    .font(Design.Typography.detail)
                    .foregroundStyle(Design.Colors.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("area-region")
                Text("Free space: \(Self.bytes(plan.freeBytes))")
                    .font(Design.Typography.detail)
                    .foregroundStyle(Design.Colors.secondaryLabel)
                    .accessibilityIdentifier("area-free-space")
                if plan.reasonKey == "no_space" {
                    Text("Not enough free space: \(Self.megabytes(plan.neededBytes)) needed, \(Self.bytes(plan.freeBytes)) available.")
                        .font(Design.Typography.detail)
                        .foregroundStyle(Design.Colors.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("area-refusal")
                } else if plan.reasonKey == "installed" {
                    Text("Already downloaded. Turn on cameras or addresses to refresh their data.")
                        .font(Design.Typography.detail)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("area-installed")
                }
            }

            VStack(alignment: .leading, spacing: Design.Spacing.s) {
                Toggle(isOn: $model.areaPlaces) {
                    VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                        Text("Places")
                            .font(Design.Typography.body)
                        Text("Place pack and place search data")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("area-include-places")
                Toggle(isOn: $model.areaCameras) {
                    VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                        Text("Cameras")
                            .font(Design.Typography.body)
                        Text("Speed and plate cameras from OpenStreetMap")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("area-include-cameras")
                Toggle(isOn: $model.areaAddresses) {
                    VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                        Text("Addresses")
                            .font(Design.Typography.body)
                        Text("Street addresses around the frame, for offline address search")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("area-include-addresses")
            }

            Text("Includes the map, places and addresses. It does not include offline routing.")
                .font(Design.Typography.detail)
                .foregroundStyle(Design.Colors.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("area-routing-note")

            HStack(spacing: Design.Spacing.s) {
                Spacer(minLength: 0)
                Button("Cancel") {
                    withAnimation(cardAnimation) { model.cancelAreaPick() }
                }
                .font(Design.Typography.button)
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("area-cancel")
                Button {
                    withAnimation(cardAnimation) { model.confirmArea() }
                } label: {
                    Text("Download")
                        .font(Design.Typography.button)
                        .foregroundStyle(Design.Colors.onAccent)
                        .padding(.horizontal, Design.Padding.buttonH)
                        .frame(minHeight: Design.Size.hitTarget)
                        .background(Design.Colors.accentFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.areaPlan?.canDownload != true)
                .opacity(model.areaPlan?.canDownload == true ? 1 : 0.4)
                .accessibilityIdentifier("area-download")
            }

            #if DEBUG
            Text(model.areaDebugLine)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("area-debug")
            #endif
        }
        .padding(Design.Padding.sheet)
        .background(
            Design.Colors.surface,
            in: RoundedRectangle(cornerRadius: Design.Radius.xl))
        .shadow(
            color: Design.Elevation.level3.color,
            radius: Design.Elevation.level3.radius,
            y: Design.Elevation.level3.y)
        .animation(cardAnimation, value: model.areaPlan?.reasonKey)
    }

    @ViewBuilder private var estimate: some View {
        if model.areaEstimating || model.areaPlan == nil {
            Text("Estimating...")
                .font(Design.Typography.metric)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("area-estimate")
        } else if let plan = model.areaPlan {
            if plan.reasonKey == "no_region" {
                Text("No offline map covers this frame")
                    .font(Design.Typography.metric)
                    .foregroundStyle(Design.Colors.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("area-estimate")
            } else if plan.reasonKey == "installed" {
                Text("Already downloaded")
                    .font(Design.Typography.metric)
                    .foregroundStyle(Design.Colors.secondaryLabel)
                    .accessibilityIdentifier("area-estimate")
            } else {
                Text("Estimated download: \(Self.megabytes(plan.neededBytes))")
                    .font(Design.Typography.metric)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("area-estimate")
            }
        }
    }

    /// Sheet motion: 320 ms spring, or a 120 ms crossfade under Reduce Motion.
    private var cardAnimation: Animation {
        reduceMotion ? Design.Motion.fade : Design.Motion.sheetSpring
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func megabytes(_ bytes: Int64) -> String {
        let mb = max(1, Int((bytes + 1024 * 1024 - 1) / (1024 * 1024)))
        if mb >= 1024 { return String(format: "%.1f GB", Double(mb) / 1024) }
        return "\(mb) MB"
    }
}

/// The dimmed outside plus the bright frame border. One path with the even-odd rule so the hole is
/// a hole; the map stays visible and reachable through it.
private struct AreaScrim: View {
    let frame: CGRect
    let size: CGSize
    let corner: CGFloat

    var body: some View {
        ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRoundedRect(in: frame, cornerSize: CGSize(width: corner, height: corner))
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            Path { path in
                path.addRoundedRect(in: frame, cornerSize: CGSize(width: corner, height: corner))
            }
            .stroke(Design.Colors.accent, lineWidth: 3)
        }
    }
}

/// The compact progress card over the map after confirmation. It keeps reading the store's state,
/// so closing the sheet, reopening it or waiting on the map all show the same download.
struct OfflineAreaProgressCard: View {
    @ObservedObject var model: OfflineModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.s) {
                Text(title)
                    .font(Design.Typography.sheetTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Design.Spacing.s)
                Button {
                    withAnimation(cardAnimation) { model.hideAreaReport() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Design.Typography.section)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Hide area download")
                .accessibilityIdentifier("area-hide")
            }
            Text(detail)
                .font(Design.Typography.detail)
                .foregroundStyle(Design.Colors.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("area-progress-stage")
            if model.areaDownloading {
                ProgressView(value: Double(model.progress), total: 100) {
                    Text("\(model.progress)%")
                        .font(Design.Typography.rating)
                }
                .tint(Design.Colors.accent)
                .accessibilityIdentifier("area-progress")
                HStack(spacing: Design.Spacing.s) {
                    Spacer(minLength: 0)
                    Button("Cancel", role: .cancel) {
                        withAnimation(cardAnimation) { model.cancel() }
                    }
                    .font(Design.Typography.button)
                    .frame(minHeight: Design.Size.hitTarget)
                    .accessibilityIdentifier("area-cancel-download")
                }
            }
            if !model.areaDownloading && (model.areaCameras || model.areaAddresses) {
                Text("Camera data: \(rows(model.areaCameraRows)). Address data: \(rows(model.areaAddressRows)).")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("area-data")
            }
            #if DEBUG
            Text(model.areaDebugLine)
                .font(Design.Typography.micro.monospaced())
                .foregroundStyle(Design.Colors.secondaryLabel)
                .accessibilityIdentifier("area-progress-debug")
            #endif
        }
        .padding(Design.Padding.sheet)
        .background(
            Design.Colors.surface,
            in: RoundedRectangle(cornerRadius: Design.Radius.xl))
        .shadow(
            color: Design.Elevation.level3.color,
            radius: Design.Elevation.level3.radius,
            y: Design.Elevation.level3.y)
        .animation(cardAnimation, value: model.areaDownloading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("area-progress-card")
    }

    /// Sheet motion: 320 ms spring, or a 120 ms crossfade under Reduce Motion.
    private var cardAnimation: Animation {
        reduceMotion ? Design.Motion.fade : Design.Motion.sheetSpring
    }

    private var title: String {
        if model.errorKey == "no_space" { return "Not enough free space" }
        if model.errorKey == "no_region" { return "No offline map covers this area" }
        if model.errorKey == "download_failed" { return "Area download failed" }
        if model.areaDownloading { return "Downloading area" }
        if model.areaReady { return "Area ready" }
        return "Area download"
    }

    private var detail: String {
        if let error = model.errorKey {
            if error == "no_space" || error == "no_region" { return "Nothing was installed." }
            // A failed piece is not a successful area: say how far it got and that the rest is kept.
            return "\(model.completedPieces) of \(model.pieceCount) pieces are complete and will be reused."
        }
        if model.areaDownloading {
            return "\(stageLabel) \(model.completedPieces) of \(model.pieceCount) pieces"
        }
        return "The map is saved. Offline routing is not included."
    }

    private var stageLabel: String {
        switch model.areaDataStage {
        case "cameras": return "Camera data"
        case "addresses": return "Address data"
        default: break
        }
        switch model.stage {
        case "pack": return "Place pack"
        case "places": return "Places archive"
        case "glyphs": return "Map fonts"
        case "basemap": return "Offline basemap"
        default: return "Preparing"
        }
    }

    private func rows(_ count: Int) -> String {
        if count < 0 { return "no answer" }
        return "\(count) rows"
    }
}
