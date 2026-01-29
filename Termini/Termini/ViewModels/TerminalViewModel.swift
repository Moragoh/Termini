//
//  TerminalViewModel.swift
//  Termini
//
//  Purpose: The "brain" of the terminal - manages state and coordinates
//           between the PTY (shell) and the View (UI).
//
//  MVVM Architecture:
//  - Model: TerminalState, PTYManager (data and business logic)
//  - ViewModel: This file (connects Model to View, manages UI state)
//  - View: ContentView (displays UI, sends user actions)
//
//  Why separate ViewModel from View?
//  1. Views should be "dumb" - they just display what they're told
//  2. ViewModels can be tested without UI
//  3. Logic changes don't require UI changes (and vice versa)
//

import SwiftUI
import Combine
import WidgetKit

/// Manages the terminal's state and handles communication between PTY and UI.
///
/// ObservableObject + @Published allows SwiftUI to automatically
/// update the view when these properties change.
@MainActor
final class TerminalViewModel: ObservableObject {

    // MARK: - Published Properties (UI State)

    /// The terminal output as styled text, ready for display.
    @Published var attributedOutput: AttributedString = AttributedString()

    /// The raw output text (with ANSI codes) - kept for debugging and sharing.
    @Published private(set) var rawOutput: String = ""

    /// Current user input being typed (before pressing Enter).
    @Published var currentInput: String = ""

    /// Whether the shell is currently running.
    @Published private(set) var isRunning: Bool = false

    /// Error message to display, if any.
    @Published var errorMessage: String?

    // MARK: - Private Properties

    /// The PTY manager that runs the shell.
    private let ptyManager = PTYManager()

    /// Shared data manager for widget communication.
    private let sharedData = SharedDataManager.shared

    /// Limits how often we save to shared data (for widget).
    /// We don't want to write to disk on every single character.
    private var saveWorkItem: DispatchWorkItem?

    /// Maximum number of characters to keep in output buffer.
    /// Prevents memory issues with very long sessions.
    private let maxOutputLength = 50_000

    // MARK: - Initialization

    init() {
        setupPTYCallbacks()
    }

    // MARK: - Public API

    /// Starts the terminal shell session.
    func start() {
        guard !isRunning else { return }

        do {
            try ptyManager.start()
            isRunning = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stops the terminal shell session.
    func stop() {
        ptyManager.stop()
        isRunning = false
    }

    /// Sends user input to the shell.
    /// Called when the user presses Enter.
    func sendCommand() {
        let command = currentInput + "\n"
        ptyManager.send(command)
        currentInput = ""
    }

    /// Sends raw text to the shell (without adding newline).
    func send(_ text: String) {
        ptyManager.send(text)
    }

    /// Sends a control character to the shell.
    /// - Parameter key: The character (e.g., "c" for Ctrl+C)
    func sendControl(_ key: Character) {
        // Control characters are ASCII 1-26 (A=1, B=2, ..., Z=26)
        guard let ascii = key.lowercased().first?.asciiValue else { return }
        let controlCode = ascii - Character("a").asciiValue! + 1
        ptyManager.sendByte(UInt8(controlCode))
    }

    /// Notifies the PTY of a window size change.
    func resize(columns: Int, rows: Int) {
        ptyManager.resize(columns: columns, rows: rows)
    }

    /// Clears the terminal output.
    func clear() {
        rawOutput = ""
        attributedOutput = AttributedString()
        saveToSharedData()
    }

    // MARK: - Private Methods

    /// Sets up callbacks from the PTY manager.
    private func setupPTYCallbacks() {
        ptyManager.onOutput = { [weak self] text in
            self?.handleOutput(text)
        }

        ptyManager.onProcessExit = { [weak self] in
            self?.isRunning = false
        }
    }

    /// Handles new output from the shell.
    private func handleOutput(_ text: String) {
        // Append to raw output
        rawOutput += text

        // Trim if too long (keep the end, discard the beginning)
        if rawOutput.count > maxOutputLength {
            let startIndex = rawOutput.index(rawOutput.endIndex, offsetBy: -maxOutputLength)
            rawOutput = String(rawOutput[startIndex...])
        }

        // Parse ANSI codes and update styled output
        attributedOutput = ANSIParser.parse(rawOutput)

        // Schedule save to shared data (debounced)
        scheduleSaveToSharedData()
    }

    /// Saves current state to shared data for the widget.
    /// Debounced to avoid excessive disk writes.
    private func scheduleSaveToSharedData() {
        saveWorkItem?.cancel()

        saveWorkItem = DispatchWorkItem { [weak self] in
            self?.saveToSharedData()
        }

        // Wait 1 second before saving (debounce).
        // This balances responsiveness with avoiding excessive disk I/O.
        // Since Apple throttles widget refreshes anyway, more frequent
        // saves don't help the widget update faster.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: saveWorkItem!)
    }

    /// Actually saves the state to shared data.
    private func saveToSharedData() {
        // Get current working directory from environment if possible
        let cwd = FileManager.default.currentDirectoryPath

        let state = TerminalState(
            outputText: rawOutput,
            timestamp: Date(),
            currentDirectory: cwd,
            isExecutingCommand: false
        )

        do {
            try sharedData.save(state: state)

            // Tell the widget to refresh.
            // Note: Apple still throttles this, but it's more responsive
            // than time-based polling. The widget will update "soon" after
            // this call, but not instantly.
            WidgetCenter.shared.reloadTimelines(ofKind: "TerminiWidget")
        } catch {
            print("Failed to save shared data: \(error)")
        }
    }
}
