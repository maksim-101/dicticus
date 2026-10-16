import SwiftUI
import AppKit

/// Content of the live transcript overlay pane (Phase 51, D-07, D-13; scene A of the 2026-10-15
/// motion study). The glass behind it is an AppKit `NSGlassEffectView` owned by `LiveOverlayPanel`.
///
/// The newest text sits at the bottom of a fixed-height clipped area; older lines leave
/// through the top, faded by a gradient mask. Appearance follows the system.
struct LiveOverlayView: View {
    @ObservedObject var model: LiveOverlayModel
    @Environment(\.colorSchemeContrast) private var contrast

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
            if model.isProcessingIndicatorActive {
                ProcessingRing(rotates: !model.reduceMotion)
                    .transition(.opacity)
            }
        }
        .animation(model.reduceMotion ? nil : .easeOut(duration: ProcessingRing.fadeDuration),
                   value: model.isProcessingIndicatorActive)
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

            transcript
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
                .animation(model.reduceMotion ? nil : .easeOut(duration: 0.3), value: model.combined)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
    }

    /// Settled words in the label colour, tentative words pale; Increase Contrast shows both at full strength.
    private var transcript: Text {
        let parts = Self.displayParts(settled: model.settled, tentative: model.tentative)
        let labelStyle = Color(nsColor: .labelColor)
        let tentativeStyle: AnyShapeStyle = contrast == .increased ? AnyShapeStyle(labelStyle) : AnyShapeStyle(.secondary)
        let settled = Text(parts.settled).foregroundStyle(labelStyle)
        let tentative = Text(parts.tentative).foregroundStyle(tentativeStyle)
        if parts.tentative.isEmpty { return Text("\(settled)") }
        if parts.settled.isEmpty { return Text("\(tentative)") }
        return Text("\(settled) \(tentative)")
    }

    /// Both runs bounded to `maxCharacters` together. Only the settled run is cut, from the front,
    /// so a tentative word is never cut away.
    static func displayParts(settled: String, tentative: String, maxCharacters: Int = 400) -> (settled: String, tentative: String) {
        let separator = settled.isEmpty || tentative.isEmpty ? 0 : 1
        let budget = max(0, maxCharacters - tentative.count - separator)
        return (displayTail(settled, maxCharacters: budget), tentative)
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

/// Processing indicator P1 "border snake" (host session 2): a short colourful segment travels
/// once around the pane edge every `period` seconds. Reduce Motion shows the whole rim at low
/// strength instead. Drawn inside the glass content, masked to a stroke along the pane shape.
private struct ProcessingRing: View {
    let rotates: Bool

    static let fadeDuration: TimeInterval = 0.35
    static let period: TimeInterval = 1.6
    static let lineWidth: CGFloat = 1.5
    static let restingOpacity = 0.35

    private static let cyan = Color(red: 0x6E / 255, green: 0xE7 / 255, blue: 0xF9 / 255)
    private static let violet = Color(red: 0xA7 / 255, green: 0x8B / 255, blue: 0xFA / 255)
    private static let pink = Color(red: 0xF4 / 255, green: 0x72 / 255, blue: 0xB6 / 255)

    @State private var turn = 0.0

    private static var snake: Gradient {
        Gradient(stops: [
            .init(color: cyan.opacity(0), location: 0),
            .init(color: cyan.opacity(0), location: 250 / 360),
            .init(color: cyan, location: 290 / 360),
            .init(color: violet, location: 320 / 360),
            .init(color: pink, location: 345 / 360),
            .init(color: pink.opacity(0), location: 1)
        ])
    }

    private static var rim: Gradient { Gradient(colors: [cyan, violet, pink, cyan]) }

    var body: some View {
        let diagonal = (LiveOverlayView.width * LiveOverlayView.width + LiveOverlayView.height * LiveOverlayView.height).squareRoot()
        Color.clear
            .frame(width: LiveOverlayView.width, height: LiveOverlayView.height)
            .overlay {
                Rectangle()
                    .fill(AngularGradient(gradient: rotates ? Self.snake : Self.rim, center: .center, angle: .degrees(-90)))
                    .frame(width: diagonal, height: diagonal)
                    .rotationEffect(.degrees(turn))
            }
            .mask {
                RoundedRectangle(cornerRadius: LiveOverlayView.cornerRadius, style: .continuous)
                    .strokeBorder(Color.black, lineWidth: Self.lineWidth)
            }
            .opacity(rotates ? 1 : Self.restingOpacity)
            .allowsHitTesting(false)
            .onAppear {
                guard rotates else { return }
                withAnimation(.linear(duration: Self.period).repeatForever(autoreverses: false)) { turn = 360 }
            }
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
