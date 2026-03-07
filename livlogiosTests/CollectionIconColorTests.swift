import Foundation
@testable import livlogios
import Testing

struct CollectionIconColorTests {

    // MARK: - CollectionIcon

    @Test func testCollectionIconParsingSystem() {
        let icon = CollectionIcon(raw: "system:folder")
        #expect(icon == .system("folder"))
        #expect(icon.rawValue == "system:folder")
    }

    @Test func testCollectionIconParsingEmoji() {
        let icon = CollectionIcon(raw: "emoji:📋")
        #expect(icon == .emoji("📋"))
        #expect(icon.rawValue == "emoji:📋")
    }

    @Test func testCollectionIconParsingBareEmojiFallback() {
        let icon = CollectionIcon(raw: "📋")
        #expect(icon == .emoji("📋"))
    }

    @Test func testCollectionIconRawValueRoundtrip() {
        for name in CollectionIcon.allSystemIcons {
            let icon = CollectionIcon(raw: "system:\(name)")
            #expect(icon == .system(name))
            #expect(CollectionIcon(raw: icon.rawValue) == icon)
        }
    }

    // MARK: - CollectionColor

    @Test func testCollectionColorAllCases() {
        #expect(CollectionColor.allCases.count == 10)
    }

    @Test func testCollectionColorRawValueRoundtrip() {
        for color in CollectionColor.allCases {
            #expect(CollectionColor(rawValue: color.rawValue) == color)
        }
    }
}
