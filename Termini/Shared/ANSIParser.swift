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
        // First, preprocess the text to remove control sequences we don't render
        let cleanedText = preprocessText(rawText)

        var result = AttributedString()
        var currentAttributes = TextAttributes()

        // Regex to match ANSI SGR (color/style) escape sequences
        // Pattern: ESC [ (numbers separated by ;) m
        // Example: \u{1B}[31;1m (red + bold)
        let pattern = "\u{1B}\\[([0-9;]*)m"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return AttributedString(cleanedText)
        }

        let nsString = cleanedText as NSString
        var lastEnd = 0

        let matches = regex.matches(in: cleanedText, range: NSRange(location: 0, length: nsString.length))

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
            if match.numberOfRanges >= 2 {
                let paramsRange = match.range(at: 1)

                let params = paramsRange.location != NSNotFound
                    ? nsString.substring(with: paramsRange)
                    : ""

                parseGraphicsCommand(params, attributes: &currentAttributes)
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

    /// Preprocesses raw terminal text by removing control sequences we don't render.
    ///
    /// This handles:
    /// - Private mode sequences: ESC[?...h/l (like bracketed paste mode)
    /// - Cursor movement: ESC[...H, ESC[...A/B/C/D, etc.
    /// - Other non-SGR sequences: ESC[...J, ESC[...K, etc.
    /// - Control characters: backspace, carriage return, etc.
    private static func preprocessText(_ rawText: String) -> String {
        var text = rawText

        // Direct removal of common problematic sequences (more reliable than regex)
        // These are the exact byte sequences that cause display issues
        text = text.replacingOccurrences(of: "\u{1B}[?2004h", with: "")
        text = text.replacingOccurrences(of: "\u{1B}[?2004l", with: "")
        text = text.replacingOccurrences(of: "\u{1B}[?1h", with: "")
        text = text.replacingOccurrences(of: "\u{1B}[?1l", with: "")
        text = text.replacingOccurrences(of: "\u{1B}[?25h", with: "")  // Show cursor
        text = text.replacingOccurrences(of: "\u{1B}[?25l", with: "")  // Hide cursor

        // Also remove orphaned versions (without ESC) that somehow slip through
        text = text.replacingOccurrences(of: "[?2004h", with: "")
        text = text.replacingOccurrences(of: "[?2004l", with: "")
        text = text.replacingOccurrences(of: "[?1h", with: "")
        text = text.replacingOccurrences(of: "[?1l", with: "")
        text = text.replacingOccurrences(of: "[?25h", with: "")
        text = text.replacingOccurrences(of: "[?25l", with: "")

        // Remove private mode sequences: ESC[?...letter (e.g., ESC[?2004h)
        // These control terminal modes like bracketed paste
        if let regex = try? NSRegularExpression(pattern: "\u{1B}\\[\\?[0-9;]*[A-Za-z]") {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(location: 0, length: text.utf16.count),
                withTemplate: ""
            )
        }

        // Remove orphaned private mode sequences (without ESC prefix)
        if let regex = try? NSRegularExpression(pattern: "\\[\\?[0-9;]*[A-Za-z]") {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(location: 0, length: text.utf16.count),
                withTemplate: ""
            )
        }

        // Remove other non-SGR escape sequences (cursor movement, clearing, etc.)
        // These end in letters other than 'm'
        if let regex = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*[A-LN-Za-ln-z]") {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(location: 0, length: text.utf16.count),
                withTemplate: ""
            )
        }

        // Remove OSC (Operating System Command) sequences: ESC]...BEL or ESC]...ESC\
        // These set window titles, etc.
        if let regex = try? NSRegularExpression(pattern: "\u{1B}\\][^\u{07}\u{1B}]*[\u{07}]|\u{1B}\\][^\u{1B}]*\u{1B}\\\\") {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(location: 0, length: text.utf16.count),
                withTemplate: ""
            )
        }

        // Handle backspace: remove character before \b and the \b itself
        // This handles things like "c\bclear" → "clear"
        while text.contains("\u{08}") {
            if let regex = try? NSRegularExpression(pattern: ".\u{08}") {
                let newText = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(location: 0, length: text.utf16.count),
                    withTemplate: ""
                )
                if newText == text { break }  // Prevent infinite loop
                text = newText
            } else {
                break
            }
        }

        // Remove standalone backspaces that might remain
        text = text.replacingOccurrences(of: "\u{08}", with: "")

        // Remove carriage returns for now.
        // TODO: Proper \r handling for progress indicators would require
        // tracking cursor position, which is complex.
        text = text.replacingOccurrences(of: "\r", with: "")

        // Remove any remaining escape sequences that might have been missed
        // This catches sequences where ESC might be represented differently
        if let regex = try? NSRegularExpression(pattern: "\u{1B}\\[[^m]*[A-Za-z]") {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(location: 0, length: text.utf16.count),
                withTemplate: ""
            )
        }

        // Final cleanup: remove orphaned CSI sequences where ESC was stripped
        // These look like [?2004h, [0m, [32m, etc. at the start of text or after newlines
        if let regex = try? NSRegularExpression(pattern: "\\[\\?[0-9;]*[A-Za-z]") {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(location: 0, length: text.utf16.count),
                withTemplate: ""
            )
        }

        // Catch remaining [0m, [32m, [1;32m style SGR codes without ESC prefix
        // Only match if it's [, then digits/semicolons, then 'm' (SGR command)
        if let regex = try? NSRegularExpression(pattern: "\\[[0-9;]+m") {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(location: 0, length: text.utf16.count),
                withTemplate: ""
            )
        }

        return text
    }

    /// Strips all ANSI escape codes from text, returning plain text.
    /// Useful when you just need the content without formatting.
    static func stripCodes(_ rawText: String) -> String {
        // Use the same preprocessing, then remove any remaining SGR codes
        var text = preprocessText(rawText)

        // Remove SGR (color) sequences
        if let regex = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*m") {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(location: 0, length: text.utf16.count),
                withTemplate: ""
            )
        }

        return text
    }

    // MARK: - Command-Based Parsing (New)

    /// Parses raw terminal output into a sequence of terminal commands.
    /// This is the new approach that properly handles cursor movement, carriage returns,
    /// and screen buffer switching instead of stripping them.
    ///
    /// - Parameter rawText: The raw terminal output.
    /// - Returns: An array of TerminalCommand to execute.
    static func parseToCommands(_ rawText: String) -> [TerminalCommand] {
        var commands: [TerminalCommand] = []
        var index = rawText.startIndex
        var currentRun = ""  // Accumulate plain text for batching

        while index < rawText.endIndex {
            let char = rawText[index]

            if char == "\u{1B}" {
                // Escape character - start of escape sequence
                // Flush any accumulated plain text first
                if !currentRun.isEmpty {
                    commands.append(.printString(currentRun))
                    currentRun = ""
                }

                // Try to parse the escape sequence
                if let (command, consumed) = parseEscapeSequence(rawText, from: index) {
                    commands.append(command)
                    index = rawText.index(index, offsetBy: consumed)
                    continue
                }
                // If we couldn't parse it, skip the ESC and continue
                index = rawText.index(after: index)
                continue
            }

            // Check for control characters
            if let controlCommand = parseControlCharacter(char) {
                // Flush plain text
                if !currentRun.isEmpty {
                    commands.append(.printString(currentRun))
                    currentRun = ""
                }
                commands.append(controlCommand)
                index = rawText.index(after: index)
                continue
            }

            // Regular printable character - accumulate it
            currentRun.append(char)
            index = rawText.index(after: index)
        }

        // Flush remaining text
        if !currentRun.isEmpty {
            commands.append(.printString(currentRun))
        }

        return commands
    }

    /// Parses a control character into a command.
    private static func parseControlCharacter(_ char: Character) -> TerminalCommand? {
        switch char {
        case "\r":      // Carriage Return
            return .carriageReturn
        case "\n":      // Line Feed
            return .lineFeed
        case "\u{08}":  // Backspace
            return .backspace
        case "\t":      // Tab
            return .tab
        case "\u{07}":  // Bell
            return .bell
        default:
            return nil
        }
    }

    /// Parses an escape sequence starting at the given index.
    /// Returns the command and number of characters consumed, or nil if not recognized.
    private static func parseEscapeSequence(_ text: String, from escIndex: String.Index) -> (TerminalCommand, Int)? {
        // We need at least ESC + one more character
        let nextIndex = text.index(after: escIndex)
        guard nextIndex < text.endIndex else { return nil }

        let nextChar = text[nextIndex]

        switch nextChar {
        case "[":
            // CSI sequence: ESC[...
            return parseCSISequence(text, from: nextIndex)
        case "]":
            // OSC sequence: ESC]...
            return parseOSCSequence(text, from: nextIndex)
        case "7":
            // Save cursor: ESC 7
            return (.saveCursor, 2)
        case "8":
            // Restore cursor: ESC 8
            return (.restoreCursor, 2)
        case "M":
            // Reverse index (scroll down): ESC M
            return (.scrollDown(1), 2)
        case "D":
            // Index (scroll up): ESC D
            return (.lineFeed, 2)
        case "E":
            // Next line: ESC E
            return (.cursorNextLine(1), 2)
        default:
            return nil
        }
    }

    /// Parses a CSI (Control Sequence Introducer) sequence: ESC[...
    private static func parseCSISequence(_ text: String, from bracketIndex: String.Index) -> (TerminalCommand, Int)? {
        var currentIndex = text.index(after: bracketIndex)
        guard currentIndex < text.endIndex else { return nil }

        var isPrivate = false
        var params = ""

        // Check for private mode indicator '?'
        if text[currentIndex] == "?" {
            isPrivate = true
            currentIndex = text.index(after: currentIndex)
        }

        // Collect parameter bytes (digits and semicolons)
        while currentIndex < text.endIndex {
            let c = text[currentIndex]
            if c.isNumber || c == ";" {
                params.append(c)
                currentIndex = text.index(after: currentIndex)
            } else {
                break
            }
        }

        // We need a final byte
        guard currentIndex < text.endIndex else { return nil }
        let finalByte = text[currentIndex]

        // Calculate total characters consumed (from ESC to finalByte inclusive)
        let consumed = text.distance(from: text.index(bracketIndex, offsetBy: -1), to: currentIndex) + 1

        // Parse the parameters
        let paramList = params.split(separator: ";").compactMap { Int($0) }

        // Interpret the sequence
        if let command = interpretCSI(finalByte: finalByte, params: paramList, isPrivate: isPrivate) {
            return (command, consumed)
        }

        return (.unknown("ESC[\(isPrivate ? "?" : "")\(params)\(finalByte)"), consumed)
    }

    /// Interprets a CSI sequence based on its final byte and parameters.
    private static func interpretCSI(finalByte: Character, params: [Int], isPrivate: Bool) -> TerminalCommand? {
        if isPrivate {
            // Private mode sequences: ESC[?...h or ESC[?...l
            let mode = params.first ?? 0
            switch finalByte {
            case "h":  // Set mode
                switch mode {
                case 1049:
                    return .switchToAlternateScreen
                case 2004:
                    return .bracketedPasteMode(true)
                case 25:
                    return .showCursor
                case 1:
                    return .setPrivateMode(1, true)  // Application cursor keys
                case 7:
                    return .setPrivateMode(7, true)  // Wraparound mode
                case 12:
                    return .setPrivateMode(12, true) // Cursor blink
                default:
                    return .setPrivateMode(mode, true)
                }
            case "l":  // Reset mode
                switch mode {
                case 1049:
                    return .switchToPrimaryScreen
                case 2004:
                    return .bracketedPasteMode(false)
                case 25:
                    return .hideCursor
                default:
                    return .setPrivateMode(mode, false)
                }
            default:
                return nil
            }
        }

        // Standard CSI sequences
        switch finalByte {
        case "A":  // Cursor Up
            return .cursorUp(params.first ?? 1)
        case "B":  // Cursor Down
            return .cursorDown(params.first ?? 1)
        case "C":  // Cursor Forward
            return .cursorForward(params.first ?? 1)
        case "D":  // Cursor Back
            return .cursorBack(params.first ?? 1)
        case "E":  // Cursor Next Line
            return .cursorNextLine(params.first ?? 1)
        case "F":  // Cursor Previous Line
            return .cursorPreviousLine(params.first ?? 1)
        case "G":  // Cursor Horizontal Absolute
            return .cursorColumn((params.first ?? 1) - 1)  // 1-based to 0-based
        case "H", "f":  // Cursor Position
            let row = (params.count > 0 ? params[0] : 1) - 1  // 1-based to 0-based
            let col = (params.count > 1 ? params[1] : 1) - 1
            if row == 0 && col == 0 && params.isEmpty {
                return .cursorHome
            }
            return .cursorPosition(row: row, col: col)
        case "J":  // Erase in Display
            let mode = params.first ?? 0
            return .eraseInDisplay(clearModeFromParam(mode))
        case "K":  // Erase in Line
            let mode = params.first ?? 0
            return .eraseInLine(clearModeFromParam(mode))
        case "L":  // Insert Lines
            return .insertLines(params.first ?? 1)
        case "M":  // Delete Lines
            return .deleteLines(params.first ?? 1)
        case "P":  // Delete Characters
            return .deleteCharacters(params.first ?? 1)
        case "@":  // Insert Characters
            return .insertCharacters(params.first ?? 1)
        case "S":  // Scroll Up
            return .scrollUp(params.first ?? 1)
        case "T":  // Scroll Down
            return .scrollDown(params.first ?? 1)
        case "m":  // SGR (Select Graphic Rendition)
            return parseSGRToCommand(params)
        case "r":  // Set Scroll Region (DECSTBM)
            let top = (params.count > 0 ? params[0] : 1) - 1
            let bottom = (params.count > 1 ? params[1] : 9999) - 1  // Use large number as default
            return .setScrollRegion(top: top, bottom: bottom)
        case "s":  // Save Cursor Position
            return .saveCursor
        case "u":  // Restore Cursor Position
            return .restoreCursor
        default:
            return nil
        }
    }

    /// Converts a numeric clear parameter to ClearMode.
    private static func clearModeFromParam(_ param: Int) -> ClearMode {
        switch param {
        case 0: return .toEnd
        case 1: return .toBeginning
        case 2: return .entire
        default: return .toEnd
        }
    }

    /// Parses SGR (Select Graphic Rendition) parameters into a command.
    private static func parseSGRToCommand(_ params: [Int]) -> TerminalCommand {
        if params.isEmpty {
            return .resetAttributes
        }

        var attributes: [SGRAttribute] = []
        var i = 0

        while i < params.count {
            let code = params[i]

            switch code {
            case 0:
                attributes.append(.reset)
            case 1:
                attributes.append(.bold(true))
            case 2:
                attributes.append(.dim(true))
            case 3:
                attributes.append(.italic(true))
            case 4:
                attributes.append(.underline(true))
            case 5, 6:
                attributes.append(.blink(true))
            case 7:
                attributes.append(.reverse(true))
            case 8:
                attributes.append(.hidden(true))
            case 9:
                attributes.append(.strikethrough(true))
            case 22:
                attributes.append(.bold(false))
                attributes.append(.dim(false))
            case 23:
                attributes.append(.italic(false))
            case 24:
                attributes.append(.underline(false))
            case 25:
                attributes.append(.blink(false))
            case 27:
                attributes.append(.reverse(false))
            case 28:
                attributes.append(.hidden(false))
            case 29:
                attributes.append(.strikethrough(false))
            case 30...37:
                attributes.append(.foreground(.standard(code - 30)))
            case 38:
                // Extended foreground color
                if i + 2 < params.count && params[i + 1] == 5 {
                    // 256-color mode: 38;5;N
                    attributes.append(.foreground(.palette256(params[i + 2])))
                    i += 2
                } else if i + 4 < params.count && params[i + 1] == 2 {
                    // RGB mode: 38;2;R;G;B
                    attributes.append(.foreground(.rgb(UInt8(params[i + 2]), UInt8(params[i + 3]), UInt8(params[i + 4]))))
                    i += 4
                }
            case 39:
                attributes.append(.foreground(nil))
            case 40...47:
                attributes.append(.background(.standard(code - 40)))
            case 48:
                // Extended background color
                if i + 2 < params.count && params[i + 1] == 5 {
                    // 256-color mode: 48;5;N
                    attributes.append(.background(.palette256(params[i + 2])))
                    i += 2
                } else if i + 4 < params.count && params[i + 1] == 2 {
                    // RGB mode: 48;2;R;G;B
                    attributes.append(.background(.rgb(UInt8(params[i + 2]), UInt8(params[i + 3]), UInt8(params[i + 4]))))
                    i += 4
                }
            case 49:
                attributes.append(.background(nil))
            case 90...97:
                attributes.append(.foreground(.bright(code - 90)))
            case 100...107:
                attributes.append(.background(.bright(code - 100)))
            default:
                break
            }

            i += 1
        }

        // If only one attribute, return it directly; otherwise we'd need a different approach
        // For simplicity, emit multiple setAttribute commands
        if attributes.count == 1 {
            return .setAttribute(attributes[0])
        }

        // Build a CellAttributes from the parsed SGR codes
        var cellAttrs = CellAttributes.default
        for attr in attributes {
            applySGRAttribute(attr, to: &cellAttrs)
        }
        return .setAttributes(cellAttrs)
    }

    /// Applies an SGR attribute to CellAttributes.
    private static func applySGRAttribute(_ sgr: SGRAttribute, to attrs: inout CellAttributes) {
        switch sgr {
        case .reset:
            attrs.reset()
        case .bold(let on):
            attrs.isBold = on
        case .dim(let on):
            attrs.isDim = on
        case .italic(let on):
            attrs.isItalic = on
        case .underline(let on):
            attrs.isUnderline = on
        case .blink:
            break  // Not implemented
        case .reverse(let on):
            attrs.isReverse = on
        case .hidden:
            break  // Not implemented
        case .strikethrough(let on):
            attrs.isStrikethrough = on
        case .foreground(let color):
            attrs.foregroundColor = color
        case .background(let color):
            attrs.backgroundColor = color
        }
    }

    /// Parses an OSC (Operating System Command) sequence: ESC]...
    private static func parseOSCSequence(_ text: String, from bracketIndex: String.Index) -> (TerminalCommand, Int)? {
        var currentIndex = text.index(after: bracketIndex)
        var content = ""

        // Read until BEL (\x07) or ST (ESC \)
        while currentIndex < text.endIndex {
            let c = text[currentIndex]
            if c == "\u{07}" {
                // BEL terminates the sequence
                let consumed = text.distance(from: text.index(bracketIndex, offsetBy: -1), to: currentIndex) + 1
                return (parseOSCContent(content), consumed)
            } else if c == "\u{1B}" {
                // Check for ST (ESC \)
                let nextIndex = text.index(after: currentIndex)
                if nextIndex < text.endIndex && text[nextIndex] == "\\" {
                    let consumed = text.distance(from: text.index(bracketIndex, offsetBy: -1), to: nextIndex) + 1
                    return (parseOSCContent(content), consumed)
                }
            }
            content.append(c)
            currentIndex = text.index(after: currentIndex)
        }

        return nil  // Incomplete sequence
    }

    /// Parses OSC content into a command.
    private static func parseOSCContent(_ content: String) -> TerminalCommand {
        // OSC 0 or 2: Set window title
        // Format: 0;title or 2;title
        if content.hasPrefix("0;") || content.hasPrefix("2;") {
            let title = String(content.dropFirst(2))
            return .setWindowTitle(title)
        }
        return .unknown("OSC: \(content)")
    }

    // MARK: - Private Parsing Helpers (Legacy)

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
