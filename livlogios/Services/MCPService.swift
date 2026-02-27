//
//  MCPService.swift
//  livlogios
//

import Foundation

actor MCPService {
    static let shared = MCPService()

    private let decoder: JSONDecoder

    private init() {
        self.decoder = JSONDecoder()
    }

    // MARK: - Get Status

    func getStatus() async throws -> MCPStatusResponse {
        let (data, _) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/mcp",
            method: "GET"
        )
        return try decoder.decode(MCPStatusResponse.self, from: data)
    }

    // MARK: - Enable

    func enable() async throws -> MCPStatusResponse {
        let (data, _) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/mcp",
            method: "POST"
        )
        return try decoder.decode(MCPStatusResponse.self, from: data)
    }

    // MARK: - Disable

    func disable() async throws {
        _ = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/mcp",
            method: "DELETE"
        )
    }
}
