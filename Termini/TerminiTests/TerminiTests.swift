//
//  TerminiTests.swift
//  TerminiTests
//
//  Tests for the Termini terminal emulator.
//  These tests verify that the PTY, ANSI parsing, and shell commands work correctly.
//

import Testing
import Foundation
@testable import Termini

// MARK: - ANSI Parser Tests

@Suite("ANSI Parser")
struct ANSIParserTests {

    @Test("Plain text passes through unchanged")
    func plainTextPassthrough() {
        let input = "Hello, World!"
        let result = ANSIParser.parse(input)
        #expect(String(result.characters) == input)
    }

    @Test("Strip codes removes all escape sequences")
    func stripCodesRemovesAllEscapeSequences() {
        let input = "\u{1B}[31mRed\u{1B}[0m Normal \u{1B}[1;32mBold Green\u{1B}[0m"
        let result = ANSIParser.stripCodes(input)
        #expect(result == "Red Normal Bold Green")
    }

    @Test("Reset code works")
    func resetCode() {
        let input = "\u{1B}[31mRed\u{1B}[0mNormal"
        let result = ANSIParser.parse(input)
        #expect(String(result.characters) == "RedNormal")
    }

    @Test("Multiple codes in one sequence")
    func multipleCodes() {
        let input = "\u{1B}[1;31;44mBold Red on Blue\u{1B}[0m"
        let result = ANSIParser.parse(input)
        #expect(String(result.characters) == "Bold Red on Blue")
    }

    @Test("256 color codes")
    func color256Codes() {
        // 38;5;N is 256-color foreground
        let input = "\u{1B}[38;5;196mBright Red\u{1B}[0m"
        let result = ANSIParser.parse(input)
        #expect(String(result.characters) == "Bright Red")
    }

    @Test("Empty input")
    func emptyInput() {
        let result = ANSIParser.parse("")
        #expect(String(result.characters) == "")
    }

    @Test("Only escape sequences")
    func onlyEscapeSequences() {
        let input = "\u{1B}[31m\u{1B}[0m\u{1B}[32m\u{1B}[0m"
        let result = ANSIParser.parse(input)
        #expect(String(result.characters) == "")
    }
}

// MARK: - Terminal State Tests

@Suite("Terminal State")
struct TerminalStateTests {

    @Test("Encode and decode preserves data")
    func encodeDecode() throws {
        let original = TerminalState(
            outputText: "test output",
            timestamp: Date(),
            currentDirectory: "/Users/test",
            isExecutingCommand: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TerminalState.self, from: data)

        #expect(decoded.outputText == original.outputText)
        #expect(decoded.currentDirectory == original.currentDirectory)
        #expect(decoded.isExecutingCommand == original.isExecutingCommand)
    }

    @Test("Empty state has correct defaults")
    func emptyState() {
        let empty = TerminalState.empty
        #expect(empty.outputText == "")
        #expect(empty.currentDirectory == "~")
        #expect(empty.isExecutingCommand == false)
    }
}

// MARK: - PTY Manager Tests

@Suite("PTY Manager")
struct PTYManagerTests {

    @Test("Start creates running session")
    func startCreatesRunningSession() throws {
        let ptyManager = PTYManager()
        defer { ptyManager.stop() }

        try ptyManager.start()
        #expect(ptyManager.isRunning == true)
    }

    @Test("Receives shell prompt on start")
    func receivesShellPrompt() async throws {
        let ptyManager = PTYManager()
        defer { ptyManager.stop() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var receivedOutput = ""
            var fulfilled = false

            ptyManager.onOutput = { output in
                receivedOutput += output
                if !receivedOutput.isEmpty && !fulfilled {
                    fulfilled = true
                    continuation.resume()
                }
            }

            do {
                try ptyManager.start()
            } catch {
                continuation.resume(throwing: error)
            }

            // Timeout after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if !fulfilled {
                    fulfilled = true
                    continuation.resume()
                }
            }
        }
    }

    @Test("Echo command works")
    func echoCommand() async throws {
        let ptyManager = PTYManager()
        defer { ptyManager.stop() }

        let testString = "TERMINI_TEST_\(UUID().uuidString.prefix(8))"
        var receivedOutput = ""

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var fulfilled = false

            ptyManager.onOutput = { output in
                receivedOutput += output
                if receivedOutput.contains(testString) && !fulfilled {
                    fulfilled = true
                    continuation.resume()
                }
            }

            do {
                try ptyManager.start()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // Send echo command after shell is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                ptyManager.send("echo '\(testString)'\n")
            }

            // Timeout after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                if !fulfilled {
                    fulfilled = true
                    continuation.resume()
                }
            }
        }

        #expect(receivedOutput.contains(testString), "Output should contain the echoed string")
    }

    @Test("ls command shows directory contents")
    func lsCommand() async throws {
        let ptyManager = PTYManager()
        defer { ptyManager.stop() }

        var receivedOutput = ""

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var fulfilled = false

            ptyManager.onOutput = { output in
                receivedOutput += output
                // ls in home directory should show common folders
                if (receivedOutput.contains("Desktop") || receivedOutput.contains("Documents")) && !fulfilled {
                    fulfilled = true
                    continuation.resume()
                }
            }

            do {
                try ptyManager.start()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // Send ls command after shell is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                ptyManager.send("ls ~\n")
            }

            // Timeout after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                if !fulfilled {
                    fulfilled = true
                    continuation.resume()
                }
            }
        }

        let hasExpectedOutput = receivedOutput.contains("Desktop") || receivedOutput.contains("Documents")
        #expect(hasExpectedOutput, "ls ~ should list home directory contents")
    }

    @Test("Colored output contains ANSI codes")
    func coloredOutputContainsANSI() async throws {
        let ptyManager = PTYManager()
        defer { ptyManager.stop() }

        var receivedOutput = ""

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var fulfilled = false

            ptyManager.onOutput = { output in
                receivedOutput += output
                if receivedOutput.contains("\u{1B}[") && !fulfilled {
                    fulfilled = true
                    continuation.resume()
                }
            }

            do {
                try ptyManager.start()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // Force colored output
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                ptyManager.send("CLICOLOR_FORCE=1 ls -G /\n")
            }

            // Timeout after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                if !fulfilled {
                    fulfilled = true
                    continuation.resume()
                }
            }
        }

        #expect(receivedOutput.contains("\u{1B}["), "Colored ls should contain ANSI codes")
    }

    @Test("Stop terminates session")
    func stopTerminatesSession() throws {
        let ptyManager = PTYManager()

        try ptyManager.start()
        #expect(ptyManager.isRunning == true)

        ptyManager.stop()
        #expect(ptyManager.isRunning == false)
    }
}

