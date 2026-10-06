import Foundation
import Security

public struct KeychainStore: Sendable {
    public let service: String
    public let accessGroup: String?
    public init(service: String = "NaturalKana.provider", accessGroup: String? = nil) { self.service = service; self.accessGroup = accessGroup }
    private func query(_ account: String) -> [String: Any] {
        var value: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        if let accessGroup { value[kSecAttrAccessGroup as String] = accessGroup }
        return value
    }
    public func read(_ account: String) throws -> String {
        var attributes = query(account)
        attributes[kSecReturnData as String] = true; attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw SuggestionError.missingKey }
        return key
    }
    public func write(_ key: String, account: String) throws {
        let attributes = query(account)
        if key.isEmpty { SecItemDelete(attributes as CFDictionary); return }
        let update: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(attributes as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var new = attributes; new[kSecValueData as String] = Data(key.utf8)
            new[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(new as CFDictionary, nil) == errSecSuccess else { throw SuggestionError.configuration }
        } else if status != errSecSuccess { throw SuggestionError.configuration }
    }
}
