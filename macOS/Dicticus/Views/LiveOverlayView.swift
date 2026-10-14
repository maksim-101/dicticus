import SwiftUI
import AppKit

/// Glass pane of the live transcript overlay (Phase 51, D-07, D-13).
///
/// The newest text sits at the bottom of a fixed-height clipped area; older lines leave
/// through the top, faded by a gradient mask. Appearance follows the system.
struct LiveOverlayView: View {
    @ObservedObject var model: LiveOverlayModel

    static let width: CGFloat = 360
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 8
    static let visibleLines = 4
    static let transcriptFont = NSFont.systemFont(ofSize: 15)

    static let transcriptLineHeight: CGFloat = lineHeight(of: transcriptFont)
    static let statusLineHeight: CGFloat = lineHeight(of: NSFont.preferredFont(forTextStyle: .caption1))
    static let transcriptHeight: CGFloat = transcriptLineHeight * CGFloat(visibleLines)
    static let height: CGFloat = padding * 2 + statusLineHeight + spacing + transcriptHeight

    private static func lineHeight(of font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Text(model.phase == .listening ? "Listening" : "Processing")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(Self.displayTail(model.text))
                .font(.system(size: 15))
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
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
