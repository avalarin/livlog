//
//  EntryService.swift
//  livlogios
//
//  Created by Claude Code on 01.02.2026.
//

import Foundation

actor EntryService {
    static let shared = EntryService()

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Get Entries

    func getEntries(collectionID: String? = nil, limit: Int = 50, offset: Int = 0) async throws -> [EntryModel] {
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]

        if let collectionID = collectionID {
            queryItems.append(URLQueryItem(name: "collection_id", value: collectionID))
        }

        var components = URLComponents()
        components.queryItems = queryItems
        let queryString = components.url?.query ?? ""

        let (data, _) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/entries?\(queryString)",
            method: "GET"
        )

        return try decoder.decode([EntryModel].self, from: data)
    }

    // MARK: - Search Entries

    func searchEntries(query: String, limit: Int = 50, offset: Int = 0) async throws -> [EntryModel] {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]
        let queryString = components.url?.query ?? ""

        let (data, _) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/entries/search?\(queryString)",
            method: "GET"
        )

        return try decoder.decode([EntryModel].self, from: data)
    }

    // MARK: - Get Entry

    func getEntry(id: String) async throws -> EntryModel {
        let (data, _) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/entries/\(id)",
            method: "GET"
        )

        return try decoder.decode(EntryModel.self, from: data)
    }

    // MARK: - Create Entry

    func createEntry(
        collectionID: String?,
        typeID: String? = nil,
        title: String,
        description: String,
        score: ScoreRating,
        date: Date,
        additionalFields: [String: String],
        imageData: [Data],
        seedImageIDs: [String] = []
    ) async throws -> EntryModel {
        struct ImageData: Codable {
            let data: String
            let isCover: Bool
            let position: Int

            enum CodingKeys: String, CodingKey {
                case data
                case isCover = "is_cover"
                case position
            }
        }

        struct Request: Codable {
            let collectionID: String?
            let typeID: String?
            let title: String
            let description: String
            let score: Int
            let date: String
            let additionalFields: [String: String]
            let images: [ImageData]
            let seedImageIDs: [String]

            enum CodingKeys: String, CodingKey {
                case collectionID = "collection_id"
                case typeID = "type_id"
                case title
                case description
                case score
                case date
                case additionalFields = "additional_fields"
                case images
                case seedImageIDs = "seed_image_ids"
            }
        }

        // Convert images to base64
        let images = imageData.enumerated().map { index, data in
            ImageData(
                data: data.base64EncodedString(),
                isCover: index == 0,
                position: index
            )
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let request = Request(
            collectionID: collectionID,
            typeID: typeID,
            title: title,
            description: description,
            score: score.rawValue,
            date: dateFormatter.string(from: date),
            additionalFields: additionalFields,
            images: images,
            seedImageIDs: seedImageIDs
        )

        let bodyData = try encoder.encode(request)

        let (data, _) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/entries",
            method: "POST",
            body: bodyData
        )

        return try decoder.decode(EntryModel.self, from: data)
    }

    // MARK: - Update Entry

    func updateEntry(
        id: String,
        collectionID: String?,
        typeID: String? = nil,
        title: String,
        description: String,
        score: ScoreRating,
        date: Date,
        additionalFields: [String: String],
        imageData: [Data]?
    ) async throws -> EntryModel {
        struct ImageData: Codable {
            let data: String
            let isCover: Bool
            let position: Int

            enum CodingKeys: String, CodingKey {
                case data
                case isCover = "is_cover"
                case position
            }
        }

        struct Request: Codable {
            let collectionID: String?
            let typeID: String?
            let title: String
            let description: String
            let score: Int
            let date: String
            let additionalFields: [String: String]
            let images: [ImageData]?

            enum CodingKeys: String, CodingKey {
                case collectionID = "collection_id"
                case typeID = "type_id"
                case title
                case description
                case score
                case date
                case additionalFields = "additional_fields"
                case images
            }
        }

        // Convert images to base64 if provided
        let images: [ImageData]? = imageData?.enumerated().map { index, data in
            ImageData(
                data: data.base64EncodedString(),
                isCover: index == 0,
                position: index
            )
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let request = Request(
            collectionID: collectionID,
            typeID: typeID,
            title: title,
            description: description,
            score: score.rawValue,
            date: dateFormatter.string(from: date),
            additionalFields: additionalFields,
            images: images
        )

        let bodyData = try encoder.encode(request)

        let (data, _) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/entries/\(id)",
            method: "PUT",
            body: bodyData
        )

        return try decoder.decode(EntryModel.self, from: data)
    }

    // MARK: - Delete Entry

    func deleteEntry(id: String) async throws {
        _ = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/entries/\(id)",
            method: "DELETE"
        )
    }

    // MARK: - Bulk Delete Entries

    func bulkDeleteEntries(ids: [String]) async throws {
        struct BulkDeleteRequest: Encodable {
            let ids: [String]
        }
        let body = try encoder.encode(BulkDeleteRequest(ids: ids))
        let (_, response) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/entries",
            method: "DELETE",
            body: body
        )
        guard response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Get Image

    func getImage(imageID: String) async throws -> Data {
        let (data, _) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/images/\(imageID)",
            method: "GET"
        )

        return data
    }
}
