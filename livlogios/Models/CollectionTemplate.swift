//
//  CollectionTemplate.swift
//  livlogios
//
//  Created by Claude Code on 08.03.2026.
//

import Foundation

struct CollectionTemplate: Codable, Identifiable {
    var id: String { slug }
    let slug: String
    let name: String
    let description: String
    let icon: String
    let color: String
}
