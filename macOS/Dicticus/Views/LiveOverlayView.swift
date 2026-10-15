import SwiftUI
import AppKit

/// Content of the live transcript overlay pane (Phase 51, D-07, D-13). The glass behind it is an
/// AppKit `NSGlassEffectView` owned by `LiveOverlayPanel`.
///
/// The newest text sits at the bottom of a fixed-height clipped area; older lines leave
/// through the top, faded by a gradient mask. Appearance follows the system.
struct LiveOverlayView: View {
    @ObservedObject var model: LiveOverlayModel

    static let width: CGFloat = 320
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 4
    static let visibleLines = 3
    static let cornerRadius: CGFloat = 22
    static let transcriptFont = NSFont.systemFont(ofSize: 14)

    static let transcriptLineHeight: CGFloat = lineHeight(of: transcriptFont)
    static let statusLineHeight: CGFloat = lineHeight(of: NSFont.preferredFont(forTextStyle: .caption2))
    static let transcriptHeight: CGFloat = transcriptLineHeight * CGFloat(visibleLines)
    static let height: CGFloat = padding * 2 + statusLineHeight + spacing + transcriptHeight

    private static func lineHeight(of font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Text(model.phase == .listening ? "Listening" : "Processing")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(Self.displayTail(model.text))
                .font(.system(size: 14))
                .foregroundStyle(Color(nsColor: .labelColor))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.transcriptHeight, alignment: .bottomLeading)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.35),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(model.phase == .processing ? 0.6 : 1)
        }
        .padding(Self.padding)
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
