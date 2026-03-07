import Foundation
@testable import livlogios
import Testing

struct CollectionModelTests {

    @Test func testCollectionModelDecoding() async throws {
        let jsonString = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "name": "Movies",
            "icon": "system:movie",
            "color": "vibrant-coral",
            "created_at": "2024-02-01T10:30:45Z",
            "updated_at": "2024-02-01T10:30:45Z"
        }
        """

        guard let jsonData = jsonString.data(using: .utf8) else {
            #expect(Bool(false), "Failed to convert string to data")
            return
        }

        let collection = try JSONDecoder().decode(CollectionModel.self, from: jsonData)

        #expect(collection.id == "123e4567-e89b-12d3-a456-426614174000")
        #expect(collection.name == "Movies")
        #expect(collection.icon == "system:movie")
        #expect(collection.color == "vibrant-coral")
    }

    @Test func testCollectionModelDecodingWithoutColor() async throws {
        let jsonString = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "name": "Old Collection",
            "icon": "system:folder",
            "created_at": "2024-02-01T10:30:45Z",
            "updated_at": "2024-02-01T10:30:45Z"
        }
        """

        guard let jsonData = jsonString.data(using: .utf8) else {
            #expect(Bool(false), "Failed to convert string to data")
            return
        }

        let collection = try JSONDecoder().decode(CollectionModel.self, from: jsonData)
        #expect(collection.color == "dodger-blue")
    }
}
