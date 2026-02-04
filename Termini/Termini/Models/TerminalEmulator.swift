//
//  TerminalEmulator.swift
//  Termini
//
//  Purpose: Coordinates terminal emulation with dual buffer support.
//           Executes TerminalCommand objects against the active buffer.
//

import SwiftUI

/// Manages the terminal emulation state, including dual screen buffers.
///
/// This class handles:
/// - Primary and alternate screen buffers (for TUI apps like vim)
/// - Command execution against the active buffer
/// - Cursor state preservation across buffer switches
/// - Terminal resize operations
final class TerminalEmulator {

    // MARK: - Properties

    /// The primary screen buffer (normal terminal content).
    private(set) var primaryBuffer: TerminalBuffer

    /// The alternate screen buffer (used by full-screen TUI apps).
    private(set) var alternateBuffer: TerminalBuffer

    /// Whether we're currently using the alternate screen buffer.
    private(set) var isUsingAlternateBuffer: Bool = false

    /// Saved cursor position for primary buffer (when switching to alternate).
    private var primarySavedCursor: CursorPosition = .origin
    private var primarySavedAttributes: CellAttributes = .default

    /// Whether the cursor is visible.
    private(set) var isCursorVisible: Bool = true

    /// Whether bracketed paste mode is enabled.
    private(set) var isBracketedPasteModeEnabled: Bool = false

    /// The active buffer (either primary or alternate).
    var activeBuffer: TerminalBuffer {
        isUsingAlternateBuffer ? alternateBuffer : primaryBuffer
    }

    /// Current cursor position in the active buffer.
    var cursorPosition: CursorPosition {
        activeBuffer.cursor
    }

    // MARK: - Initialization

    /// Creates a new terminal emulator with the specified dimensions.
    /// - Parameters:
    ///   - rows: Number of rows (default 24).
    ///   - columns: Number of columns (default 80).
    init(rows: Int = 24, columns: Int = 80) {
        self.primaryBuffer = TerminalBuffer(rows: rows, columns: columns)
        self.alternateBuffer = TerminalBuffer(rows: rows, columns: columns)
    }

    // MARK: - Command Execution

    /// Executes a terminal command against the active buffer.
    /// - Parameter command: The command to execute.
    func execute(_ command: TerminalCommand) {
        let buffer = activeBuffer

        switch command {
        // Text output
        case .print(let char):
            buffer.writeCharacter(char)

        case .printString(let str):
            for char in str {
                buffer.writeCharacter(char)
            }

        // Control characters
        case .carriageReturn:
            buffer.carriageReturn()

        case .lineFeed:
            buffer.lineFeed()

        case .backspace:
            buffer.backspace()

        case .tab:
            buffer.tab()

        case .bell:
            // Could trigger system alert - for now, ignore
            NSSound.beep()

        // Cursor movement
        case .cursorUp(let n):
            buffer.moveCursorRelative(deltaRow: -n, deltaColumn: 0)

        case .cursorDown(let n):
            buffer.moveCursorRelative(deltaRow: n, deltaColumn: 0)

        case .cursorForward(let n):
            buffer.moveCursorRelative(deltaRow: 0, deltaColumn: n)

        case .cursorBack(let n):
            buffer.moveCursorRelative(deltaRow: 0, deltaColumn: -n)

        case .cursorNextLine(let n):
            buffer.moveCursorRelative(deltaRow: n, deltaColumn: 0)
            buffer.carriageReturn()

        case .cursorPreviousLine(let n):
            buffer.moveCursorRelative(deltaRow: -n, deltaColumn: 0)
            buffer.carriageReturn()

        case .cursorColumn(let col):
            buffer.moveCursor(to: CursorPosition(row: buffer.cursor.row, column: col))

        case .cursorPosition(let row, let col):
            print("[DEBUG Emulator] cursorPosition row=\(row) col=\(col)")
            buffer.moveCursor(to: CursorPosition(row: row, column: col))

        case .cursorHome:
            print("[DEBUG Emulator] cursorHome")
            buffer.moveCursor(to: .origin)

        case .saveCursor:
            buffer.saveCursor()

        case .restoreCursor:
            buffer.restoreCursor()

        // Erasing
        case .eraseInDisplay(let mode):
            print("[DEBUG Emulator] eraseInDisplay mode=\(mode)")
            buffer.clearScreen(mode: mode)

        case .eraseInLine(let mode):
            print("[DEBUG Emulator] eraseInLine mode=\(mode)")
            buffer.clearLine(mode: mode)

        case .deleteCharacters(let n):
            buffer.deleteCharacters(n)

        case .insertCharacters(let n):
            buffer.insertCharacters(n)

        case .deleteLines(let n):
            buffer.deleteLines(n)

        case .insertLines(let n):
            buffer.insertLines(n)

        // Scrolling
        case .scrollUp(let n):
            buffer.scrollUp(lines: n)

        case .scrollDown(let n):
            buffer.scrollDown(lines: n)

        case .setScrollRegion(let top, let bottom):
            let clampedBottom = min(bottom, buffer.rows - 1)
            buffer.setScrollRegion(top: top, bottom: clampedBottom)

        // Attributes
        case .setAttributes(let attrs):
            buffer.currentAttributes = attrs

        case .resetAttributes:
            buffer.currentAttributes = .default

        case .setAttribute(let sgr):
            applyAttribute(sgr, to: buffer)

        // Screen buffer switching
        case .switchToAlternateScreen:
            switchToAlternateScreen()

        case .switchToPrimaryScreen:
            switchToPrimaryScreen()

        // Private modes
        case .setPrivateMode(_, _):
            // Most private modes don't affect our emulation
            break

        case .bracketedPasteMode(let enabled):
            isBracketedPasteModeEnabled = enabled

        case .showCursor:
            isCursorVisible = true

        case .hideCursor:
            isCursorVisible = false

        // Other
        case .setWindowTitle:
            // Could be used to set window title - not implemented
            break

        case .unknown:
            // Log unknown sequences for debugging if needed
            break
        }
    }

