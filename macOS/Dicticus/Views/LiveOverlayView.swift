import SwiftUI
import AppKit

/// Content of the live transcript overlay pane (Phase 51, D-07, D-13; scene A of the 2026-10-15
/// motion study). The glass behind it is an AppKit `NSGlassEffectView` owned by `LiveOverlayPanel`.
///
/// The newest text sits at the bottom of a fixed-height clipped area; older lines leave
/// through the top, faded by a gradient mask. Appearance follows the system.
struct LiveOverlayView: View {
    @ObservedObject var model: LiveOverlayModel

    static let width: CGFloat = 420
    static let horizontalPadding: CGFloat = 18
    static let verticalPadding: CGFloat = 13
    static let spacing: CGFloat = 5
    static let visibleLines = 3
    static let cornerRadius: CGFloat = 22
    static let transcriptFont = NSFont.systemFont(ofSize: 14.5)

    static let transcriptLineHeight: CGFloat = lineHeight(of: transcriptFont)
    static let statusLineHeight: CGFloat = lineHeight(of: NSFont.preferredFont(forTextStyle: .caption2))
    static let transcriptHeight: CGFloat = transcriptLineHeight * CGFloat(visibleLines)
    static let height: CGFloat = verticalPadding * 2 + statusLineHeight + spacing + transcriptHeight

    private static func lineHeight(of font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    private var processing: Bool { model.phase == .processing }

    var body: some View {
        ZStack {
            if model.reduceTransparency {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            } else {
                Sheen()
            }
            content
        }
        .frame(width: Self.width, height: Self.height)
        .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            HStack(spacing: 6) {
                Circle().frame(width: 5, height: 5).opacity(processing ? 0.35 : 0.8)
                Text(processing ? "Processing" : "Listening")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(Self.displayTail(model.text))
                .font(Font(Self.transcriptFont))
                .foregroundStyle(Color(nsColor: .labelColor))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.transcriptHeight, alignment: .bottomLeading)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.38),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(processing ? 0.6 : 1)
                .animation(model.reduceMotion ? nil : .easeOut(duration: 0.3), value: model.text)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
    }

    /// Bounded tail of the transcript: keeps layout cost constant for long dictations.
    /// The cut moves forward to the next word start so no partial word leads.
    static func displayTail(_ text: String, maxCharacters: Int = 400) -> String {
        guard text.count > maxCharacters else { return text }
        let start = text.index(text.endIndex, offsetBy: -maxCharacters)
        let tail = text[start...]
        if text[text.index(before: start)].isWhitespace {
            return String(tail.drop(while: \.isWhitespace))
        }
        guard let firstSpace = tail.firstIndex(where: \.isWhitespace) else { return String(tail) }
        return String(tail[firstSpace...].drop(while: \.isWhitespace))
    }
}

/// Light catch along the top edge of the glass.
private struct Sheen: View {
    var body: some View {
        RoundedRectangle(cornerRadius: LiveOverlayView.cornerRadius, style: .continuous)
            .fill(LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.11), location: 0),
                    .init(color: .white.opacity(0.025), location: 0.13),
                    .init(color: .clear, location: 0.3)
                ],
                startPoint: .top,
                endPoint: .bottom))
            .allowsHitTesting(false)
    }
}
