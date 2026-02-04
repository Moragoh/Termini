//
//  TerminalCommand.swift
//  Termini
//
//  Shared between: Main App & Widget Extension
//  Purpose: Defines all terminal operations as commands that the emulator can execute.
//           This separates parsing from execution, making the code more testable.
//

import Foundation

// MARK: - Terminal Command

/// Represents a terminal operation that can be executed by the emulator.
/// The ANSIParser converts raw text into a sequence of these commands.
enum TerminalCommand: Equatable {

    // MARK: - Text Output

    /// Print a single character at the cursor position.
    case print(Character)

    /// Print a string of characters (optimization for runs of plain text).
    case printString(String)

    // MARK: - Control Characters

    /// Carriage return - move cursor to column 0, same row.
    case carriageReturn

    /// Line feed - move cursor down one row, scroll if at bottom.
    case lineFeed

    /// Backspace - move cursor left one column.
    case backspace

    /// Horizontal tab - move to next tab stop.
    case tab

    /// Bell - produce audible/visual alert.
    case bell

    // MARK: - Cursor Movement (CSI Sequences)

    /// Move cursor up by N rows. ESC[nA
    case cursorUp(Int)

    /// Move cursor down by N rows. ESC[nB
    case cursorDown(Int)

    /// Move cursor forward (right) by N columns. ESC[nC
    case cursorForward(Int)

    /// Move cursor backward (left) by N columns. ESC[nD
    case cursorBack(Int)

    /// Move cursor to next line, column 0. ESC[nE
    case cursorNextLine(Int)

    /// Move cursor to previous line, column 0. ESC[nF
    case cursorPreviousLine(Int)

    /// Move cursor to absolute column. ESC[nG
    case cursorColumn(Int)

    /// Move cursor to absolute position (row, column). ESC[n;mH or ESC[n;mf
    case cursorPosition(row: Int, col: Int)

    /// Move cursor to home position (0, 0). ESC[H
    case cursorHome

    /// Save cursor position. ESC[s or ESC 7
    case saveCursor

    /// Restore cursor position. ESC[u or ESC 8
    case restoreCursor

    // MARK: - Erasing

    /// Erase in display. ESC[nJ
    /// - 0: Clear from cursor to end of screen
    /// - 1: Clear from beginning to cursor
    /// - 2: Clear entire screen
    /// - 3: Clear entire screen and scrollback (not implemented)
    case eraseInDisplay(ClearMode)

    /// Erase in line. ESC[nK
    /// - 0: Clear from cursor to end of line
    /// - 1: Clear from beginning of line to cursor
    /// - 2: Clear entire line
    case eraseInLine(ClearMode)

    /// Delete N characters at cursor position. ESC[nP
    case deleteCharacters(Int)

    /// Insert N blank characters at cursor position. ESC[n@
    case insertCharacters(Int)

    /// Delete N lines at cursor position. ESC[nM
    case deleteLines(Int)

    /// Insert N blank lines at cursor position. ESC[nL
    case insertLines(Int)

    // MARK: - Scrolling

    /// Scroll up by N lines. ESC[nS
    case scrollUp(Int)

    /// Scroll down by N lines. ESC[nT
    case scrollDown(Int)

    /// Set scroll region (top and bottom margins). ESC[n;mr
    case setScrollRegion(top: Int, bottom: Int)

    // MARK: - Text Attributes (SGR)

    /// Set multiple text attributes at once.
    case setAttributes(CellAttributes)

    /// Reset all text attributes to default.
    case resetAttributes

    /// Set a single attribute (used during parsing).
    case setAttribute(SGRAttribute)

    // MARK: - Screen Buffer

    /// Switch to alternate screen buffer. ESC[?1049h
    /// Also saves cursor and clears alternate screen.
    case switchToAlternateScreen

    /// Switch back to primary screen buffer. ESC[?1049l
    /// Also restores cursor.
    case switchToPrimaryScreen

    // MARK: - Private Modes

    /// Set or reset a private mode. ESC[?nh or ESC[?nl
    case setPrivateMode(Int, Bool)

    /// Enable/disable bracketed paste mode. ESC[?2004h/l
    case bracketedPasteMode(Bool)

    /// Show cursor. ESC[?25h
    case showCursor

    /// Hide cursor. ESC[?25l
    case hideCursor

    // MARK: - Other

    /// Set window title (OSC sequence). ESC]0;titleBEL
    case setWindowTitle(String)

    /// Unknown or unsupported sequence (ignored but logged).
    case unknown(String)
}

// MARK: - SGR Attribute

/// Individual SGR (Select Graphic Rendition) attribute changes.
enum SGRAttribute: Equatable {
    case reset
    case bold(Bool)
    case dim(Bool)
    case italic(Bool)
    case underline(Bool)
    case blink(Bool)
    case reverse(Bool)
    case hidden(Bool)
    case strikethrough(Bool)
    case foreground(TerminalColor?)
    case background(TerminalColor?)
}
