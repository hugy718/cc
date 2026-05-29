import Foundation
import Security

enum KeychainTokenProvider {
    /// Best-effort lookup of the Claude Code OAuth token from the login keychain.
    /// Service/account names confirmed during implementation; returns nil if absent.
    static func token(service: String = "Claude Code-credentials") -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let raw = String(data: data, encoding: .utf8) else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let t = json["accessToken"] as? String { return t }
            if let nested = json["claudeAiOauth"] as? [String: Any],
               let t = nested["accessToken"] as? String { return t }
        }
        return raw
    }
}
