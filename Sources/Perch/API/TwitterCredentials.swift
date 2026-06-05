import Foundation
import Security

/// Persisted X/Twitter session: cookies + resolved user identity.
struct TwitterCredentials: Codable {
    var authToken: String
    var ct0: String
    var userId: String
    var username: String
    var displayName: String
    var avatarURL: String? = nil
}

/// Store for X sessions.
/// DEBUG builds persist to a file under Application Support so unstable
/// dev-build code signatures never trigger the keychain access prompt;
/// release builds use the keychain.
enum TwitterCredentialStore {
    private static let service = "com.perch.twitter"
    private static let legacyAccount = "session"
    private static let accountPrefix = "session."

    private static func accountName(for creds: TwitterCredentials) -> String {
        "\(accountPrefix)\(creds.userId)"
    }

    private static func dedupe(_ creds: [TwitterCredentials]) -> [TwitterCredentials] {
        var seen: Set<String> = []
        var out: [TwitterCredentials] = []
        for c in creds {
            guard !c.userId.isEmpty, !seen.contains(c.userId) else { continue }
            seen.insert(c.userId)
            out.append(c)
        }
        return out
    }

#if DEBUG
    private static let fileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Perch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }()

    private static let legacyFileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Perch", isDirectory: true)
        return dir.appendingPathComponent("session.json")
    }()

    static func save(_ creds: TwitterCredentials) {
        var all = loadAll()
        if let idx = all.firstIndex(where: { $0.userId == creds.userId }) {
            all[idx] = creds
        } else {
            all.append(creds)
        }
        saveAll(all)
    }

    private static func saveAll(_ creds: [TwitterCredentials]) {
        guard let data = try? JSONEncoder().encode(dedupe(creds)) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    static func load() -> TwitterCredentials? {
        loadAll().first
    }

    static func loadAll() -> [TwitterCredentials] {
        if let data = try? Data(contentsOf: fileURL) {
            if let creds = try? JSONDecoder().decode([TwitterCredentials].self, from: data) {
                return dedupe(creds)
            }
            if let legacy = try? JSONDecoder().decode(TwitterCredentials.self, from: data) {
                return [legacy]
            }
        }
        if let legacyData = try? Data(contentsOf: legacyFileURL),
           let legacy = try? JSONDecoder().decode(TwitterCredentials.self, from: legacyData) {
            return [legacy]
        }
        return []
    }

    static func clear(accountId: String) {
        let userId = accountId.replacingOccurrences(of: "axlive_", with: "")
        saveAll(loadAll().filter { $0.userId != userId })
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: legacyFileURL)
    }
#else
    static func save(_ creds: TwitterCredentials) {
        guard let data = try? JSONEncoder().encode(creds) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName(for: creds),
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> TwitterCredentials? {
        loadAll().first
    }

    static func loadAll() -> [TwitterCredentials] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let items = item as? [[String: Any]] else { return [] }

        let keyed: [(String, TwitterCredentials)] = items.compactMap { row in
            guard let account = row[kSecAttrAccount as String] as? String,
                  account == legacyAccount || account.hasPrefix(accountPrefix),
                  let data = row[kSecValueData as String] as? Data,
                  let creds = try? JSONDecoder().decode(TwitterCredentials.self, from: data)
            else { return nil }
            return (account, creds)
        }
        let prefixed = keyed.filter { $0.0.hasPrefix(accountPrefix) }.map(\.1)
        let legacy = keyed.filter { $0.0 == legacyAccount }.map(\.1)
        return dedupe(prefixed + legacy)
    }

    static func clear(accountId: String) {
        let userId = accountId.replacingOccurrences(of: "axlive_", with: "")
        let shouldDeleteLegacy = loadLegacy()?.userId == userId
        let scoped: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(accountPrefix)\(userId)",
        ]
        SecItemDelete(scoped as CFDictionary)

        if shouldDeleteLegacy {
            let legacy: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: legacyAccount,
            ]
            SecItemDelete(legacy as CFDictionary)
        }
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func loadLegacy() -> TwitterCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let creds = try? JSONDecoder().decode(TwitterCredentials.self, from: data)
        else { return nil }
        return creds
    }
#endif
}
