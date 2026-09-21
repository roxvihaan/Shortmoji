import AppKit
import Carbon.HIToolbox
import ShortmojiCore

final class DemoWindowController: NSWindowController, NSTextViewDelegate {
    private let catalog = EmojiCatalog.shared
    private let suggestions = SuggestionPanelController(appearance: NSAppearance(named: .aqua))
    private let textView = DemoTextView(frame: .zero)
    private var matches: [EmojiEntry] = []
    private var selectedIndex = 0
    private var queryRange: NSRange?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Shortmoji Playground"
        window.appearance = NSAppearance(named: .aqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.center()
        window.minSize = NSSize(width: 680, height: 480)
        super.init(window: window)
        buildContent()
        suggestions.attach(to: window)

        suggestions.chooseHandler = { [weak self] index in
            self?.choose(index: index)
        }
        suggestions.chooseEntryHandler = { [weak self] entry in
            self?.choose(entry: entry)
        }
        suggestions.relatedProvider = { [catalog] entry in
            catalog.related(to: entry)
        }
        suggestions.searchProvider = { [catalog] query in
            catalog.search(query, limit: 25)
        }
        textView.interceptKey = { [weak self] event in
            self?.handleKey(event) ?? false
        }
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refreshSuggestions()
        }
    }

    private func buildContent() {
        guard let window else { return }
        let background = NSVisualEffectView(frame: .zero)
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active
        window.contentView = background

        let eyebrow = NSTextField(labelWithString: "SYSTEM-WIDE EMOJI SHORTCODES")
        eyebrow.font = .systemFont(ofSize: 11, weight: .semibold)
        eyebrow.textColor = .secondaryLabelColor
        eyebrow.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Type naturally. Find emoji instantly.")
        title.font = .systemFont(ofSize: 26, weight: .semibold)
        title.textColor = .labelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "Try :sku below, then use ↑↓ and Return. A complete :shortcode: replaces itself automatically.")
        subtitle.font = .systemFont(ofSize: 13.5, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 12
        scrollView.layer?.cornerCurve = .continuous
        scrollView.layer?.borderWidth = 0.5
        scrollView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.65).cgColor

        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 22)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 34, height: 32)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        textView.string = "Draft a message\n\nShortmoji stays out of the way until you type a colon.\nTry it here: :sku"
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        scrollView.documentView = textView

        let privacy = NSTextField(labelWithString: "⌘  Everything happens on your Mac — no text leaves this device.")
        privacy.font = .systemFont(ofSize: 12, weight: .regular)
        privacy.textColor = .tertiaryLabelColor
        privacy.translatesAutoresizingMaskIntoConstraints = false

        [eyebrow, title, subtitle, scrollView, privacy].forEach(background.addSubview)
        NSLayoutConstraint.activate([
            eyebrow.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 42),
            eyebrow.topAnchor.constraint(equalTo: background.topAnchor, constant: 62),
            title.leadingAnchor.constraint(equalTo: eyebrow.leadingAnchor),
            title.topAnchor.constraint(equalTo: eyebrow.bottomAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: eyebrow.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: background.trailingAnchor, constant: -42),
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 42),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -42),
            scrollView.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 26),
            scrollView.bottomAnchor.constraint(equalTo: privacy.topAnchor, constant: -20),
            privacy.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            privacy.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -24),
        ])
    }

    func textDidChange(_ notification: Notification) {
        refreshSuggestions()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if !textView.hasMarkedText() { refreshSuggestions() }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if suggestions.isVisible {
            if suggestions.isShowingRelatedGrid {
                switch Int(event.keyCode) {
                case kVK_RightArrow:
                    suggestions.moveRelatedSelection(by: 1)
                    return true
                case kVK_LeftArrow:
                    suggestions.moveRelatedSelection(by: -1)
                    return true
                case kVK_DownArrow:
                    suggestions.moveRelatedSelection(by: 5)
                    return true
                case kVK_UpArrow:
                    suggestions.moveRelatedSelection(by: -5)
                    return true
                case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab:
                    suggestions.chooseSelectedRelated()
                    return true
                case kVK_Delete:
                    _ = suggestions.deleteRelatedSearchCharacter()
                    return true
                case kVK_Escape:
                    if !suggestions.clearRelatedSearch() {
                        suggestions.showSuggestionList()
                    }
                    return true
                default:
                    if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
                        _ = suggestions.appendRelatedSearch(characters)
                        return true
                    }
                }
            }

            switch Int(event.keyCode) {
            case kVK_RightArrow:
                suggestions.showRelatedGrid()
                return true
            case kVK_DownArrow:
                selectedIndex = (selectedIndex + 1) % matches.count
                suggestions.updateSelection(selectedIndex)
                return true
            case kVK_UpArrow:
                selectedIndex = (selectedIndex - 1 + matches.count) % matches.count
                suggestions.updateSelection(selectedIndex)
                return true
            case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab:
                choose(index: selectedIndex)
                return true
            case kVK_Escape:
                suggestions.hide()
                matches = []
                return true
            default:
                break
            }
        }

        if event.charactersIgnoringModifiers == ":",
           let queryRange,
           let match = catalog.exactMatch((textView.string as NSString).substring(with: queryRange)) {
            replace(range: queryRange, with: match.emoji)
            return true
        }
        return false
    }

    private func refreshSuggestions() {
        guard let range = activeQueryRange() else {
            suggestions.hide()
            queryRange = nil
            matches = []
            return
        }
        let query = (textView.string as NSString).substring(with: range)
        guard query.count > 1 else {
            suggestions.hide()
            queryRange = range
            matches = []
            return
        }

        queryRange = range
        matches = catalog.search(query, limit: 6)
        selectedIndex = 0
        guard !matches.isEmpty else {
            suggestions.hide()
            return
        }

        var actual = NSRange()
        let caretRect = textView.firstRect(
            forCharacterRange: NSRange(location: textView.selectedRange().location, length: 0),
            actualRange: &actual
        )
        let anchor = NSPoint(x: caretRect.minX - 3, y: caretRect.minY - 8)
        suggestions.show(entries: matches, selectedIndex: selectedIndex, anchorTopLeft: anchor)
    }

    private func activeQueryRange() -> NSRange? {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return nil }
        let value = textView.string as NSString
        guard selection.location <= value.length else { return nil }
        let prefix = value.substring(to: selection.location) as NSString
        let range = prefix.range(
            of: #":[A-Za-z0-9_+\-]*$"#,
            options: .regularExpression
        )
        return range.location == NSNotFound ? nil : range
    }

    private func choose(index: Int) {
        guard matches.indices.contains(index), let queryRange else { return }
        replace(range: queryRange, with: matches[index].emoji)
    }

    private func choose(entry: EmojiEntry) {
        guard let queryRange else { return }
        replace(range: queryRange, with: entry.emoji)
    }

    private func replace(range: NSRange, with emoji: String) {
        guard textView.shouldChangeText(in: range, replacementString: emoji) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: emoji)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location + (emoji as NSString).length, length: 0))
        suggestions.hide()
        queryRange = nil
        matches = []
    }
}

private final class DemoTextView: NSTextView {
    var interceptKey: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if interceptKey?(event) == true { return }
        super.keyDown(with: event)
    }
}
