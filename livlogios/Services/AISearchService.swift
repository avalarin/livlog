//
//  AISearchService.swift
//  livlogios
//
//  Created by Claude Code on 01.02.2026.
//

import Foundation
import UIKit

actor AISearchService {
    static let shared = AISearchService()

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Models

    struct EntryOption: Identifiable {
        let id: String
        let title: String
        let entryType: String
        let year: String?
        let genre: String?
        let author: String?
        let platform: String?
        let description: String
        let imageUrls: [String]
        var downloadedImages: [Data] = []

        var suggestedIcon: String {
            switch entryType.lowercased() {
            case "movie": return "🎬"
            case "book": return "📚"
            case "game": return "🎮"
            default: return "📝"
            }
        }

        var additionalFields: [String: String] {
            var fields: [String: String] = [:]
            if let year = year, !year.isEmpty { fields["Year"] = year }
            if let genre = genre, !genre.isEmpty { fields["Genre"] = genre }
            if let author = author, !author.isEmpty { fields["Author"] = author }
            if let platform = platform, !platform.isEmpty { fields["Platform"] = platform }
            return fields
        }
    }

    private struct EntryOptionDTO: Codable {
        let id: String
        let title: String
        let entryType: String
        let year: String?
        let genre: String?
        let author: String?
        let platform: String?
        let description: String
        let imageUrls: [String]

        func toEntryOption() -> EntryOption {
            EntryOption(
                id: id,
                title: title,
                entryType: entryType,
                year: year,
                genre: genre,
                author: author,
                platform: platform,
                description: description,
                imageUrls: imageUrls
            )
        }
    }

    private struct SearchResponse: Codable {
        let options: [EntryOptionDTO]
    }

    private struct SearchRequest: Codable {
        let query: String
    }

    // MARK: - Search

    func searchOptions(for query: String) async throws -> [EntryOption] {
        let request = SearchRequest(query: query)
        let bodyData = try encoder.encode(request)

        let (data, response) = try await BackendService.shared.makeAuthenticatedRequest(
            path: "/search",
            method: "POST",
            body: bodyData
        )

        // Check for rate limit error
        if response.statusCode == 429 {
            throw AISearchError.rateLimitExceeded
        }

        let searchResponse = try decoder.decode(SearchResponse.self, from: data)
        return searchResponse.options.map { $0.toEntryOption() }
    }

    // MARK: - Image Download

    /// Downloads images for an entry option (up to 3 images)
    func downloadImages(for option: EntryOption) async -> EntryOption {
        var updatedOption = option
        var downloadedImages: [Data] = []

        // Take only first 3 URLs
        let urls = Array(option.imageUrls.prefix(3))

        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                // Add user agent to avoid being blocked
                let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"
                request.addValue(userAgent, forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else { continue }

                // Verify it's actually an image
                if let image = UIImage(data: data),
                   let compressedData = image.jpegData(compressionQuality: 0.8) {
                    downloadedImages.append(compressedData)
                }
            } catch {
                // Skip failed downloads
                print("Failed to download image: \(error.localizedDescription)")
                continue
            }

            // Stop if we have 3 images
            if downloadedImages.count >= 3 { break }
        }

        updatedOption.downloadedImages = downloadedImages
        return updatedOption
    }
}

// MARK: - Errors

enum AISearchError: LocalizedError {
    case rateLimitExceeded

    var errorDescription: String? {
        switch self {
        case .rateLimitExceeded:
            return "You have exceeded your daily AI search limit. Please try again tomorrow."
        }
    }
}
