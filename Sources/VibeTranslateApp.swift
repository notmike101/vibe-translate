import AppKit
import SwiftUI

@main
struct VibeTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var settings = ProviderSettings()

    var body: some Scene {
        WindowGroup("Vibe Translate") {
            TranslateView(settings: settings)
                .environmentObject(settings)
        }
        .windowResizability(.contentMinSize)
        .commands {
            // One window, one job — the New/Open items have nothing to do.
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .appSettings) {
                Button("Set Up Provider…") {
                    NotificationCenter.default.post(name: .showProviderSetup, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
