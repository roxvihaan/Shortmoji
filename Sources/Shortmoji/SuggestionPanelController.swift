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
    private var browseCategory = "Similar"
    private(set) var entries: [EmojiEntry] = []
    private(set) var selectedIndex = 0
    private(set) var isShowingRelatedGrid = false
    private(set) var isTrackingCategoryMenu = false
    var chooseHandler: ((Int) -> Void)?
    var chooseEntryHandler: ((EmojiEntry) -> Void)?
    var relatedProvider: ((EmojiEntry) -> [EmojiEntry])?
    var searchProvider: ((String) -> [EmojiEntry])?
    var browseProvider: (() -> [EmojiEntry])?
    var preferredSkinTone: Int { UserDefaults.standard.integer(forKey: "preferredSkinTone") }

    func preferredEntry(_ entry: EmojiEntry) -> EmojiEntry {
        EmojiCatalog.shared.applyingSkinTone(preferredSkinTone, to: entry)
    }

    private func changeSkinTone(_ tone: Int) {
        UserDefaults.standard.set(tone, forKey: "preferredSkinTone")
        listView.tonePicker.selectItem(at: tone)
        gridView.tonePicker.selectItem(at: tone)
        listView.configure(entries: entries.map(preferredEntry), selectedIndex: selectedIndex)
        gridView.configure(entries: relatedEntries.map(preferredEntry), selectedIndex: relatedSelectedIndex,
                           searchQuery: relatedSearchQuery)
    }

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
        gridView.onCategory = { [weak self] category in
            self?.browseCategory = category
            self?.refreshRelatedSearch()
        }
        gridView.onMenuTracking = { [weak self] tracking in self?.isTrackingCategoryMenu = tracking }
        for picker in [listView.tonePicker, gridView.tonePicker] {
            picker.selectItem(at: min(5, max(0, preferredSkinTone)))
            picker.onChange = { [weak self] tone in self?.changeSkinTone(tone) }
            picker.onTracking = { [weak self] tracking in self?.isTrackingCategoryMenu = tracking }
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
        listView.configure(entries: self.entries.map(preferredEntry), selectedIndex: self.selectedIndex)
        resizeAndPosition(height: listView.preferredHeight)
        panel.orderFrontRegardless()
    }

    func updateSelection(_ index: Int) {
        guard !entries.isEmpty else { return }
        selectedIndex = (index + entries.count) % entries.count
        listView.configure(entries: entries.map(preferredEntry), selectedIndex: selectedIndex)
    }

    func moveRelatedSelection(by offset: Int) {
        guard isShowingRelatedGrid, !relatedEntries.isEmpty else { return }
        relatedSelectedIndex = ((relatedSelectedIndex + offset) % relatedEntries.count + relatedEntries.count) % relatedEntries.count
        gridView.configure(
            entries: relatedEntries.map(preferredEntry),
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
        initialRelatedEntries = related
        relatedEntries = related
        relatedSelectedIndex = 0
        relatedSearchQuery = ""
        browseCategory = "Similar"
        gridView.resetCategory()
        isShowingRelatedGrid = true
        listView.isHidden = true
        gridView.isHidden = false
        gridView.configure(entries: related.map(preferredEntry), selectedIndex: relatedSelectedIndex, searchQuery: "")
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
            relatedEntries = browseCategory == "Similar" ? initialRelatedEntries : (browseProvider?() ?? [])
        } else {
            relatedEntries = searchProvider?(relatedSearchQuery) ?? []
        }
        if browseCategory != "Similar", browseCategory != "All emoji" {
            relatedEntries = relatedEntries.filter { $0.category == browseCategory }
        }
        relatedSelectedIndex = 0
        gridView.configure(
            entries: relatedEntries.map(preferredEntry),
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
    let tonePicker = SkinTonePicker(frame: .zero, pullsDown: false)
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
        addSubview(tonePicker)
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
            x: 220,
            y: 8,
            width: bounds.width - 236,
            height: Metrics.footerHeight - 12
        )
        similarButton.frame = NSRect(x: 10, y: 4, width: 132, height: Metrics.footerHeight - 8)
        tonePicker.frame = NSRect(x: 145, y: 5, width: 66, height: 28)
    }

}

