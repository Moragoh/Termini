//
//  PTYManager.swift
//  Termini
//
//  Purpose: Manages a pseudo-terminal (PTY) session running Zsh.
//
//  What is a PTY?
//  A pseudo-terminal tricks a shell into thinking it's running in a real terminal.
//  This is necessary because:
//  1. Interactive programs (vim, htop) check if they're in a terminal
//  2. Color output (ANSI codes) only works in terminal mode
//  3. Line editing (arrow keys, history) requires terminal mode
//
//  Without PTY: `ls` works, but `htop` fails and colors don't show.
//  With PTY: Everything works like a real Terminal.app
//

import Foundation
import Darwin

/// Manages a PTY session with a running shell.
///
/// Architecture:
/// - Uses forkpty() to create PTY and fork in one call
/// - The child process runs /bin/zsh
/// - Parent reads output from master file descriptor
/// - Parent writes input to master file descriptor
///
/// Why a class?
/// - Manages system resources (file descriptors, child process)
/// - Needs cleanup on deallocation (deinit)
/// - Reference semantics match the "one shell session" concept
final class PTYManager {

    // MARK: - Properties

    /// File descriptor for the master side of the PTY.
    /// We read shell output from here and write user input to here.
    private var masterFD: Int32 = -1

    /// Process ID of the child shell process.
    private var childPID: pid_t = -1

    /// Background queue for reading shell output.
    /// We don't want to block the main thread while waiting for output.
    private let readQueue = DispatchQueue(label: "com.termini.pty.read", qos: .userInitiated)

    /// Called whenever new output is received from the shell.
    /// The String contains raw output including ANSI escape codes.
    var onOutput: ((String) -> Void)?

    /// Called when the shell process terminates.
    var onProcessExit: (() -> Void)?

    /// Whether the PTY session is currently active.
    var isRunning: Bool {
        childPID > 0
    }

    // MARK: - Lifecycle

    deinit {
        stop()
    }

    // MARK: - Public API

    /// Starts a new shell session.
    /// This creates the PTY, forks a child process, and begins reading output.
    ///
    /// - Throws: PTYError if the PTY cannot be created.
    func start() throws {
        guard !isRunning else {
            print("PTYManager: Already running")
            return
        }

        // Set up terminal size
        var winSize = winsize()
        winSize.ws_col = 80
        winSize.ws_row = 24
        winSize.ws_xpixel = 0
        winSize.ws_ypixel = 0

        // forkpty() creates the PTY pair, forks, and sets up the child's
        // stdin/stdout/stderr to use the slave PTY - all in one call.
        // It returns:
        //   - In parent: child's PID, masterFD is set to master PTY
        //   - In child: returns 0, child is attached to slave PTY
        childPID = forkpty(&masterFD, nil, nil, &winSize)

        if childPID == -1 {
            throw PTYError.failedToFork
        }

        if childPID == 0 {
            // === CHILD PROCESS ===
            // This code runs in the forked child

            // Set up environment for proper terminal behavior
            setenv("TERM", "xterm-256color", 1)
            setenv("LANG", "en_US.UTF-8", 1)
            setenv("LC_ALL", "en_US.UTF-8", 1)

            // Execute the shell using execv (avoids nil type issues with execl)
            let shell = "/bin/zsh"

            // Build null-terminated argument array for execv
            let arg0 = strdup(shell)
            let arg1 = strdup("--login")
            var args: [UnsafeMutablePointer<CChar>?] = [arg0, arg1, nil]

            execv(shell, &args)

            // If execv returns, it failed - exit child
            _exit(1)
        }

        // === PARENT PROCESS ===
        // Start reading output from the shell
        startReadingOutput()

        print("PTYManager: Started shell with PID \(childPID)")
    }

    /// Stops the shell session and cleans up resources.
    func stop() {
        guard isRunning else { return }

        // Send SIGHUP to terminate the shell gracefully
        kill(childPID, SIGHUP)

        // Wait for child to exit (prevents zombie process)
        var status: Int32 = 0
        waitpid(childPID, &status, 0)

        // Close the master file descriptor
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }

        childPID = -1
        print("PTYManager: Stopped")
    }

    /// Sends input to the shell (e.g., a command typed by the user).
    ///
    /// - Parameter text: The text to send (usually ends with \n for Enter).
    func send(_ text: String) {
        guard isRunning, masterFD >= 0 else { return }

        text.withCString { ptr in
            write(masterFD, ptr, strlen(ptr))
        }
    }

    /// Sends a single byte to the shell (for control characters).
    ///
    /// - Parameter byte: The byte to send (e.g., 3 for Ctrl+C).
    func sendByte(_ byte: UInt8) {
        guard isRunning, masterFD >= 0 else { return }

        var b = byte
        write(masterFD, &b, 1)
    }

    /// Resizes the PTY window.
    /// Call this when the terminal view changes size.
    ///
    /// - Parameters:
    ///   - columns: Number of character columns.
    ///   - rows: Number of character rows.
    func resize(columns: Int, rows: Int) {
        guard masterFD >= 0 else { return }

        var winSize = winsize()
        winSize.ws_col = UInt16(columns)
        winSize.ws_row = UInt16(rows)
        winSize.ws_xpixel = 0
        winSize.ws_ypixel = 0

        _ = ioctl(masterFD, TIOCSWINSZ, &winSize)

        // Notify the shell of the size change
        if childPID > 0 {
            kill(childPID, SIGWINCH)
        }
    }

    // MARK: - Private Methods

    /// Continuously reads output from the shell on a background queue.
    private func startReadingOutput() {
        readQueue.async { [weak self] in
            guard let self = self else { return }

            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)

            while self.masterFD >= 0 && self.childPID > 0 {
                let bytesRead = read(self.masterFD, &buffer, bufferSize)

                if bytesRead > 0 {
                    // Convert bytes to string and notify
                    let data = Data(buffer[0..<bytesRead])
                    if let text = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.onOutput?(text)
                        }
                    }
                } else if bytesRead == 0 {
                    // EOF - shell closed
                    DispatchQueue.main.async {
                        self.onProcessExit?()
                    }
                    break
                } else if bytesRead < 0 && errno != EINTR {
                    // Error (but not an interrupt)
                    break
                }
            }
        }
    }
}

// MARK: - Errors

/// Errors that can occur when managing the PTY.
enum PTYError: LocalizedError {
    case failedToFork

    var errorDescription: String? {
        switch self {
        case .failedToFork:
            return "Failed to create pseudo-terminal and fork process"
        }
    }
}
