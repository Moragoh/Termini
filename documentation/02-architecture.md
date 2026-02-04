# Architecture

This document describes Termini's software architecture, design patterns, and component relationships.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        MAIN APPLICATION                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────────────┐     ┌───────────────────┐     ┌───────────┐ │
│   │ ContentView  │◄───►│TerminalViewModel  │◄───►│PTYManager │ │
│   │   (View)     │     │   (ViewModel)     │     │  (Model)  │ │
│   └──────────────┘     └───────────────────┘     └───────────┘ │
│                               │                        │        │
│                               │                        │        │
│                               ▼                        ▼        │
│                        ┌─────────────┐         ┌──────────┐    │
│                        │ ANSIParser  │         │ /bin/zsh │    │
│                        └─────────────┘         └──────────┘    │
│                               │                                 │
└───────────────────────────────┼─────────────────────────────────┘
                                │
                                ▼ writes JSON
                    ┌───────────────────────┐
                    │   App Group Container  │
                    │  (terminal_state.json) │
                    └───────────────────────┘
                                ▲ reads JSON
                                │
┌───────────────────────────────┼─────────────────────────────────┐
│                        WIDGET EXTENSION                          │
├─────────────────────────────────────────────────────────────────┤
│   ┌──────────────┐     ┌───────────────────┐                    │
│   │WidgetEntryView│◄───│TimelineProvider   │                    │
│   └──────────────┘     └───────────────────┘                    │
│                               │                                  │
│                               ▼                                  │
│                     ┌─────────────────────┐                     │
│                     │ SharedDataManager   │                     │
│                     └─────────────────────┘                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Design Pattern: MVVM

Termini follows the **Model-View-ViewModel** pattern for clean separation of concerns.

### Layer Responsibilities

| Layer | Component | Responsibility |
|-------|-----------|----------------|
| **Model** | `PTYManager`, `TerminalState` | Business logic, data structures, shell process management |
| **ViewModel** | `TerminalViewModel` | Coordinates between Model and View, manages UI state, handles business rules |
| **View** | `ContentView` | Displays UI, captures user input, contains minimal logic |

### Why MVVM?

1. **Testability:** ViewModels can be unit tested without UI
2. **Separation:** Views remain "dumb" — they only display what they're told
3. **Maintainability:** Logic changes don't require UI changes (and vice versa)
4. **Reusability:** ViewModels can be reused with different views

### Data Binding

SwiftUI's `@Published` properties in the ViewModel automatically update the View:

```swift
// ViewModel
@Published var attributedOutput: AttributedString

// View (automatically updates when attributedOutput changes)
Text(viewModel.attributedOutput)
```

---

## Two-Process Architecture

Termini consists of two separate processes that communicate via the filesystem:

### Main Application Process

- Runs the terminal UI
- Manages the PTY and shell subprocess
- Writes terminal state to shared container

### Widget Extension Process

- Runs independently from main app
- Reads terminal state from shared container
- Updates on WidgetKit timeline schedule

### Why Separate Processes?

Apple requires widgets to run as separate extension processes. They cannot:
- Share memory with the main app
- Directly call main app functions
- Run continuously (they're timeline-based)

This necessitates file-based IPC via App Groups.

---

## Component Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    Main Application                      │
│                                                          │
│  ┌─────────────────────────────────────────────────────┐│
│  │                    TerminiApp                        ││
│  │  - App entry point                                   ││
│  │  - Window configuration                              ││
│  │  - AppDelegate for lifecycle                         ││
│  └─────────────────────────────────────────────────────┘│
│                          │                               │
│                          ▼                               │
│  ┌─────────────────────────────────────────────────────┐│
│  │                   ContentView                        ││
│  │  - Terminal output display (ScrollView + Text)       ││
│  │  - Input field (TextField)                           ││
│  │  - Keyboard handling (Ctrl+C, Escape)                ││
│  └─────────────────────────────────────────────────────┘│
│                          │                               │
│                          ▼                               │
│  ┌─────────────────────────────────────────────────────┐│
│  │               TerminalViewModel                      ││
│  │  - @Published properties for UI binding              ││
│  │  - Output buffer management                          ││
│  │  - ANSI parsing coordination                         ││
│  │  - Widget sync scheduling                            ││
│  └─────────────────────────────────────────────────────┘│
│                          │                               │
│            ┌─────────────┴─────────────┐                │
│            ▼                           ▼                │
│  ┌──────────────────┐      ┌──────────────────────┐    │
│  │   PTYManager     │      │     ANSIParser       │    │
│  │  - forkpty()     │      │  - Parse colors      │    │
│  │  - Shell I/O     │      │  - Strip controls    │    │
│  │  - Process mgmt  │      │  - AttributedString  │    │
│  └──────────────────┘      └──────────────────────┘    │
│            │                                            │
│            ▼                                            │
│  ┌──────────────────┐                                  │
│  │    /bin/zsh      │                                  │
│  │  (child process) │                                  │
│  └──────────────────┘                                  │
└─────────────────────────────────────────────────────────┘

                    │
                    │ SharedDataManager
                    ▼

┌─────────────────────────────────────────────────────────┐
│              App Group Container (Disk)                  │
│                                                          │
│  ┌─────────────────────────────────────────────────────┐│
│  │              terminal_state.json                     ││
│  │  {                                                   ││
│  │    "outputText": "...",                              ││
│  │    "timestamp": "2026-01-29T...",                    ││
│  │    "currentDirectory": "/Users/...",                 ││
│  │    "isExecutingCommand": false                       ││
│  │  }                                                   ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘

                    │
                    │ SharedDataManager
                    ▼

┌─────────────────────────────────────────────────────────┐
│                  Widget Extension                        │
│                                                          │
│  ┌─────────────────────────────────────────────────────┐│
│  │              TimelineProvider                        ││
│  │  - Generates timeline entries                        ││
│  │  - Reads from SharedDataManager                      ││
│  │  - Schedules refreshes                               ││
│  └─────────────────────────────────────────────────────┘│
│                          │                               │
│                          ▼                               │
│  ┌─────────────────────────────────────────────────────┐│
│  │             TerminiWidgetEntryView                   ││
│  │  - Displays terminal output                          ││
│  │  - Adapts to widget sizes                            ││
│  │  - Shows last update time                            ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

---

## Threading Model

### Main Thread
- All UI updates
- SwiftUI view rendering
- ViewModel `@Published` property changes

### Background Queue (PTY Read)
- Continuous read loop on shell output
- Dispatches to main thread for processing

```swift
readQueue.async { [weak self] in
    while self.masterFD >= 0 {
        let bytesRead = read(self.masterFD, &buffer, bufferSize)
        if bytesRead > 0 {
            DispatchQueue.main.async {
                self.onOutput?(text)  // Back to main thread
            }
        }
    }
}
```

### Debounce Queue (Widget Sync)
- Delays widget updates by 5 seconds
- Prevents excessive disk I/O and widget reload requests

---

## Memory Management

### Output Buffer Limits
```swift
private let maxOutputLength = 50_000  // Characters
```

When exceeded, the oldest content is discarded:
```swift
if rawOutput.count > maxOutputLength {
    let startIndex = rawOutput.index(rawOutput.endIndex, offsetBy: -maxOutputLength)
    rawOutput = String(rawOutput[startIndex...])
}
```

### Weak References
Callbacks use `[weak self]` to prevent retain cycles:
```swift
ptyManager.onOutput = { [weak self] text in
    self?.handleOutput(text)
}
```
