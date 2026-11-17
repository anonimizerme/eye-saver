import Foundation

actor CycleRunner {
    static let shared = CycleRunner()
    private var running = false

    func run(_ executable: URL) async throws {
        guard !running else { return }
        running = true
        defer { running = false }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.standardOutput = output
            process.standardError = output
            process.terminationHandler = { completed in
                let details = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if completed.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    NSLog("EyeSaver helper failed: %@", details)
                    continuation.resume(throwing: NSError(domain: "EyeSaver", code: Int(completed.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "Unable to switch modes. Check the Samsung monitor's connection."]))
                }
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                NSLog("EyeSaver helper could not start: %@", error.localizedDescription)
                continuation.resume(throwing: NSError(domain: "EyeSaver", code: (error as NSError).code,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to start the monitor helper."]))
            }
        }
    }
}