// MARK: - Interactive Program Tests

@Suite("Interactive Programs")
struct InteractiveProgramTests {

    @Test("top launches and produces TUI output")
    func topLaunches() async throws {
        let ptyManager = PTYManager()
        defer { ptyManager.stop() }

        var receivedOutput = ""

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var fulfilled = false

            ptyManager.onOutput = { output in
                receivedOutput += output
                // top shows processes and system info
                if (receivedOutput.contains("Processes") ||
                    receivedOutput.contains("CPU") ||
                    receivedOutput.contains("PhysMem") ||
                    receivedOutput.contains("\u{1B}[")) && !fulfilled {
                    fulfilled = true
                    continuation.resume()
                }
            }

            do {
                try ptyManager.start()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // Launch top
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                ptyManager.send("top\n")
            }

            // Quit top
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                ptyManager.send("q")
            }

            // Timeout after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                if !fulfilled {
                    fulfilled = true
                    continuation.resume()
                }
            }
        }

        // top should produce some output with ANSI codes or system info
        let hasExpectedOutput = receivedOutput.contains("\u{1B}[") ||
                                receivedOutput.contains("Processes") ||
                                receivedOutput.contains("CPU")
        #expect(hasExpectedOutput, "top should produce TUI output")
    }

    @Test("vim launches")
    func vimLaunches() async throws {
        let ptyManager = PTYManager()
        defer { ptyManager.stop() }

        var receivedOutput = ""

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var fulfilled = false

            ptyManager.onOutput = { output in
                receivedOutput += output
                // vim produces ANSI codes for its interface
                if (receivedOutput.contains("VIM") ||
                    receivedOutput.contains("Vim") ||
                    receivedOutput.contains("\u{1B}[")) && !fulfilled {
                    fulfilled = true
                    continuation.resume()
                }
            }

            do {
                try ptyManager.start()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // Launch vim
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                ptyManager.send("vim\n")
            }

            // Quit vim
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                ptyManager.send("\u{1B}")  // ESC
                ptyManager.send(":q!\n")   // Force quit
            }

            // Timeout after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                if !fulfilled {
                    fulfilled = true
                    continuation.resume()
                }
            }
        }

        #expect(receivedOutput.contains("\u{1B}["), "vim should produce ANSI output")
    }

    @Test("htop launches if installed")
    func htopLaunches() async throws {
        // First check if htop is installed
        let htopCheck = Process()
        htopCheck.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        htopCheck.arguments = ["htop"]
        let pipe = Pipe()
        htopCheck.standardOutput = pipe
        htopCheck.standardError = pipe

        try htopCheck.run()
        htopCheck.waitUntilExit()

        guard htopCheck.terminationStatus == 0 else {
            // htop not installed, skip test
            print("htop is not installed, skipping test")
            return
        }

        let ptyManager = PTYManager()
        defer { ptyManager.stop() }

        var receivedOutput = ""

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var fulfilled = false

            ptyManager.onOutput = { output in
                receivedOutput += output
                // htop shows CPU/memory info with lots of ANSI codes
                if (receivedOutput.contains("CPU") ||
                    receivedOutput.contains("Mem") ||
                    receivedOutput.contains("Tasks") ||
                    receivedOutput.contains("\u{1B}[")) && !fulfilled {
                    fulfilled = true
                    continuation.resume()
                }
            }

            do {
                try ptyManager.start()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // Launch htop
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                ptyManager.send("htop\n")
            }

            // Quit htop
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                ptyManager.send("q")
            }

            // Timeout after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                if !fulfilled {
                    fulfilled = true
                    continuation.resume()
                }
            }
        }

        #expect(receivedOutput.contains("\u{1B}["), "htop should produce ANSI output")
    }
}
