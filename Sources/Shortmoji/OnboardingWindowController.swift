import AppKit

final class OnboardingWindowController: NSWindowController {
    var permissionGranted: (() -> Void)?
    var openPlayground: (() -> Void)?
    private let statusLabel = NSTextField(labelWithString: "Accessibility access is required")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 390),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Shortmoji"
        window.titlebarAppearsTransparent = true
        window.center()
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        refreshStatus()
    }

    private func buildContent() {
        guard let window else { return }
        let background = NSVisualEffectView(frame: .zero)
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active
        window.contentView = background

        let icon = NSImageView(frame: .zero)
        icon.image = NSImage(systemSymbolName: "face.smiling.inverse", accessibilityDescription: "Shortmoji")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 45, weight: .medium)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Emoji shortcuts, everywhere")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(wrappingLabelWithString: "Shortmoji watches for codes like :skull: and inserts the matching emoji in any app. macOS requires Accessibility permission so it can read shortcuts and type the replacement.")
        body.font = .systemFont(ofSize: 13.5)
        body.textColor = .secondaryLabelColor
        body.alignment = .center
        body.maximumNumberOfLines = 4
        body.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let openButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openSettings))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .large
        openButton.keyEquivalent = "\r"
        openButton.translatesAutoresizingMaskIntoConstraints = false

        let checkButton = NSButton(title: "Check Again", target: self, action: #selector(checkAgain))
        checkButton.bezelStyle = .rounded
        checkButton.translatesAutoresizingMaskIntoConstraints = false

        let tryButton = NSButton(title: "Try the Playground", target: self, action: #selector(tryPlayground))
        tryButton.bezelStyle = .rounded
        tryButton.translatesAutoresizingMaskIntoConstraints = false

        [icon, title, body, statusLabel, openButton, checkButton, tryButton].forEach(background.addSubview)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            icon.topAnchor.constraint(equalTo: background.topAnchor, constant: 62),
            icon.widthAnchor.constraint(equalToConstant: 58),
            icon.heightAnchor.constraint(equalToConstant: 58),
            title.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 18),
            body.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            body.widthAnchor.constraint(equalToConstant: 390),
            statusLabel.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 18),
            openButton.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            openButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            openButton.widthAnchor.constraint(equalToConstant: 230),
            checkButton.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            checkButton.topAnchor.constraint(equalTo: openButton.bottomAnchor, constant: 10),
            tryButton.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            tryButton.topAnchor.constraint(equalTo: checkButton.bottomAnchor, constant: 8),
        ])
    }

    private func refreshStatus() {
        let trusted = GlobalInputController.isAccessibilityTrusted()
        statusLabel.stringValue = trusted ? "Access granted — Shortmoji is ready" : "Accessibility access is required"
        statusLabel.textColor = trusted ? .systemGreen : .secondaryLabelColor
        if trusted {
            permissionGranted?()
            window?.close()
        }
    }

    @objc private func openSettings() {
        _ = GlobalInputController.isAccessibilityTrusted(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func checkAgain() {
        refreshStatus()
    }

    @objc private func tryPlayground() {
        window?.close()
        openPlayground?()
    }
}
