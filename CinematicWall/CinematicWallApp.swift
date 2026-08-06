import AppKit
import SwiftUI

@main
struct CinematicWallApp: App {
    @NSApplicationDelegateAdaptor(CinematicWallAppDelegate.self) private var appDelegate
    @StateObject private var engine: WallpaperEngine
    @StateObject private var library: WallpaperLibrary
    @StateObject private var updateManager: UpdateManager
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    init() {
        Self.migrateLegacyUserDefaults()
        UserDefaults.standard.register(defaults: [
            "pauseOnBattery": false,
            "pauseOnLowPower": true,
            "pauseWhenFullscreen": true,
            "restoreLastWallpaper": true,
            "resumeAfterWake": true,
            "syncLockScreenWallpaper": true,
            "wallpaperFit": "fill",
            "displayMode": "all",
            "transitionDuration": 0.35,
            "wallpaperMuted": true,
            "playbackRate": 1.0,
            "appLanguage": AppLanguage.english.rawValue,
        ])

        let wallpaperEngine = WallpaperEngine()
        let wallpaperLibrary = WallpaperLibrary(engine: wallpaperEngine)
        let appUpdateManager = UpdateManager.shared
        _engine = StateObject(wrappedValue: wallpaperEngine)
        _library = StateObject(wrappedValue: wallpaperLibrary)
        _updateManager = StateObject(wrappedValue: appUpdateManager)
        MainAppWindowController.shared.configure(
            engine: wallpaperEngine,
            library: wallpaperLibrary,
            updateManager: appUpdateManager
        )
        // The app delegate can be notified before SwiftUI has finished injecting
        // the shared model objects. A next-run-loop presentation keeps the native
        // main window reliable on both a cold launch and a restored menu-bar launch.
        DispatchQueue.main.async {
            MainAppWindowController.shared.show()
        }
    }

    private static func migrateLegacyUserDefaults() {
        let legacyBundleIdentifier = "com.cinematicwall.app"
        guard let legacyValues = UserDefaults.standard.persistentDomain(forName: legacyBundleIdentifier) else { return }

        let keys = [
            "pauseOnBattery", "pauseOnLowPower", "pauseWhenFullscreen",
            "restoreLastWallpaper", "resumeAfterWake", "wallpaperFit",
            "syncLockScreenWallpaper", "displayMode", "transitionDuration", "wallpaperMuted",
            "playbackRate", "appLanguage",
        ]
        for key in keys where UserDefaults.standard.object(forKey: key) == nil {
            if let value = legacyValues[key] {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            NowPlayingPanelView()
                .environmentObject(library)
                .environmentObject(engine)
                .environment(\.colorScheme, .dark)
        } label: {
            Image(systemName: engine.currentItem == nil ? "sparkles.tv" : "sparkles.tv.fill")
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(after: .newItem) {
                Button(AppLanguage(rawValue: appLanguage)?.text("Import Wallpaper…", "导入壁纸…") ?? "Import Wallpaper…") {
                    library.presentImportPanel()
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(library)
                .environmentObject(engine)
                .environmentObject(updateManager)
                .preferredColorScheme(.dark)
        }
    }

}

@MainActor
final class CinematicWallAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainAppWindowController.shared.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainAppWindowController.shared.show()
        return true
    }
}

@MainActor
final class MainAppWindowController: NSObject, NSWindowDelegate {
    static let shared = MainAppWindowController()

    private var engine: WallpaperEngine?
    private var library: WallpaperLibrary?
    private var updateManager: UpdateManager?
    private var window: NSWindow?

    func configure(engine: WallpaperEngine, library: WallpaperLibrary, updateManager: UpdateManager) {
        self.engine = engine
        self.library = library
        self.updateManager = updateManager
    }

    func show() {
        guard let engine, let library, let updateManager else { return }
        if let window {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let content = RootView()
            .environmentObject(library)
            .environmentObject(engine)
            .environmentObject(updateManager)
            .preferredColorScheme(.dark)
            .background(WindowAppearanceConfigurator())
        let hostingView = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_320, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppLanguage.current.brandName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 1_080, height: 700)
        window.contentView = hostingView
        window.delegate = self
        window.center()
        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
