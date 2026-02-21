//
//  AuthService.swift
//  livlogios
//
//  Created by Claude Code on 31.01.2026.
//

import AuthenticationServices
import Combine
import Foundation

@MainActor
class AuthService: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User?
    @Published var error: Error?

    private let keychainManager = KeychainManager.shared

    // MARK: - Sign in with Apple

    func signInWithApple(authorization: ASAuthorization) async throws -> User {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.invalidToken
        }

        guard let identityTokenData = appleIDCredential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AuthError.invalidToken
        }

        let authorizationCode: String? = {
            guard let codeData = appleIDCredential.authorizationCode else { return nil }
            return String(data: codeData, encoding: .utf8)
        }()

        let fullName: PersonNameComponents? = {
            guard let name = appleIDCredential.fullName else { return nil }
            return PersonNameComponents(
                givenName: name.givenName,
                familyName: name.familyName
            )
        }()

        let email = appleIDCredential.email

        do {
            let authResponse = try await BackendService.shared.appleAuth(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                fullName: fullName,
                email: email
            )

            // Save tokens to Keychain
            keychainManager.saveAccessToken(authResponse.accessToken)
            keychainManager.saveRefreshToken(authResponse.refreshToken)

            // Update state
            isAuthenticated = true
            currentUser = authResponse.user

            return authResponse.user
        } catch {
            self.error = error
            throw error
        }
    }

    // MARK: - Check Auth Status

    func checkAuthStatus() async -> Bool {
        guard let accessToken = keychainManager.getAccessToken() else {
            return false
        }

        // Try to get current user with existing token
        do {
            let user = try await BackendService.shared.getCurrentUser()
            currentUser = user
            isAuthenticated = true
            return true
        } catch {
            // Token might be expired, try to refresh
            if let refreshToken = keychainManager.getRefreshToken() {
                do {
                    try await refreshAccessToken()
                    return true
                } catch {
                    // Refresh failed, user needs to sign in again
                    await logout()
                    return false
                }
            } else {
                await logout()
                return false
            }
        }
    }

    // MARK: - Refresh Access Token

    func refreshAccessToken() async throws {
        guard let refreshToken = keychainManager.getRefreshToken() else {
            throw AuthError.unauthorized
        }

        do {
            let authResponse = try await BackendService.shared.refreshToken(refreshToken)

            // Save new tokens
            keychainManager.saveAccessToken(authResponse.accessToken)
            keychainManager.saveRefreshToken(authResponse.refreshToken)

            // Update user
            currentUser = authResponse.user
            isAuthenticated = true
        } catch {
            self.error = error
            throw error
        }
    }

    // MARK: - Logout

    func logout() async {
        // Try to logout on backend
        if let refreshToken = keychainManager.getRefreshToken() {
            try? await BackendService.shared.logout(refreshToken: refreshToken)
        }

        // Clear local state
        keychainManager.clearAll()
        isAuthenticated = false
        currentUser = nil
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        try await BackendService.shared.deleteAccount()

        // Clear local state
        keychainManager.clearAll()
        isAuthenticated = false
        currentUser = nil
    }

    // MARK: - Sign in with Email

    func sendVerificationCode(email: String) async throws -> Int {
        do {
            let response = try await BackendService.shared.sendVerificationCode(email: email)
            return response.expiresIn
        } catch {
            self.error = error
            throw error
        }
    }

    func resendVerificationCode(email: String) async throws -> Int {
        do {
            let response = try await BackendService.shared.resendVerificationCode(email: email)
            return response.expiresIn
        } catch {
            self.error = error
            throw error
        }
    }

    func signInWithEmail(email: String, code: String) async throws -> User {
        do {
            let authResponse = try await BackendService.shared.verifyEmailCode(
                email: email,
                code: code
            )

            // Save tokens to Keychain
            keychainManager.saveAccessToken(authResponse.accessToken)
            keychainManager.saveRefreshToken(authResponse.refreshToken)

            // Update state
            isAuthenticated = true
            currentUser = authResponse.user

            return authResponse.user
        } catch {
            self.error = error
            throw error
        }
    }
}
