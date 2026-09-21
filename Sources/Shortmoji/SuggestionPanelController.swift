import AppKit
import ShortmojiCore

final class SuggestionPanelController {
    private let panel: SuggestionPanel
    private let materialView: NSVisualEffectView
    private let listView: SuggestionListView
    private let gridView: RelatedEmojiGridView
    private var anchorTopLeft = NSPoint.zero
    private var initialRelatedEntries: [EmojiEntry] = []
    private var relatedEntries: [EmojiEntry] = []
    private var relatedSelectedIndex = 0
    private var relatedSearchQuery = ""
    private(set) var entries: [EmojiEntry] = []
    private(set) var selectedIndex = 0
    private(set) var isShowingRelatedGrid = false
    var chooseHandler: ((Int) -> Void)?
    var chooseEntryHandler: ((EmojiEntry) -> Void)?
    var relatedProvider: ((EmojiEntry) -> [EmojiEntry])?
    var searchProvider: ((String) -> [EmojiEntry])?

    var isVisible: Bool { panel.isVisible }
    var isMouseInside: Bool { panel.isVisible && panel.frame.contains(NSEvent.mouseLocation) }

    init(appearance: NSAppearance? = nil) {
        panel = SuggestionPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.appearance = appearance

        materialView = NSVisualEffectView(frame: .zero)
        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 13
        materialView.layer?.cornerCurve = .continuous
        materialView.layer?.masksToBounds = true
        materialView.layer?.borderWidth = 0.5
        materialView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        materialView.autoresizingMask = [.width, .height]

        listView = SuggestionListView(frame: .zero)
        listView.autoresizingMask = [.width, .height]
        materialView.addSubview(listView)
        gridView = RelatedEmojiGridView(frame: .zero)
        gridView.autoresizingMask = [.width, .height]
        gridView.isHidden = true
        materialView.addSubview(gridView)
        panel.contentView = materialView

        listView.onChoose = { [weak self] index in
            self?.chooseHandler?(index)
        }
        listView.onShowSimilar = { [weak self] in
            self?.showRelatedGrid()
        }
        gridView.onChoose = { [weak self] index in
            guard let self, self.relatedEntries.indices.contains(index) else { return }
            self.chooseEntryHandler?(self.relatedEntries[index])
        }
        gridView.onBack = { [weak self] in
            self?.showSuggestionList()
        }
        gridView.onClearSearch = { [weak self] in
            _ = self?.clearRelatedSearch()
        }
    }

    func attach(to parent: NSWindow) {
        parent.addChildWindow(panel, ordered: .above)
    }

    func show(entries: [EmojiEntry], selectedIndex: Int, anchorTopLeft: NSPoint) {
        guard !entries.isEmpty else {
            hide()
            return
        }

        self.entries = Array(entries.prefix(6))
        self.selectedIndex = min(max(0, selectedIndex), self.entries.count - 1)
        self.anchorTopLeft = anchorTopLeft
        isShowingRelatedGrid = false
        relatedEntries = []
        listView.isHidden = false
        gridView.isHidden = true
        listView.configure(entries: self.entries, selectedIndex: self.selectedIndex)
        resizeAndPosition(height: listView.preferredHeight)
        panel.orderFrontRegardless()
    }

    func updateSelection(_ index: Int) {
        guard !entries.isEmpty else { return }
        selectedIndex = (index + entries.count) % entries.count
        listView.configure(entries: entries, selectedIndex: selectedIndex)
    }

    func moveRelatedSelection(by offset: Int) {
        guard isShowingRelatedGrid, !relatedEntries.isEmpty else { return }
        relatedSelectedIndex = (relatedSelectedIndex + offset + relatedEntries.count) % relatedEntries.count
        gridView.configure(
            entries: relatedEntries,
            selectedIndex: relatedSelectedIndex,
            searchQuery: relatedSearchQuery
        )
    }

