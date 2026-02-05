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

### Current Status: Implemented

Termini now includes a full terminal buffer with cursor tracking (`TerminalBuffer`) that properly handles carriage returns and line feeds.

### How It Works

When a program outputs:
```
Progress: 50%\rProgress: 75%\r
```

Termini:
1. Prints "Progress: 50%" at the cursor position
2. `.carriageReturn` moves cursor to column 0 (same row)
3. Prints "Progress: 75%" overwriting the previous text

### Swift CRLF Quirk

**Important implementation detail:** Swift treats `\r\n` (CRLF) as a single `Character` (grapheme cluster) when iterating over strings. This means:

```swift
let s = "hello\r\n"
print(s.count)  // Prints 6, not 7!
```

The `ANSIParser.parseControlCharacter()` method handles this by explicitly checking for the combined `"\r\n"` character and returning both `.carriageReturn` and `.lineFeed` commands:

```swift
case "\r\n":    // CRLF - Swift treats as single grapheme cluster
    return [.carriageReturn, .lineFeed]
```

Without this fix, CRLF sequences would be treated as printable text and written to the buffer, causing command output to not display correctly.

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

### ANSI Codes Support Status

| Category | Examples | Status |
|----------|----------|--------|
| Cursor movement | `ESC[A`, `ESC[B`, `ESC[C`, `ESC[D` | **Implemented** |
| Cursor position | `ESC[H`, `ESC[n;mH` | **Implemented** |
| Erase operations | `ESC[K`, `ESC[J` | **Implemented** |
| Scrolling | `ESC[S`, `ESC[T` | **Implemented** |
| Alternate screen | `ESC[?1049h/l` | **Implemented** |
| Bracketed paste | `ESC[?2004h/l` | **Implemented** (mode tracked) |
| Mouse tracking | `ESC[?1000h` | Not implemented |
| True color (24-bit) | `ESC[38;2;r;g;bm` | **Implemented** |

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
| Bracketed paste | Mode tracked, sequences parsed |

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

## Recently Implemented

The following features have been added:

1. **Cursor tracking** — Full terminal state machine with `TerminalBuffer` for proper cursor position tracking
2. **True color** — RGB color support via `ESC[38;2;r;g;bm` sequences
3. **Alternate screen buffer** — Dual buffer support for TUI applications (vim, htop)
4. **Proper CRLF handling** — Swift treats `\r\n` as a single Character; parser now handles this correctly

---

## Future Improvements

Potential enhancements that could address remaining limitations:

1. **Dynamic sizing** — Report actual view size to PTY
2. **Multiple sessions** — Tab support for multiple terminals
3. **Scrollback search** — Find text in output history
4. **Mouse support** — Translate mouse events for TUI applications
