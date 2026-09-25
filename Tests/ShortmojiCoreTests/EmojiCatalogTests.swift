import XCTest
@testable import ShortmojiCore

final class EmojiCatalogTests: XCTestCase {
    func testEveryBundledEmojiHasAnExactShortcodeIncludingVariants() {
        let catalog = EmojiCatalog.shared
        XCTAssertEqual(catalog.entries.count, 3953)
        for entry in catalog.entries {
            XCTAssertEqual(catalog.exactMatch(entry.shortcode)?.emoji, entry.emoji, entry.shortcode)
            var query = ShortcodeQueryBuffer()
            query.begin()
            XCTAssertNotNil(query.append(entry.name), entry.name)
        }
        for emoji in ["🥷🏽", "🫱🏻‍🫲🏼", "🏳️‍🌈", "🇺🇸", "👩🏽‍💻"] {
            XCTAssertTrue(catalog.entries.contains { $0.emoji == emoji }, emoji)
        }
        XCTAssertEqual(catalog.search("ninja").first?.emoji, "🥷")
    }

    func testSkullPrefixReturnsBothRelatedSkullEmojiFirst() {
        let results = EmojiCatalog.shared.search("sku", limit: 4)
        XCTAssertEqual(results.prefix(2).map(\.name), ["skull", "skull_and_crossbones"])
        // A complete catalog also contains skunk, which matches this prefix.
    }

    func testShortcodeColonsAreIgnoredForExactMatches() {
        XCTAssertEqual(EmojiCatalog.shared.exactMatch(":skull:")?.emoji, "💀")
    }

    func testExpandedCatalogIncludesPreviouslyMissingEmoji() {
        XCTAssertGreaterThan(EmojiCatalog.shared.entries.count, 1800)
        for (name, emoji) in [("ninja", "🥷"), ("melting_face", "🫠"),
                              ("saluting_face", "🫡"), ("goose", "🪿")] {
            XCTAssertEqual(EmojiCatalog.shared.exactMatch(":\(name):")?.emoji, emoji)
            XCTAssertEqual(EmojiCatalog.shared.search(name).first?.emoji, emoji)
        }
        XCTAssertEqual(EmojiCatalog.shared.search("ninj").first?.emoji, "🥷")
    }

    func testAliasesAndKeywordsAreSearchable() {
        XCTAssertTrue(EmojiCatalog.shared.search("laugh").contains { $0.name == "joy" })
        XCTAssertEqual(EmojiCatalog.shared.exactMatch("laughing")?.emoji, "😆")
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
