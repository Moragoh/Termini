# Known Limitations

This document describes the current limitations of Termini and explains why they exist.

---

## Widget Refresh Rate

### The Limitation

Widgets do not update in real-time. There is a delay of up to several minutes between terminal output and widget display.

### Why It Exists

Apple's WidgetKit imposes strict refresh limits:

| Metric | Approximate Value |
|--------|-------------------|
| Maximum refreshes per day | 40-70 |
| Minimum interval | ~15 minutes (system-determined) |
| App-requested refreshes | Throttled by system |

### Technical Details

When the app calls:
```swift
WidgetCenter.shared.reloadTimelines(ofKind: "TerminiWidget")
```

WidgetKit may:
- Honor the request immediately
- Delay the request
- Ignore the request entirely (if quota exceeded)

### Mitigation

The app uses a 5-second debounce to batch rapid output changes:
```swift
private let saveDebounceSeconds: Double = 5.0
```

This reduces unnecessary refresh requests while still updating reasonably quickly.

### User Impact

- Running `htop` or similar live-updating programs won't show real-time updates in the widget
- Widget is best suited for viewing recent command output, not live monitoring

---

## Carriage Return Handling

### The Limitation

Progress indicators and spinners that use carriage return (`\r`) to update in place will display as multiple lines instead.

### Example

A download progress indicator like:
```
Downloading... 50%
Downloading... 75%
Downloading... 100%
```

May appear in Termini as:
```
Downloading... 50%
Downloading... 75%
Downloading... 100%
```

Instead of updating a single line.

### Why It Exists

Proper carriage return handling requires a full terminal state machine with:
- Cursor position tracking (row and column)
- Line buffer management
- Character overwrite logic

Termini uses a simplified append-based model for output.

### Technical Background

When a program outputs:
```
Progress: 50%\rProgress: 75%\r
```

A full terminal emulator:
1. Prints "Progress: 50%"
2. Moves cursor to start of line (doesn't erase)
3. Prints "Progress: 75%" overwriting characters

Termini currently:
1. Appends all text to buffer
2. Strips `\r` characters during preprocessing
3. Results in accumulated output

### Workaround

Programs that use full screen clearing (like vim, htop) work correctly because they use escape sequences that Termini does detect:
- `ESC[2J` — Clear entire screen
- `ESC[H` — Cursor to home position

---

## Terminal Size Awareness

### The Limitation

Some programs may not correctly detect the terminal size, affecting their layout.

### Why It Exists

While `PTYManager` sets initial window size and supports resize:
```swift
func resize(columns: Int, rows: Int) {
    var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(columns), ...)
    ioctl(masterFD, TIOCSWINSZ, &size)
}
```

The SwiftUI view doesn't currently calculate and report its actual size to the PTY.

### Impact

- TUI programs may assume 80x24 default size
- Layout may not match visible area

---

## Missing Terminal Features

### Features Not Implemented

| Feature | Status | Notes |
|---------|--------|-------|
| Mouse support | Not implemented | Would require mouse event translation |
| Scrollback buffer | Limited | Fixed 50,000 character limit |
| Tabs/Splits | Not implemented | Single terminal session only |
| Search | Not implemented | Cannot search output history |
| Selection/Copy | System default | Basic text selection only |
| True color (24-bit) | Not implemented | 256-color maximum |
| Ligatures | Not implemented | Monospace font without ligatures |
| Images (iTerm2 protocol) | Not implemented | Text-only output |

### ANSI Codes Not Supported

| Category | Examples | Status |
|----------|----------|--------|
| Cursor movement | `ESC[A`, `ESC[B`, `ESC[C`, `ESC[D` | Stripped (not rendered) |
| Cursor position | `ESC[H`, `ESC[;H` | Detected for screen clear only |
| Erase operations | `ESC[K`, `ESC[J` | `ESC[2J` detected, others stripped |
| Scrolling | `ESC[S`, `ESC[T` | Not implemented |
| Private modes | `ESC[?1049h` (alt screen) | Stripped |
| Mouse tracking | `ESC[?1000h` | Stripped |

---

## Shell Compatibility

### The Limitation

Some shell features may behave differently than in a full terminal emulator.

### Known Issues

| Feature | Behavior |
|---------|----------|
| Command history | Works (handled by shell) |
| Tab completion | Works (handled by shell) |
| Arrow keys in prompt | Works (shell line editing) |
| Arrow keys in vim | Works (application sends escape sequences) |
| Ctrl+Z (suspend) | Works (SIGTSTP sent to foreground process) |
| Job control (`fg`, `bg`) | Works |
| Bracketed paste | Disabled (sequences stripped) |

---

## Performance

### Large Output

When a command produces very large output (megabytes), you may notice:
- Slight delay in display
- Memory usage increase
- Output truncation at 50,000 characters

### Rapid Output

Very rapid output (thousands of lines per second) may cause:
- UI lag
- Dropped frames in animation

The background read queue processes output as fast as possible, but UI updates are limited by SwiftUI's rendering.

---

## Platform Limitations

### macOS Version

Requires macOS 14.0 (Sonoma) or later due to:
- SwiftUI features used
- WidgetKit APIs used
- Modern Swift concurrency

### No iOS/iPadOS Support

Termini is macOS-only because:
- iOS does not allow forking processes
- iOS does not provide PTY APIs
- iOS sandboxing prevents shell execution

---

## Future Improvements

Potential enhancements that could address some limitations:

1. **Cursor tracking** — Full terminal state machine for proper `\r` handling
2. **Dynamic sizing** — Report actual view size to PTY
3. **True color** — Parse `ESC[38;2;r;g;bm` sequences
4. **Multiple sessions** — Tab support for multiple terminals
5. **Scrollback search** — Find text in output history
