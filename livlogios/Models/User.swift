//
//  User.swift
//  livlogios
//
//  Created by Claude Code on 31.01.2026.
//

import Foundation

struct User: Codable, Identifiable {
    let id: UUID
    let email: String?
    let displayName: String?
    let emailVerified: Bool
    let authProviders: [String]
    let createdAt: Date
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case emailVerified = "email_verified"
        case authProviders = "auth_providers"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

struct PersonNameComponents: Codable {
    let givenName: String?
    let familyName: String?

    enum CodingKeys: String, CodingKey {
        case givenName = "given_name"
        case familyName = "family_name"
    }
}

enum AuthError: Error, LocalizedError {
    case canceled
    case invalidToken
    case unauthorized
    case networkError
    case serverError(String)
    case invalidEmail
    case invalidVerificationCode
    case verificationCodeExpired
    case rateLimitExceeded(retryAfter: Int?)
    case unknown

    var errorDescription: String? {
        switch self {
        case .canceled:
            return "Sign in was canceled"
        case .invalidToken:
            return "Invalid authentication token"
        case .unauthorized:
            return "Session expired, please sign in again"
        case .networkError:
            return "Network error, please try again"
        case .serverError(let message):
            return message
        case .invalidEmail:
            return "Please enter a valid email address"
        case .invalidVerificationCode:
            return "Invalid verification code"
        case .verificationCodeExpired:
            return "Verification code expired, please request a new one"
        case .rateLimitExceeded(let seconds):
            if let seconds = seconds {
                return "Too many requests. Please wait \(seconds) seconds"
            }
            return "Too many requests. Please try again later"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

struct SendCodeResponse: Codable {
    let message: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case message
        case expiresIn = "expires_in"
    }
}
