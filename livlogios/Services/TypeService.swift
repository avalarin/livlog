//
//  TypeService.swift
//  livlogios
//
//  Created by Claude Code on 23.02.2026.
//

import Foundation

actor TypeService {
    static let shared = TypeService()

    private let decoder: JSONDecoder

    private init() {
        self.decoder = JSONDecoder()
    }

    func getTypes() async throws -> [EntryTypeModel] {
        let (data, _) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/types",
            method: "GET"
        )
        return try decoder.decode([EntryTypeModel].self, from: data)
    }
}
