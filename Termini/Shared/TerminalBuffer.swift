//
//  TerminalBuffer.swift
//  Termini
//
//  Shared between: Main App & Widget Extension
//  Purpose: Represents a 2D terminal screen buffer with cursor tracking.
//           This is the core data structure for proper terminal emulation.
//

import SwiftUI

// MARK: - Cursor Position

/// Represents the cursor's position in the terminal grid.
struct CursorPosition: Equatable {
    var row: Int
    var column: Int

    /// Origin position (top-left corner).
    static let origin = CursorPosition(row: 0, column: 0)
}

// MARK: - Terminal Cell

/// A single cell in the terminal grid.
/// Each cell holds one character and its styling attributes.
struct TerminalCell: Equatable {
    var character: Character
    var attributes: CellAttributes

    /// An empty cell (space with default attributes).
    static let empty = TerminalCell(character: " ", attributes: .default)

    init(character: Character = " ", attributes: CellAttributes = .default) {
        self.character = character
        self.attributes = attributes
    }
}

// MARK: - Clear Mode

/// Specifies how to clear the screen or line.
enum ClearMode {
    case toEnd        // Clear from cursor to end of line/screen
    case toBeginning  // Clear from beginning to cursor
    case entire       // Clear entire line/screen
}

// MARK: - Terminal Buffer

/// A 2D grid of terminal cells with cursor tracking.
///
/// This class manages the terminal's display buffer, handling:
/// - Character writing at cursor position
/// - Cursor movement
/// - Line/screen clearing
/// - Scrolling
/// - Rendering to AttributedString
final class TerminalBuffer {

    // MARK: - Properties

    /// Number of rows in the buffer.
    private(set) var rows: Int

    /// Number of columns in the buffer.
    private(set) var columns: Int

    /// The 2D grid of cells: cells[row][column].
    private(set) var cells: [[TerminalCell]]

    /// Current cursor position.
    var cursor: CursorPosition = .origin

    /// Current text attributes (applied to newly written characters).
    var currentAttributes: CellAttributes = .default

    /// Top of the scroll region (0-indexed).
    var scrollTop: Int = 0

    /// Bottom of the scroll region (0-indexed, inclusive).
    var scrollBottom: Int

    /// Saved cursor position (for ESC 7 / ESC 8).
    private var savedCursor: CursorPosition = .origin
    private var savedAttributes: CellAttributes = .default

    // MARK: - Initialization

    /// Creates a new terminal buffer with the specified dimensions.
    /// - Parameters:
    ///   - rows: Number of rows (default 24).
    ///   - columns: Number of columns (default 80).
    init(rows: Int = 24, columns: Int = 80) {
        self.rows = rows
        self.columns = columns
        self.scrollBottom = rows - 1
        self.cells = Self.createEmptyGrid(rows: rows, columns: columns)
    }

    /// Creates an empty grid of cells.
    private static func createEmptyGrid(rows: Int, columns: Int) -> [[TerminalCell]] {
        Array(repeating: Array(repeating: .empty, count: columns), count: rows)
    }

    // MARK: - Character Writing

    /// Writes a character at the current cursor position and advances the cursor.
    /// - Parameter char: The character to write.
    func writeCharacter(_ char: Character) {
        // Ensure cursor is within bounds
        clampCursor()

        // Handle line wrap: if at end of line, move to next line
        if cursor.column >= columns {
            cursor.column = 0
            lineFeed()
        }

        // Write character with current attributes
        guard cursor.row >= 0 && cursor.row < rows else { return }
        cells[cursor.row][cursor.column] = TerminalCell(
            character: char,
            attributes: currentAttributes
        )

        // Advance cursor
        cursor.column += 1
    }

    /// Writes a string, handling special characters appropriately.
    /// - Parameter string: The string to write.
    func writeString(_ string: String) {
        for char in string {
            writeCharacter(char)
        }
    }

    // MARK: - Cursor Movement

    /// Moves the cursor to the specified position.
    /// - Parameter position: The target position.
    func moveCursor(to position: CursorPosition) {
        cursor = position
        clampCursor()
    }

    /// Moves the cursor relative to its current position.
    /// - Parameters:
    ///   - deltaRow: Rows to move (positive = down, negative = up).
    ///   - deltaColumn: Columns to move (positive = right, negative = left).
    func moveCursorRelative(deltaRow: Int, deltaColumn: Int) {
        cursor.row += deltaRow
        cursor.column += deltaColumn
        clampCursor()
    }

    /// Performs a carriage return (moves cursor to column 0, same row).
    func carriageReturn() {
        cursor.column = 0
    }

    /// Performs a line feed (moves cursor down one row, scrolls if at bottom).
    func lineFeed() {
        print("[DEBUG TerminalBuffer.lineFeed] Before: row=\(cursor.row) scrollBottom=\(scrollBottom)")
        if cursor.row >= scrollBottom {
            // At bottom of scroll region - scroll up
            print("[DEBUG TerminalBuffer.lineFeed] At scroll bottom, scrolling up")
            scrollUp(lines: 1)
        } else {
            cursor.row += 1
            print("[DEBUG TerminalBuffer.lineFeed] Incremented row to \(cursor.row)")
        }
    }

