//
//  ANSIParser.swift
//  Termini
//
//  Shared between: Main App & Widget Extension
//  Purpose: Converts raw terminal output (with ANSI escape codes) into
//           styled AttributedString for display in SwiftUI.
//
//  What are ANSI escape codes?
//  They're special character sequences that terminals interpret as formatting commands.
//  Example: "\u{1B}[31m" means "start red text", "\u{1B}[0m" means "reset formatting"
//
//  The escape character is \u{1B} (ESC, ASCII 27), followed by [ and then numbers/letters.
//

import SwiftUI

/// Parses ANSI escape codes and converts them to AttributedString.
///
/// Supported codes:
/// - Colors: 30-37 (foreground), 40-47 (background), 90-97, 100-107 (bright)
/// - 256 colors: 38;5;N and 48;5;N
/// - Styles: 1 (bold), 3 (italic), 4 (underline), 0 (reset)
///
/// Why a struct with static methods?
/// - No state needed between parse calls
/// - Purely functional: input string → output AttributedString
/// - Easy to test
struct ANSIParser {

    // MARK: - Main Parsing Function

    /// Converts a string with ANSI codes to a styled AttributedString.
    ///
    /// - Parameter rawText: The raw terminal output containing ANSI escape codes.
    /// - Returns: An AttributedString with colors and styles applied.
    static func parse(_ rawText: String) -> AttributedString {
        var result = AttributedString()
        var currentAttributes = TextAttributes()

        // Regex to match ANSI escape sequences
        // Pattern: ESC [ (numbers separated by ;) letter
        // Example: \u{1B}[31;1m (red + bold)
        let pattern = "\u{1B}\\[([0-9;]*)([A-Za-z])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return AttributedString(rawText)
        }

        let nsString = rawText as NSString
        var lastEnd = 0

        let matches = regex.matches(in: rawText, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            // Add text before this escape sequence
            if match.range.location > lastEnd {
                let textRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let plainText = nsString.substring(with: textRange)
                var styledText = AttributedString(plainText)
                currentAttributes.apply(to: &styledText)
                result += styledText
            }

            // Parse the escape sequence
            if match.numberOfRanges >= 3 {
                let paramsRange = match.range(at: 1)
                let commandRange = match.range(at: 2)

                let params = paramsRange.location != NSNotFound
                    ? nsString.substring(with: paramsRange)
                    : ""
                let command = commandRange.location != NSNotFound
                    ? nsString.substring(with: commandRange)
                    : ""

                // Handle SGR (Select Graphic Rendition) - the 'm' command
                if command == "m" {
                    parseGraphicsCommand(params, attributes: &currentAttributes)
                }
                // Other commands (cursor movement, etc.) are ignored for now
            }

            lastEnd = match.range.location + match.range.length
        }

        // Add remaining text after last escape sequence
        if lastEnd < nsString.length {
            let remaining = nsString.substring(from: lastEnd)
            var styledText = AttributedString(remaining)
            currentAttributes.apply(to: &styledText)
            result += styledText
        }

