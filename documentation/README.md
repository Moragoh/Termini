# Termini Documentation

Welcome to the Termini documentation. This documentation provides a complete guide to understanding, using, and developing the Termini terminal emulator.

---

## Table of Contents

| Document | Description |
|----------|-------------|
| [01 - Overview](01-overview.md) | What Termini is, key features, technology stack, requirements |
| [02 - Architecture](02-architecture.md) | MVVM pattern, two-process architecture, component diagrams, threading model |
| [03 - Project Structure](03-project-structure.md) | Directory layout, target membership, file descriptions, entitlements |
| [04 - Core Components](04-core-components.md) | PTYManager, ANSIParser, TerminalViewModel, SharedDataManager, Widget |
| [05 - Data Flow](05-data-flow.md) | User input flow, shell output flow, widget sync, ANSI parsing |
| [06 - Configuration](06-configuration.md) | App Groups, environment variables, window settings, buffer limits |
| [07 - Known Limitations](07-known-limitations.md) | Widget refresh, carriage returns, missing features, platform limits |
| [08 - Development Guide](08-development-guide.md) | Building, testing, debugging, code style, adding features |

---

## Quick Links

### For Users

- [What is Termini?](01-overview.md#what-is-termini)
- [Quick Start](01-overview.md#quick-start)
- [Known Limitations](07-known-limitations.md)

### For Developers

- [Architecture Overview](02-architecture.md)
- [Project Structure](03-project-structure.md)
- [Development Guide](08-development-guide.md)

### Technical Deep Dives

- [How PTY Works](04-core-components.md#1-ptymanager)
- [ANSI Parsing](04-core-components.md#2-ansiparser)
- [Widget Sync Flow](05-data-flow.md#widget-sync-flow)

---

## Document Conventions

### Code Examples

Swift code is shown in fenced code blocks:

```swift
let example = "Hello, World!"
print(example)
```

### Diagrams

Architecture diagrams use ASCII art for compatibility:

```
┌───────────────┐     ┌───────────────┐
│  Component A  │────►│  Component B  │
└───────────────┘     └───────────────┘
```

### Tables

Information is organized in tables where appropriate:

| Column 1 | Column 2 |
|----------|----------|
| Data | Description |

---

## Version

This documentation corresponds to Termini version 1.0.

Last updated: January 2026
