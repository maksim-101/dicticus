import SwiftUI

struct SpokenPunctuationReferenceView: View {
    var body: some View {
        List {
            Section("Always") {
                LabeledContent("hyphen / Bindestrich", value: "-")
                LabeledContent("slash / Schrägstrich", value: "/")
                LabeledContent("backslash", value: "\\")
                LabeledContent("underscore / Unterstrich", value: "_")
                LabeledContent("asterisk / Sternchen", value: "*")
                LabeledContent("semicolon", value: ";")
                LabeledContent("at sign / Klammeraffe", value: "@")
                LabeledContent("hash / Raute", value: "#")
                LabeledContent("caret", value: "^")
                LabeledContent("tilde", value: "~")
            }

            Section {
                LabeledContent("minus", value: "-")
                LabeledContent("dot", value: ".")
                LabeledContent("colon", value: ":")
                LabeledContent("dollar", value: "$")
            } header: {
                Text("Between identifier words")
            } footer: {
                Text("Conditional symbols collapse only when flanked by identifier-shaped words (e.g. \"Claude minus ops\" → \"Claude-ops\"). \"dot\" also collapses between number-words (\"ten dot five\" → \"10.5\").")
            }

            Section {
                LabeledContent("scratch that", value: "deletes the last sentence")
                LabeledContent("scratch the last sentence", value: "deletes the last sentence")
                LabeledContent("ignore the last sentence", value: "deletes the last sentence")
                LabeledContent("forget the last sentence", value: "deletes the last sentence")
                LabeledContent("scratch the last word", value: "deletes the last word")
                LabeledContent("ignore the last word", value: "deletes the last word")
                LabeledContent("ignoriere den letzten Satz", value: "deletes the last sentence")
                LabeledContent("ignorier den letzten Satz", value: "deletes the last sentence")
                LabeledContent("vergiss den letzten Satz", value: "deletes the last sentence")
                LabeledContent("streich das", value: "deletes the last sentence")
                LabeledContent("streiche das", value: "deletes the last sentence")
                LabeledContent("ignoriere das letzte Wort", value: "deletes the last word")
                LabeledContent("vergiss das letzte Wort", value: "deletes the last word")
                LabeledContent("streich das letzte Wort", value: "deletes the last word")
                LabeledContent("streiche das letzte Wort", value: "deletes the last word")
            } header: {
                Text("Voice Commands")
            } footer: {
                Text("A command only counts when it stands alone at a clause boundary — at the start of what you're saying, or right after a period or comma. If you keep talking in the same breath (e.g. \"I told him to scratch that idea\"), it's treated as ordinary dictated words, not a command. Voice Commands work in AI Cleanup mode only, and can be turned off in Settings → AI Cleanup.")
            }
        }
        .navigationTitle("Spoken Punctuation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SpokenPunctuationReferenceView()
    }
}
