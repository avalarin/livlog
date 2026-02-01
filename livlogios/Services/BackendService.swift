//
//  BackendService.swift
//  livlogios
//
//  Created by avprokopev on 31.01.2026.
//

import Foundation

struct DatabaseStatus: Decodable {
    let status: String
    let pingMs: Int

    enum CodingKeys: String, CodingKey {
        case status
        case pingMs = "ping_ms"
    }
}

struct HealthResponse: Decodable {
    let status: String
    let timestamp: String
    let version: String
    let uptime: String
    let database: DatabaseStatus

    var isHealthy: Bool {
        status == "ok" && database.status == "connected"
    }
}

actor BackendService {
    static let shared = BackendService()

    private let baseURL: String
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        self.baseURL = AppConfig.baseURL ?? "http://localhost:8080/api/v1"

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Health Check

    func checkHealth() async -> Bool {
        guard let url = AppConfig.healthCheckURL else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            let healthResponse = try decoder.decode(HealthResponse.self, from: data)
            return healthResponse.isHealthy
        } catch {
            return false
        }
    }

    // MARK: - Private Request Helper

    private func makeRequest(
        path: String,
        method: String,
        body: Data? = nil,
        includeAuth: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw AuthError.networkError
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30

        // Add authorization header if available
        if includeAuth, let token = KeychainManager.shared.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }

        // Handle errors
        if httpResponse.statusCode == 401 {
            throw AuthError.unauthorized
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw AuthError.rateLimitExceeded(retryAfter: retryAfter)
        }

        if httpResponse.statusCode >= 400 {
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                throw AuthError.serverError(errorResponse.message)
            }
            throw AuthError.serverError("Server error: \(httpResponse.statusCode)")
        }

        return (data, httpResponse)
    }

    // MARK: - Auth Endpoints

    func appleAuth(
        identityToken: String,
        authorizationCode: String?,
        fullName: PersonNameComponents?,
        email: String?
    ) async throws -> AuthResponse {
        let requestBody = AppleAuthRequest(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            fullName: fullName,
            email: email
        )

        let bodyData = try encoder.encode(requestBody)
        let (data, _) = try await makeRequest(
            path: "/auth/apple",
            method: "POST",
            body: bodyData,
            includeAuth: false
        )

        return try decoder.decode(AuthResponse.self, from: data)
    }

    func refreshToken(_ refreshToken: String) async throws -> AuthResponse {
        let requestBody = RefreshTokenRequest(refreshToken: refreshToken)
        let bodyData = try encoder.encode(requestBody)

        let (data, _) = try await makeRequest(
            path: "/auth/refresh",
            method: "POST",
            body: bodyData,
            includeAuth: false
        )

        return try decoder.decode(AuthResponse.self, from: data)
    }

    func logout(refreshToken: String) async throws {
        let requestBody = LogoutRequest(refreshToken: refreshToken)
        let bodyData = try encoder.encode(requestBody)

        _ = try await makeRequest(
            path: "/auth/logout",
            method: "POST",
            body: bodyData,
            includeAuth: true
        )
    }

    func getCurrentUser() async throws -> User {
        let (data, _) = try await makeRequest(
            path: "/auth/me",
            method: "GET",
            includeAuth: true
        )

        return try decoder.decode(User.self, from: data)
    }

    func deleteAccount() async throws {
        _ = try await makeRequest(
            path: "/auth/account",
            method: "DELETE",
            includeAuth: true
        )
    }

    // MARK: - Email Auth Endpoints

    func sendVerificationCode(email: String) async throws -> SendCodeResponse {
        let requestBody = SendCodeRequest(email: email)
        let bodyData = try encoder.encode(requestBody)

        let (data, _) = try await makeRequest(
            path: "/auth/email/send-code",
            method: "POST",
            body: bodyData,
            includeAuth: false
        )

        return try decoder.decode(SendCodeResponse.self, from: data)
    }

    func resendVerificationCode(email: String) async throws -> SendCodeResponse {
        let requestBody = ResendCodeRequest(email: email)
        let bodyData = try encoder.encode(requestBody)

        let (data, _) = try await makeRequest(
            path: "/auth/email/resend-code",
            method: "POST",
            body: bodyData,
            includeAuth: false
        )

        return try decoder.decode(SendCodeResponse.self, from: data)
    }

    func verifyEmailCode(email: String, code: String) async throws -> AuthResponse {
        let requestBody = VerifyCodeRequest(email: email, code: code)
        let bodyData = try encoder.encode(requestBody)

        let (data, _) = try await makeRequest(
            path: "/auth/email/verify",
            method: "POST",
            body: bodyData,
            includeAuth: false
        )

        return try decoder.decode(AuthResponse.self, from: data)
    }
}

// MARK: - Request/Response Models

private struct AppleAuthRequest: Codable {
    let identityToken: String
    let authorizationCode: String?
    let fullName: PersonNameComponents?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case authorizationCode = "authorization_code"
        case fullName = "full_name"
        case email
    }
}

private struct RefreshTokenRequest: Codable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct LogoutRequest: Codable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct ErrorResponse: Codable {
    let error: String
    let message: String
}

private struct SendCodeRequest: Codable {
    let email: String
}

private struct ResendCodeRequest: Codable {
    let email: String
}

private struct VerifyCodeRequest: Codable {
    let email: String
    let code: String
}
