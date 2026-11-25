import SwiftUI

/// Lays subviews out left to right and wraps onto a new line when the width runs out.
/// With `maxLines`, the last subview is an overflow marker ("…"): shown at the end of the
/// last line when the words need more lines, and hidden, like the words cut off, otherwise.
/// It then also shows only as many lines (at least one) as the proposed height holds, so the
/// text gives up lines when its container has less room.
struct WrappingLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4
    var maxLines: Int? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, height: proposal.height, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, height: bounds.height, subviews: subviews)
        let shown = Set(rows.flatMap(\.indices))
        for index in subviews.indices where !shown.contains(index) {
            subviews[index].place(at: bounds.origin, proposal: .zero)
        }
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = Self.fittedSize(subviews[index], width: bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private static func fittedSize(_ subview: LayoutSubview, width: CGFloat) -> CGSize {
        let natural = subview.sizeThatFits(.unspecified)
        guard natural.width > width else { return natural }
        return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, height: CGFloat?, subviews: Subviews) -> [Row] {
        guard var maxLines, let marker = subviews.indices.last else { return wrap(width: width, subviews: subviews, count: subviews.count) }
        var rows = wrap(width: width, subviews: subviews, count: marker)
        if let height, height.isFinite {
            var used: CGFloat = 0
            var fitting = 0
            for row in rows {
                used += (fitting == 0 ? 0 : lineSpacing) + row.height
                if used > height + 0.5 { break }
                fitting += 1
            }
            maxLines = min(maxLines, max(fitting, 1))
        }
        guard rows.count > maxLines, maxLines > 0 else { return rows }
        rows.removeLast(rows.count - maxLines)
        let markerWidth = Self.fittedSize(subviews[marker], width: width).width
        var last = rows[maxLines - 1]
        while last.indices.count > 1, last.width + spacing + markerWidth > width {
            last.indices.removeLast()
            last.width = last.indices.map { Self.fittedSize(subviews[$0], width: width).width }.reduce(0, +)
                + spacing * CGFloat(last.indices.count - 1)
        }
        // A single word too wide for the marker beside it keeps the line to itself, without "…".
        if last.width + spacing + markerWidth <= width {
            last.indices.append(marker)
            last.width += spacing + markerWidth
        }
        rows[maxLines - 1] = last
        return rows
    }

    private func wrap(width: CGFloat, subviews: Subviews, count: Int) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.prefix(count).enumerated() {
            let size = Self.fittedSize(subview, width: width)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