    func chooseSelectedRelated() {
        guard isShowingRelatedGrid, relatedEntries.indices.contains(relatedSelectedIndex) else { return }
        chooseEntryHandler?(relatedEntries[relatedSelectedIndex])
    }

    func showSuggestionList() {
        guard isShowingRelatedGrid else { return }
        isShowingRelatedGrid = false
        gridView.isHidden = true
        listView.isHidden = false
        resizeAndPosition(height: listView.preferredHeight)
    }

    func showRelatedGrid() {
        guard entries.indices.contains(selectedIndex),
              let relatedProvider else { return }
        let related = relatedProvider(entries[selectedIndex])
        guard !related.isEmpty else { return }

        initialRelatedEntries = related
        relatedEntries = related
        relatedSelectedIndex = 0
        relatedSearchQuery = ""
        isShowingRelatedGrid = true
        listView.isHidden = true
        gridView.isHidden = false
        gridView.configure(entries: related, selectedIndex: relatedSelectedIndex, searchQuery: "")
        resizeAndPosition(height: gridView.preferredHeight)
    }

    @discardableResult
    func appendRelatedSearch(_ characters: String) -> Bool {
        guard isShowingRelatedGrid else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_+- "))
        guard characters.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        relatedSearchQuery.append(characters.lowercased())
        refreshRelatedSearch()
        return true
    }

    @discardableResult
    func deleteRelatedSearchCharacter() -> Bool {
        guard isShowingRelatedGrid, !relatedSearchQuery.isEmpty else { return false }
        relatedSearchQuery.removeLast()
        refreshRelatedSearch()
        return true
    }

    @discardableResult
    func clearRelatedSearch() -> Bool {
        guard isShowingRelatedGrid, !relatedSearchQuery.isEmpty else { return false }
        relatedSearchQuery = ""
        refreshRelatedSearch()
        return true
    }

    func hide() {
        panel.orderOut(nil)
        entries = []
        initialRelatedEntries = []
        relatedEntries = []
        selectedIndex = 0
        relatedSelectedIndex = 0
        relatedSearchQuery = ""
        isShowingRelatedGrid = false
        gridView.isHidden = true
        listView.isHidden = false
    }

    private func refreshRelatedSearch() {
        if relatedSearchQuery.isEmpty {
            relatedEntries = initialRelatedEntries
        } else {
            relatedEntries = searchProvider?(relatedSearchQuery) ?? []
        }
        relatedSelectedIndex = 0
        gridView.configure(
            entries: relatedEntries,
            selectedIndex: relatedSelectedIndex,
            searchQuery: relatedSearchQuery
        )
        resizeAndPosition(height: gridView.preferredHeight)
    }

    private func resizeAndPosition(height: CGFloat) {
        let size = NSSize(width: 386, height: height)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorTopLeft) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = min(max(anchorTopLeft.x, visible.minX + 8), visible.maxX - size.width - 8)
        var y = anchorTopLeft.y - size.height
        if y < visible.minY + 8 {
            y = min(anchorTopLeft.y + 12, visible.maxY - size.height - 8)
        }
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        materialView.frame = NSRect(origin: .zero, size: size)
        listView.frame = materialView.bounds
        gridView.frame = materialView.bounds
        panel.orderFrontRegardless()
    }
}

private final class SuggestionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class SuggestionListView: NSView {
    private enum Metrics {
        static let outerPadding: CGFloat = 7
        static let rowHeight: CGFloat = 58
        static let footerHeight: CGFloat = 37
    }

    private var rows: [SuggestionRowView] = []
    private let separator = NSBox(frame: .zero)
    private let similarButton = PopoverActionView(title: "See similar", symbolName: "square.grid.2x2")
    private let footer = NSTextField(labelWithString: "Return to insert")
    var onChoose: ((Int) -> Void)?
    var onShowSimilar: (() -> Void)?

