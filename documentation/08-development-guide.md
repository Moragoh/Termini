# Development Guide

This document provides guidance for developers working on the Termini codebase.

---

## Building the Project

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later
- Apple Developer account (for code signing)

### Build Steps

1. Open `Termini.xcodeproj` in Xcode
2. Select the **Termini** scheme
3. Select a destination (e.g., "My Mac")
4. Press `Cmd+B` to build or `Cmd+R` to build and run

### First Run

On first run:
1. The app window appears
2. A zsh shell session starts automatically
3. You should see the shell prompt

If the shell doesn't start, check Console.app for error messages.

---

## Running Tests

### Unit Tests

```bash
# From command line
xcodebuild test -scheme Termini -destination 'platform=macOS'

# Or in Xcode
Cmd+U
```

### Test Coverage

Current tests cover:
- `ANSIParser` — Color parsing, code stripping
- `TerminalState` — Encoding/decoding
- `PTYManager` — Shell execution, I/O

### Adding Tests

Tests are located in `TerminiTests/TerminiTests.swift`.

Example test structure:
```swift
func testFeatureName() throws {
    // Arrange
    let input = "test input"

    // Act
    let result = functionUnderTest(input)

    // Assert
    XCTAssertEqual(result, expectedValue)
}
```

---

## Debugging

### Console Output

The app doesn't print debug output by default. Add print statements as needed:

```swift
print("[DEBUG] PTY output: \(text.debugDescription)")
```

### Common Issues

#### Shell Doesn't Start

1. Check that App Sandbox is disabled
2. Verify `/bin/zsh` exists
3. Check Console.app for fork/exec errors

#### Widget Shows Old Data

1. Verify App Group is configured in both targets
2. Check that identifiers match exactly
3. Try removing and re-adding the widget

#### ANSI Codes Visible in Output

1. Check that `ANSIParser.parse()` is being called
2. Verify the escape sequences match expected patterns
3. Add the pattern to preprocessing if needed

### Inspecting Shared Data

View the terminal state JSON:

```bash
cat ~/Library/Group\ Containers/group.com.junminkim.termini/terminal_state.json | jq
```

### PTY Debugging

To see raw PTY output before parsing:

```swift
// In TerminalViewModel.handleOutput()
print("[RAW] \(text.debugDescription)")  // Shows escape sequences
```

---

## Code Style

### Swift Conventions

- Use `final class` for classes not intended for subclassing
- Use `@MainActor` for classes that update UI
- Prefer `let` over `var` where possible
- Use meaningful variable names

### File Organization

```
// MARK: - Properties
// MARK: - Initialization
// MARK: - Public Methods
// MARK: - Private Methods
```

### Error Handling

```swift
do {
    try operation()
} catch {
    print("Operation failed: \(error.localizedDescription)")
    // Handle gracefully, don't crash
}
```

---

## Adding New Features

### Adding a New ANSI Code

1. Open `Shared/ANSIParser.swift`
2. Add handling in `processParams()` method:

```swift
case 99:  // Example: new code
    currentStyle.newProperty = true
```

3. Add tests in `TerminiTests.swift`

### Adding a New Control Character

1. Open `Termini/ContentView.swift`
2. Add a new `.onKeyPress` handler:

```swift
.onKeyPress(characters: .init(charactersIn: "d"), phases: .down) { keyPress in
    if keyPress.modifiers.contains(.control) {
        viewModel.sendControl("d")  // Ctrl+D = EOF
        return .handled
    }
    return .ignored
}
```

3. Verify in `PTYManager.sendByte()` that the byte is correctly calculated

### Adding Widget Sizes

1. Open `TerminiWidget/TerminiWidget.swift`
2. Add the new size to `supportedFamilies`:

```swift
.supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
```

3. Handle the new size in `TerminiWidgetEntryView`:

```swift
case .systemExtraLarge:
    maxLines = 40
    fontSize = 11
```

---

## Architecture Decisions

### Why MVVM?

- **Testability:** ViewModel can be tested without UI
- **Separation:** View only handles display, ViewModel handles logic
- **SwiftUI Integration:** `@Published` works naturally with SwiftUI

### Why File-Based IPC?

Apple requires widgets to run as separate processes. Options considered:

| Method | Verdict |
|--------|---------|
| App Groups + Files | **Chosen** — Simple, reliable, works |
| UserDefaults (shared) | Limited to 1MB, less flexible |
| Core Data | Overkill for simple state |
| Network | Requires server, complex |

### Why forkpty()?

Alternatives considered:

| Method | Verdict |
|--------|---------|
| `forkpty()` | **Chosen** — Standard, handles PTY setup |
| Manual `openpty()` + `fork()` | More code, same result |
| `Process` class | No PTY support, no interactive programs |
| `posix_spawn` | No PTY support |

---

## Release Checklist

Before releasing a new version:

1. **Tests Pass**
   ```bash
   xcodebuild test -scheme Termini
   ```

2. **No Warnings**
   - Build with "Treat Warnings as Errors" enabled

3. **Documentation Updated**
   - Update version numbers if applicable
   - Document new features

4. **Widget Works**
   - Fresh install test
   - Verify widget updates

5. **Manual Testing**
   - Basic commands (`ls`, `echo`, `pwd`)
   - Interactive programs (`vim`, `htop`)
   - Ctrl+C interruption
   - Window close and reopen (session persists)

---

## Useful Resources

### Apple Documentation

- [WidgetKit](https://developer.apple.com/documentation/widgetkit)
- [App Groups](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_application-groups)
- [SwiftUI](https://developer.apple.com/documentation/swiftui)

### Terminal Emulation

- [ANSI Escape Codes](https://en.wikipedia.org/wiki/ANSI_escape_code)
- [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)
- [PTY Manual](https://man7.org/linux/man-pages/man7/pty.7.html)

### Swift

- [Swift Documentation](https://docs.swift.org/swift-book/)
- [AttributedString](https://developer.apple.com/documentation/foundation/attributedstring)
