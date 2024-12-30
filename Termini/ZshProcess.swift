//
//  ZshProcess.swift
//  Termini
//
//  Created by Jun Min Kim on 12/27/24.
//

import Foundation // Includes APIs for handling processes and pipe

func runZshCommand(_ userCommand: String) {
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh") // Sets target for the process as the default zsh shell on macOS
//    process.arguments = ["-c", "top -n 30"]
    process.arguments = ["-c", userCommand]
    // Temp file that the latest output of termini will go to
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("termini_output.txt")
    let pipe = Pipe() // Buffer between the zsh process and the Termini app
    process.standardOutput = pipe // Redirect process output to file
    process.standardError = pipe
   
    do {
        try process.run() // Start process
        
        // Asynchronously read from the pipe that zsh process writes to
        DispatchQueue.global().async { // DispatchQueue is a thread pool abstraction that the system manages
            let handle = pipe.fileHandleForReading
            while process.isRunning {
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8) {
                    do {
                        try output.write(to: fileURL, atomically: true, encoding: .utf8)
                    } catch {
                        print("Failed to write to temp file: \(error)")
                    }
                }
                Thread.sleep(forTimeInterval:1) // Blocks the thread from DispatchQueue
            }
        }
    } catch {
        print("Error starting zsh process: \(error)")
    }
}
