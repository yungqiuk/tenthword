import Foundation
import Security

/// Хранилище, переживающее удаление приложения.
///
/// Именно поэтому дата начала триала лежит здесь, а не в `UserDefaults`:
/// элементы Keychain остаются на устройстве после удаления приложения —
/// это штатное поведение iOS, и оно закрывает самый массовый способ обхода.
///
/// Класс доступа `AfterFirstUnlockThisDeviceOnly`: значение не уезжает в резервную
/// копию и не переносится на новое устройство восстановлением из бэкапа —
/// иначе бэкап стал бы способом сбросить триал.
enum KeychainStore {

    private static let service = "com.tenthword.trial"

    static func string(for key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        return UserDefaults.standard.string(forKey: fallbackKey(key))
    }

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        let data = Data(value.utf8)
        let query = baseQuery(key)

        if SecItemUpdate(query as CFDictionary,
                         [kSecValueData as String: data] as CFDictionary) == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: fallbackKey(key))
            return true
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        var status = SecItemAdd(insert as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemDelete(query as CFDictionary)
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        if status == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: fallbackKey(key))
            return true
        }

        // Keychain недоступен целиком — так бывает у сборки без нужного
        // entitlement (например, неподписанной для симулятора). Пишем
        // в UserDefaults: защита триала слабее, но читатель получает свои
        // три дня, а не «бесплатный режим» с порога. Молча лишать человека
        // оплаченного триала хуже, чем упростить обход.
        UserDefaults.standard.set(value, forKey: fallbackKey(key))
        return true
    }

    private static func fallbackKey(_ key: String) -> String { "trial.fallback." + key }

    static func date(for key: String) -> Date? {
        guard let raw = string(for: key), let seconds = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    @discardableResult
    static func set(_ date: Date, for key: String) -> Bool {
        set(String(date.timeIntervalSince1970), for: key)
    }

    static func double(for key: String) -> Double? {
        string(for: key).flatMap(Double.init)
    }

    @discardableResult
    static func set(_ value: Double, for key: String) -> Bool {
        set(String(value), for: key)
    }

    /// Только для отладки. В приложении не вызывается: очистка Keychain — это
    /// и есть тот обход, от которого мы защищаемся.
    static func removeAll() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service] as CFDictionary)
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix("trial.fallback.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
}
