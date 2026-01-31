//
//  OpenAIService.swift
//  livlogios
//
//  Created by avprokopev on 31.12.2025.
//

import Foundation
import UIKit

struct OpenAIService {
    private static let apiKey = "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"
    private static let baseURL = "https://openrouter.ai/api/v1/chat/completions"
    
    struct EntryOption: Identifiable {
        let id = UUID()
        let title: String
        let entryType: String
        let year: String?
        let genre: String?
        let author: String?
        let platform: String?
        let summaryLine: String
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
    
    // Decodable version for parsing JSON
    private struct EntryOptionDTO: Decodable {
        let title: String
        let entryType: String
        let year: String?
        let genre: String?
        let author: String?
        let platform: String?
        let summaryLine: String?
        let description: String
        let imageUrls: [String]?

        func toEntryOption() -> EntryOption {
            EntryOption(
                title: title,
                entryType: entryType,
                year: year,
                genre: genre,
                author: author,
                platform: platform,
                summaryLine: summaryLine ?? "",
                description: description,
                imageUrls: imageUrls ?? []
            )
        }
    }
    
    private struct OptionsResponseDTO: Decodable {
        let options: [EntryOptionDTO]
    }
    
    // swiftlint:disable line_length
    static func searchOptions(for query: String) async throws -> [EntryOption] {
        let prompt = """
        User is searching for: "\(query)"

        Search and find what this might be. It could be a movie, book, game, or something else.
        Return up to 5 most relevant options as JSON array.

        For each option provide:
        - title: the exact title
        - entryType: one of "movie", "book", "game", or "custom"
        - year: release/publication year (if applicable)
        - genre: genre(s)
        - author: author name (for books only, null otherwise)
        - platform: gaming platform (for games only, null otherwise)
        - summaryLine: a short one-line summary with the most important info, tailored to its type. Examples: for movies "2023 • Sci-Fi, Thriller • Christopher Nolan", for books "2020 • Fantasy • Brandon Sanderson", for games "2022 • RPG • PlayStation 5, PC". Use bullet separator •
        - description: brief 1-2 sentence description
        - imageUrls: array of up to 3 image URLs (posters, covers, screenshots) - direct links to images

        Return ONLY valid JSON in this exact format, no markdown, no extra text:
        {"options": [{"title": "...", "entryType": "...", "year": "...", "genre": "...", "author": null, "platform": null, "summaryLine": "...", "description": "...", "imageUrls": ["url1", "url2"]}]}
        """
        // swiftlint:enable line_length
        
        let requestBody: [String: Any] = [
            "model": "perplexity/sonar",
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]
        
        guard let url = URL(string: baseURL) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("livlogios", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        
        // Parse OpenRouter response (OpenAI-compatible format)
        let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        
        guard let content = chatResponse.choices.first?.message.content else {
            throw APIError.noContent
        }
        
        // Parse the JSON from the text
        let cleanedText = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleanedText.data(using: .utf8) else {
            throw APIError.invalidJSON
        }
        
        let optionsResponse = try JSONDecoder().decode(OptionsResponseDTO.self, from: jsonData)
        return optionsResponse.options.map { $0.toEntryOption() }
    }
    
    /// Downloads images for an entry option (up to 3 images)
    static func downloadImages(for option: EntryOption) async -> EntryOption {
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
                request.addValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
                
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

// MARK: - OpenRouter API Response Models (OpenAI-compatible)

struct ChatCompletionResponse: Decodable {
    let choices: [Choice]
}

struct Choice: Decodable {
    let message: Message
}

struct Message: Decodable {
    let content: String?
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case noContent
    case invalidJSON
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let statusCode, let message):
            return "API Error (\(statusCode)): \(message)"
        case .noContent:
            return "No content in response"
        case .invalidJSON:
            return "Could not parse response"
        }
    }
}
