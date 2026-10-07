import Foundation

public enum SharingFailure: Error, Equatable, Sendable {
    case groupMetadata, groupAmbiguous, containerUnavailable, defaultsUnavailable, keychain(Int32), keychainGroup
    public var message: String {
        switch self {
        case .groupMetadata: "共享配置缺失（G01）。请重新签名安装。"
        case .groupAmbiguous: "共享组不唯一（G02）。请检查重签结果。"
        case .containerUnavailable: "共享容器不可用（G03）。键盘请允许完全访问后重新打开；仍失败请检查签名。"
        case .defaultsUnavailable: "共享设置不可用（G04）。请检查签名。"
        case .keychain(let code): "钥匙串不可用（\(code)）。请解锁设备或检查共享权限。"
        case .keychainGroup: "钥匙串共享组不匹配（K01）。请检查重签结果。"
        }
    }
}

/// One source of shared storage for the app, keyboard, dictionaries and model settings.
/// UserDefaults is thread-safe; the URL and identifier are immutable.
public struct SharedContainer: @unchecked Sendable {
    public let identifier: String
    public let url: URL
    public let defaults: UserDefaults

    public static func identifier(info: [String: Any]) throws -> String {
        guard let base = info["NaturalKanaAppGroup"] as? String,
              base.hasPrefix("group."), !base.contains("$(") else { throw SharingFailure.groupMetadata }
        guard let rewritten = info["ALTAppGroups"] else { return base }
        guard let groups = rewritten as? [String] else { throw SharingFailure.groupMetadata }
        let matches = Set(groups.filter { $0 == base || ($0.hasPrefix(base + ".") && !$0.contains("$(")) })
        guard matches.count == 1, let selected = matches.first else { throw SharingFailure.groupAmbiguous }
        return selected
    }

    public static let current: Result<SharedContainer, SharingFailure> = {
        do {
            let group = try identifier(info: Bundle.main.infoDictionary ?? [:])
            guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
                return .failure(.containerUnavailable)
            }
            guard let defaults = UserDefaults(suiteName: group) else { return .failure(.defaultsUnavailable) }
            return .success(SharedContainer(identifier: group, url: url, defaults: defaults))
        } catch let error as SharingFailure { return .failure(error) }
        catch { return .failure(.groupMetadata) }
    }()

    public static var failure: SharingFailure? {
        if case .failure(let failure) = current { return failure }
        return nil
    }

    /// Native entry points must check `failure` before constructing the upstream UI.
    /// This is an initialization invariant, never a fallback to private storage.
    public static var required: SharedContainer {
        switch current {
        case .success(let container): return container
        case .failure: preconditionFailure("Shared storage used before installation gate")
        }
    }

    /// Read the installed extension's identifier; signing tools can rename both targets.
    public static func keyboardBundleIdentifier(bundle: Bundle = .main) -> String? {
        if bundle.bundleURL.pathExtension == "appex" { return bundle.bundleIdentifier }
        guard let plugins = bundle.builtInPlugInsURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) else { return nil }
        return urls.compactMap(Bundle.init(url:)).first {
            ($0.infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String == "com.apple.keyboard-service"
        }?.bundleIdentifier
    }
}
