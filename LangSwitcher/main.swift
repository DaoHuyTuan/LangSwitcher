import Cocoa
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var appInputMappings: [String: String] = [:]

    func applicationDidFinishLaunching(_ aNotification: Notification) {
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
        let addItem = NSMenuItem(title: "Add Application", action: #selector(addApplication), keyEquivalent: "")
        addItem.target = self // Đảm bảo target được gán
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        
        menu.addItem(addItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
        
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
                print("Switching to input source \(inputSource) for \(bundleID)")
                self.switchInputSource(to: inputSource)
            }
        }
    }
    
    @objc func addApplication() {
        print("Add Application clicked")
        DispatchQueue.main.async { // Đảm bảo chạy trên main thread
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            
            panel.begin { response in
                print("Panel response: \(response)")
                if response == .OK, let url = panel.url {
                    print("Selected app: \(url)")
                    self.selectInputSource(for: url)
                } else {
                    print("No app selected or panel canceled")
                }
            }
        }
    }
    
    func selectInputSource(for appURL: URL) {
        print("Selecting input source for: \(appURL)")
        guard let bundleID = Bundle(url: appURL)?.bundleIdentifier else {
            print("No bundle ID found for \(appURL)")
            return
        }
        print("Bundle ID: \(bundleID)")
        
        let alert = NSAlert()
        alert.messageText = "Select Input Source for \(appURL.lastPathComponent)"
        
        let inputSources = getAvailableInputSources()
        print("Available input sources: \(inputSources)")
        if inputSources.isEmpty {
            print("No input sources available")
            return
        }
        
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 25))
        popup.addItems(withTitles: inputSources)
        
        alert.accessoryView = popup
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        print("Alert response: \(response)") // .alertFirstButtonReturn = 1000
        if response == .alertFirstButtonReturn {
            let selectedSource = popup.selectedItem?.title ?? ""
            print("Mapped \(bundleID) to \(selectedSource)")
            self.appInputMappings[bundleID] = selectedSource
            self.saveMappings()
            self.updateMenu()
        } else {
            print("Alert canceled")
        }
    }
    
    func getAvailableInputSources() -> [String] {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            print("Failed to get input sources")
            return []
        }
        
        let sourceNames = sources.compactMap { source -> String? in
            guard let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return nil }
            return Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
        }
        return sourceNames
    }
    
    func switchInputSource(to sourceName: String) {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            print("Failed to get input sources for switching")
            return
        }
        
        for source in sources {
            guard let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { continue }
            let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
            if name == sourceName {
                print("Switching input source to: \(name)")
                TISSelectInputSource(source)
                break
            }
        }
    }
    
    func saveMappings() {
        UserDefaults.standard.set(appInputMappings, forKey: "AppInputMappings")
        print("Mappings saved: \(appInputMappings)")
    }
    
    func loadMappings() {
        if let savedMappings = UserDefaults.standard.dictionary(forKey: "AppInputMappings") as? [String: String] {
            appInputMappings = savedMappings
            print("Mappings loaded: \(appInputMappings)")
            updateMenu()
        }
    }
    
    func updateMenu() {
        menu.removeAllItems()
        
        for (appID, source) in appInputMappings {
            if let appName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID)?.lastPathComponent {
                let item = NSMenuItem(title: "\(appName): \(source)", action: nil, keyEquivalent: "")
                menu.addItem(item)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        let addItem = NSMenuItem(title: "Add Application", action: #selector(addApplication), keyEquivalent: "")
        addItem.target = self
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(addItem)
        menu.addItem(quitItem)
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(self)
    }
}

// Khởi chạy ứng dụng
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApp.run()
