import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let suggestionPanel = SuggestionPanelController()
    private lazy var globalInput = GlobalInputController(suggestions: suggestionPanel)
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private var stateItem: NSMenuItem!
    private var demoWindow: DemoWindowController?
    private var onboardingWindow: OnboardingWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()

        globalInput.statusChanged = { [weak self] _ in
            self?.refreshMenuState()
        }

        if CommandLine.arguments.contains("--demo") || UserDefaults.standard.bool(forKey: "ShortmojiPreviewMode") {
            showPlayground(nil)
            return
        }

        let shouldEnable = UserDefaults.standard.object(forKey: "ShortmojiEnabled") as? Bool ?? true
        if shouldEnable, globalInput.start() == false {
            showOnboarding()
        }
        refreshMenuState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalInput.stop()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "face.smiling.inverse", accessibilityDescription: "Shortmoji")
            button.image?.isTemplate = true
            button.toolTip = "Shortmoji"
        }

        let menu = NSMenu()
        stateItem = NSMenuItem(title: "Shortmoji is ready", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        enabledItem = NSMenuItem(title: "Enable Shortmoji", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)

        let playgroundItem = NSMenuItem(title: "Open Playground…", action: #selector(showPlayground), keyEquivalent: "")
        playgroundItem.target = self
        menu.addItem(playgroundItem)

        let permissionsItem = NSMenuItem(title: "Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Shortmoji", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func refreshMenuState() {
        let trusted = GlobalInputController.isAccessibilityTrusted()
        enabledItem.state = globalInput.isRunning ? .on : .off
        stateItem.title = globalInput.isRunning
            ? "Shortmoji is listening"
            : (trusted ? "Shortmoji is paused" : "Accessibility access needed")
    }

    @objc private func toggleEnabled() {
        if globalInput.isRunning {
            globalInput.stop()
            UserDefaults.standard.set(false, forKey: "ShortmojiEnabled")
        } else if globalInput.start() {
            UserDefaults.standard.set(true, forKey: "ShortmojiEnabled")
        } else {
            showOnboarding()
        }
        refreshMenuState()
    }

    @objc private func showPlayground(_ sender: Any?) {
        if demoWindow == nil { demoWindow = DemoWindowController() }
        demoWindow?.show()
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            let controller = OnboardingWindowController()
            controller.permissionGranted = { [weak self] in
                UserDefaults.standard.set(true, forKey: "ShortmojiEnabled")
                _ = self?.globalInput.start()
                self?.refreshMenuState()
            }
            controller.openPlayground = { [weak self] in
                self?.showPlayground(nil)
            }
            onboardingWindow = controller
        }
        onboardingWindow?.show()
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
