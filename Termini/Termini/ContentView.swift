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
                    // Display the parsed ANSI output
                    Text(viewModel.attributedOutput)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Invisible anchor for auto-scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(8)
            }
            .onChange(of: viewModel.attributedOutput) { _, _ in
                // Auto-scroll to bottom when new output arrives
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
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
