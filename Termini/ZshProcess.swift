//
//  ZshProcess.swift
//  Termini
//
//  Created by Jun Min Kim on 12/27/24.
//

import Foundation // Includes APIs for handling processes and pipe

func runZshCommand() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh") // Sets target for the process as the default zsh shell on macOS
    process.arguments = ["-c", "echo hello"] // Similar to how execv is used in C++ to pass in arguments to process
    
    let pipe = Pipe() // Buffer between the zsh process and the Termini app
    process.standardOutput = pipe
    
    do {
        try process.run() // Start process
    } catch {
        print("Error starting zsh process: \(error)")
    }
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile() // Reads data from the pipe (which is the process output since we redirected stdout of process to pipe
    if let output = String(data:data, encoding: .utf8) { //  Converts data object to String and prints it out
        print("\(output)")
    }
}

runZshCommand()
