//
//  Item.swift
//  livlogios
//
//  Created by avprokopev on 31.12.2025.
//

import Foundation
import SwiftData

// MARK: - Collection Model

@Model
final class Collection {
    var name: String
    var icon: String  // emoji
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \Item.collection)
    var items: [Item] = []
    
    init(name: String, icon: String = "📁") {
        self.name = name
        self.icon = icon
        self.createdAt = Date()
    }
}

extension Collection {
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

// MARK: - Item Model

@Model
final class Item {
    var collection: Collection?
    var title: String
    var entryDescription: String
    var score: ScoreRating
    var date: Date
    var createdAt: Date
    
    /// Dynamic additional fields (key: field name, value: field value)
    var additionalFields: [String: String] = [:]
    
    /// Images stored as Data (1-3 images)
    var images: [Data] = []
    
    init(
        collection: Collection?,
        title: String,
        entryDescription: String = "",
        score: ScoreRating,
        date: Date = Date(),
        additionalFields: [String: String] = [:],
        images: [Data] = []
    ) {
        self.collection = collection
        self.title = title
        self.entryDescription = entryDescription
        self.score = score
        self.date = date
        self.createdAt = Date()
        self.additionalFields = additionalFields
        self.images = images
    }
}
