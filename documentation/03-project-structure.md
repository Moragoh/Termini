# Project Structure

This document describes the file organization and target membership for the Termini project.

---

## Directory Layout

```
Termini/
├── Termini.xcodeproj/             # Xcode project configuration
│
├── Termini/                       # Main application target
│   ├── TerminiApp.swift           # App entry point (@main)
│   ├── ContentView.swift          # Main terminal UI view
│   ├── Termini.entitlements       # App capabilities (App Groups)
│   ├── Assets.xcassets/           # App icons and colors
│   │
│   ├── PTY/                       # Pseudo-terminal module
│   │   └── PTYManager.swift       # Shell process management
│   │
│   └── ViewModels/                # MVVM ViewModel layer
│       └── TerminalViewModel.swift
│
├── Shared/                        # Code shared between app and widget
│   ├── TerminalState.swift        # Data model (Codable)
│   ├── SharedDataManager.swift    # App Group file I/O
│   └── ANSIParser.swift           # ANSI escape code parser
│
├── TerminiWidget/                 # Widget extension target
│   ├── TerminiWidgetBundle.swift  # Widget bundle entry (@main)
│   ├── TerminiWidget.swift        # Widget provider and views
│   ├── Assets.xcassets/           # Widget assets
│   └── Info.plist                 # Widget configuration
│
├── TerminiWidgetExtension.entitlements  # Widget App Groups
│
├── TerminiTests/                  # Unit test target
│   └── TerminiTests.swift         # All unit tests
│
├── TerminiUITests/                # UI test target
│   ├── TerminiUITests.swift
│   └── TerminiUITestsLaunchTests.swift
│
└── documentation/                 # This documentation
    ├── 01-overview.md
    ├── 02-architecture.md
    ├── 03-project-structure.md
    └── ...
```

---

## Target Membership

Files must be assigned to the correct Xcode targets to compile properly.

### Shared Files (Both Targets)

These files are used by both the main app and the widget extension:

| File | Termini | TerminiWidgetExtension |
|------|:-------:|:----------------------:|
| `Shared/TerminalState.swift` | ✓ | ✓ |
| `Shared/SharedDataManager.swift` | ✓ | ✓ |
| `Shared/ANSIParser.swift` | ✓ | ✓ |

### Main App Only

These files are only used by the main application:

| File | Termini | TerminiWidgetExtension |
|------|:-------:|:----------------------:|
| `Termini/TerminiApp.swift` | ✓ | — |
| `Termini/ContentView.swift` | ✓ | — |
| `Termini/PTY/PTYManager.swift` | ✓ | — |
| `Termini/ViewModels/TerminalViewModel.swift` | ✓ | — |

### Widget Extension Only

These files are only used by the widget:

| File | Termini | TerminiWidgetExtension |
|------|:-------:|:----------------------:|
| `TerminiWidget/TerminiWidgetBundle.swift` | — | ✓ |
| `TerminiWidget/TerminiWidget.swift` | — | ✓ |

---

## File Descriptions

### Main Application

| File | Purpose |
|------|---------|
| **TerminiApp.swift** | SwiftUI `@main` entry point. Configures window style, size, and app delegate for background persistence. |
| **ContentView.swift** | Main UI with terminal output display (ScrollView + Text) and input field (TextField). Handles keyboard shortcuts. |
| **PTYManager.swift** | Creates and manages the pseudo-terminal. Forks the shell process, handles I/O, sends control signals. |
| **TerminalViewModel.swift** | Coordinates between PTY and View. Manages output buffer, ANSI parsing, and widget synchronization. |

### Shared

| File | Purpose |
|------|---------|
| **TerminalState.swift** | `Codable` struct representing terminal state. Contains output text, timestamp, working directory, and execution status. |
| **SharedDataManager.swift** | Singleton that reads/writes `TerminalState` to the App Group container as JSON. |
| **ANSIParser.swift** | Parses ANSI escape codes into SwiftUI `AttributedString`. Handles colors, styles, and control sequence stripping. |

### Widget Extension

| File | Purpose |
|------|---------|
| **TerminiWidgetBundle.swift** | Widget bundle `@main` entry point. Declares which widgets are available. |
| **TerminiWidget.swift** | Contains `TimelineProvider`, `TimelineEntry`, widget view, and configuration. |

### Tests

| File | Purpose |
|------|---------|
| **TerminiTests.swift** | Unit tests for ANSIParser, TerminalState encoding, PTYManager operations, and interactive programs. |

---

## Entitlements

### Termini.entitlements (Main App)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.junminkim.termini</string>
    </array>
</dict>
</plist>
```

**Note:** App Sandbox is intentionally disabled (not present) because terminal emulators require:
- Forking child processes
- Full filesystem access
- Execution of arbitrary commands

### TerminiWidgetExtension.entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.junminkim.termini</string>
    </array>
</dict>
</plist>
```

**Critical:** Both entitlement files must have the **exact same** App Group identifier.

---

## Build Configurations

### Schemes

| Scheme | Purpose |
|--------|---------|
| **Termini** | Builds and runs the main application |
| **TerminiWidgetExtension** | Builds the widget (usually built automatically with main app) |
| **TerminiTests** | Runs unit tests |

### Targets

| Target | Product | Bundle ID |
|--------|---------|-----------|
| Termini | Application | `com.junminkim.termini` |
| TerminiWidgetExtension | Widget Extension | `com.junminkim.termini.TerminiWidget` |
| TerminiTests | Unit Test Bundle | `com.junminkim.terminiTests` |

---

## Adding New Files

### To Main App Only
1. Create file in `Termini/` directory
2. In Xcode File Inspector, check only **Termini** target

### To Widget Only
1. Create file in `TerminiWidget/` directory
2. In Xcode File Inspector, check only **TerminiWidgetExtension** target

### To Both (Shared)
1. Create file in `Shared/` directory
2. In Xcode File Inspector, check **both** targets:
   - ✓ Termini
   - ✓ TerminiWidgetExtension

### Verifying Target Membership
1. Select the file in Xcode's Project Navigator
2. Open File Inspector (right panel, or `Cmd+Option+1`)
3. Check the **Target Membership** section
