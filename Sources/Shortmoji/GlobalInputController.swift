import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ShortmojiCore

final class GlobalInputController {
    private let catalogProvider: () -> EmojiCatalog
    private lazy var catalog = catalogProvider()
    private let suggestions: SuggestionPanelController
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var queryBuffer = ShortcodeQueryBuffer()
    private var matches: [EmojiEntry] = []
    private var selectedIndex = 0
    private var lastAnchor = NSPoint(x: 300, y: 500)
    private(set) var isRunning = false
    var statusChanged: ((Bool) -> Void)?

    private let injectedMarker: Int64 = 0x53484F52544D4A
    private let replayedMarker: Int64 = 0x53484F52545250
    private var replacementInFlight = false
    private var deferredEvents: [CGEvent] = []
    private var isDrainingDeferredEvents = false

    init(catalog: @autoclosure @escaping () -> EmojiCatalog = .shared, suggestions: SuggestionPanelController) {
        self.catalogProvider = catalog
        self.suggestions = suggestions
        suggestions.chooseHandler = { [weak self] index in
            self?.choose(index: index)
        }
        suggestions.chooseEntryHandler = { [weak self] entry in
            self?.choose(entry: entry)
        }
        suggestions.relatedProvider = { [weak self] entry in
            self?.catalog.related(to: entry) ?? []
        }
        suggestions.searchProvider = { [weak self] query in
            self?.catalog.search(query, limit: Int.max) ?? []
        }
        suggestions.browseProvider = { [weak self] in
            self?.catalog.browsingEntries ?? []
        }
    }

    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        guard Self.isAccessibilityTrusted() else {
            statusChanged?(false)
            return false
        }

