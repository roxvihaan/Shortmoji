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
        try click(backTarget, in: panel)
        XCTAssertFalse(controller.isShowingRelatedGrid)
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
