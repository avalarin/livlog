//
//  livlogiosTests.swift
//  livlogiosTests
//
//  Created by avprokopev on 31.12.2025.
//

import Foundation
@testable import livlogios
import Testing

struct livlogiosTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func testCollectionModelDecoding() async throws {
        // Test decoding a collection response from the backend
        let jsonString = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "name": "Movies",
            "icon": "🎬",
            "created_at": "2024-02-01T10:30:45Z",
            "updated_at": "2024-02-01T10:30:45Z"
        }
        """

        guard let jsonData = jsonString.data(using: .utf8) else {
            #expect(Bool(false), "Failed to convert string to data")
            return
        }
        let decoder = JSONDecoder()

        let collection = try decoder.decode(CollectionModel.self, from: jsonData)

        #expect(collection.id == "123e4567-e89b-12d3-a456-426614174000")
        #expect(collection.name == "Movies")
        #expect(collection.icon == "🎬")
    }

    @Test func testEntryModelDecoding() async throws {
        // Test decoding an entry response from the backend
        let jsonString = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174001",
            "collection_id": "123e4567-e89b-12d3-a456-426614174000",
            "title": "The Matrix",
            "description": "A great sci-fi movie",
            "score": 3,
            "date": "2024-02-01",
            "additional_fields": {
                "Year": "1999",
                "Genre": "Sci-Fi"
            },
            "images": [
                {"id": "img-id-1", "is_cover": true, "position": 0},
                {"id": "img-id-2", "is_cover": false, "position": 1}
            ],
            "created_at": "2024-02-01T10:30:45Z",
            "updated_at": "2024-02-01T10:30:45Z"
        }
        """

        guard let jsonData = jsonString.data(using: .utf8) else {
            #expect(Bool(false), "Failed to convert string to data")
            return
        }
        let decoder = JSONDecoder()

        let entry = try decoder.decode(EntryModel.self, from: jsonData)

        #expect(entry.id == "123e4567-e89b-12d3-a456-426614174001")
        #expect(entry.collectionID == "123e4567-e89b-12d3-a456-426614174000")
        #expect(entry.title == "The Matrix")
        #expect(entry.description == "A great sci-fi movie")
        #expect(entry.score == .great)
        #expect(entry.additionalFields["Year"] == "1999")
        #expect(entry.additionalFields["Genre"] == "Sci-Fi")
        #expect(entry.images.count == 2)
        #expect(entry.images[0].id == "img-id-1")
        #expect(entry.images[0].isCover == true)
        #expect(entry.images[1].id == "img-id-2")
        #expect(entry.images[1].position == 1)
    }

    @Test func testEntryModelDecodingWithTimezone() async throws {
        // Test decoding an entry with timezone offset instead of Z
        let jsonString = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174001",
            "collection_id": null,
            "title": "Test Entry",
            "description": "Test description",
            "score": 2,
            "date": "2024-02-01",
            "additional_fields": {},
            "images": [],
            "created_at": "2024-02-01T10:30:45+00:00",
            "updated_at": "2024-02-01T10:30:45+00:00"
        }
        """

        guard let jsonData = jsonString.data(using: .utf8) else {
            #expect(Bool(false), "Failed to convert string to data")
            return
        }
        let decoder = JSONDecoder()

        let entry = try decoder.decode(EntryModel.self, from: jsonData)

        #expect(entry.id == "123e4567-e89b-12d3-a456-426614174001")
        #expect(entry.collectionID == nil)
        #expect(entry.score == .okay)
    }

}
