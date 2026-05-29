import Foundation
import Security
import ClaudeUsageBarCore

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
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let raw = String(data: data, encoding: .utf8) else {
            log("keychain lookup '\(service)' failed (OSStatus \(status))")
            return nil
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let t = json["accessToken"] as? String {
                log("token from key 'accessToken' (len \(t.count))"); return t
            }
            if let nested = json["claudeAiOauth"] as? [String: Any],
               let t = nested["accessToken"] as? String {
                log("token from 'claudeAiOauth.accessToken' (len \(t.count))"); return t
            }
            log("keychain JSON found but no known token field; top-level keys: \(Array(json.keys))")
        }
        log("falling back to raw keychain string (len \(raw.count); looks like JSON: \(raw.hasPrefix("{")))")
        return raw
    }

    private static func log(_ message: String) {
        CCULog.write(message)
    }
}
