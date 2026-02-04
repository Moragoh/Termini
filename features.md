# Feature Request: Enhance PTY for Full Terminal Emulation

## Goal

The objective is to upgrade Termini's pseudo-terminal (PTY) capabilities to match the behavior of modern terminal emulators like zsh. This involves implementing a proper terminal state machine that can correctly interpret and render advanced ANSI control sequences. This will fix issues with progress bars, TUI applications, and cursor positioning.

---

### 1. Implement Correct Carriage Return (\r) Handling

**Goal:** Process the carriage return character `\r` to move the cursor to the beginning of the current line, allowing subsequent text to overwrite existing characters on that line.

**Current Behavior:**
The `ANSIParser` currently strips the `\r` character. This causes programs that use it for progress updates (e.g., `curl`, `wget`) to print each update on a new line.

**Example:**
A command showing `Downloading... 50%` then `\r` then `Downloading... 75%` currently renders as:
```
Downloading... 50%
Downloading... 75%
```

**Desired Behavior:**
The output should render as a single line that updates in place:
```
Downloading... 75%
```

**Implementation Plan:**
To achieve this, the terminal model must evolve from a simple append-only string buffer to a stateful grid.

1.  **Introduce a Terminal State Model:**
    *   Instead of a single `rawOutput: String`, the `TerminalViewModel` needs to manage a 2D grid of characters (e.g., `[[Character]]` or a list of line objects) representing the terminal's screen.
    *   It must also track the cursor's position (e.g., `cursor: (row: Int, column: Int)`).

2.  **Update Output Handling:**
    *   In `TerminalViewModel`, modify `handleOutput(_:)` to process incoming text character by character.
    *   When a normal character is received, place it at the current cursor position and advance the cursor.
    *   When a `\r` character is received, update the state by setting `cursor.column = 0` without changing the `cursor.row`.

3.  **Refactor Rendering:**
    *   The `ContentView` should render the 2D grid model instead of a single `AttributedString`. The `ANSIParser` will need to be adapted to apply attributes to this grid structure.

---

### 2. Implement Advanced Cursor Control and Screen Management

**Goal:** Process essential ANSI escape sequences for cursor movement and screen buffer switching, which are critical for TUI applications like `vim`, `htop`, and `less`.

#### A. Cursor Movement (CSI Sequences)

**Goal:** Handle ANSI escape codes for moving the cursor up, down, left, and right.

**Current Behavior:**
Codes like `ESC[A` (up), `ESC[B` (down), `ESC[C` (forward), and `ESC[D` (back) are stripped by `ANSIParser` and ignored.

**Desired Behavior:**
The terminal's internal cursor position should be updated according to these commands, affecting where subsequent text is rendered.

**Implementation Plan:**

1.  **Enhance `ANSIParser`:**
    *   Modify the parser to recognize and decode these cursor movement sequences. For example, `\u{1B}[10C` should be parsed as an instruction to move the cursor 10 columns forward.

2.  **Update `TerminalViewModel`:**
    *   The `handleOutput` function (or a new dedicated processor) should receive these instructions from the parser.
    *   Update the `cursor.row` and `cursor.column` properties based on the instruction, ensuring the cursor stays within the bounds of the terminal grid.

#### B. Alternate Screen Buffer

**Goal:** Implement the "alternate screen buffer" used by full-screen TUI applications to provide their own interface without overwriting the user's existing terminal history.

**Current Behavior:**
The control sequences `ESC[?1049h` (enter alternate screen) and `ESC[?1049l` (exit alternate screen) are stripped and ignored. The application clears the main buffer when it detects other clear-screen commands, but it doesn't restore the previous content on exit.

**Desired Behavior:**
*   When `ESC[?1049h` is received, the application should save its current screen content and display a new, blank screen for the TUI application.
*   When the TUI application exits and sends `ESC[?1049l`, the application should restore the original screen content, making it seem as if the TUI application never overwrote the user's session.

**Implementation Plan:**

1.  **Manage Multiple Buffers:**
    *   In `TerminalViewModel`, maintain two separate screen buffers: `primaryBuffer` and `alternateBuffer`.
    *   Also, add a state variable, e.g., `isUsingAlternateBuffer: Bool`, to track which buffer is active.

2.  **Handle Buffer Switching Commands:**
    *   When `ESC[?1049h` is parsed:
        1.  Set `isUsingAlternateBuffer = true`.
        2.  Clear the `alternateBuffer`.
        3.  The UI should now render content from the `alternateBuffer`.
    *   When `ESC[?1049l` is parsed:
        1.  Set `isUsingAlternateBuffer = false`.
        2.  The UI should switch back to rendering the `primaryBuffer`, which contains the user's original command history.
