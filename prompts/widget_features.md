# Feature Request: Upgrade Widget for Full Terminal Emulation

## Goal

This document outlines the necessary changes to the Termini Widget to make it compatible with the enhanced terminal emulator. Once the main application is overhauled to support a full terminal state (with cursor positioning, styled characters, and alternate screen buffers), the widget must be updated to accurately render this rich visual data instead of the plain text it currently displays.

---

### 1. Current Widget Implementation

To understand what needs to change, it's important to first see how the widget currently works. The process is designed for simplicity and only handles unformatted text.

1.  **Data Preparation:** The `TerminalViewModel` in the main app takes the terminal's raw output and uses `ANSIParser.stripCodes()` to remove all styling (colors, bold, etc.).
2.  **Shared Data Structure:** The resulting plain `String` is stored in the `Shared/TerminalState.swift` struct, which looks like this:
    ```swift
    struct TerminalState: Codable {
        let outputText: String // A simple, unformatted string
        let timestamp: Date
        // ... other simple properties
    }
    ```
3.  **Data Transfer:** The `SharedDataManager` serializes this simple `TerminalState` object into a JSON file in the shared App Group container.
4.  **Widget Rendering:** The widget's `TimelineProvider` reads the JSON file, and the `TerminiWidgetEntryView` renders the `outputText` using a single SwiftUI `Text` view.

This entire pipeline is incapable of handling the rich, 2D grid of a real terminal screen.

---

### 2. Required Changes for the Widget Overhaul

To make the widget display a faithful representation of the new terminal, we must upgrade the data model and the rendering logic.

#### A. Redesign the Shared Data Model

The contract between the app and the widget must be changed to pass structured, styled data.

**Implementation Plan:**

1.  **Modify `Shared/TerminalState.swift`:** Replace the current `TerminalState` struct with a new one that can describe a grid of styled characters. This will be the new "source of truth" for the widget.

    ```swift
    // It's recommended to create a Codable-friendly color struct
    struct CodableColor: Codable {
        let red: Double
        let green: Double
        let blue: Double
    }

    // A new struct to represent a single styled character on the screen
    struct TerminalCell: Codable {
        let char: Character
        let foregroundColor: CodableColor
        let backgroundColor: CodableColor
        let isBold: Bool
        let isUnderline: Bool
        // Add other style attributes as needed
    }

    // The new state object to be shared as JSON
    struct TerminalState: Codable {
        // A 2D array representing the entire visible terminal screen
        let screenGrid: [[TerminalCell]]
        let timestamp: Date
    }
    ```

#### B. Update the Main App's Saving Process

The `TerminalViewModel` must be updated to save this new, rich data structure.

**Implementation Plan:**

1.  **Modify `saveToSharedData()`:** This method in `TerminalViewModel` should no longer strip ANSI codes.
2.  **Convert Internal State:** It must convert its internal terminal grid model (which will be a 2D array of styled characters) into the new `Codable` `TerminalState` object containing the `screenGrid`.
3.  **Save Active Screen:** The logic should be smart enough to save the currently active screen. If the alternate screen buffer is in use (e.g., for `vim`), the widget should display the `vim` interface.

#### C. Rebuild the Widget's View

The widget's UI can no longer be a single `Text` view. It must be rebuilt to render the `screenGrid`.

**Implementation Plan:**

1.  **Update `TerminiWidgetEntryView`:** Modify the widget's view to accept the new `TerminalState` containing the `screenGrid`.
2.  **Implement Grid Rendering:** The view's `body` will need to construct the display by iterating through the data:
    *   Use a `VStack` to represent the rows of the terminal.
    *   Inside the `VStack`, loop through each `[TerminalCell]` array (each line) in the `screenGrid`.
    *   For each line, use an `HStack` or compose `Text` views together. Loop through each `TerminalCell` in the line.
    *   For each `TerminalCell`, create a `Text(String(cell.char))` and apply the appropriate modifiers: `.foregroundColor()`, `.backgroundColor()`, `.bold()`, etc., using the data from the cell.
    *   This will reconstruct the terminal's appearance, character by character, line by line, with all styling preserved.

By implementing these changes, the widget will transform from a simple text display into a true, read-only mirror of the main application's advanced terminal emulator.
