//
//  ZshProcess.swift
//  Termini
//
//  Created by Jun Min Kim on 12/27/24.
//

import Foundation // Includes APIs for handling processes and pipe

func writeProcessOutput(process: Process, pipe: Pipe, fileURL: URL) {
    DispatchQueue.global().async {
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
}

func runZshCommand(_ userCommand: String) {
    let process = Process()
    
    // Fetch the system's environment variables (including PATH)
    // This lets Termini use any commnads users have installed
    var environment = ProcessInfo.processInfo.environment
   
    // Add common macOS paths to PATH
    if var systemPath = environment["PATH"] {
        // Append some common directories for macOS
        systemPath += ":/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:/opt/bin"
        environment["PATH"] = systemPath
    }
    // Set the process's environment to the system environment (including PATH)
    process.environment = environment
    
    process.executableURL = URL(fileURLWithPath: "/bin/zsh") // Sets target for the process as the default zsh shell on macOS
    process.arguments = ["-c", "\(userCommand)"] // By default, termini will try and run with -n arg to make it fit in pipe
    
    // Temp file that the latest output of termini will go to
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("termini_output.txt")
    let pipe = Pipe() // Buffer between the zsh process and the Termini app
    process.standardOutput = pipe // Redirect process output to file
    process.standardError = pipe
   
    do {
        try process.run() // Try running it with the -n 30 argument
        writeProcessOutput(process: process, pipe: pipe, fileURL:fileURL)

        // STUFF FOR AUTOMATIC -n flag handling later
//        // Check if the process is still running
//        let isRunning = process.isRunning
//        // If the process finishes immediately, check its termination status
//        process.waitUntilExit()
//        if process.terminationStatus != 0 {
//            // Means command will not run with -n flag, so run it normally
//            process.arguments = ["-c", "\(userCommand)"] // Run the command without flags
//            do {
//                try process.run() // Start process again without flags
//                writeProcessOutput(process: process, pipe: pipe, fileURL:fileURL)
//            } catch {
//                print("Error starting zsh process without flags: \(error)")
//            }
//        }
                
    } catch {
        print("Error running zsh process: \(error)")
    }
}
