# Termini Overview

**A macOS Terminal Emulator with Desktop Widget Integration**

---

## What is Termini?

Termini is a native macOS application that provides a functional terminal window running Zsh, paired with a desktop widget that mirrors the terminal's output. The shell session persists in the background even when the main window is closed.

---

## Components

| Component | Description |
|-----------|-------------|
| **Host Application** | A functional terminal window running the user's default Zsh shell with full support for standard commands and TUI applications |
| **Desktop Widget** | A macOS widget that displays the most recent terminal output, updated periodically |
| **Background Persistence** | The shell session continues running when the window is closed, maintaining state |

---

## Key Features

- Full pseudo-terminal (PTY) implementation for proper shell behavior
- ANSI escape code parsing for colored terminal output
- Inter-process communication between app and widget via App Groups
- Support for interactive programs (vim, htop, top, nano)
- Keyboard shortcuts including Ctrl+C for process interruption
- Background persistence — shell keeps running when window is closed

---

## Technology Stack

| Technology | Purpose |
|------------|---------|
| **Swift** | Primary programming language |
| **SwiftUI** | User interface framework |
| **WidgetKit** | Desktop widget framework |
| **App Groups** | Inter-process communication |
| **PTY (forkpty)** | Pseudo-terminal for shell execution |

---

## Requirements

- **macOS:** 14.0 (Sonoma) or later
- **Xcode:** 15.0 or later (for development)
- **Architecture:** Apple Silicon or Intel

---

## Quick Start

1. Open `Termini.xcodeproj` in Xcode
2. Select the `Termini` scheme
3. Press `Cmd+R` to build and run
4. The terminal window appears — type commands and press Enter
5. Add the widget: Right-click desktop → Edit Widgets → Search "Termini"

---

## Use Cases

- **Quick Command Access:** Run terminal commands without opening a full terminal app
- **Monitoring:** Keep an eye on command output via the desktop widget
- **Persistent Sessions:** Close the window without losing your shell session
- **Learning:** Well-documented codebase for understanding terminal emulator internals
