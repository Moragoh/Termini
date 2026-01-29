# Project Specification: Termini (macOS Terminal Widget)

## 1. Project Overview
**Name:** Termini
**Platform:** macOS (Native App + Widget Extension)
**Language:** Swift
**Frameworks:** SwiftUI, WidgetKit, Combine
**Core Concept:** Termini is a desktop widget that acts as a visual mirror for a persistent, background-running Zsh shell session.

---

## 2. Functional Description

### The Host Application (The Terminal)
* **Behavior:** The main app launches a functional terminal window running the user's default Zsh shell.
* **Capabilities:** It must behave like a standard terminal. It should accept input and correctly display output for standard commands (`ls`, `echo`) and interactive TUI (Text User Interface) applications (like `htop`, `vim`, or `nano`).
* **Background Persistence:** When the user closes or minimizes the main window, the shell session **must not terminate**. It should continue running in the background so the widget can continue monitoring it.

### The Widget (The Mirror)
* **Visual Mirroring:** The widget displays the most recent standard output (`stdout`) of the Host Application's shell session.
* **Interaction:** Clicking the widget should summon/open the Host Application window.
* **State Synchronization:** The widget must reflect the shell's output even if the main app window is closed.

---

## 3. Technical Architecture & Constraints

### A. Data Synchronization (App Groups)
* **Constraint:** The Host App and the Widget run in separate processes.
* **Requirement:** You must implement a robust data-sharing mechanism using **App Groups** (likely via a shared JSON file or `UserDefaults`).
* **Flow:** The Host App writes the shell output to this shared container; the Widget reads from it.

### B. Shell Execution (PTY - Pseudo Terminal)
* **Constraint:** Simply running a `Process` (pipe) in Swift is insufficient because it cannot handle interactive programs like `htop` or colors.
* **Requirement:** You must implement a **Pseudo-Terminal (PTY)** structure. This allows the app to trick the shell into thinking it is running in a real terminal window, enabling interactive modes and correct formatting.

### C. ANSI Parsing (Crucial)
* **The Problem:** The raw text output from Zsh contains ANSI escape codes (e.g., `\033[31m`) used for colors, bold text, and cursor positioning.
* **Requirement:** The app cannot simply display raw text strings, or the user will see garbage characters.
* **Implementation:** You must implement parsing logic that converts these ANSI codes into SwiftUI-compatible styling (e.g., `AttributedString` with colors). The Widget must display the text **in color**, matching the terminal.

### D. Widget Limitations
* **Constraint:** Apple limits how often Widgets can refresh (they are timelines, not video streams).
* **Goal:** Implement the most aggressive refresh strategy allowed by Apple to make the widget feel as "live" as possible, but clearly explain the limitations in the code comments.

---

## 4. Rules for the LLM

1.  **File Integrity:** Always reread all relevant files (for instance, `ContentView.swift`, `TerminiApp.swift`, `WidgetExtension.swift`, etc.) before proposing changes. Assume I may have manually edited them.
2.  **Ambiguity Check:** If a technical requirement is vague, **ASK** before coding.
3. Prioritize making the codebase clean and easy-to-understand
4.  **Educational Focus (Priority):** I am a novice in software architecture.
    * **Explain Why:** Every time you create a new file or struct, explain *why* it is necessary.
    * **Explain Architecture:** Tell me why you are separating the "Shell Logic" from the "View Logic" (MVVM).
    * **Clean Code:** Prioritize readable, modular code over clever one-liners.
5. Whenever a feature is implemented, write tests and run them to confirm that it works as intended.

---

## 5. First Task
Start by setting up the project structure. Explain how I should configure the **App Group** in Xcode (as this requires manual setup in project settings), and then generate the basic file structure to handle the Shared Data model.