import SwiftUI

struct ContentView: View {
    @State private var terminalOutput = "> " // @State makes it so view refreshes when this gets updated
    @State private var userCommand = ""  // User input for the command
    
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("termini_output.txt")
    
    var body: some View {
        VStack(spacing: 0) { // Spacing 0 makes it so that there is no space between the terminal and the search bar
            // Command input bar
            TextField("Enter command...", text: $userCommand, onCommit: {
                if !userCommand.isEmpty {
                    runZshCommand(userCommand)
                    
                    // Clear the text field after pressing Enter
                    DispatchQueue.main.async {
                        userCommand = ""  // Ensure it's done on the main thread
                    }
                }
            })
            .font(.system(.body, design: .monospaced)) // Match terminal font
            .foregroundColor(.green)                  // Match terminal text color
            .background(Color.black)                  // Match terminal background color
            .textFieldStyle(PlainTextFieldStyle()) // Removes gray border/shawoding
            .padding(7)                               // Add some internal padding
            .cornerRadius(3)                        // No rounding for a terminal-like look

            TextEditor(text: $terminalOutput)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.green)
                .background(Color.black)
                .frame(minHeight: 200)
                .lineLimit(nil)
                .disabled(true) // Prevents editing
        }
        .onAppear {
//            runZshCommand()
            startUpdating()
        }
    }
    
    func startUpdating() {
        // Starts thread with .background priority (lowest
        DispatchQueue.global(qos: .background).async {
            var lastContent = ""
            
            while true{
                do {
                    let currentContent = try String(contentsOf: fileURL, encoding: .utf8)
                    
                    // If the content has changed, update the UI
                    if currentContent != lastContent {
                        lastContent = currentContent
                        DispatchQueue.main.async {
                            self.terminalOutput = currentContent
                        }
                    }
                } catch {
                    // Handle any errors in reading the file
                    print("Error reading file: \(error)")
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
        
        
        //        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {_ in // _ is a placeholder for the Timer object since this func doesn't need that directly
        //            do {
        //                let output = try String(contentsOf: fileURL, encoding: .utf8)
        //
        //                // SwiftUI makes you update UI on main thread only to ensure thread safety, avoid race conditions, etc.
        //                DispatchQueue.main.async {
        //                    print("updated output")
        //                    self.terminalOutput = output
        //                }
        //            } catch {
        //                DispatchQueue.main.async {
        //                    self.terminalOutput = "Failed to read output: \(error)"
        //                }
        //            }
        //        }
        //    }
    }
    
    
    
    struct ContentView_Previews: PreviewProvider {
        static var previews: some View {
            ContentView()
        }
    }
    
}
