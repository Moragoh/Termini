# Data Flow

This document describes how data moves through the Termini application.

---

## User Input Flow

When a user types a command and presses Enter:

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User types "ls -la" in TextField                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. ContentView                                                   │
│    - TextField binding: viewModel.currentInput = "ls -la"        │
│    - User presses Enter → .onSubmit triggers                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. TerminalViewModel.sendCommand()                               │
│    - Clears output buffer (rawOutput = "")                       │
│    - Appends newline: command = "ls -la\n"                       │
│    - Clears input: currentInput = ""                             │
│    - Calls ptyManager.send(command)                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. PTYManager.send()                                             │
│    - write(masterFD, "ls -la\n", 7)                              │
│    - Bytes written to PTY master file descriptor                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Kernel PTY Layer                                              │
│    - Forwards bytes to slave PTY                                 │
│    - Shell's stdin receives the command                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. /bin/zsh (Child Process)                                      │
│    - Reads "ls -la\n" from stdin                                 │
│    - Parses and executes command                                 │
│    - Writes output to stdout                                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Shell Output Flow

When the shell produces output:

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Shell writes to stdout                                        │
│    "drwxr-xr-x  5 user  staff   160 Jan 29 10:00 Documents\n"   │
│    (may include ANSI codes for colors)                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. PTYManager Read Loop (Background Queue)                       │
│    while self.masterFD >= 0 {                                    │
│        let bytesRead = read(self.masterFD, &buffer, 4096)        │
│        if bytesRead > 0 {                                        │
│            let text = String(data: data, encoding: .utf8)        │
│            DispatchQueue.main.async {                            │
│                self.onOutput?(text)  ─────────────────────┐      │
│            }                                               │      │
│        }                                                   │      │
│    }                                                       │      │
└────────────────────────────────────────────────────────────┼──────┘
                                                             │
                              ┌──────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. TerminalViewModel.handleOutput() [Main Thread]                │
│                                                                  │
│    a. Check for screen clear sequences                           │
│       if containsScreenClear(text) {                             │
│           rawOutput = text        // Reset buffer                │
│       } else {                                                   │
│           rawOutput += text       // Append                      │
│       }                                                          │
│                                                                  │
│    b. Trim if too long                                           │
│       if rawOutput.count > 50_000 { ... }                        │
│                                                                  │
│    c. Parse ANSI codes                                           │
│       attributedOutput = ANSIParser.parse(rawOutput)             │
│                                                                  │
│    d. Schedule widget sync                                       │
│       scheduleSaveToSharedData()                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ @Published triggers SwiftUI update
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. ContentView Updates                                           │
│    Text(viewModel.attributedOutput)                              │
│    - SwiftUI re-renders the Text view                            │
│    - Styled output appears on screen                             │
│    - ScrollView auto-scrolls to bottom                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Widget Sync Flow

How terminal output reaches the desktop widget:

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. TerminalViewModel.scheduleSaveToSharedData()                  │
│    - Cancels any pending save                                    │
│    - Schedules new save in 5 seconds (debounce)                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ 5 seconds later...
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. TerminalViewModel.saveToSharedData()                          │
│                                                                  │
│    a. Strip ANSI codes for clean widget display                  │
│       let cleanOutput = ANSIParser.stripCodes(rawOutput)         │
│                                                                  │
│    b. Create state object                                        │
│       let state = TerminalState(                                 │
│           outputText: cleanOutput,                               │
│           timestamp: Date(),                                     │
│           currentDirectory: cwd,                                 │
│           isExecutingCommand: false                              │
│       )                                                          │
│                                                                  │
│    c. Save to disk                                               │
│       try sharedData.save(state: state)                          │
│                                                                  │
│    d. Request widget refresh                                     │
│       WidgetCenter.shared.reloadTimelines(ofKind: "TerminiWidget")│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. SharedDataManager.save()                                      │
│    - Encodes TerminalState to JSON                               │
│    - Writes to App Group container (atomic)                      │
│    - File: ~/Library/Group Containers/.../terminal_state.json    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ (Separate Process)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. Widget Extension - TimelineProvider.getTimeline()             │
│    - Called by WidgetKit on refresh                              │
│    - Calls createEntry()                                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. TimelineProvider.createEntry()                                │
│    - SharedDataManager.shared.load()                             │
│    - Reads JSON from App Group container                         │
│    - Creates TerminalEntry with parsed output                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. TerminiWidgetEntryView                                        │
│    - Displays entry.terminalOutput                               │
│    - Shows entry.lastUpdated as "X ago"                          │
│    - Widget on desktop updates                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Control Character Flow

When the user presses Ctrl+C:

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User presses Ctrl+C                                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. ContentView .onKeyPress handler                               │
│    .onKeyPress(characters: .init(charactersIn: "c"), ...) {      │
│        if keyPress.modifiers.contains(.control) {                │
│            viewModel.sendControl("c")                            │
│            return .handled                                       │
│        }                                                         │
│    }                                                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. TerminalViewModel.sendControl("c")                            │
│    - Converts 'c' to control code: ASCII 3                       │
│    - controlCode = 'c' - 'a' + 1 = 3                             │
│    - Calls ptyManager.sendByte(3)                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. PTYManager.sendByte(3)                                        │
│    - write(masterFD, &byte, 1)                                   │
│    - Single byte 0x03 written to PTY                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Kernel Terminal Driver                                        │
│    - Recognizes 0x03 as interrupt character                      │
│    - Sends SIGINT to foreground process group                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. Running Process (e.g., sleep, ping)                           │
│    - Receives SIGINT                                             │
│    - Default handler terminates the process                      │
│    - Shell regains control, displays new prompt                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## ANSI Parsing Flow

How raw output becomes styled text:

```
┌─────────────────────────────────────────────────────────────────┐
│ Input: "\u{1B}[32mSuccess\u{1B}[0m: File created"                │
│        └─green─┘       └reset┘                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ ANSIParser.parse()                                               │
│                                                                  │
│ Step 1: preprocessText()                                         │
│ - Remove control sequences (none in this example)                │
│ - Result: "\u{1B}[32mSuccess\u{1B}[0m: File created"             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: Regex match SGR codes                                    │
│ Pattern: \u{1B}\[([0-9;]*)m                                      │
│                                                                  │
│ Match 1: "\u{1B}[32m" at position 0, params="32"                 │
│ Match 2: "\u{1B}[0m" at position 14, params="0"                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: Build AttributedString                                   │
│                                                                  │
│ a. Process "\u{1B}[32m" → set foregroundColor = green            │
│                                                                  │
│ b. Text "Success" (positions 7-13)                               │
│    → AttributedString("Success") with green color                │
│                                                                  │
│ c. Process "\u{1B}[0m" → reset all attributes                    │
│                                                                  │
│ d. Text ": File created" (positions 18-31)                       │
│    → AttributedString(": File created") with default color       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Output: AttributedString                                         │
│ ┌─────────────────────────────────────────┐                     │
│ │ "Success"        │ ": File created"     │                     │
│ │ color: green     │ color: default       │                     │
│ └─────────────────────────────────────────┘                     │
└─────────────────────────────────────────────────────────────────┘
```
