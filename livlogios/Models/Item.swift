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
    let entryCount: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case entryCount = "entry_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(id: String, name: String, icon: String, entryCount: Int = 0, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.icon = icon
        self.entryCount = entryCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        entryCount = try container.decodeIfPresent(Int.self, forKey: .entryCount) ?? 0

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
        try container.encode(entryCount, forKey: .entryCount)

        // Encode timestamps as ISO8601
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        try container.encode(iso8601Formatter.string(from: createdAt), forKey: .createdAt)
        try container.encode(iso8601Formatter.string(from: updatedAt), forKey: .updatedAt)
    }
}

// MARK: - Entry Type Model

struct EntryTypeModel: Codable, Identifiable {
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

    init(id: String, name: String, icon: String, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.icon = icon
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)

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

    init(id: String, isCover: Bool, position: Int) {
        self.id = id
        self.isCover = isCover
        self.position = position
    }

    enum CodingKeys: String, CodingKey {
        case id
        case isCover = "is_cover"
        case position
    }
}

// MARK: - Preview Data

#if DEBUG
extension CollectionModel {
    static let previewMyList = CollectionModel(id: "my-list", name: "My List", icon: "📋")

    static let previewCollections: [CollectionModel] = [previewMyList]
}

extension EntryTypeModel {
    static let previewMovie = EntryTypeModel(id: "movie", name: "Movie", icon: "🎬")
    static let previewBook = EntryTypeModel(id: "book", name: "Book", icon: "📚")
    static let previewGame = EntryTypeModel(id: "game", name: "Game", icon: "🎮")
    static let previewTypes: [EntryTypeModel] = [previewMovie, previewBook, previewGame]
}

extension EntryModel {
    static let previewItems: [EntryModel] = [
        EntryModel(
            id: "1", collectionID: "my-list", typeID: "movie", title: "Inception",
            description: "Inception (2010) is a sci-fi heist thriller in which Dom Cobb, a skilled thief who steals secrets from inside people's dreams, is offered a chance to clear his criminal record. His team must attempt the harder task of inception - planting an idea in a target's mind - by entering layered dream worlds with shifting rules and unstable physics. As the dreams deepen, time stretches and reality becomes harder to distinguish from illusion. The film explores memory, guilt, and perception, building to an ambiguous ending.",
            score: .great, date: .now, additionalFields: ["Year": "2010", "Genre": "Sci-Fi"],
            images: [ImageMeta(id: "00000000-0000-0000-0001-000000000001", isCover: true, position: 0)]
        ),
        EntryModel(
            id: "2", collectionID: "my-list", typeID: "book", title: "One Thousand Eight Hundred Eighty-Four",
            description: "Orwell presents a bleak dystopian vision of a future shaped by an all-powerful totalitarian state—one that maintains control through constant surveillance, relentless propaganda, and the steady erosion of individual freedom, privacy, and independent thought.",
            score: .great, date: .now.addingTimeInterval(-86400 * 5),
            additionalFields: ["Year": "1949", "Author": "George Orwell"],
            images: [ImageMeta(id: "00000000-0000-0000-0001-000000000002", isCover: true, position: 0)]
        ),
        EntryModel(
            id: "3", collectionID: "my-list", typeID: "game", title: "Elden Ring",
            description: "A demanding open-world adventure that doesn't shy away from testing your patience and skill, but pays you back in a big way with a strong sense of progress, memorable discoveries, and the satisfaction of overcoming obstacles through persistence and smart choices.",
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
            description: "Heath Ledger's Joker is widely regarded as an iconic performance, bringing a chilling mix of unpredictability, dark humor, and menace to the character while giving him a strangely compelling presence that lingers long after the film ends.",
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
#endif
