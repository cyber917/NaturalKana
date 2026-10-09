#if os(iOS)
import SwiftUI
import NaturalSuggestCore

/// The controller reserves exactly this height, independently of the number of candidates.
public struct IOSSuggestionPanel: View {
    public static let height: CGFloat = 132
    private let language: SuggestionLanguage
    private let original: String
    private let highlightChanges: Bool
    private let suggestions: [Suggestion]
    private let accept: (Int) -> Void
    private let dismiss: () -> Void
    @State private var selection = 0

    public init(suggestions: [Suggestion], language: SuggestionLanguage = .japanese, original: String = "", highlightChanges: Bool = true, accept: @escaping (Int) -> Void, dismiss: @escaping () -> Void) {
        self.language = language
        self.original = original; self.highlightChanges = highlightChanges
        self.suggestions = suggestions; self.accept = accept; self.dismiss = dismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(language.registerTitle(suggestions.indices.contains(selection) ? suggestions[selection].register : .casual))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button { selection = max(0, selection - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(selection == 0).accessibilityLabel(UIText.t("上一条"))
                Text("\(selection + 1) / \(suggestions.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button { selection = min(suggestions.count - 1, selection + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(selection >= suggestions.count - 1).accessibilityLabel(UIText.t("下一条"))
                Button(action: dismiss) { Image(systemName: "xmark") }.accessibilityLabel(language.closeTitle)
            }
            .font(.system(size: 13, weight: .medium)).buttonStyle(.plain)
            .padding(.horizontal, 14).frame(height: 34)
            ScrollView(.vertical) {
                if suggestions.indices.contains(selection) {
                    HighlightedSuggestion.text(suggestions[selection].text, original: original, enabled: highlightChanges).font(.system(size: 17))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { accept(selection) }
                }
            }
            .modifier(SuggestionScrollEdges())
            .id(selection)
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                selection = min(max(0, selection + (value.translation.width < 0 ? 1 : -1)), max(0, suggestions.count - 1))
            }.exclusively(before: TapGesture().onEnded { accept(selection) }))
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.06), lineWidth: 0.5) }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(height: Self.height)
        .onChange(of: suggestions) { _ in selection = 0 }
    }
}
private struct SuggestionScrollEdges: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // The compact card has its own header; the system edge blur obscures its first line.
            content.scrollEdgeEffectHidden()
        } else {
            content
        }
    }
}
#endif
