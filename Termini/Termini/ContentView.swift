//
//  ContentView.swift
//  Termini
//
//  Purpose: The main terminal view - displays output and handles input.
//
//  This is the "View" in MVVM. It should:
//  1. Display data from the ViewModel
//  2. Send user actions to the ViewModel
//  3. Contain minimal logic (just UI concerns)
//

import SwiftUI

struct ContentView: View {
    /// The ViewModel that manages terminal state.
    /// @StateObject means this view "owns" the ViewModel.
    @StateObject private var viewModel = TerminalViewModel()

    /// Controls focus for keyboard input.
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Terminal output area
            terminalOutputView

            // Input area at bottom
            inputView
        }
        .background(Color.black)
        .onAppear {
            viewModel.start()
            isInputFocused = true
        }
        .onDisappear {
            // Note: We do NOT stop the shell here.
            // The spec requires the shell to persist in the background.
        }
    }

    // MARK: - Subviews

    /// The scrollable terminal output display.
    private var terminalOutputView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Display the terminal output
                    // The .id(updateCounter) forces SwiftUI to recreate the Text view
                    // on every update, which is necessary for apps that rapidly clear
                    // and redraw the screen (like pomodoro timers, progress bars, etc.)
                    Text(viewModel.attributedOutput)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(viewModel.updateCounter)

                    // Invisible anchor for auto-scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(8)
            }
            .onChange(of: viewModel.attributedOutput) { _, _ in
                // Only auto-scroll when NOT in alternate screen mode.
                // TUI apps (vim, htop) manage their own display and shouldn't scroll.
                if !viewModel.isAlternateScreenActive {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .background(Color.black)
    }

    /// The command input field at the bottom.
    private var inputView: some View {
        HStack(spacing: 8) {
            // Prompt indicator
            Text(">")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.green)

            // Text input field
            TextField("", text: $viewModel.currentInput)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .focused($isInputFocused)
                .onSubmit {
                    viewModel.sendCommand()
                }
                .onKeyPress(.escape) {
                    // Send Ctrl+C on Escape
                    viewModel.sendControl("c")
                    viewModel.currentInput = ""
                    return .handled
                }
                .onKeyPress(characters: .init(charactersIn: "c"), phases: .down) { keyPress in
                    // Ctrl+C sends interrupt signal (SIGINT) to terminate running command
                    if keyPress.modifiers.contains(.control) {
                        viewModel.sendControl("c")
                        viewModel.currentInput = ""
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.upArrow) {
                    viewModel.send("\u{1B}[A")
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    viewModel.send("\u{1B}[B")
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    viewModel.send("\u{1B}[C")
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    viewModel.send("\u{1B}[D")
                    return .handled
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(white: 0.1))
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .frame(width: 600, height: 400)
}
