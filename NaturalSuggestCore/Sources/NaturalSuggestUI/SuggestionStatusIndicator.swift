import SwiftUI
import NaturalSuggestCore

public struct SuggestionStatusIndicator: View {
    private let status: Diagnostics
    public init(status: Diagnostics) { self.status = status }
    public static func isVisible(_ status: Diagnostics) -> Bool {
        switch status {
        case .idle, .disabled, .ready, .filtered: false
        default: true
        }
    }
    private var symbol: String {
        switch status {
        case .natural: "checkmark.circle"
        case .waiting: "ellipsis"
        case .noSuggestions, .unsupportedDraft, .contextUnavailable: "questionmark.circle"
        default: "exclamationmark.circle"
        }
    }
    private var color: Color {
        switch status {
        case .natural: .green
        case .waiting, .requesting, .noSuggestions, .unsupportedDraft, .contextUnavailable: .secondary
        default: .orange
        }
    }
    public var body: some View {
        Group {
            if status == .requesting {
                ProgressView().controlSize(.small).scaleEffect(0.75)
            } else {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(color)
            }
        }.frame(width: 20, height: 20)
            .help(status.message).accessibilityLabel(status.message)
    }
}

#if os(iOS)
public struct KeyboardSuggestionStatus: View {
    private let status: Diagnostics
    private let retry: () -> Void
    @State private var expanded = false
    public init(status: Diagnostics, expanded: Bool = false, retry: @escaping () -> Void) {
        self.status = status; self.retry = retry; _expanded = State(initialValue: expanded)
    }
    public var body: some View {
        Button { expanded.toggle() } label: {
            SuggestionStatusIndicator(status: status).frame(width: 28, height: 30).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(status.message)
            // Keys are drawn above the bar (upstream zIndex), so the message must stay within the bar's height.
            .overlay(alignment: .trailing) {
                if expanded {
                    HStack(spacing: 10) {
                        Text(status.message).font(.system(size: 12)).lineLimit(2).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if status != .natural && status != .waiting && status != .requesting {
                            Button("重试") { expanded = false; retry() }.font(.system(size: 13, weight: .medium))
                        }
                        Button { expanded = false } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .medium)) }
                            .accessibilityLabel("关闭")
                    }
                    .buttonStyle(.plain).padding(.horizontal, 10)
                    .frame(width: min(UIScreen.main.bounds.width - 12, 520), height: 38)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.08), lineWidth: 0.5) }
                    .contentShape(Rectangle()).onTapGesture { expanded = false }
                }
            }
            .onChange(of: status) { _ in expanded = false }
    }
}
#endif