    /// Executes multiple commands in sequence.
    /// - Parameter commands: The commands to execute.
    func execute(_ commands: [TerminalCommand]) {
        for command in commands {
            execute(command)
        }
    }

    // MARK: - Screen Buffer Management

    /// Switches to the alternate screen buffer.
    /// Saves the primary buffer's cursor and clears the alternate buffer.
    private func switchToAlternateScreen() {
        guard !isUsingAlternateBuffer else { return }

        // Save primary cursor state
        primarySavedCursor = primaryBuffer.cursor
        primarySavedAttributes = primaryBuffer.currentAttributes

        // Switch to alternate
        isUsingAlternateBuffer = true

        // Clear alternate buffer
        alternateBuffer.reset()
    }

    /// Switches back to the primary screen buffer.
    /// Restores the primary buffer's cursor.
    private func switchToPrimaryScreen() {
        guard isUsingAlternateBuffer else { return }

        // Switch back to primary
        isUsingAlternateBuffer = false

        // Restore primary cursor state
        primaryBuffer.cursor = primarySavedCursor
        primaryBuffer.currentAttributes = primarySavedAttributes
    }

    /// Applies a single SGR attribute to the buffer's current attributes.
    private func applyAttribute(_ sgr: SGRAttribute, to buffer: TerminalBuffer) {
        switch sgr {
        case .reset:
            buffer.currentAttributes.reset()
        case .bold(let on):
            buffer.currentAttributes.isBold = on
        case .dim(let on):
            buffer.currentAttributes.isDim = on
        case .italic(let on):
            buffer.currentAttributes.isItalic = on
        case .underline(let on):
            buffer.currentAttributes.isUnderline = on
        case .blink:
            break  // Not implemented
        case .reverse(let on):
            buffer.currentAttributes.isReverse = on
        case .hidden:
            break  // Not implemented
        case .strikethrough(let on):
            buffer.currentAttributes.isStrikethrough = on
        case .foreground(let color):
            buffer.currentAttributes.foregroundColor = color
        case .background(let color):
            buffer.currentAttributes.backgroundColor = color
        }
    }

    // MARK: - Resize

    /// Resizes both buffers to new dimensions.
    /// - Parameters:
    ///   - rows: New number of rows.
    ///   - columns: New number of columns.
    func resize(rows: Int, columns: Int) {
        primaryBuffer.resize(rows: rows, columns: columns)
        alternateBuffer.resize(rows: rows, columns: columns)
    }

    // MARK: - Reset

    /// Resets the emulator to initial state.
    func reset() {
        primaryBuffer.reset()
        alternateBuffer.reset()
        isUsingAlternateBuffer = false
        isCursorVisible = true
        isBracketedPasteModeEnabled = false
        primarySavedCursor = .origin
        primarySavedAttributes = .default
    }

    // MARK: - Rendering

    /// Returns the active buffer's content as an AttributedString.
    func toAttributedString() -> AttributedString {
        activeBuffer.toAttributedString()
    }

    /// Returns the active buffer's content as plain text.
    func toPlainText() -> String {
        activeBuffer.toPlainText()
    }
}
