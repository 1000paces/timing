import SwiftUI

struct CrossingRow: View {
    let row: Row
    let offsetMs: Int
    var onFilter: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onFilter) { Image(systemName: "line.3.horizontal.decrease.circle") }
                .buttonStyle(.borderless)
                .disabled(row.bib == nil)
                .accessibilityLabel("Show only this bib")
            Text(formatClock(row.atMs + offsetMs))
                .font(.callout.monospacedDigit())
                .fixedSize()
            VStack(spacing: 0) {
                Button(action: onEdit) { Text(row.bib ?? "—").bold() }
                    .buttonStyle(.borderless)
                    .disabled(row.locked)
                    .accessibilityLabel("Edit bib")
                    .accessibilityValue(row.bib ?? "no bib")
                if let note = row.enteredNote {
                    Text(note).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 64)
            VStack(alignment: .leading, spacing: 2) {
                if let name = row.name { Text(name).lineLimit(1) }
                if let race = row.race { Text(race).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                FlowChips(row: row)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .accessibilityLabel("Delete crossing")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("crossing")
    }
}

private struct FlowChips: View {
    let row: Row

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(row.chips, id: \.self) { Chip(text: $0.rawValue, color: .red, filled: true) }
            Chip(text: row.lap.map { "Lap \($0)" } ?? "Lap —", color: .secondary, filled: false)
            if let flag = row.lapFlag, let lapMs = row.lapMs {
                Chip(text: "\(lapFlagLabel(flag)) \(formatElapsed(lapMs))", color: .orange, filled: true, icon: "exclamationmark.triangle")
            }
        }
        .padding(.top, 2)
    }
}

struct Chip: View {
    let text: String
    let color: Color
    let filled: Bool
    var icon: String?

    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .foregroundStyle(filled ? Color.white : color)
        .background(Capsule().fill(filled ? color : Color.clear))
        .overlay(Capsule().stroke(color.opacity(filled ? 0 : 0.6)))
    }
}

// Lays its children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Line { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0; var y: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = [Line()]
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !lines[lines.count - 1].items.isEmpty && lines[lines.count - 1].width + spacing + size.width > width {
                let last = lines[lines.count - 1]
                lines.append(Line(y: last.y + last.height + spacing))
            }
            var line = lines[lines.count - 1]
            line.width += (line.items.isEmpty ? 0 : spacing) + size.width
            line.height = max(line.height, size.height)
            line.items.append(index)
            lines[lines.count - 1] = line
        }
        return lines
    }
}
