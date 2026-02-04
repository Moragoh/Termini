//
//  CellAttributes.swift
//  Termini
//
//  Shared between: Main App & Widget Extension
//  Purpose: Defines terminal cell styling attributes (colors, bold, italic, etc.)
//           that can be attached to each character in the terminal grid.
//

import SwiftUI

// MARK: - Terminal Color

/// Represents a terminal color in a serializable format.
/// SwiftUI.Color is not Codable, so we store color indices and convert when rendering.
enum TerminalColor: Equatable, Hashable {
    case standard(Int)      // 0-7: standard ANSI colors
    case bright(Int)        // 0-7: bright ANSI colors (maps to 8-15)
    case palette256(Int)    // 0-255: full 256-color palette
    case rgb(UInt8, UInt8, UInt8)  // True color (24-bit)
    case `default`          // Default terminal color

    /// Converts this terminal color to a SwiftUI Color for rendering.
    func toSwiftUIColor(isForeground: Bool = true) -> Color {
        switch self {
        case .standard(let index):
            return Self.standardColor(index)
        case .bright(let index):
            return Self.brightColor(index)
        case .palette256(let index):
            return Self.color256(index)
        case .rgb(let r, let g, let b):
            return Color(
                red: Double(r) / 255.0,
                green: Double(g) / 255.0,
                blue: Double(b) / 255.0
            )
        case .default:
            return isForeground ? .white : .clear
        }
    }

    // MARK: - Color Definitions (matching ANSIParser)

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

// MARK: - Cell Attributes

/// Styling attributes for a single terminal cell.
/// Each cell in the terminal grid has its own set of attributes.
struct CellAttributes: Equatable, Hashable {
    var foregroundColor: TerminalColor?
    var backgroundColor: TerminalColor?
    var isBold: Bool = false
    var isDim: Bool = false
    var isItalic: Bool = false
    var isUnderline: Bool = false
    var isStrikethrough: Bool = false
    var isReverse: Bool = false  // Swap foreground/background

    /// Default attributes (no styling).
    static let `default` = CellAttributes()

    /// Resets all attributes to default.
    mutating func reset() {
        foregroundColor = nil
        backgroundColor = nil
        isBold = false
        isDim = false
        isItalic = false
        isUnderline = false
        isStrikethrough = false
        isReverse = false
    }

    /// Applies these attributes to an AttributedString.
    func apply(to string: inout AttributedString) {
        // Handle reverse video (swap foreground/background)
        let effectiveFg = isReverse ? backgroundColor : foregroundColor
        let effectiveBg = isReverse ? foregroundColor : backgroundColor

        // Foreground color - default to white for visibility on black background
        if let fg = effectiveFg {
            var color = fg.toSwiftUIColor(isForeground: true)
            if isDim {
                color = color.opacity(0.5)
            }
            string.foregroundColor = color
        } else {
            // No color specified - use white (or dimmed white)
            string.foregroundColor = isDim ? Color.white.opacity(0.5) : Color.white
        }

        // Background color
        if let bg = effectiveBg {
            string.backgroundColor = bg.toSwiftUIColor(isForeground: false)
        }

        // Font weight
        if isBold {
            string.font = .system(.body, design: .monospaced, weight: .bold)
        } else {
            string.font = .system(.body, design: .monospaced)
        }

        // Italic
        if isItalic {
            string.font = (string.font ?? .system(.body, design: .monospaced)).italic()
        }

        // Underline
        if isUnderline {
            string.underlineStyle = .single
        }

        // Strikethrough
        if isStrikethrough {
            string.strikethroughStyle = .single
        }
    }
}
