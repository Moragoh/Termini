# Configuration

This document covers the configuration options and setup requirements for Termini.

---

## App Groups

App Groups enable data sharing between the main application and widget extension.

### Setup Requirements

Both targets must have the **same** App Group identifier configured:

| Target | Entitlements File |
|--------|-------------------|
| Termini | `Termini/Termini.entitlements` |
| TerminiWidgetExtension | `TerminiWidgetExtension.entitlements` |

### App Group Identifier

```
group.com.junminkim.termini
```

### Verifying Configuration

1. Open Xcode project
2. Select target (Termini or TerminiWidgetExtension)
3. Go to **Signing & Capabilities** tab
4. Verify **App Groups** capability is present
5. Confirm the identifier matches exactly

### Shared Container Location

```
~/Library/Group Containers/group.com.junminkim.termini/
```

Files stored here:
- `terminal_state.json` — Current terminal state

---

## Environment Variables

Environment variables set in the PTY child process:

| Variable | Value | Purpose |
|----------|-------|---------|
| `TERM` | `xterm-256color` | Enables 256-color support in shell and applications |
| `LANG` | `en_US.UTF-8` | Sets language and encoding |
| `LC_ALL` | `en_US.UTF-8` | Overrides all locale settings for UTF-8 |
| `PROMPT_EOL_MARK` | `""` (empty) | Disables zsh's `%` marker for partial lines |

### Why These Variables?

**TERM=xterm-256color**
- Required for color output in tools like `ls`, `git`, `grep`
- Enables proper rendering in TUI applications (vim, htop)
- Standard terminal type that most programs understand

**LANG and LC_ALL**
- Enables UTF-8 character support
- Required for proper display of special characters and emoji
- Prevents encoding errors in output

**PROMPT_EOL_MARK**
- Zsh-specific variable
- Without this, zsh displays `%` when a command doesn't end with newline
- Setting to empty string prevents this visual artifact

---

## Window Configuration

### Window Size

Configured in `TerminiApp.swift`:

```swift
.windowStyle(.hiddenTitleBar)
.defaultSize(width: 800, height: 600)
```

### PTY Size

Default terminal dimensions:

```swift
var winSize = winsize(
    ws_row: 24,      // 24 rows
    ws_col: 80,      // 80 columns
    ws_xpixel: 0,
    ws_ypixel: 0
)
```

These can be updated dynamically via `PTYManager.resize(columns:rows:)`.

---

## Widget Configuration

### Supported Sizes

| Size | Description | Lines Displayed | Font Size |
|------|-------------|-----------------|-----------|
| `systemSmall` | Small square | 6 lines | 8pt |
| `systemMedium` | Wide rectangle | 8 lines | 9pt |
| `systemLarge` | Large square | 20 lines | 10pt |

### Refresh Policy

```swift
let refreshDate = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
```

- Requests refresh every 1 minute
- Actual refresh controlled by WidgetKit (may be throttled)
- Immediate refresh triggered by main app via `WidgetCenter.shared.reloadTimelines()`

---

## Buffer Limits

### Output Buffer

```swift
private let maxOutputLength = 50_000  // Characters
```

When the buffer exceeds this limit, the oldest content is trimmed:

```swift
if rawOutput.count > maxOutputLength {
    let startIndex = rawOutput.index(rawOutput.endIndex, offsetBy: -maxOutputLength)
    rawOutput = String(rawOutput[startIndex...])
}
```

### Widget Sync Debounce

```swift
private let saveDebounceSeconds: Double = 5.0
```

Widget updates are debounced to prevent excessive disk I/O and WidgetKit refresh requests.

---

## Shell Configuration

### Default Shell

```swift
let shell = "/bin/zsh"
let args = [shell, "--login"]
```

The `--login` flag ensures:
- User's `.zprofile` is sourced
- User's `.zshrc` is sourced
- Login shell environment is properly initialized

### Changing the Shell

To use a different shell, modify `PTYManager.swift`:

```swift
let shell = "/bin/bash"  // Or any other shell path
let args = [shell, "--login"]
```

Note: ANSI parsing is shell-agnostic, but some environment variables (like `PROMPT_EOL_MARK`) are zsh-specific.

---

## Sandbox Configuration

### Why Sandbox is Disabled

Terminal emulators require capabilities incompatible with App Sandbox:

| Capability | Sandbox Status | Why Needed |
|------------|----------------|------------|
| Fork child processes | Blocked | Required for `forkpty()` |
| Execute arbitrary binaries | Blocked | Shell must run user commands |
| Full filesystem access | Limited | User expects `cd` to work anywhere |
| Signal delivery | Restricted | Ctrl+C sends SIGINT |

### Entitlements

The main app entitlements file contains only App Groups:

```xml
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.junminkim.termini</string>
    </array>
</dict>
```

App Sandbox keys are intentionally omitted.

### Security Implications

Without sandbox:
- App has full user-level filesystem access
- App can execute any program the user can
- App can send signals to processes

This is expected and necessary for a terminal emulator.
