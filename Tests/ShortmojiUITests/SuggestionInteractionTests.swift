import AppKit
import XCTest
import ShortmojiCore
@testable import Shortmoji

final class SuggestionInteractionTests: XCTestCase {
    func testControlHitTargetsAndSearchInsertion() throws {
        _ = NSApplication.shared
        let controller = SuggestionPanelController()
        let catalog = EmojiCatalog.shared
        controller.relatedProvider = { catalog.related(to: $0) }
        controller.searchProvider = { catalog.search($0, limit: 25) }
        controller.browseProvider = { catalog.entries }
        var inserted: EmojiEntry?
        controller.chooseEntryHandler = { inserted = $0 }
        controller.show(entries: catalog.search("sku", limit: 6), selectedIndex: 0,
                        anchorTopLeft: NSPoint(x: 300, y: 600))
        defer { controller.hide() }
        let panel = try XCTUnwrap(NSApp.windows.first { String(describing: type(of: $0)) == "SuggestionPanel" })
        let content = try XCTUnwrap(panel.contentView)
        content.layoutSubtreeIfNeeded()
        let footerTarget = try XCTUnwrap(content.hitTest(NSPoint(x: 65, y: 18)))
        XCTAssertEqual(String(describing: type(of: footerTarget)), "PopoverActionView")
        try click(footerTarget, in: panel)
        XCTAssertTrue(controller.isShowingRelatedGrid)
        content.layoutSubtreeIfNeeded()
        let backTarget = try XCTUnwrap(content.hitTest(NSPoint(x: 65, y: content.bounds.height - 21)))
        XCTAssertEqual(String(describing: type(of: backTarget)), "PopoverActionView")
        let searchTarget = try XCTUnwrap(content.hitTest(NSPoint(x: 80, y: content.bounds.height - 60)))
        try click(searchTarget, in: panel, tracksRelease: false)
        XCTAssertTrue(controller.appendRelatedSearch("heart"))
        controller.chooseSelectedRelated()
        XCTAssertEqual(inserted?.emoji, catalog.search("heart", limit: 25).first?.emoji)
        XCTAssertTrue(controller.clearRelatedSearch())
        let popup = try XCTUnwrap(descendant(NSPopUpButton.self, in: content))
        popup.selectItem(withTitle: "All emoji")
        NSApp.sendAction(try XCTUnwrap(popup.action), to: popup.target, from: popup)
        content.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(descendant(NSTableView.self, in: content))
        XCTAssertEqual(table.numberOfRows, (catalog.entries.count + 4) / 5)
        XCTAssertLessThanOrEqual(content.bounds.height, 420)
        popup.selectItem(withTitle: "Flags")
        NSApp.sendAction(try XCTUnwrap(popup.action), to: popup.target, from: popup)
        XCTAssertEqual(table.numberOfRows, (catalog.entries.filter { $0.category == "Flags" }.count + 4) / 5)
        content.layoutSubtreeIfNeeded()
        table.layoutSubtreeIfNeeded()
        let rowView = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true))
        XCTAssertEqual(rowView.subviews.count, 5)
        XCTAssertGreaterThan(rowView.subviews.first?.frame.width ?? 0, 60)
        if let path = ProcessInfo.processInfo.environment["SHORTMOJI_QA_PATH"],
           let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        try click(backTarget, in: panel)
        XCTAssertFalse(controller.isShowingRelatedGrid)
    }

    func testGlobalControllerDoesNotLoadCatalogOnStartup() {
        var loads = 0
        func load() -> EmojiCatalog { loads += 1; return EmojiCatalog(entries: []) }
        let controller = GlobalInputController(catalog: load(), suggestions: SuggestionPanelController())
        XCTAssertEqual(loads, 0)
        withExtendedLifetime(controller) {}
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        for child in view.subviews {
            if let result = descendant(type, in: child) { return result }
        }
        return nil
    }

    private func click(_ view: NSView, in window: NSWindow, tracksRelease: Bool = true) throws {
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        view.mouseDown(with: down)
        if tracksRelease {
            let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
                modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
            view.mouseUp(with: up)
        }
    }
}
