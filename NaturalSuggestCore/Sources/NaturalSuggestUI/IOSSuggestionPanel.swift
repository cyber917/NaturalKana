#if os(iOS)
import SwiftUI
import NaturalSuggestCore

/// The controller reserves exactly this height, independently of the number of candidates.
public struct IOSSuggestionPanel: View {
    public static let height: CGFloat = 132
    private let original: String
    private let highlightChanges: Bool
    private let suggestions: [Suggestion]
    private let accept: (Int) -> Void
    private let dismiss: () -> Void
    @State private var selection = 0

    public init(suggestions: [Suggestion], original: String = "", highlightChanges: Bool = true, accept: @escaping (Int) -> Void, dismiss: @escaping () -> Void) {
        self.original = original; self.highlightChanges = highlightChanges
        self.suggestions = suggestions; self.accept = accept; self.dismiss = dismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(suggestions.indices.contains(selection) && suggestions[selection].register == .polite ? "丁寧" : "カジュアル")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button { selection = max(0, selection - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(selection == 0).accessibilityLabel("前の候補")
                Text("\(selection + 1) / \(suggestions.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button { selection = min(suggestions.count - 1, selection + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(selection >= suggestions.count - 1).accessibilityLabel("次の候補")
                Button(action: dismiss) { Image(systemName: "xmark") }.accessibilityLabel("閉じる")
            }
            .font(.system(size: 13, weight: .medium)).buttonStyle(.plain)
            .padding(.horizontal, 14).frame(height: 34)
            TabView(selection: $selection) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    ScrollView(.vertical) {
                        Button { accept(index) } label: {
                            HighlightedSuggestion.text(suggestion.text, original: original, enabled: highlightChanges).font(.system(size: 17))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }.tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.06), lineWidth: 0.5) }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(height: Self.height)
        .onChange(of: suggestions) { _ in selection = 0 }
    }
}
#endif
