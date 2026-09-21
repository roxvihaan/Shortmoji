import XCTest
@testable import ShortmojiCore

final class EmojiCatalogTests: XCTestCase {
    func testSkullPrefixReturnsBothRelatedSkullEmojiFirst() {
        let results = EmojiCatalog.shared.search("sku", limit: 4)
        XCTAssertEqual(results.prefix(2).map(\.name), ["skull", "skull_and_crossbones"])
        XCTAssertEqual(results.count, 2)
    }

    func testShortcodeColonsAreIgnoredForExactMatches() {
        XCTAssertEqual(EmojiCatalog.shared.exactMatch(":skull:")?.emoji, "💀")
    }

    func testAliasesAndKeywordsAreSearchable() {
        XCTAssertEqual(EmojiCatalog.shared.search("laugh").first?.name, "joy")
        XCTAssertTrue(EmojiCatalog.shared.search("party").contains { $0.name == "tada" })
    }

    func testRelatedSkullEmojiAreRelevantAndExcludeTheSource() {
        let skull = try! XCTUnwrap(EmojiCatalog.shared.exactMatch("skull"))
        let related = EmojiCatalog.shared.related(to: skull)

        XCTAssertFalse(related.contains(skull))
        XCTAssertEqual(related.first?.name, "skull_and_crossbones")
        XCTAssertTrue(related.contains { $0.name == "ghost" })
        XCTAssertFalse(related.contains { $0.name == "stuck_out_tongue" })
    }

    func testDeletingAndRetypingKeepsTheExistingShortcodePrefix() {
        var query = ShortcodeQueryBuffer()
        query.begin()
        query.append("smile")
        query.deleteBackward()
        query.deleteBackward()
        query.append("rk")

        XCTAssertEqual(query.value, ":smirk")
    }

    func testDeletingTheOpeningColonEndsTheShortcode() {
        var query = ShortcodeQueryBuffer()
        query.begin()

        XCTAssertNil(query.deleteBackward())
        XCTAssertFalse(query.isActive)
    }
}
