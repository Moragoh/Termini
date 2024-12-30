//
//  TerminiApp.swift
//  Termini
//
//  Created by Jun Min Kim on 12/27/24.
//

import SwiftUI
import SwiftData

@main
struct TerminiApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
            .frame(minWidth: 600, minHeight: 400) // Set the minimum window size
            .onAppear {
                // shared.windows is an array of windows managed by the app. We select the first and only window
                // After we obtain window, we make stylistic changes to it
                if let window = NSApplication.shared.windows.first {
                    window.titlebarAppearsTransparent = true
                    window.isOpaque = false
                    window.backgroundColor = .black
                    window.hasShadow = false
//                    window.styleMask.remove(.titled)
//                    window.styleMask.remove(.resizable)
//                    window.styleMask.remove(.closable)
//                    window.styleMask.remove(.miniaturizable)
                }
           }
        }
        .modelContainer(sharedModelContainer)
    }
}