private final class RelatedEmojiGridView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private enum Metrics {
        static let columns = 5
        static let outerPadding: CGFloat = 7
        static let headerHeight: CGFloat = 82
        static let cellHeight: CGFloat = 64
    }

    private var entries: [EmojiEntry] = []
    private var selectedIndex = 0
    private let scrollView = NSScrollView(frame: .zero)
    private let table = NSTableView(frame: .zero)
    private let backButton = PopoverActionView(title: "Suggestions", symbolName: "chevron.left")
    private let categoryButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let searchField = ForwardedSearchField(frame: .zero)
    let tonePicker = SkinTonePicker(frame: .zero, pullsDown: false)
    private let separator = NSBox(frame: .zero)
    var onChoose: ((Int) -> Void)?
    var onBack: (() -> Void)?
    var onClearSearch: (() -> Void)?
    var onCategory: ((String) -> Void)?
    var onMenuTracking: ((Bool) -> Void)?

    var preferredHeight: CGFloat {
        let rows = min(5, Int(ceil(Double(max(1, entries.count)) / Double(Metrics.columns))))
        return Metrics.headerHeight + Metrics.outerPadding * 2 + CGFloat(rows) * Metrics.cellHeight
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        backButton.onClick = { [weak self] in self?.onBack?() }
        addSubview(backButton)

        categoryButton.addItems(withTitles: ["Similar", "All emoji", "Smileys & Emotion", "People & Body",
            "Animals & Nature", "Food & Drink", "Travel & Places", "Activities", "Objects", "Symbols", "Flags", "Component"])
        categoryButton.font = .systemFont(ofSize: 12.5, weight: .medium)
        categoryButton.target = self
        categoryButton.action = #selector(categoryChanged)
        categoryButton.menu?.delegate = self
        addSubview(categoryButton)

        searchField.placeholderString = "Search emoji"
        searchField.isEditable = false
        searchField.isSelectable = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 12.5)
        searchField.onClear = { [weak self] in self?.onClearSearch?() }
        addSubview(searchField)
        addSubview(tonePicker)

        separator.boxType = .separator
        addSubview(separator)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = Metrics.cellHeight
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("emoji")))
        table.dataSource = self
        table.delegate = self
        scrollView.documentView = table
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { nil }

    func configure(entries: [EmojiEntry], selectedIndex: Int, searchQuery: String) {
        let changed = self.entries != entries
        let previousIndex = self.selectedIndex
        self.entries = entries
        self.selectedIndex = selectedIndex
        if changed {
            table.reloadData()
        } else if !entries.isEmpty {
            table.reloadData(forRowIndexes: IndexSet([previousIndex / 5, selectedIndex / 5]), columnIndexes: IndexSet(integer: 0))
        }
        if !entries.isEmpty { table.scrollRowToVisible(selectedIndex / 5) }
        searchField.stringValue = searchQuery
        needsLayout = true
    }

    func resetCategory() { categoryButton.selectItem(withTitle: "Similar") }

    @objc private func categoryChanged() {
        onCategory?(categoryButton.titleOfSelectedItem ?? "Similar")
    }

    func menuWillOpen(_ menu: NSMenu) { onMenuTracking?(true) }
    func menuDidClose(_ menu: NSMenu) { onMenuTracking?(false) }

    func numberOfRows(in tableView: NSTableView) -> Int { (entries.count + 4) / 5 }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("emojiRow")
        let view = tableView.makeView(withIdentifier: identifier, owner: self) ?? NSView(frame: .zero)
        view.identifier = identifier
        view.subviews.forEach { $0.removeFromSuperview() }
        let width = floor(tableView.bounds.width / 5)
        for index in (row * 5)..<min(row * 5 + 5, entries.count) {
            let cell = RelatedEmojiCellView(entry: entries[index], isSelected: index == selectedIndex)
            cell.frame = NSRect(x: CGFloat(index % 5) * width, y: 0, width: width, height: Metrics.cellHeight)
            cell.toolTip = entries[index].shortcode
            cell.onClick = { [weak self] in self?.onChoose?(index) }
            view.addSubview(cell)
        }
        return view
    }

    override func layout() {
        super.layout()
        backButton.frame = NSRect(x: 8, y: bounds.height - 35, width: 112, height: 28)
        categoryButton.frame = NSRect(x: 140, y: bounds.height - 35, width: bounds.width - 150, height: 28)
        searchField.frame = NSRect(x: 10, y: bounds.height - 75, width: bounds.width - 94, height: 28)
        tonePicker.frame = NSRect(x: bounds.width - 76, y: bounds.height - 75, width: 66, height: 28)
        separator.frame = NSRect(x: 0, y: bounds.height - Metrics.headerHeight, width: bounds.width, height: 1)

        scrollView.frame = NSRect(x: Metrics.outerPadding, y: Metrics.outerPadding,
            width: bounds.width - Metrics.outerPadding * 2,
            height: bounds.height - Metrics.headerHeight - Metrics.outerPadding * 2)
        table.frame.size.width = scrollView.contentSize.width
        table.tableColumns.first?.width = scrollView.contentSize.width
    }

}

private final class SkinTonePicker: NSPopUpButton, NSMenuDelegate {
    var onChange: ((Int) -> Void)?
    var onTracking: ((Bool) -> Void)?

    override init(frame: NSRect, pullsDown: Bool) {
        super.init(frame: frame, pullsDown: pullsDown)
        addItems(withTitles: ["✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿"])
        let names = ["Default yellow", "Light", "Medium-light", "Medium", "Medium-dark", "Dark"]
        for (index, item) in itemArray.enumerated() { item.setAccessibilityLabel(names[index]) }
        font = .systemFont(ofSize: 17)
        toolTip = "Preferred skin tone — applies to all supported emoji"
        setAccessibilityLabel("Preferred skin tone")
        target = self
        action = #selector(changed)
        menu?.delegate = self
    }

    required init?(coder: NSCoder) { nil }
    @objc private func changed() { onChange?(indexOfSelectedItem) }
    func menuWillOpen(_ menu: NSMenu) { onTracking?(true) }
    func menuDidClose(_ menu: NSMenu) { onTracking?(false) }
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
    private let titleLabel = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?

    init(title: String, symbolName: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6

        let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.controlAccentColor]))
        let attachment = NSTextAttachment()
        attachment.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)
        // Keep the symbol and words in one text run. Center the symbol on the
        // font's cap height, not on two unrelated view bounding boxes.
        attachment.bounds = NSRect(x: 0, y: (font.capHeight - 12) / 2, width: 12, height: 12)
        let label = NSMutableAttributedString(attachment: attachment)
        label.append(NSAttributedString(string: "  " + title))
        label.addAttributes([.font: font, .foregroundColor: NSColor.controlAccentColor],
                            range: NSRange(location: 0, length: label.length))
        titleLabel.attributedStringValue = label
        titleLabel.font = font
        titleLabel.textColor = .controlAccentColor
        titleLabel.lineBreakMode = .byClipping
        titleLabel.setAccessibilityLabel(title)
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let labelHeight = titleLabel.intrinsicContentSize.height
        titleLabel.frame = NSRect(
            x: 4, y: (bounds.height - labelHeight) / 2,
            width: max(0, bounds.width - 8), height: labelHeight
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
