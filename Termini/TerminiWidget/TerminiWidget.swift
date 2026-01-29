//
//  TerminiWidget.swift
//  TerminiWidget
//
//  Purpose: The widget that mirrors the terminal output.
//           Reads from the shared App Group container and displays
//           the most recent terminal output.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

/// Provides timeline entries for the widget.
///
/// How widgets work:
/// - Widgets don't run continuously - they display "snapshots" at specific times
/// - The provider generates a timeline of entries (snapshots)
/// - The system displays each entry at its scheduled time
/// - We request updates as frequently as Apple allows
struct Provider: TimelineProvider {

    /// Placeholder shown while the widget loads.
    func placeholder(in context: Context) -> TerminalEntry {
        TerminalEntry(
            date: Date(),
            terminalOutput: AttributedString("Loading terminal..."),
            lastUpdated: Date()
        )
    }

    /// Snapshot for the widget gallery preview.
    func getSnapshot(in context: Context, completion: @escaping (TerminalEntry) -> ()) {
        let entry = createEntry()
        completion(entry)
    }

    /// Generates the timeline of entries.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TerminalEntry>) -> ()) {
        let entry = createEntry()

        // Widget refresh strategy:
        //
        // We use `.atEnd` policy which tells the system to request a new
        // timeline as soon as the current one expires. Combined with the
        // main app calling WidgetCenter.shared.reloadTimelines() when
        // output changes, this gives us the most responsive updates possible.
        //
        // IMPORTANT LIMITATION: Apple throttles widget refreshes regardless
        // of what we request. In practice, expect updates every few minutes
        // at best. For real-time display (like htop), users must use the
        // main app window — the widget shows "last known state" only.
        //
        // We set a 1-minute refresh as a fallback, but the app-triggered
        // reloads are the primary update mechanism.
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date()

        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }

    /// Creates an entry by reading from shared data.
    private func createEntry() -> TerminalEntry {
        let state = SharedDataManager.shared.load()

        if let state = state {
            // Parse ANSI codes for colored display
            let attributed = ANSIParser.parse(getLastLines(from: state.outputText, count: 20))
            return TerminalEntry(
                date: Date(),
                terminalOutput: attributed,
                lastUpdated: state.timestamp
            )
        } else {
            return TerminalEntry(
                date: Date(),
                terminalOutput: AttributedString("No terminal output yet.\nOpen Termini to start."),
                lastUpdated: Date()
            )
        }
    }

    /// Gets the last N lines from the output for display in the widget.
    /// Widgets have limited space, so we only show recent output.
    private func getLastLines(from text: String, count: Int) -> String {
        let lines = text.components(separatedBy: "\n")
        let lastLines = lines.suffix(count)
        return lastLines.joined(separator: "\n")
    }
}

// MARK: - Timeline Entry

/// Represents a single snapshot of the widget's state.
struct TerminalEntry: TimelineEntry {
    /// When this entry should be displayed (required by TimelineEntry).
    let date: Date

    /// The parsed terminal output to display.
    let terminalOutput: AttributedString

    /// When the terminal data was last updated.
    let lastUpdated: Date
}

// MARK: - Widget View

/// The actual widget UI.
struct TerminiWidgetEntryView: View {
    var entry: Provider.Entry

    @Environment(\.widgetFamily) var widgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header with update time
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(.green)
                Text("Termini")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(entry.lastUpdated, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Terminal output
            Text(entry.terminalOutput)
                .font(.system(size: fontSize, design: .monospaced))
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(8)
    }

    /// Adjust font size based on widget size.
    private var fontSize: CGFloat {
        switch widgetFamily {
        case .systemSmall:
            return 8
        case .systemMedium:
            return 9
        case .systemLarge:
            return 10
        default:
            return 9
        }
    }

    /// Adjust line limit based on widget size.
    private var lineLimit: Int {
        switch widgetFamily {
        case .systemSmall:
            return 6
        case .systemMedium:
            return 8
        case .systemLarge:
            return 20
        default:
            return 8
        }
    }
}

// MARK: - Widget Configuration

struct TerminiWidget: Widget {
    let kind: String = "TerminiWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(macOS 14.0, *) {
                TerminiWidgetEntryView(entry: entry)
                    .containerBackground(Color.black, for: .widget)
            } else {
                TerminiWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color.black)
            }
        }
        .configurationDisplayName("Termini")
        .description("Mirror your terminal output on your desktop.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    TerminiWidget()
} timeline: {
    TerminalEntry(
        date: Date(),
        terminalOutput: AttributedString("$ ls\nDocuments  Downloads  Desktop\n$ echo 'Hello'\nHello"),
        lastUpdated: Date()
    )
}
