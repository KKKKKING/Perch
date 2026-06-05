import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    var window: NSWindow!
    let appState = AppState()

    private let railW: CGFloat = 78
    private let colW: CGFloat = 374
    private let initialColW: CGFloat = 552
    private var mainContentSize: NSSize { NSSize(width: railW + initialColW, height: 872) }
    private let welcomeSize = NSSize(width: 560, height: 584)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = PerchAppIcon.shared
        if let iconPath = ProcessInfo.processInfo.environment["PERCH_ICON_PNG"] {
            PerchAppIcon.writePNG(to: iconPath, pixels: 512)
            NSApplication.shared.terminate(nil)
            return
        }
        buildMainMenu()

        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: mainContentSize.width, height: mainContentSize.height),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = "Perch"
        window.isMovableByWindowBackground = true
        window.backgroundColor = ThemeManager.shared.theme.bgBase
        window.minSize = NSSize(width: railW + colW, height: 520)

        // keep native traffic lights overlaid on the reserved top-left area of the rail
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false

        window.makeKeyAndOrderFront(nil)
        app(activate: NSApplication.shared)

        let snapshotEnv = ProcessInfo.processInfo.environment["PERCH_SNAPSHOT"]
        let stateEnv = ProcessInfo.processInfo.environment["PERCH_STATE"]
        let restored = snapshotEnv == nil ? TwitterService.shared.restoreSessions() : []
        appState.seedAccounts()
        if snapshotEnv != nil, stateEnv != "welcome", appState.accounts.isEmpty {
            let acct = Account(id: "debug_x", name: "Alex Rivers", handle: "alexrivers",
                               colorToken: "indigo-700", verified: true, platform: .x,
                               followers: "24.8K", following: "892")
            appState.accounts = [acct]
            appState.activeId = acct.id!
            appState.composeFrom = acct.id!
            appState.unread[acct.id!] = 0
        }

        if stateEnv == "welcome" || appState.accounts.isEmpty {
            showWelcome()
        } else {
            showMainApp()
            if let acct = restored.first(where: { $0.id == appState.activeId }) ?? restored.first {
                appState.setActive(acct.id!)
                appState.refreshLiveTimeline(for: acct)
            }
        }

        // App-level foreground/background gating for auto-refresh. The RootVC view
        // lifecycle handles the initial start (its `viewDidAppear`, after the launch
        // activation above); these hooks pause polling when the app is hidden and
        // resume — with an immediate tick — on return. Skipped under snapshot mode,
        // which terminates deterministically and has no live session to poll.
        if snapshotEnv == nil {
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(appDidBecomeActive),
                           name: NSApplication.didBecomeActiveNotification, object: nil)
            nc.addObserver(self, selector: #selector(appWillResignActive),
                           name: NSApplication.willResignActiveNotification, object: nil)
        }

        if let path = snapshotEnv {
            let state = ProcessInfo.processInfo.environment["PERCH_STATE"]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if let state, let root = self?.window.contentViewController as? RootViewController {
                    root.debugApply(state)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self?.snapshot(to: path)
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    func showWelcome() {
        let wc = WelcomeViewController(appState: appState, onOpenApp: { [weak self] in self?.showMainApp() })
        window.contentViewController = wc
        window.backgroundColor = ThemeManager.shared.theme.bgBase
        window.setContentSize(welcomeSize)
        window.minSize = welcomeSize
        window.center()
    }

    func showMainApp() {
        let root = RootViewController(appState: appState)
        root.onRequestWelcome = { [weak self] in self?.showWelcome() }
        window.contentViewController = root
        window.minSize = NSSize(width: railW + colW, height: 520)
        window.setContentSize(mainContentSize)
        window.center()
    }

    private func snapshot(to path: String) {
        // Auxiliary panels (compose/settings/add-account) are now their own
        // windows; snapshot the frontmost panel when one is open.
        let target: NSWindow = (NSApp.keyWindow as? PanelWindow)
            ?? NSApp.windows.first(where: { $0 is PanelWindow && $0.isVisible })
            ?? window
        guard let content = target.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let rect = content.bounds
        guard let rep = content.bitmapImageRepForCachingDisplay(in: rect) else { return }
        content.cacheDisplay(in: rect, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private func app(activate app: NSApplication) {
        app.activate(ignoringOtherApps: true)
    }


    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    @objc private func appDidBecomeActive() { appState.resumeAutoRefresh() }
    @objc private func appWillResignActive() { appState.pauseAutoRefresh() }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let appName = "Perch"
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu (for text fields / textarea support)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApplication.shared.windowsMenu = windowMenu

        NSApplication.shared.mainMenu = mainMenu
    }
}