        let mask = [
            CGEventType.keyDown,
            .keyUp,
            .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseUp,
        ].reduce(CGEventMask(0)) { partial, type in
            partial | CGEventMask(1 << type.rawValue)
        }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: globalEventTapCallback,
            userInfo: pointer
        ) else {
            statusChanged?(false)
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        isRunning = true
        statusChanged?(true)
        return true
    }

    func stop() {
        suggestions.hide()
        resetQuery()
        replacementInFlight = false
        deferredEvents.removeAll()
        isDrainingDeferredEvents = false
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
        statusChanged?(false)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let marker = event.getIntegerValueField(.eventSourceUserData)
        guard marker != injectedMarker else {
            return Unmanaged.passUnretained(event)
        }

        if marker != replayedMarker, replacementInFlight || isDrainingDeferredEvents {
            if let copied = event.copy() {
                copied.setIntegerValueField(.eventSourceUserData, value: 0)
                deferredEvents.append(copied)
            }
            return nil
        }

        // Let AppKit own input while its category menu tracks outside the panel.
        if suggestions.isTrackingCategoryMenu { return Unmanaged.passUnretained(event) }

        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            guard queryBuffer.isActive || suggestions.isVisible else { return Unmanaged.passUnretained(event) }
            if suggestions.isMouseInside {
                return Unmanaged.passUnretained(event)
            }
            resetAndHide()
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate])
        if !flags.isEmpty {
            if queryBuffer.isActive || suggestions.isVisible { resetAndHide() }
            return Unmanaged.passUnretained(event)
        }

        if suggestions.isVisible {
            if suggestions.isShowingRelatedGrid {
                switch Int(keyCode) {
                case kVK_RightArrow:
                    suggestions.moveRelatedSelection(by: 1)
                    return nil
                case kVK_LeftArrow:
                    suggestions.moveRelatedSelection(by: -1)
                    return nil
                case kVK_DownArrow:
                    suggestions.moveRelatedSelection(by: 5)
                    return nil
                case kVK_UpArrow:
                    suggestions.moveRelatedSelection(by: -5)
                    return nil
                case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab:
                    suggestions.chooseSelectedRelated()
                    return nil
                case kVK_Delete:
                    _ = suggestions.deleteRelatedSearchCharacter()
                    return nil
                case kVK_Escape:
                    if !suggestions.clearRelatedSearch() {
                        suggestions.showSuggestionList()
                    }
                    return nil
                default:
                    break
                }
            }

            switch Int(keyCode) {
            case kVK_RightArrow:
                suggestions.showRelatedGrid()
                return nil
            case kVK_DownArrow:
                selectedIndex = (selectedIndex + 1) % matches.count
                suggestions.updateSelection(selectedIndex)
                return nil
            case kVK_UpArrow:
                selectedIndex = (selectedIndex - 1 + matches.count) % matches.count
                suggestions.updateSelection(selectedIndex)
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab:
                choose(index: selectedIndex)
                return nil
            case kVK_Escape:
                resetAndHide()
                return nil
            default:
                break
            }
        }

        if Int(keyCode) == kVK_Delete {
            if queryBuffer.isActive {
                if queryBuffer.deleteBackward() == nil {
                    resetAndHide()
                } else {
                    refreshSuggestions(afterEvent: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if [kVK_ForwardDelete, kVK_LeftArrow, kVK_RightArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown]
            .contains(Int(keyCode)) {
            if queryBuffer.isActive || suggestions.isVisible { resetAndHide() }
            return Unmanaged.passUnretained(event)
        }

        let characters = unicodeCharacters(from: event)
        guard !characters.isEmpty else { return Unmanaged.passUnretained(event) }

        if suggestions.isShowingRelatedGrid {
            _ = suggestions.appendRelatedSearch(characters)
            return nil
        }

        if characters == ":" {
            if let query = queryBuffer.value, query.count > 1, let match = catalog.exactMatch(query) {
                insert(match, replacingCharacterCount: query.count)
                return nil
            }
            queryBuffer.begin()
            matches = []
            selectedIndex = 0
            suggestions.hide()
            return Unmanaged.passUnretained(event)
        }

        if queryBuffer.isActive {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_+-"))
            if characters.unicodeScalars.allSatisfy({ allowed.contains($0) }),
               queryBuffer.append(characters.lowercased()) != nil {
                refreshSuggestions(afterEvent: true)
            } else {
                resetAndHide()
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func refreshSuggestions(afterEvent: Bool) {
        guard let activeQuery = queryBuffer.value, activeQuery.count > 1 else {
            suggestions.hide()
            return
        }
        matches = catalog.search(activeQuery, limit: 6)
        selectedIndex = 0
        guard !matches.isEmpty else {
            suggestions.hide()
            return
        }

        let delay = afterEvent ? 0.018 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.matches.isEmpty, self.queryBuffer.value == activeQuery,
                  !self.suggestions.isShowingRelatedGrid else { return }
            if let anchor = self.focusedCaretAnchor() {
                self.lastAnchor = anchor
            }
            self.suggestions.show(entries: self.matches, selectedIndex: self.selectedIndex, anchorTopLeft: self.lastAnchor)
        }
    }

    private func choose(index: Int) {
        guard matches.indices.contains(index), let query = queryBuffer.value else { return }
        insert(matches[index], replacingCharacterCount: query.count)
    }

    private func choose(entry: EmojiEntry) {
        guard let query = queryBuffer.value else { return }
        insert(entry, replacingCharacterCount: query.count)
    }

    private func insert(_ entry: EmojiEntry, replacingCharacterCount count: Int) {
        replacementInFlight = true
        resetAndHide()
        paste(suggestions.preferredEntry(entry).emoji, replacingCharacterCount: count)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self else { return }
            self.replacementInFlight = false
            self.drainDeferredEvents()
        }
    }

    private func resetAndHide() {
        resetQuery()
        suggestions.hide()
    }

    private func resetQuery() {
        queryBuffer.reset()
        matches = []
        selectedIndex = 0
    }

    private func drainDeferredEvents() {
        guard !replacementInFlight else { return }
        guard !deferredEvents.isEmpty else {
            isDrainingDeferredEvents = false
            return
        }

        isDrainingDeferredEvents = true
        let event = deferredEvents.removeFirst()
        event.setIntegerValueField(.eventSourceUserData, value: replayedMarker)
        event.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.004) { [weak self] in
            self?.drainDeferredEvents()
        }
    }

    private func unicodeCharacters(from event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        return String(utf16CodeUnits: buffer, count: length)
    }

    private func paste(_ string: String, replacingCharacterCount count: Int) {
        let pasteboard = NSPasteboard.general
        let previousItems: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }

        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        let replacementChangeCount = pasteboard.changeCount

        for _ in 0..<count { postKey(code: CGKeyCode(kVK_Delete)) }
        postKey(code: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard pasteboard.changeCount == replacementChangeCount else { return }
            pasteboard.clearContents()
            let restored = previousItems.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            if !restored.isEmpty { pasteboard.writeObjects(restored) }
        }
    }

    private func postKey(code: CGKeyCode, flags: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: injectedMarker)
        up.setIntegerValueField(.eventSourceUserData, value: injectedMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func focusedCaretAnchor() -> NSPoint? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue else { return nil }

        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success,
        let rangeValue,
        CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(unsafeBitCast(rangeValue, to: AXValue.self), .cfRange, &range),
              let axRange = AXValueCreate(.cfRange, &range) else { return nil }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focused,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            axRange,
            &boundsValue
        ) == .success,
        let boundsValue,
        CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }

        var bounds = CGRect.zero
        guard AXValueGetValue(unsafeBitCast(boundsValue, to: AXValue.self), .cgRect, &bounds) else { return nil }

        let mainScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
        return NSPoint(x: bounds.minX, y: mainScreenTop - bounds.maxY - 7)
    }
}

private let globalEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<GlobalInputController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}