        return result
    }

    /// Strips all ANSI escape codes from text, returning plain text.
    /// Useful when you just need the content without formatting.
    static func stripCodes(_ rawText: String) -> String {
        let pattern = "\u{1B}\\[[0-9;]*[A-Za-z]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return rawText
        }
        let range = NSRange(location: 0, length: rawText.utf16.count)
        return regex.stringByReplacingMatches(in: rawText, range: range, withTemplate: "")
    }

    // MARK: - Private Parsing Helpers

    /// Parses SGR parameters and updates the current attributes.
    private static func parseGraphicsCommand(_ params: String, attributes: inout TextAttributes) {
        // Split by semicolon: "31;1" → ["31", "1"]
        let codes = params.split(separator: ";").compactMap { Int($0) }

        if codes.isEmpty {
            // Empty params (ESC[m) means reset
            attributes.reset()
            return
        }

        var i = 0
        while i < codes.count {
            let code = codes[i]

            switch code {
            // Reset
            case 0:
                attributes.reset()

            // Bold
            case 1:
                attributes.isBold = true

            // Dim (faint)
            case 2:
                attributes.isDim = true

            // Italic
            case 3:
                attributes.isItalic = true

            // Underline
            case 4:
                attributes.isUnderline = true

            // Normal intensity (not bold, not dim)
            case 22:
                attributes.isBold = false
                attributes.isDim = false

            // Not italic
            case 23:
                attributes.isItalic = false

            // Not underlined
            case 24:
                attributes.isUnderline = false

            // Standard foreground colors (30-37)
            case 30...37:
                attributes.foregroundColor = Self.standardColor(code - 30)

            // Default foreground
            case 39:
                attributes.foregroundColor = nil

            // Standard background colors (40-47)
            case 40...47:
                attributes.backgroundColor = Self.standardColor(code - 40)

            // Default background
            case 49:
                attributes.backgroundColor = nil

            // Bright foreground colors (90-97)
            case 90...97:
                attributes.foregroundColor = Self.brightColor(code - 90)

            // Bright background colors (100-107)
            case 100...107:
                attributes.backgroundColor = Self.brightColor(code - 100)

            // 256-color mode: 38;5;N (foreground) or 48;5;N (background)
            case 38:
                if i + 2 < codes.count && codes[i + 1] == 5 {
                    attributes.foregroundColor = Self.color256(codes[i + 2])
                    i += 2
                }

            case 48:
                if i + 2 < codes.count && codes[i + 1] == 5 {
                    attributes.backgroundColor = Self.color256(codes[i + 2])
                    i += 2
                }

            default:
                break // Ignore unknown codes
            }

            i += 1
        }
    }

    // MARK: - Color Definitions

    /// Standard 8 ANSI colors (0-7).
    private static func standardColor(_ index: Int) -> Color {
        switch index {
        case 0: return Color(red: 0.0, green: 0.0, blue: 0.0)       // Black
        case 1: return Color(red: 0.8, green: 0.0, blue: 0.0)       // Red
        case 2: return Color(red: 0.0, green: 0.8, blue: 0.0)       // Green
        case 3: return Color(red: 0.8, green: 0.8, blue: 0.0)       // Yellow
        case 4: return Color(red: 0.0, green: 0.0, blue: 0.8)       // Blue
        case 5: return Color(red: 0.8, green: 0.0, blue: 0.8)       // Magenta
        case 6: return Color(red: 0.0, green: 0.8, blue: 0.8)       // Cyan
        case 7: return Color(red: 0.75, green: 0.75, blue: 0.75)    // White
        default: return Color.primary
        }
    }

    /// Bright ANSI colors (8-15).
    private static func brightColor(_ index: Int) -> Color {
        switch index {
        case 0: return Color(red: 0.5, green: 0.5, blue: 0.5)       // Bright Black (Gray)
        case 1: return Color(red: 1.0, green: 0.0, blue: 0.0)       // Bright Red
        case 2: return Color(red: 0.0, green: 1.0, blue: 0.0)       // Bright Green
        case 3: return Color(red: 1.0, green: 1.0, blue: 0.0)       // Bright Yellow
        case 4: return Color(red: 0.0, green: 0.0, blue: 1.0)       // Bright Blue
        case 5: return Color(red: 1.0, green: 0.0, blue: 1.0)       // Bright Magenta
        case 6: return Color(red: 0.0, green: 1.0, blue: 1.0)       // Bright Cyan
        case 7: return Color(red: 1.0, green: 1.0, blue: 1.0)       // Bright White
        default: return Color.primary
        }
    }

    /// 256-color palette lookup.
    /// 0-7: standard colors, 8-15: bright colors, 16-231: color cube, 232-255: grayscale
    private static func color256(_ index: Int) -> Color {
        switch index {
        case 0...7:
            return standardColor(index)
        case 8...15:
            return brightColor(index - 8)
        case 16...231:
            // 6x6x6 color cube
            let adjusted = index - 16
            let r = adjusted / 36
            let g = (adjusted % 36) / 6
            let b = adjusted % 6
            return Color(
                red: r > 0 ? Double(r * 40 + 55) / 255.0 : 0,
                green: g > 0 ? Double(g * 40 + 55) / 255.0 : 0,
                blue: b > 0 ? Double(b * 40 + 55) / 255.0 : 0
            )
        case 232...255:
            // Grayscale ramp
            let gray = Double((index - 232) * 10 + 8) / 255.0
            return Color(red: gray, green: gray, blue: gray)
        default:
            return Color.primary
        }
    }
}

// MARK: - Text Attributes

/// Tracks the current text styling state as we parse ANSI codes.
private struct TextAttributes {
    var foregroundColor: Color?
    var backgroundColor: Color?
    var isBold: Bool = false
    var isDim: Bool = false
    var isItalic: Bool = false
    var isUnderline: Bool = false

    /// Resets all attributes to default.
    mutating func reset() {
        foregroundColor = nil
        backgroundColor = nil
        isBold = false
        isDim = false
        isItalic = false
        isUnderline = false
    }

    /// Applies these attributes to an AttributedString.
    func apply(to string: inout AttributedString) {
        if let fg = foregroundColor {
            string.foregroundColor = fg
        }
        if let bg = backgroundColor {
            string.backgroundColor = bg
        }
        if isBold {
            string.font = .system(.body, weight: .bold)
        }
        if isItalic {
            string.font = (string.font ?? .body).italic()
        }
        if isUnderline {
            string.underlineStyle = .single
        }
        if isDim {
            string.foregroundColor = (foregroundColor ?? .primary).opacity(0.5)
        }
    }
}