    var preferredHeight: CGFloat {
        Metrics.outerPadding * 2 + CGFloat(rows.count) * Metrics.rowHeight + Metrics.footerHeight
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        separator.boxType = .separator
        addSubview(separator)

        similarButton.onClick = { [weak self] in self?.onShowSimilar?() }
        addSubview(similarButton)

        footer.font = .systemFont(ofSize: 12.5, weight: .regular)
        footer.textColor = .secondaryLabelColor
        footer.alignment = .right
        footer.lineBreakMode = .byClipping
        addSubview(footer)
    }

    required init?(coder: NSCoder) { nil }

    func configure(entries: [EmojiEntry], selectedIndex: Int) {
        rows.forEach { $0.removeFromSuperview() }
        rows = entries.enumerated().map { index, entry in
            let row = SuggestionRowView(entry: entry, isSelected: index == selectedIndex)
            row.onClick = { [weak self] in self?.onChoose?(index) }
            addSubview(row)
            return row
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var top = bounds.maxY - Metrics.outerPadding
        for row in rows {
            top -= Metrics.rowHeight
            row.frame = NSRect(
                x: Metrics.outerPadding,
                y: top,
                width: bounds.width - Metrics.outerPadding * 2,
                height: Metrics.rowHeight
            )
        }

        let footerTop = top
        separator.frame = NSRect(x: 0, y: footerTop - 1, width: bounds.width, height: 1)
        footer.frame = NSRect(
            x: 156,
            y: 8,
            width: bounds.width - 172,
            height: Metrics.footerHeight - 12
        )
        similarButton.frame = NSRect(x: 10, y: 4, width: 132, height: Metrics.footerHeight - 8)
    }

}

private final class RelatedEmojiGridView: NSView {
    private enum Metrics {
        static let columns = 5
        static let outerPadding: CGFloat = 7
        static let headerHeight: CGFloat = 82
        static let cellHeight: CGFloat = 64
    }

    private var cells: [RelatedEmojiCellView] = []
    private let backButton = PopoverActionView(title: "Suggestions", symbolName: "chevron.left")
    private let titleLabel = NSTextField(labelWithString: "Similar emoji")
    private let searchField = ForwardedSearchField(frame: .zero)
    private let separator = NSBox(frame: .zero)
    var onChoose: ((Int) -> Void)?
    var onBack: (() -> Void)?
    var onClearSearch: (() -> Void)?

    var preferredHeight: CGFloat {
        let rows = Int(ceil(Double(max(1, cells.count)) / Double(Metrics.columns)))
        return Metrics.headerHeight + Metrics.outerPadding * 2 + CGFloat(rows) * Metrics.cellHeight
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        backButton.onClick = { [weak self] in self?.onBack?() }
        addSubview(backButton)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        searchField.placeholderString = "Search emoji"
        searchField.isEditable = false
        searchField.isSelectable = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 12.5)
        searchField.onClear = { [weak self] in self?.onClearSearch?() }
        addSubview(searchField)

        separator.boxType = .separator
        addSubview(separator)
    }

    required init?(coder: NSCoder) { nil }

    func configure(entries: [EmojiEntry], selectedIndex: Int, searchQuery: String) {
        cells.forEach { $0.removeFromSuperview() }
        cells = entries.enumerated().map { index, entry in
            let cell = RelatedEmojiCellView(entry: entry, isSelected: index == selectedIndex)
            cell.onClick = { [weak self] in self?.onChoose?(index) }
            addSubview(cell)
            return cell
        }
        searchField.stringValue = searchQuery
        needsLayout = true
    }

