//
//  OnboardingService.swift
//  livlogios
//
//  Created by Claude Code on 08.03.2026.
//

import Foundation

actor OnboardingService {
    static let shared = OnboardingService()

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Get Templates

    func getTemplates() async throws -> [CollectionTemplate] {
        let (data, _) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/onboarding/templates",
            method: "GET"
        )
        return try decoder.decode([CollectionTemplate].self, from: data)
    }

    // MARK: - Update Display Name

    func updateDisplayName(_ name: String) async throws {
        struct Request: Codable {
            let displayName: String

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
            }
        }

        let request = Request(displayName: name)
        let bodyData = try encoder.encode(request)

        _ = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/users/me/display-name",
            method: "PUT",
            body: bodyData
        )
    }

    // MARK: - Create Collection from Template

    func createFromTemplate(slug: String, includeEntries: Bool) async throws {
        struct Request: Codable {
            let includeEntries: Bool

            enum CodingKeys: String, CodingKey {
                case includeEntries = "include_entries"
            }
        }

        let request = Request(includeEntries: includeEntries)
        let bodyData = try encoder.encode(request)

        _ = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/collections/from-template/\(slug)",
            method: "POST",
            body: bodyData
        )
    }

    // MARK: - Complete Onboarding

    func completeOnboarding() async throws {
        _ = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/onboarding/complete",
            method: "POST",
            body: "{}".data(using: .utf8)
        )
    }
}
