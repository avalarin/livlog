//
//  Item.swift
//  livlogios
//
//  Created by avprokopev on 31.12.2025.
//

import Foundation

// MARK: - Collection Role

enum CollectionRole: String, Codable {
    case owner
    case write
    case read

    var canEdit: Bool { self == .owner }
    var canWrite: Bool { self == .owner || self == .write }
}

// MARK: - Collection Member

struct CollectionMember: Codable, Identifiable {
    var id: String { userId }
    let userId: String
    let email: String?
    let displayName: String?
    let role: CollectionRole

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case displayName = "display_name"
        case role
    }
}

// MARK: - Collection Model

struct CollectionModel: Codable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: String
    let allowedEntryTypes: [String]
    let entryCount: Int
    let memberCount: Int
    let myRole: CollectionRole
    let sharedBy: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case color
        case allowedEntryTypes = "allowed_entry_types"
        case entryCount = "entry_count"
        case memberCount = "member_count"
        case myRole = "my_role"
        case sharedBy = "shared_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        name: String,
        icon: String,
        color: String = "dodger-blue",
        allowedEntryTypes: [String] = [],
        entryCount: Int = 0,
        memberCount: Int = 1,
        myRole: CollectionRole = .owner,
        sharedBy: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.allowedEntryTypes = allowedEntryTypes
        self.entryCount = entryCount
        self.memberCount = memberCount
        self.myRole = myRole
        self.sharedBy = sharedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "dodger-blue"
        allowedEntryTypes = try container.decodeIfPresent([String].self, forKey: .allowedEntryTypes) ?? []
        entryCount = try container.decodeIfPresent(Int.self, forKey: .entryCount) ?? 0
        memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount) ?? 1
        myRole = try container.decodeIfPresent(CollectionRole.self, forKey: .myRole) ?? .read
        sharedBy = try container.decodeIfPresent(String.self, forKey: .sharedBy)

        createdAt = try parseISO8601(container.decode(String.self, forKey: .createdAt))
        updatedAt = try parseISO8601(container.decode(String.self, forKey: .updatedAt))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(color, forKey: .color)
        try container.encode(allowedEntryTypes, forKey: .allowedEntryTypes)
        try container.encode(entryCount, forKey: .entryCount)
        try container.encode(memberCount, forKey: .memberCount)
        try container.encode(myRole, forKey: .myRole)
        try container.encodeIfPresent(sharedBy, forKey: .sharedBy)

        // Encode timestamps as ISO8601
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        try container.encode(iso8601Formatter.string(from: createdAt), forKey: .createdAt)
        try container.encode(iso8601Formatter.string(from: updatedAt), forKey: .updatedAt)
    }
}

// MARK: - Collection Statistic

struct CollectionStatistic: Codable, Identifiable {
    let title: String
    let displayValue: String

    var id: String { title }

    enum CodingKeys: String, CodingKey {
        case title
        case displayValue = "display_value"
    }
}

// MARK: - Available Statistic

struct AvailableStatistic: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let isEnabled: Bool
    let position: Int

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case isEnabled = "is_enabled"
        case position
    }

    init(id: String, title: String, description: String, isEnabled: Bool, position: Int) {
        self.id = id
        self.title = title
        self.description = description
        self.isEnabled = isEnabled
        self.position = position
    }
}

// MARK: - Field Definition

struct FieldDefinition: Codable, Equatable {
    let key: String
    let label: String
    let type: String // "string" or "number"

    var isNumber: Bool { type == "number" }
}

// MARK: - Entry Type Model

