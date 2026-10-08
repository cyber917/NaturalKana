import Foundation

/// Optional iPhone keyboard layouts.
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

public enum KeyboardSwitchLanguage: String, CaseIterable, Sendable {
    case japanese, english, korean, french, russian

    public var title: String {
        switch self {
        case .japanese: UIText.t("日语")
        case .english: UIText.t("英语")
        case .korean: UIText.t("韩语")
        case .french: UIText.t("法语")
        case .russian: UIText.t("俄语")
        }
    }
}
