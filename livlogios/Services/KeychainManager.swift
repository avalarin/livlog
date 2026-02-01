//
//  KeychainManager.swift
//  livlogios
//
//  Created by Claude Code on 31.01.2026.
//

import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()

    private let service = "net.avalarin.livlog"
    private let accessTokenKey = "access_token"
    private let refreshTokenKey = "refresh_token"

    private init() {}

    // MARK: - Access Token

    func saveAccessToken(_ token: String) {
        save(token, forKey: accessTokenKey)
    }

    func getAccessToken() -> String? {
        return get(forKey: accessTokenKey)
    }

    func deleteAccessToken() {
        delete(forKey: accessTokenKey)
    }

    // MARK: - Refresh Token

    func saveRefreshToken(_ token: String) {
        save(token, forKey: refreshTokenKey)
    }

    func getRefreshToken() -> String? {
        return get(forKey: refreshTokenKey)
    }

    func deleteRefreshToken() {
        delete(forKey: refreshTokenKey)
    }

    // MARK: - Clear All

    func clearAll() {
        deleteAccessToken()
        deleteRefreshToken()
    }

    // MARK: - Private Methods

    private func save(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            print("Keychain save error for key '\(key)': \(status)")
        }
    }

    private func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                print("Keychain get error for key '\(key)': \(status)")
            }
            return nil
        }

        return value
    }

    private func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            print("Keychain delete error for key '\(key)': \(status)")
        }
    }
}
