# Core Components

This document provides detailed documentation for each core component in Termini.

---

## Table of Contents

1. [PTYManager](#1-ptymanager)
2. [ANSIParser](#2-ansiparser)
3. [TerminalViewModel](#3-terminalviewmodel)
4. [SharedDataManager](#4-shareddatamanager)
5. [Widget Components](#5-widget-components)

---

## 1. PTYManager

**File:** `Termini/PTY/PTYManager.swift`

The PTYManager handles the pseudo-terminal that runs the shell process.

### What is a PTY?

A pseudo-terminal (PTY) tricks the shell into thinking it's running in a real terminal. This is essential because:

| Feature | Without PTY | With PTY |
|---------|-------------|----------|
| Basic commands (`ls`, `echo`) | ✓ Works | ✓ Works |
| Color output | ✗ No colors | ✓ Full color |
| Interactive programs (`vim`, `htop`) | ✗ Fails | ✓ Works |
| Line editing (arrow keys) | ✗ Raw input | ✓ Works |
| Job control (`Ctrl+Z`) | ✗ No effect | ✓ Works |

### How PTY Works

```
┌──────────────────────────────────────────────────────────┐
│                    TERMINI PROCESS                        │
│                                                           │
│   ┌─────────────────┐         ┌─────────────────┐        │
│   │  PTYManager     │◄───────►│  Master FD      │        │
│   │  (reads/writes) │         │  (pipe endpoint)│        │
│   └─────────────────┘         └────────┬────────┘        │
│                                        │                  │
└────────────────────────────────────────┼──────────────────┘
                                         │
                              ┌──────────┴──────────┐
                              │    PTY Kernel       │
                              │    (bidirectional)  │
                              └──────────┬──────────┘
                                         │
┌────────────────────────────────────────┼──────────────────┐
│                    SHELL PROCESS                          │
│                                        │                  │
│   ┌─────────────────┐         ┌────────┴────────┐        │
│   │    /bin/zsh     │◄───────►│  Slave FD       │        │
│   │  (stdin/stdout) │         │  (looks like    │        │
│   │                 │         │   real terminal)│        │
│   └─────────────────┘         └─────────────────┘        │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

### Implementation

The PTY is created using BSD's `forkpty()` function:

```swift
childPID = forkpty(&masterFD, nil, nil, &winSize)

if childPID == 0 {
    // Child process: becomes the shell
    setenv("TERM", "xterm-256color", 1)
    execv("/bin/zsh", &args)
}
// Parent process: masterFD is now connected to shell's stdin/stdout
```

### Public API

```swift
final class PTYManager {
    // Properties
    var isRunning: Bool { get }
    var onOutput: ((String) -> Void)?
    var onProcessExit: (() -> Void)?

    // Methods
    func start() throws
    func stop()
    func send(_ text: String)
    func sendByte(_ byte: UInt8)
    func resize(columns: Int, rows: Int)
}
```

### Method Details

| Method | Description |
|--------|-------------|
| `start()` | Creates PTY, forks child, executes `/bin/zsh --login`, starts read loop |
| `stop()` | Sends SIGHUP, waits for child exit, closes file descriptor |
| `send(_:)` | Writes text to shell's stdin (typically ends with `\n`) |
| `sendByte(_:)` | Writes single byte for control characters (e.g., `3` for Ctrl+C) |
| `resize(columns:rows:)` | Updates PTY size, sends SIGWINCH to shell |

### Environment Setup

```swift
setenv("TERM", "xterm-256color", 1)    // Enable 256 colors
setenv("LANG", "en_US.UTF-8", 1)       // UTF-8 support
setenv("LC_ALL", "en_US.UTF-8", 1)     // Locale override
setenv("PROMPT_EOL_MARK", "", 1)       // Disable zsh's '%' marker
```

---

## 2. ANSIParser

**File:** `Shared/ANSIParser.swift`

Converts raw terminal output containing ANSI escape codes into `TerminalCommand` sequences for execution by the emulator.

### What are ANSI Escape Codes?

ANSI codes are character sequences that control terminal formatting:

```
ESC[31m     → Red text
ESC[1m      → Bold
ESC[0m      → Reset all formatting
ESC[38;5;82m → 256-color (green)
```

The escape character is `\u{1B}` (ASCII 27), also written as `ESC` or `^[`.

### Public API

```swift
struct ANSIParser {
    // Command-based parsing (primary API for terminal emulation)
    static func parseToCommands(_ rawText: String) -> [TerminalCommand]

    // Legacy API for simple AttributedString conversion
    static func parse(_ rawText: String) -> AttributedString
    static func stripCodes(_ rawText: String) -> String
}
```

### Command-Based Parsing

The `parseToCommands()` method converts raw terminal output into a sequence of `TerminalCommand` objects that the `TerminalEmulator` executes. This approach properly handles:

- Control characters (`\r`, `\n`, `\t`, backspace, bell)
- Cursor movement sequences
- Screen/line clearing
- Text attributes (colors, bold, italic, etc.)
- Screen buffer switching (for TUI apps)

### Swift CRLF Handling

**Important:** Swift treats `\r\n` (CRLF) as a single grapheme cluster when iterating over `Character` values. The parser handles this by checking for the combined `"\r\n"` character and emitting both `.carriageReturn` and `.lineFeed` commands:

```swift
private static func parseControlCharacter(_ char: Character) -> [TerminalCommand]? {
    switch char {
    case "\r\n":    // CRLF - Swift treats as single Character
        return [.carriageReturn, .lineFeed]
    case "\r":
        return [.carriageReturn]
    case "\n":
        return [.lineFeed]
    // ...
    }
}
```

### Supported SGR Codes

| Code | Effect | Example |
|------|--------|---------|
| 0 | Reset all | `ESC[0m` |
| 1 | Bold | `ESC[1m` |
| 2 | Dim | `ESC[2m` |
| 3 | Italic | `ESC[3m` |
| 4 | Underline | `ESC[4m` |
| 22 | Normal weight | `ESC[22m` |
| 23 | Not italic | `ESC[23m` |
| 24 | Not underlined | `ESC[24m` |
| 30-37 | Standard foreground | `ESC[31m` (red) |
| 39 | Default foreground | `ESC[39m` |
| 40-47 | Standard background | `ESC[44m` (blue) |
| 49 | Default background | `ESC[49m` |
| 90-97 | Bright foreground | `ESC[91m` |
| 100-107 | Bright background | `ESC[104m` |
| 38;5;N | 256-color foreground | `ESC[38;5;196m` |
| 48;5;N | 256-color background | `ESC[48;5;21m` |

### Color Palette

**Standard Colors (0-7):**
| Index | Color |
|-------|-------|
| 0 | Black |
| 1 | Red |
| 2 | Green |
| 3 | Yellow |
| 4 | Blue |
| 5 | Magenta |
| 6 | Cyan |
| 7 | White |

**256-Color Palette:**
- 0-7: Standard colors
- 8-15: Bright colors
- 16-231: 6×6×6 color cube
- 232-255: Grayscale (24 shades)

### Supported Control Characters

| Character | Command Generated | Action |
|-----------|-------------------|--------|
| `\r` | `.carriageReturn` | Move cursor to column 0 |
| `\n` | `.lineFeed` | Move cursor down, scroll if at bottom |
| `\r\n` | `.carriageReturn`, `.lineFeed` | Both (Swift CRLF handling) |
| `\t` | `.tab` | Move to next tab stop |
| `\b` | `.backspace` | Move cursor left one column |
| `\x07` | `.bell` | System beep |

### Supported CSI Sequences

| Sequence | Command Generated | Action |
|----------|-------------------|--------|
| `ESC[?2004h/l` | `.bracketedPasteMode` | Enable/disable bracketed paste |
| `ESC[?25h/l` | `.showCursor`/`.hideCursor` | Cursor visibility |
| `ESC[?1049h/l` | `.switchToAlternateScreen`/`.switchToPrimaryScreen` | Buffer switching |
| `ESC[nA/B/C/D` | `.cursorUp/Down/Forward/Back` | Cursor movement |
| `ESC[H` | `.cursorHome` | Cursor to origin |
| `ESC[n;mH` | `.cursorPosition` | Cursor to row/column |
| `ESC[J` | `.eraseInDisplay` | Clear screen |
| `ESC[K` | `.eraseInLine` | Clear line |
| `ESC[...m` | `.setAttribute` | Text styling (SGR) |

---

## 3. TerminalViewModel

**File:** `Termini/ViewModels/TerminalViewModel.swift`

Coordinates between the PTY and UI, managing all terminal state.

### Published Properties

```swift
@MainActor
final class TerminalViewModel: ObservableObject {
    @Published var attributedOutput: AttributedString  // Styled output
    @Published var rawOutput: String                   // Raw with ANSI
    @Published var currentInput: String                // User input buffer
    @Published var isRunning: Bool                     // Shell status
    @Published var errorMessage: String?               // Error display
}
```

### Public Methods

```swift
func start()                          // Start shell session
func stop()                           // Stop shell session
func sendCommand()                    // Send currentInput + newline
func send(_ text: String)             // Send raw text
func sendControl(_ key: Character)    // Send control char (e.g., "c" for Ctrl+C)
func resize(columns: Int, rows: Int)  // Update terminal size
func clear()                          // Clear output buffer
```

### Key Behaviors

**1. Output Handling**
```swift
private func handleOutput(_ text: String) {
    if containsScreenClear(text) {
        rawOutput = text              // Reset for TUI programs
    } else {
        rawOutput += text             // Append normally
    }
    attributedOutput = ANSIParser.parse(rawOutput)
    scheduleSaveToSharedData()
}
```

**2. Buffer Management**
- Maximum 50,000 characters
- Oldest content discarded when exceeded

**3. Screen Clear Detection**
Detects TUI redraw sequences to prevent accumulation:
- `ESC[2J` — Clear screen
- `ESC[H` — Cursor home
- `ESC[1;1H` — Cursor to (1,1)

**4. Widget Sync**
- 5-second debounce before saving
- Strips ANSI codes before saving (plain text for widget)
- Calls `WidgetCenter.shared.reloadTimelines()`

---

## 4. SharedDataManager

**File:** `Shared/SharedDataManager.swift`

Manages file-based IPC between app and widget via App Groups.

### How App Groups Work

```
┌─────────────────┐                    ┌─────────────────┐
│   Main App      │                    │     Widget      │
│                 │                    │                 │
│  SharedData     │                    │  SharedData     │
│  Manager.save() │                    │  Manager.load() │
└────────┬────────┘                    └────────┬────────┘
         │                                      │
         ▼                                      ▼
┌─────────────────────────────────────────────────────────┐
│              App Group Container                         │
│   ~/Library/Group Containers/group.com.junminkim.termini│
│                                                          │
│   ┌─────────────────────────────────────────────────┐   │
│   │              terminal_state.json                 │   │
│   └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### Public API

```swift
final class SharedDataManager {
    static let shared: SharedDataManager

    func save(state: TerminalState) throws
    func load() -> TerminalState?
    func clear()
}
```

### JSON Format

```json
{
    "outputText": "$ ls\nDocuments  Downloads  Desktop",
    "timestamp": "2026-01-29T15:30:00Z",
    "currentDirectory": "/Users/junminkim",
    "isExecutingCommand": false
}
```

### Atomic Writes

```swift
try data.write(to: fileURL, options: .atomic)
```

Using `.atomic` ensures the widget never reads a partially-written file.

---

## 5. Widget Components

**File:** `TerminiWidget/TerminiWidget.swift`

### TimelineProvider

Provides snapshots for WidgetKit's timeline system:

```swift
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TerminalEntry
    func getSnapshot(in context: Context, completion: @escaping (TerminalEntry) -> ())
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ())
}
```

### Timeline Refresh Strategy

```swift
func getTimeline(...) {
    let entry = createEntry()
    let refreshDate = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
    let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
    completion(timeline)
}
```

**Refresh Triggers:**
1. Time-based: Every 1 minute (requested, not guaranteed)
2. App-triggered: `WidgetCenter.shared.reloadTimelines(ofKind: "TerminiWidget")`

**Apple Throttling:** ~40-70 refreshes per day maximum.

### Widget Sizes

| Size | Lines | Font Size |
|------|-------|-----------|
| `systemSmall` | 6 | 8pt |
| `systemMedium` | 8 | 9pt |
| `systemLarge` | 20 | 10pt |

### TerminalEntry

```swift
struct TerminalEntry: TimelineEntry {
    let date: Date                       // When to display
    let terminalOutput: AttributedString // Parsed output
    let lastUpdated: Date                // For "X ago" display
}
```
