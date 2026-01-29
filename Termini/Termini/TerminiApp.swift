//
//  TerminiApp.swift
//  Termini
//
//  Purpose: The app entry point. Configures the main window and
//           ensures the shell persists when the window is closed.
//

import SwiftUI

@main
struct TerminiApp: App {
    /// Delegate to handle app lifecycle events.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 400, minHeight: 300)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 600, height: 400)
        .commands {
            // Add keyboard shortcuts
            CommandGroup(replacing: .newItem) { }  // Disable Cmd+N (we only want one terminal)
        }
    }
}

// MARK: - App Delegate

/// Handles app-level events like window closing.
///
/// Why do we need this?
/// By default, macOS apps quit when the last window closes.
/// We need to override this so the shell keeps running in the background.
class AppDelegate: NSObject, NSApplicationDelegate {

    /// Called when the last window is closed.
    /// Return false to prevent the app from terminating.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the app running so the shell persists
        // The user can quit via Cmd+Q or the menu
        return false
    }

    /// Called when the user clicks the dock icon while the app is running.
    /// This reopens the window if it was closed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows - create one
            // The WindowGroup will automatically recreate the window
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }
}