struct EntryTypeModel: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let fields: [FieldDefinition]
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case fields
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        name: String,
        icon: String,
        fields: [FieldDefinition] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.fields = fields
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        fields = try container.decodeIfPresent([FieldDefinition].self, forKey: .fields) ?? []

        createdAt = try parseISO8601(container.decode(String.self, forKey: .createdAt))
        updatedAt = try parseISO8601(container.decode(String.self, forKey: .updatedAt))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(fields, forKey: .fields)

        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        try container.encode(iso8601Formatter.string(from: createdAt), forKey: .createdAt)
        try container.encode(iso8601Formatter.string(from: updatedAt), forKey: .updatedAt)
    }
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
    let typeID: String?
    let title: String
    let description: String
    let score: ScoreRating
    let date: Date
    let additionalFields: [String: String]
    let images: [ImageMeta]
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case collectionID = "collection_id"
        case typeID = "type_id"
        case title
        case description
        case score
        case date
        case additionalFields = "additional_fields"
        case images
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        collectionID: String?,
        typeID: String? = nil,
        title: String,
        description: String,
        score: ScoreRating,
        date: Date,
        additionalFields: [String: String] = [:],
        images: [ImageMeta] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.collectionID = collectionID
        self.typeID = typeID
        self.title = title
        self.description = description
        self.score = score
        self.date = date
        self.additionalFields = additionalFields
        self.images = images
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        collectionID = try container.decodeIfPresent(String.self, forKey: .collectionID)
        typeID = try container.decodeIfPresent(String.self, forKey: .typeID)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        score = try container.decode(ScoreRating.self, forKey: .score)
        additionalFields = try container.decode([String: String].self, forKey: .additionalFields)
        images = try container.decode([ImageMeta].self, forKey: .images)

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

        createdAt = try parseISO8601(container.decode(String.self, forKey: .createdAt))
        updatedAt = try parseISO8601(container.decode(String.self, forKey: .updatedAt))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(collectionID, forKey: .collectionID)
        try container.encodeIfPresent(typeID, forKey: .typeID)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(score, forKey: .score)
        try container.encode(additionalFields, forKey: .additionalFields)
        try container.encode(images, forKey: .images)

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

// MARK: - Image Metadata Model

struct ImageMeta: Codable, Identifiable {
    let id: String
    let isCover: Bool
    let position: Int
    let hash: String?

    init(id: String, isCover: Bool, position: Int, hash: String? = nil) {
        self.id = id
        self.isCover = isCover
        self.position = position
        self.hash = hash
    }

    enum CodingKeys: String, CodingKey {
        case id
        case isCover = "is_cover"
        case position
        case hash
    }
}

// MARK: - MCP Model

struct MCPStatusResponse: Codable {
    let enabled: Bool
    let url: String?
}

// MARK: - Helpers

private func parseISO8601(_ string: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: string) { return date }
    throw DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: [], debugDescription: "Invalid ISO8601 date: \(string)")
    )
}

// MARK: - Preview Data

#if DEBUG
extension CollectionModel {
    static let previewMyList = CollectionModel(
        id: "my-list", name: "My List", icon: "system:folder", color: "dodger-blue"
    )

    static let previewCollections: [CollectionModel] = [previewMyList]
}

extension EntryTypeModel {
    static let previewMovie = EntryTypeModel(id: "movie", name: "Movie", icon: "🎬", fields: [
        FieldDefinition(key: "Year", label: "Year", type: "number"),
        FieldDefinition(key: "Genre", label: "Genre", type: "string")
    ])
    static let previewBook = EntryTypeModel(id: "book", name: "Book", icon: "📚", fields: [
        FieldDefinition(key: "Year", label: "Year", type: "number"),
        FieldDefinition(key: "Author", label: "Author", type: "string")
    ])
    static let previewGame = EntryTypeModel(id: "game", name: "Game", icon: "🎮", fields: [
        FieldDefinition(key: "Year", label: "Year", type: "number"),
        FieldDefinition(key: "Platform", label: "Platform", type: "string")
    ])
    static let previewShow = EntryTypeModel(id: "show", name: "Show", icon: "📺", fields: [
        FieldDefinition(key: "Year", label: "Year", type: "number"),
        FieldDefinition(key: "Genre", label: "Genre", type: "string")
    ])
    static let previewMusic = EntryTypeModel(id: "music", name: "Music", icon: "🎵", fields: [
        FieldDefinition(key: "Year", label: "Year", type: "number"),
        FieldDefinition(key: "Artist", label: "Artist", type: "string")
    ])
    static let previewOther = EntryTypeModel(id: "other", name: "Other", icon: "📝")
    static let previewTypes: [EntryTypeModel] = [
        previewMovie, previewBook, previewGame, previewShow, previewMusic, previewOther
    ]
}

