//
//  SharedDataManager.swift
//  Termini
//
//  Shared between: Main App & Widget Extension
//  Purpose: Handles reading/writing TerminalState to the App Group container.
//           This is the "bridge" that allows the app and widget to communicate.
//

import Foundation

/// Manages the shared data between the main app and widget.
///
/// How App Groups work:
/// - Both app and widget have access to a shared folder on disk
/// - We save a JSON file to this folder from the main app
/// - The widget reads this JSON file to get the terminal state
///
/// Why a class (not struct)?
/// - We want a single shared instance (singleton pattern)
/// - File I/O operations are side effects, which fit better with reference semantics
final class SharedDataManager {

    /// Singleton instance - both app and widget use the same manager.
    /// This ensures consistent access to the shared data.
    static let shared = SharedDataManager()

    /// The App Group identifier - MUST match what you set in Xcode.
    /// This is how the system knows which shared container to use.
    private let appGroupIdentifier = "group.com.junminkim.termini"

    /// The filename for our shared state file.
    private let stateFileName = "terminal_state.json"

    /// JSON encoder configured for our needs.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601  // Standard date format
        encoder.outputFormatting = .prettyPrinted // Readable for debugging
        return encoder
    }()

    /// JSON decoder configured to match our encoder.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Private init enforces singleton pattern.
    private init() {}

    // MARK: - File URL

    /// Gets the URL to the shared container directory.
    /// Returns nil if App Groups aren't properly configured.
    private var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// The full path to the state JSON file.
    private var stateFileURL: URL? {
        containerURL?.appendingPathComponent(stateFileName)
    }

    // MARK: - Public API

    /// Saves the terminal state to the shared container.
    /// Called by the main app whenever the terminal output changes.
    ///
    /// - Parameter state: The current terminal state to save.
    /// - Throws: If encoding fails or file cannot be written.
    func save(state: TerminalState) throws {
        guard let fileURL = stateFileURL else {
            throw SharedDataError.appGroupNotConfigured
        }

        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)

        // .atomic means: write to temp file first, then rename.
        // This prevents the widget from reading a half-written file.
    }

    /// Loads the terminal state from the shared container.
    /// Called by the widget to get the latest terminal output.
    ///
    /// - Returns: The saved terminal state, or nil if no state exists yet.
    func load() -> TerminalState? {
        guard let fileURL = stateFileURL else {
            print("SharedDataManager: App Group not configured")
            return nil
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // No state saved yet - this is normal on first launch
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(TerminalState.self, from: data)
        } catch {
            print("SharedDataManager: Failed to load state - \(error)")
            return nil
        }
    }

    /// Clears the saved state (useful for testing or reset).
    func clear() {
        guard let fileURL = stateFileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Errors

/// Errors that can occur when accessing shared data.
enum SharedDataError: LocalizedError {
    case appGroupNotConfigured

    var errorDescription: String? {
        switch self {
        case .appGroupNotConfigured:
            return "App Group is not properly configured. Check your entitlements."
        }
    }
}
