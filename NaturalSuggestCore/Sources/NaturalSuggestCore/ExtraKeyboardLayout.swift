import Foundation

/// iPhone layouts, in the order used by the language switch key.
public enum ExtraKeyboardLayout: String, CaseIterable, Sendable {
    case korean, french, russian

    public var title: String {
        switch self {
        case .korean: UIText.t("韩语")
        case .french: UIText.t("法语")
        case .russian: UIText.t("俄语")
        }
    }
}
