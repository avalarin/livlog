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

    // MARK: - Complete Onboarding

    func completeOnboarding(displayName: String, templateSlug: String?) async throws {
        struct Request: Codable {
            let displayName: String
            let templateSlug: String?

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
                case templateSlug = "template_slug"
            }
        }

        let request = Request(displayName: displayName, templateSlug: templateSlug)
        let bodyData = try encoder.encode(request)

        _ = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/onboarding/complete",
            method: "POST",
            body: bodyData
        )
    }
}
