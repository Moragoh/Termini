//
//  TerminalState.swift
//  Termini
//
//  Shared between: Main App & Widget Extension
//  Purpose: Defines the data structure for terminal output that gets
//           passed from the main app to the widget via App Groups.
//

import Foundation

/// Represents a snapshot of the terminal's current state.
/// This struct is saved to the shared App Group container so the widget can read it.
///
/// Why Codable? We need to serialize this to JSON to save it to a file.
/// Both the app and widget will encode/decode this struct.
struct TerminalState: Codable {

    /// The raw terminal output, including ANSI escape codes for colors.
    /// Example: "\u{1B}[32mHello\u{1B}[0m" (green "Hello")
    ///
    /// We store raw ANSI rather than pre-parsed colors because:
    /// 1. It's simpler to serialize (just a String)
    /// 2. Both app and widget will parse it the same way
    let outputText: String

    /// When this state was captured.
    /// The widget can use this to show "Last updated: X seconds ago"
    let timestamp: Date

    /// The current working directory of the shell.
    /// Useful for display purposes (e.g., showing "~/Projects" in the widget)
    let currentDirectory: String

    /// Whether the shell is currently running a command.
    /// The widget could show a spinner or indicator when true.
    let isExecutingCommand: Bool

    /// Creates a new terminal state snapshot.
    init(
        outputText: String,
        timestamp: Date = Date(),
        currentDirectory: String = "~",
        isExecutingCommand: Bool = false
    ) {
        self.outputText = outputText
        self.timestamp = timestamp
        self.currentDirectory = currentDirectory
        self.isExecutingCommand = isExecutingCommand
    }

    /// An empty state for initialization or when no data exists yet.
    static let empty = TerminalState(
        outputText: "",
        timestamp: Date(),
        currentDirectory: "~",
        isExecutingCommand: false
    )
}
