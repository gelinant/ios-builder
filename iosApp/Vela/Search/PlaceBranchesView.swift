import SwiftUI

/// The count chip the place sheet shows when Google's reply carried other listings at the same
/// address. It opens the list just under the chip; nothing is drawn when the reply had no sibling.
struct PlaceBranchChip: View {
    let count: Int
    let expanded: Bool
    let onOpen: () -> Void

    private var title: String {
        count == 1 ? "1 location" : "\(count) locations"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Image(systemName: "building.2.fill")
                    .font(.caption)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("\(VelaL10n.text("place_also_at_location")), \(title)")
        .accessibilityIdentifier("place-branch-chip")
        .accessibilityValue("\(count)")
    }
}

/// Every listing Google placed at this address, the open one excluded because the sheet is
/// already about it. A tap opens that listing without closing the group, so the original stays in
/// this same list one tap away.
struct PlaceBranchList: View {
    @ObservedObject var model: PlaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(VelaL10n.text("place_also_at_location"))
                .font(.headline)
                .padding(.top, 4)
            ForEach(model.branches) { row in
                Button {
                    model.openBranch(row)
                } label: {
                    PlaceBranchRowView(row: row)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("place-branch-row")
                .accessibilityLabel(row.accessibilityLabel)
                Divider()
            }
            Text(VelaL10n.text("search_these_listings_share_this_address_on"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place-branch-list")
    }
}

private struct PlaceBranchRowView: View {
    let row: BranchRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !row.summary.isEmpty {
                    Text(row.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let status = row.status {
                    Text(status)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(
                            row.permanentlyClosed || row.openNow == false
                                ? Color(uiColor: .systemRed) : Color(uiColor: .systemGreen))
                }
                if let address = row.address, !address.isEmpty {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.forward.circle")
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .frame(minHeight: 44)
    }
}

private extension BranchRow {
    var accessibilityLabel: String {
        var parts = [name]
        if let rating {
            parts.append(reviewCount.map { String(format: "%.1f stars, %d reviews", rating, $0) }
                ?? String(format: "%.1f stars", rating))
        }
        if let category, !category.isEmpty { parts.append(category) }
        if let status { parts.append(status) }
        if let address, !address.isEmpty { parts.append(address) }
        return parts.joined(separator: ", ")
    }
}
