//
//  TerminalViewModel.swift
//  Termini
//
//  Purpose: The "brain" of the terminal - manages state and coordinates
//           between the PTY (shell) and the View (UI).
//
//  MVVM Architecture:
//  - Model: TerminalState, PTYManager, TerminalEmulator (data and business logic)
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
final class TerminalViewModel: ObservableObject {

    // MARK: - Published Properties (UI State)

    /// Counter that increments on every update (for debugging SwiftUI reactivity)
    @Published var updateCounter: Int = 0

    /// The terminal output as styled text, ready for display.
    @Published var attributedOutput: AttributedString = AttributedString()

    /// Plain text output for debugging
    @Published var plainTextOutput: String = ""

    /// Current user input being typed (before pressing Enter).
    @Published var currentInput: String = ""

    /// Whether the shell is currently running.
    @Published private(set) var isRunning: Bool = false

    /// Whether we're currently in the alternate screen buffer (TUI apps like vim).
    @Published private(set) var isAlternateScreenActive: Bool = false

    /// Current cursor position in the terminal.
    @Published private(set) var cursorPosition: CursorPosition = .origin

    /// Error message to display, if any.
    @Published var errorMessage: String?

    // MARK: - Private Properties

    /// The terminal emulator with 2D buffer and cursor tracking.
    private let emulator: TerminalEmulator

    /// The PTY manager that runs the shell.
    private let ptyManager = PTYManager()

    /// Shared data manager for widget communication.
    private let sharedData = SharedDataManager.shared

    /// Limits how often we save to shared data (for widget).
    /// We don't want to write to disk on every single character.
    private var saveWorkItem: DispatchWorkItem?

    /// Tracks when we last saved to shared data (for throttling).
    private var lastSaveTime: Date = .distantPast

    /// Terminal dimensions.
    private var terminalRows: Int = 24
    private var terminalColumns: Int = 80

    // MARK: - Initialization

    init() {
        self.emulator = TerminalEmulator(rows: terminalRows, columns: terminalColumns)
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

    /// Notifies the PTY and emulator of a window size change.
    func resize(columns: Int, rows: Int) {
        terminalColumns = columns
        terminalRows = rows
        ptyManager.resize(columns: columns, rows: rows)
        emulator.resize(rows: rows, columns: columns)
        renderOutput()
    }

    /// Clears the terminal output.
    func clear() {
        emulator.reset()
        renderOutput()
        saveToSharedData()
    }

    // MARK: - Private Methods

    /// Sets up callbacks from the PTY manager.
    private func setupPTYCallbacks() {
        // Note: PTYManager already dispatches these callbacks to main thread
        ptyManager.onOutput = { [weak self] text in
            self?.handleOutput(text)
        }

        ptyManager.onProcessExit = { [weak self] in
            self?.isRunning = false
        }
    }

    /// Handles new output from the shell using command-based parsing.
    private func handleOutput(_ text: String) {
        // DEBUG: Print what we received from the shell
        print("[DEBUG] Received \(text.count) chars: \(text.debugDescription)")

        // Parse raw output into terminal commands
        let commands = ANSIParser.parseToCommands(text)

        // DEBUG: Print each parsed command
        print("[DEBUG] Parsed \(commands.count) commands:")
        for (i, cmd) in commands.enumerated() {
            print("[DEBUG]   [\(i)] \(cmd)")
        }

        // Execute each command on the emulator
        print("[DEBUG] Cursor before execution: row=\(emulator.activeBuffer.cursor.row) col=\(emulator.activeBuffer.cursor.column)")
        for (i, cmd) in commands.enumerated() {
            emulator.execute(cmd)
            print("[DEBUG]   After cmd[\(i)]: cursor row=\(emulator.activeBuffer.cursor.row) col=\(emulator.activeBuffer.cursor.column)")
        }

        // Update published state
        isAlternateScreenActive = emulator.isUsingAlternateBuffer
        cursorPosition = emulator.cursorPosition

        // Re-render the display
        renderOutput()

        // DEBUG: Print buffer state
        print("[DEBUG] Buffer cursor: row=\(emulator.activeBuffer.cursor.row) col=\(emulator.activeBuffer.cursor.column)")
        print("[DEBUG] Plain text output: \"\(emulator.toPlainText())\"")

        // Schedule save to shared data (debounced)
        scheduleSaveToSharedData()
    }

    /// Renders the emulator's buffer to the published output properties.
    private func renderOutput() {
        // Force SwiftUI to see the update by explicitly triggering objectWillChange
        objectWillChange.send()
        updateCounter += 1
        plainTextOutput = emulator.toPlainText()
        attributedOutput = emulator.toAttributedString()
    }

    /// Saves current state to shared data for the widget.
    /// Throttled to avoid excessive disk writes while ensuring updates happen.
    private func scheduleSaveToSharedData() {
        let throttleInterval: TimeInterval = 10.0
        let timeSinceLastSave = Date().timeIntervalSince(lastSaveTime)

        // If enough time has passed, save immediately
        if timeSinceLastSave >= throttleInterval {
            saveToSharedData()
            return
        }

        // Otherwise, schedule a save for when the throttle window ends
        // (but only if one isn't already scheduled)
        guard saveWorkItem == nil else { return }

        let delay = throttleInterval - timeSinceLastSave
        saveWorkItem = DispatchWorkItem { [weak self] in
            self?.saveWorkItem = nil
            self?.saveToSharedData()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: saveWorkItem!)
    }

    /// Actually saves the state to shared data.
    private func saveToSharedData() {
        lastSaveTime = Date()

        // Get current working directory from environment if possible
        let cwd = FileManager.default.currentDirectoryPath

        // Get plain text output from the emulator
        // Only save primary buffer content to widget (not alternate screen content)
        let plainOutput: String
        if emulator.isUsingAlternateBuffer {
            // When in alternate screen (vim, htop), show a message in widget
            plainOutput = "[TUI application running]"
        } else {
            plainOutput = emulator.toPlainText()
        }

        let state = TerminalState(
            outputText: plainOutput,
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
