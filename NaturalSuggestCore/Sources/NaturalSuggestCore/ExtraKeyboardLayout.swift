import Foundation

/// Optional iPhone keyboard layouts.
public enum ExtraKeyboardLayout: String, CaseIterable, Sendable {
    case korean, french, russian, chinese

    public var title: String {
        switch self {
        case .korean: UIText.t("韩语")
        case .french: UIText.t("法语")
        case .russian: UIText.t("俄语")
        case .chinese: UIText.t("中文")
        }
    }
}

/// Buttons that can stay at the left of the iPhone candidate bar while candidates are shown.
public enum KeyboardTool: String, CaseIterable, Sendable {
    case emoji, clipboard

    public var title: String {
        switch self {
        case .emoji: UIText.t("表情")
        case .clipboard: UIText.t("剪贴板")
        }
    }
}

public enum KeyboardSwitchLanguage: String, CaseIterable, Sendable {
    case japanese, english, korean, french, russian, chinese

    public var title: String {
        switch self {
        case .japanese: UIText.t("日语")
        case .english: UIText.t("英语")
        case .korean: UIText.t("韩语")
        case .french: UIText.t("法语")
        case .russian: UIText.t("俄语")
        case .chinese: UIText.t("中文")
        }
    }
}
