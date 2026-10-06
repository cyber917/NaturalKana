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
    public init(status: Diagnostics, retry: @escaping () -> Void) { self.status = status; self.retry = retry }
    public var body: some View {
        Button { expanded.toggle() } label: {
            SuggestionStatusIndicator(status: status).frame(width: 28, height: 30).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(status.message)
            .overlay(alignment: .topTrailing) {
                if expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(status.message).font(.caption).fixedSize(horizontal: false, vertical: true)
                        if status != .natural && status != .waiting && status != .requesting {
                            Button("重试") { expanded = false; retry() }.font(.caption)
                        }
                    }.padding(10).frame(width: 210, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .offset(y: 30)
                }
            }
            .onChange(of: status) { _ in expanded = false }
    }
}
#endif
