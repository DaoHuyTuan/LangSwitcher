import Cocoa
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var appInputMappings: [String: String] = [:]

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyboard Switcher")
        }
        
        setupMenu()
        setupAppSwitchObserver()
        loadMappings()
    }
    
    func setupMenu() {
        menu = NSMenu()
        updateMenu()
        statusItem.menu = menu
    }
    
    func setupAppSwitchObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            
            if let inputSource = self.appInputMappings[bundleID] {
                self.switchInputSource(to: inputSource)
            }
        }
    }
    
    @objc func addApplication() {
        // Temporarily switch to regular mode to handle the panel
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        panel.level = .floating
        positionWindowNearMouse(window: panel)
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.selectInputSource(for: url)
            }
            // Revert to accessory mode after panel interaction
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    func selectInputSource(for appURL: URL) {
        guard let bundleID = Bundle(url: appURL)?.bundleIdentifier else { return }
        
        // Temporarily switch to regular mode to handle the alert
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        let alert = NSAlert()
        alert.messageText = "Select Input Source for \(appURL.lastPathComponent)"
        
        let inputSources = getAvailableInputSources()
        if inputSources.isEmpty {
            NSApp.setActivationPolicy(.accessory)
            return
        }
        
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 25))
        popup.addItems(withTitles: inputSources)
        
        alert.accessoryView = popup
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        alert.window.level = .floating
        positionWindowNearMouse(window: alert.window)
        
        if alert.runModal() == .alertFirstButtonReturn {
            let selectedSource = popup.selectedItem?.title ?? ""
            self.appInputMappings[bundleID] = selectedSource
            self.saveMappings()
            self.updateMenu()
        }
        
        // Revert to accessory mode after alert interaction
        NSApp.setActivationPolicy(.accessory)
    }
    
    func positionWindowNearMouse(window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        
        var newOrigin = mouseLocation
        let windowSize = window.frame.size
        
        newOrigin.x = min(max(newOrigin.x, screenFrame.minX), screenFrame.maxX - windowSize.width)
        newOrigin.y = min(max(newOrigin.y - windowSize.height, screenFrame.minY), screenFrame.maxY - windowSize.height)
        
        window.setFrameOrigin(newOrigin)
    }
    
    func getAvailableInputSources() -> [String] {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return sources.compactMap { source in
            guard let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return nil }
            return Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
        }
    }
    
    func switchInputSource(to sourceName: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return }
            for source in sources {
                guard let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { continue }
                let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
                if name == sourceName {
                    TISSelectInputSource(source)
                    break
                }
            }
        }
    }
    
    func saveMappings() {
        UserDefaults.standard.set(appInputMappings, forKey: "AppInputMappings")
    }
    
    func loadMappings() {
        if let savedMappings = UserDefaults.standard.dictionary(forKey: "AppInputMappings") as? [String: String] {
            appInputMappings = savedMappings
            updateMenu()
        }
    }
    
    func updateMenu() {
        menu.removeAllItems()
        
        for (appID, source) in appInputMappings {
            if let appName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID)?.lastPathComponent {
                menu.addItem(withTitle: "\(appName): \(source)", action: nil, keyEquivalent: "")
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Add Application", action: #selector(addApplication), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(self)
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApp.setActivationPolicy(.prohibited)
NSApp.run()
