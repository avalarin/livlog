//
//  CollectionService.swift
//  livlogios
//
//  Created by Claude Code on 01.02.2026.
//

import Foundation

actor CollectionService {
    static let shared = CollectionService()

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Get Collections

    func getCollections() async throws -> [CollectionModel] {
        let (data, _) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/collections",
            method: "GET"
        )

        return try decoder.decode([CollectionModel].self, from: data)
    }

    // MARK: - Create Collection

    func createCollection(name: String, icon: String) async throws -> CollectionModel {
        struct Request: Codable {
            let name: String
            let icon: String
        }

        let request = Request(name: name, icon: icon)
        let bodyData = try encoder.encode(request)

        let (data, _) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/collections",
            method: "POST",
            body: bodyData
        )

        return try decoder.decode(CollectionModel.self, from: data)
    }

    // MARK: - Create Default Collections

    func createDefaultCollections() async throws -> [CollectionModel] {
        let (data, _) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/collections/default",
            method: "POST"
        )

        return try decoder.decode([CollectionModel].self, from: data)
    }

    // MARK: - Update Collection

    func updateCollection(id: String, name: String, icon: String) async throws -> CollectionModel {
        struct Request: Codable {
            let name: String
            let icon: String
        }

        let request = Request(name: name, icon: icon)
        let bodyData = try encoder.encode(request)

        let (data, _) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/collections/\(id)",
            method: "PUT",
            body: bodyData
        )

        return try decoder.decode(CollectionModel.self, from: data)
    }

    // MARK: - Delete Collection

    func deleteCollection(id: String) async throws {
        _ = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/collections/\(id)",
            method: "DELETE"
        )
    }
}
