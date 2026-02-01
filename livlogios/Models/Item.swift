//
//  Item.swift
//  livlogios
//
//  Created by avprokopev on 31.12.2025.
//

import Foundation

// MARK: - Collection Model

struct CollectionModel: Codable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)

        // Decode ISO8601 timestamps
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        if let parsedCreatedAt = iso8601Formatter.date(from: createdAtString) {
            createdAt = parsedCreatedAt
        } else {
            iso8601Formatter.formatOptions = [.withInternetDateTime]
            guard let parsedCreatedAt = iso8601Formatter.date(from: createdAtString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .createdAt,
                    in: container,
                    debugDescription: "CreatedAt string does not match ISO8601 format"
                )
            }
            createdAt = parsedCreatedAt
        }

        let updatedAtString = try container.decode(String.self, forKey: .updatedAt)
        if let parsedUpdatedAt = iso8601Formatter.date(from: updatedAtString) {
            updatedAt = parsedUpdatedAt
        } else {
            iso8601Formatter.formatOptions = [.withInternetDateTime]
            guard let parsedUpdatedAt = iso8601Formatter.date(from: updatedAtString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .updatedAt,
                    in: container,
                    debugDescription: "UpdatedAt string does not match ISO8601 format"
                )
            }
            updatedAt = parsedUpdatedAt
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)

        // Encode timestamps as ISO8601
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        try container.encode(iso8601Formatter.string(from: createdAt), forKey: .createdAt)
        try container.encode(iso8601Formatter.string(from: updatedAt), forKey: .updatedAt)
    }
}

extension CollectionModel {
    static let defaultCollections: [(name: String, icon: String)] = [
        ("Movies", "🎬"),
        ("Books", "📚"),
        ("Games", "🎮")
    ]
}

// MARK: - Score Rating

enum ScoreRating: Int, Codable, CaseIterable, Identifiable {
    case undecided = 0
    case bad = 1
    case okay = 2
    case great = 3

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .undecided: return "🆕"
        case .bad: return "👎"
        case .okay: return "👌"
        case .great: return "🤩"
        }
    }

    var label: String {
        switch self {
        case .undecided: return "Undecided, ask me later"
        case .bad: return "Not my thing at all"
        case .okay: return "Fine for once"
        case .great: return "Absolutely unhinged"
        }
    }
}

// MARK: - Entry Model

struct EntryModel: Codable, Identifiable {
    let id: String
    let collectionID: String?
    let title: String
    let description: String
    let score: ScoreRating
    let date: Date
    let additionalFields: [String: String]
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case collectionID = "collection_id"
        case title
        case description
        case score
        case date
        case additionalFields = "additional_fields"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        collectionID = try container.decodeIfPresent(String.self, forKey: .collectionID)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        score = try container.decode(ScoreRating.self, forKey: .score)
        additionalFields = try container.decode([String: String].self, forKey: .additionalFields)

        // Decode date field (YYYY-MM-DD format)
        let dateString = try container.decode(String.self, forKey: .date)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        guard let parsedDate = dateFormatter.date(from: dateString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .date,
                in: container,
                debugDescription: "Date string does not match expected format yyyy-MM-dd"
            )
        }
        date = parsedDate

        // Decode ISO8601 timestamps
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        if let parsedCreatedAt = iso8601Formatter.date(from: createdAtString) {
            createdAt = parsedCreatedAt
        } else {
            iso8601Formatter.formatOptions = [.withInternetDateTime]
            guard let parsedCreatedAt = iso8601Formatter.date(from: createdAtString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .createdAt,
                    in: container,
                    debugDescription: "CreatedAt string does not match ISO8601 format"
                )
            }
            createdAt = parsedCreatedAt
        }

        let updatedAtString = try container.decode(String.self, forKey: .updatedAt)
        if let parsedUpdatedAt = iso8601Formatter.date(from: updatedAtString) {
            updatedAt = parsedUpdatedAt
        } else {
            iso8601Formatter.formatOptions = [.withInternetDateTime]
            guard let parsedUpdatedAt = iso8601Formatter.date(from: updatedAtString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .updatedAt,
                    in: container,
                    debugDescription: "UpdatedAt string does not match ISO8601 format"
                )
            }
            updatedAt = parsedUpdatedAt
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(collectionID, forKey: .collectionID)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(score, forKey: .score)
        try container.encode(additionalFields, forKey: .additionalFields)

        // Encode date as YYYY-MM-DD
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        try container.encode(dateFormatter.string(from: date), forKey: .date)

        // Encode timestamps as ISO8601
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        try container.encode(iso8601Formatter.string(from: createdAt), forKey: .createdAt)
        try container.encode(iso8601Formatter.string(from: updatedAt), forKey: .updatedAt)
    }
}

// MARK: - Entry Image Model

struct EntryImage: Codable, Identifiable {
    let id: String
    let data: String // base64 encoded
    let isCover: Bool
    let position: Int

    enum CodingKeys: String, CodingKey {
        case id
        case data
        case isCover = "is_cover"
        case position
    }
}
