//
//  KeychainService.swift
//  Outly
//
//  Created by Luka Rakusa Djurdjevic on 8. 1. 26.
//

import Foundation
import Security

/// Varna shramba zetonov. Vnosi so kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly:
/// ne gredo v varnostne kopije na drugo napravo in so berljivi sele po prvem odklepu.
final class KeychainService: Sendable {
    static let shared = KeychainService()
    private init() {}

    private let service = "com.outly.app"

    enum Kljuc: String {
        case accessToken  = "authToken"      // ime ostane zaradi zdruzljivosti s starimi namestitvami
        case refreshToken = "refreshToken"
    }

    // MARK: - Simulator (appetize.io, Xcode): nepodpisana aplikacija brez pravic
    // v simulatorju NE more pisati v Keychain (errSecMissingEntitlement, -34018) ->
    // prijava je javljala "Could not save your session on this device".
    // Samo v simulatorju zato uporabimo UserDefaults; na pravi napravi ostane Keychain.
    #if targetEnvironment(simulator)
    private var simKey: String { "sim.keychain." + service + "." }
    #endif

    // MARK: - Splosno

    @discardableResult
    func save(_ value: String, for kljuc: Kljuc) -> Bool {
        #if targetEnvironment(simulator)
        UserDefaults.standard.set(value, forKey: simKey + kljuc.rawValue)
        return true
        #else
        let data = Data(value.utf8)
        _ = delete(kljuc)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kljuc.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        #endif
    }

    func read(_ kljuc: Kljuc) -> String? {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.string(forKey: simKey + kljuc.rawValue)
        #else
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kljuc.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
        #endif
    }

    @discardableResult
    func delete(_ kljuc: Kljuc) -> Bool {
        #if targetEnvironment(simulator)
        UserDefaults.standard.removeObject(forKey: simKey + kljuc.rawValue)
        return true
        #else
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kljuc.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
        #endif
    }

    // MARK: - Stari klici (obdrzani, da obstojeca koda dela)

    func saveToken(_ token: String) -> Bool { save(token, for: .accessToken) }
    func readToken() -> String? { read(.accessToken) }
    func deleteToken() -> Bool { delete(.accessToken) }
}