extension EntryModel {
    static let previewItems: [EntryModel] = [
        EntryModel(
            id: "1", collectionID: "my-list", typeID: "movie", title: "Inception",
            description: "A sci-fi heist thriller about a thief who steals secrets from dreams, "
                + "tasked with planting an idea in a target's mind through layered dream worlds.",
            score: .great, date: .now, additionalFields: ["Year": "2010", "Genre": "Sci-Fi"],
            images: [ImageMeta(id: "00000000-0000-0000-0001-000000000001", isCover: true, position: 0)]
        ),
        EntryModel(
            id: "2", collectionID: "my-list", typeID: "book", title: "One Thousand Eight Hundred Eighty-Four",
            description: "Orwell's bleak dystopia of a totalitarian state that controls through "
                + "surveillance, propaganda, and the erosion of individual freedom.",
            score: .great, date: .now.addingTimeInterval(-86400 * 5),
            additionalFields: ["Year": "1949", "Author": "George Orwell"],
            images: [ImageMeta(id: "00000000-0000-0000-0001-000000000002", isCover: true, position: 0)]
        ),
        EntryModel(
            id: "3", collectionID: "my-list", typeID: "game", title: "Elden Ring",
            description: "A demanding open-world adventure that doesn't shy away from testing your patience and skill, "
                + "but pays you back with memorable discoveries and the satisfaction of overcoming obstacles.",
            score: .great, date: .now.addingTimeInterval(-86400 * 14),
            additionalFields: ["Year": "2022", "Platform": "PC"],
            images: [ImageMeta(id: "00000000-0000-0000-0001-000000000003", isCover: true, position: 0)]
        ),
        EntryModel(
            id: "4", collectionID: "my-list", typeID: "movie", title: "Dune",
            description: "Dune",
            score: .great, date: .now.addingTimeInterval(-86400 * 2),
            additionalFields: ["Year": "1965", "Genre": "Sci-Fi", "Author": "Frank Herbert"],
            images: []
        ),
        EntryModel(
            id: "5", collectionID: "my-list", typeID: "movie", title: "The Dark Knight",
            description: "Heath Ledger's Joker is widely regarded as an iconic performance, bringing a chilling mix "
                + "of unpredictability, dark humor, and menace that lingers long after the film ends.",
            score: .great, date: .now.addingTimeInterval(-86400 * 2),
            additionalFields: ["Year": "2008", "Genre": "Action"],
            images: [ImageMeta(id: "00000000-0000-0000-0001-000000000004", isCover: true, position: 0)]
        ),
        EntryModel(
            id: "6", collectionID: "my-list", typeID: nil, title: "Concert: Radiohead",
            description: "Amazing live performance, goosebumps throughout.",
            score: .great, date: .now.addingTimeInterval(-86400 * 30),
            images: [ImageMeta(id: "00000000-0000-0000-0001-000000000005", isCover: true, position: 0)]
        )
    ]
}

extension CollectionStatistic {
    static let previewItems: [CollectionStatistic] = [
        CollectionStatistic(title: "Total", displayValue: "6"),
        CollectionStatistic(title: "Backlog", displayValue: "0"),
        CollectionStatistic(title: "Last Entry", displayValue: "Mar 21, 2026")
    ]
}

extension AvailableStatistic {
    static let previewItems: [AvailableStatistic] = [
        AvailableStatistic(id: "total_entries", title: "Total", description: "Total number of entries", isEnabled: true, position: 0),
        AvailableStatistic(id: "backlog", title: "Backlog", description: "Entries not yet rated", isEnabled: true, position: 1),
        AvailableStatistic(id: "last_entry", title: "Last Entry", description: "Date of the most recent entry", isEnabled: true, position: 2),
        AvailableStatistic(id: "top_genre", title: "Top Genre", description: "Most frequent genre", isEnabled: false, position: -1),
        AvailableStatistic(id: "avg_score", title: "Avg Score", description: "Average rating", isEnabled: false, position: -1),
    ]
}
#endif