    /// Performs a backspace (moves cursor left one column, doesn't delete).
    func backspace() {
        if cursor.column > 0 {
            cursor.column -= 1
        }
    }

    /// Moves cursor to next tab stop (every 8 columns).
    func tab() {
        let nextTab = ((cursor.column / 8) + 1) * 8
        cursor.column = min(nextTab, columns - 1)
    }

    /// Saves the current cursor position and attributes.
    func saveCursor() {
        savedCursor = cursor
        savedAttributes = currentAttributes
    }

    /// Restores the previously saved cursor position and attributes.
    func restoreCursor() {
        cursor = savedCursor
        currentAttributes = savedAttributes
        clampCursor()
    }

    /// Clamps the cursor to valid bounds.
    private func clampCursor() {
        cursor.row = max(0, min(cursor.row, rows - 1))
        cursor.column = max(0, min(cursor.column, columns - 1))
    }

    // MARK: - Clearing

    /// Clears part or all of the screen.
    /// - Parameter mode: The clear mode.
    func clearScreen(mode: ClearMode) {
        switch mode {
        case .toEnd:
            // Clear from cursor to end of screen
            clearLine(mode: .toEnd)
            for row in (cursor.row + 1)..<rows {
                clearRow(row)
            }
        case .toBeginning:
            // Clear from beginning to cursor
            for row in 0..<cursor.row {
                clearRow(row)
            }
            clearLine(mode: .toBeginning)
        case .entire:
            // Clear entire screen
            for row in 0..<rows {
                clearRow(row)
            }
        }
    }

    /// Clears part or all of the current line.
    /// - Parameter mode: The clear mode.
    func clearLine(mode: ClearMode) {
        guard cursor.row >= 0 && cursor.row < rows else { return }

        switch mode {
        case .toEnd:
            // Clear from cursor to end of line
            for col in cursor.column..<columns {
                cells[cursor.row][col] = .empty
            }
        case .toBeginning:
            // Clear from beginning to cursor
            for col in 0...cursor.column {
                cells[cursor.row][col] = .empty
            }
        case .entire:
            // Clear entire line
            clearRow(cursor.row)
        }
    }

    /// Clears an entire row.
    private func clearRow(_ row: Int) {
        guard row >= 0 && row < rows else { return }
        cells[row] = Array(repeating: .empty, count: columns)
    }

    // MARK: - Scrolling

    /// Scrolls the scroll region up by the specified number of lines.
    /// New blank lines appear at the bottom of the scroll region.
    /// - Parameter lines: Number of lines to scroll.
    func scrollUp(lines: Int = 1) {
        guard lines > 0 else { return }

        for _ in 0..<lines {
            // Remove top line of scroll region
            cells.remove(at: scrollTop)
            // Insert blank line at bottom of scroll region
            cells.insert(Array(repeating: .empty, count: columns), at: scrollBottom)
        }
    }

    /// Scrolls the scroll region down by the specified number of lines.
    /// New blank lines appear at the top of the scroll region.
    /// - Parameter lines: Number of lines to scroll.
    func scrollDown(lines: Int = 1) {
        guard lines > 0 else { return }

        for _ in 0..<lines {
            // Remove bottom line of scroll region
            cells.remove(at: scrollBottom)
            // Insert blank line at top of scroll region
            cells.insert(Array(repeating: .empty, count: columns), at: scrollTop)
        }
    }

    /// Sets the scroll region.
    /// - Parameters:
    ///   - top: Top row of region (0-indexed).
    ///   - bottom: Bottom row of region (0-indexed, inclusive).
    func setScrollRegion(top: Int, bottom: Int) {
        scrollTop = max(0, min(top, rows - 1))
        scrollBottom = max(scrollTop, min(bottom, rows - 1))
        // Move cursor to home position when scroll region changes
        cursor = .origin
    }

    // MARK: - Character/Line Insertion and Deletion

    /// Deletes characters at the cursor position, shifting remaining characters left.
    /// - Parameter count: Number of characters to delete.
    func deleteCharacters(_ count: Int) {
        let row = cursor.row
        let col = cursor.column
        guard row >= 0 && row < rows else { return }

        // Shift characters left
        for c in col..<(columns - count) {
            if c + count < columns {
                cells[row][c] = cells[row][c + count]
            }
        }
        // Fill remainder with spaces
        for c in max(col, columns - count)..<columns {
            cells[row][c] = .empty
        }
    }

    /// Inserts blank characters at the cursor position, shifting remaining characters right.
    /// - Parameter count: Number of blank characters to insert.
    func insertCharacters(_ count: Int) {
        let row = cursor.row
        let col = cursor.column
        guard row >= 0 && row < rows else { return }

        // Shift characters right
        for c in stride(from: columns - 1, through: col + count, by: -1) {
            if c - count >= col {
                cells[row][c] = cells[row][c - count]
            }
        }
        // Fill inserted positions with spaces
        for c in col..<min(col + count, columns) {
            cells[row][c] = .empty
        }
    }

