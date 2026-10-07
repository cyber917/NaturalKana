import Foundation
import Security

public enum SharedKeychain {
    public static func matches(group: String, suffix: String) -> Bool {
        guard !suffix.isEmpty, !suffix.contains("$("), group.hasSuffix("." + suffix) else { return false }
        let prefix = group.dropLast(suffix.count + 1)
        return !prefix.isEmpty && !prefix.contains(".") && !prefix.contains("$(")
    }

    /// The OS returns the actual access group. No Team ID or signing-prefix guess.
    /// Only a non-secret marker is created; provider keys still use explicit access groups.
    public static func accessGroup(bundle: Bundle = .main) throws -> String {
        guard let suffix = bundle.object(forInfoDictionaryKey: "NaturalKanaKeychainSuffix") as? String else {
            throw SharingFailure.keychainGroup
        }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: "NaturalKana.access-group-probe",
                                  kSecAttrAccount as String: "metadata"]
        var query = base
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            var item = base
            item[kSecValueData as String] = Data()
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            item[kSecReturnAttributes as String] = true
            status = SecItemAdd(item as CFDictionary, &result)
            if status == errSecDuplicateItem { status = SecItemCopyMatching(query as CFDictionary, &result) }
        }
        guard status == errSecSuccess else { throw SharingFailure.keychain(status) }
        guard let attributes = result as? [String: Any], let group = attributes[kSecAttrAccessGroup as String] as? String,
              matches(group: group, suffix: suffix) else { throw SharingFailure.keychainGroup }
        return group
    }
}