    override func layout() {
        super.layout()
        backButton.frame = NSRect(x: 8, y: bounds.height - 35, width: 112, height: 28)
        titleLabel.frame = NSRect(x: 120, y: bounds.height - 31, width: bounds.width - 240, height: 20)
        searchField.frame = NSRect(x: 10, y: bounds.height - 75, width: bounds.width - 20, height: 28)
        separator.frame = NSRect(x: 0, y: bounds.height - Metrics.headerHeight, width: bounds.width, height: 1)

        let availableWidth = bounds.width - Metrics.outerPadding * 2
        let cellWidth = floor(availableWidth / CGFloat(Metrics.columns))
        let contentTop = bounds.height - Metrics.headerHeight - Metrics.outerPadding
        for (index, cell) in cells.enumerated() {
            let row = index / Metrics.columns
            let column = index % Metrics.columns
            cell.frame = NSRect(
                x: Metrics.outerPadding + CGFloat(column) * cellWidth,
                y: contentTop - CGFloat(row + 1) * Metrics.cellHeight,
                width: cellWidth,
                height: Metrics.cellHeight
            )
        }
    }

}

// Labels are decorative: route their entire hit area to the owning control.
private class ClickTargetView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// Keyboard input is forwarded by GlobalInputController (or the playground)
// so the destination app retains its caret while this field is searched.
private final class ForwardedSearchField: NSSearchField {
    var onClear: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let searchCell = cell as? NSSearchFieldCell,
           !stringValue.isEmpty,
           searchCell.cancelButtonRect(forBounds: bounds).contains(point) {
            onClear?()
        }
        // Give visible feedback without making this nonactivating panel key.
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.controlAccentColor.cgColor
    }
}

private final class PopoverActionView: ClickTargetView {
    private let imageView = NSImageView(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?

    init(title: String, symbolName: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)
        imageView.contentTintColor = .controlAccentColor
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        addSubview(imageView)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = .controlAccentColor
        titleLabel.lineBreakMode = .byClipping
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let iconSize: CGFloat = 14
        let labelHeight = titleLabel.intrinsicContentSize.height
        imageView.frame = NSRect(
            x: 4, y: (bounds.height - iconSize) / 2,
            width: iconSize, height: iconSize
        )
        titleLabel.frame = NSRect(
            x: 24, y: (bounds.height - labelHeight) / 2,
            width: max(0, bounds.width - 28), height: labelHeight
        )
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }
}

private final class RelatedEmojiCellView: ClickTargetView {
    private let emojiLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?

    init(entry: EmojiEntry, isSelected: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.17).cgColor
            : NSColor.clear.cgColor

        emojiLabel.stringValue = entry.emoji
        emojiLabel.font = .systemFont(ofSize: 27)
        emojiLabel.alignment = .center
        addSubview(emojiLabel)

        nameLabel.stringValue = entry.name.replacingOccurrences(of: "_", with: " ")
        nameLabel.font = .systemFont(ofSize: 9.5, weight: isSelected ? .semibold : .regular)
        nameLabel.textColor = isSelected ? .controlAccentColor : .secondaryLabelColor
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        emojiLabel.frame = NSRect(x: 4, y: 21, width: bounds.width - 8, height: 35)
        nameLabel.frame = NSRect(x: 5, y: 6, width: bounds.width - 10, height: 14)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

private final class SuggestionRowView: ClickTargetView {
    private let emojiLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let selected: Bool
    var onClick: (() -> Void)?

    init(entry: EmojiEntry, isSelected: Bool) {
        selected = isSelected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor

        emojiLabel.stringValue = entry.emoji
        emojiLabel.font = .systemFont(ofSize: 27)
        emojiLabel.alignment = .center
        emojiLabel.maximumNumberOfLines = 1
        addSubview(emojiLabel)

        nameLabel.stringValue = entry.shortcode
        nameLabel.font = .systemFont(ofSize: 15.5, weight: isSelected ? .semibold : .medium)
        nameLabel.textColor = isSelected ? .white : .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        emojiLabel.frame = NSRect(x: 13, y: 10, width: 46, height: 38)
        nameLabel.frame = NSRect(x: 70, y: 18, width: bounds.width - 84, height: 24)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