    /// Deletes lines at the cursor position, scrolling content up within scroll region.
    /// - Parameter count: Number of lines to delete.
    func deleteLines(_ count: Int) {
        let row = cursor.row
        guard row >= scrollTop && row <= scrollBottom else { return }

        for _ in 0..<count {
            // Remove the line at cursor row
            if row < cells.count {
                cells.remove(at: row)
                // Add blank line at bottom of scroll region
                cells.insert(Array(repeating: .empty, count: columns), at: scrollBottom)
            }
        }
    }

    /// Inserts blank lines at the cursor position, scrolling content down within scroll region.
    /// - Parameter count: Number of blank lines to insert.
    func insertLines(_ count: Int) {
        let row = cursor.row
        guard row >= scrollTop && row <= scrollBottom else { return }

        for _ in 0..<count {
            // Remove line at bottom of scroll region
            if scrollBottom < cells.count {
                cells.remove(at: scrollBottom)
                // Insert blank line at cursor row
                cells.insert(Array(repeating: .empty, count: columns), at: row)
            }
        }
    }

    // MARK: - Resizing

    /// Resizes the buffer to new dimensions.
    /// Content is preserved where possible.
    /// - Parameters:
    ///   - newRows: New number of rows.
    ///   - newColumns: New number of columns.
    func resize(rows newRows: Int, columns newColumns: Int) {
        guard newRows > 0 && newColumns > 0 else { return }

        var newCells = Self.createEmptyGrid(rows: newRows, columns: newColumns)

        // Copy existing content
        let rowsToCopy = min(rows, newRows)
        let colsToCopy = min(columns, newColumns)

        for row in 0..<rowsToCopy {
            for col in 0..<colsToCopy {
                newCells[row][col] = cells[row][col]
            }
        }

        rows = newRows
        columns = newColumns
        cells = newCells
        scrollBottom = newRows - 1
        clampCursor()
    }

    /// Resets the buffer to empty state.
    func reset() {
        cells = Self.createEmptyGrid(rows: rows, columns: columns)
        cursor = .origin
        currentAttributes = .default
        scrollTop = 0
        scrollBottom = rows - 1
    }

    // MARK: - Rendering

    /// Converts the buffer to an AttributedString for SwiftUI display.
    /// - Returns: Styled AttributedString representing the buffer contents.
    func toAttributedString() -> AttributedString {
        var result = AttributedString()
        var lastNonEmptyRow = -1

        // First pass: find the last row with content
        for row in 0..<rows {
            for col in 0..<columns {
                if cells[row][col].character != " " {
                    lastNonEmptyRow = row
                    break
                }
            }
        }

        // If buffer is completely empty, return empty string
        if lastNonEmptyRow < 0 {
            return AttributedString()
        }

        // Second pass: render rows up to and including the last non-empty row
        for row in 0...lastNonEmptyRow {
            // Find last non-space column in this row
            var lastNonSpaceCol = -1
            for col in (0..<columns).reversed() {
                if cells[row][col].character != " " {
                    lastNonSpaceCol = col
                    break
                }
            }

            // Render characters up to last non-space (or nothing if row is empty)
            if lastNonSpaceCol >= 0 {
                for col in 0...lastNonSpaceCol {
                    let cell = cells[row][col]
                    var charString = AttributedString(String(cell.character))
                    cell.attributes.apply(to: &charString)
                    result += charString
                }
            }

            // Add newline except for last row
            if row < lastNonEmptyRow {
                result += AttributedString("\n")
            }
        }

        return result
    }

    /// Converts the buffer to plain text (no styling).
    /// - Returns: Plain text string.
    func toPlainText() -> String {
        var result = ""
        var lastNonEmptyRow = -1

        // First pass: find the last row with content
        for row in 0..<rows {
            for col in 0..<columns {
                if cells[row][col].character != " " {
                    lastNonEmptyRow = row
                    break
                }
            }
        }

        // If buffer is completely empty, return empty string
        if lastNonEmptyRow < 0 {
            return ""
        }

        // Second pass: render rows up to and including the last non-empty row
        for row in 0...lastNonEmptyRow {
            // Find last non-space column in this row
            var lastNonSpaceCol = -1
            for col in (0..<columns).reversed() {
                if cells[row][col].character != " " {
                    lastNonSpaceCol = col
                    break
                }
            }

            // Render characters up to last non-space (or nothing if row is empty)
            if lastNonSpaceCol >= 0 {
                for col in 0...lastNonSpaceCol {
                    result.append(cells[row][col].character)
                }
            }

            // Add newline except for last row
            if row < lastNonEmptyRow {
                result += "\n"
            }
        }

        return result
    }

    // MARK: - Debug

    /// Returns a debug string representation of the buffer.
    func debugDescription() -> String {
        var result = "TerminalBuffer(\(columns)x\(rows)) cursor=(\(cursor.column),\(cursor.row))\n"
        for row in 0..<min(rows, 10) {
            result += "[\(row)]: "
            for col in 0..<columns {
                result.append(cells[row][col].character)
            }
            result += "\n"
        }
        if rows > 10 {
            result += "... (\(rows - 10) more rows)\n"
        }
        return result
    }
}
