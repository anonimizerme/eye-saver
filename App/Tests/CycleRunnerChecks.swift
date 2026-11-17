import Foundation

@main
struct CycleRunnerChecks {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("helper")
        let record = directory.appendingPathComponent("calls")
        try "#!/bin/sh\n/usr/bin/sleep 0.3\nprintf x >> '\(record.path)'\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let runner = CycleRunner()
        async let first: Void = runner.run(helper)
        async let duplicate: Void = runner.run(helper)
        _ = try await (first, duplicate)
        precondition((try? String(contentsOf: record, encoding: .utf8)) == "x", "Overlapping clicks must be ignored")
        try await runner.run(helper)
        precondition((try? String(contentsOf: record, encoding: .utf8)) == "xx", "A later click must run")

        let failure = directory.appendingPathComponent("failure")
        try "#!/bin/sh\nexit 3\n".write(to: failure, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: failure.path)
        do {
            try await runner.run(failure)
            preconditionFailure("Nonzero exit must fail")
        } catch {
            precondition((error as NSError).code == 3)
        }
        try await runner.run(helper)
        precondition((try? String(contentsOf: record, encoding: .utf8)) == "xxx", "Failure must release the busy state")

        do {
            try await runner.run(directory.appendingPathComponent("missing-helper"))
            preconditionFailure("A missing executable must fail")
        } catch {
            precondition((error as NSError).domain == "EyeSaver")
            precondition(error.localizedDescription == "Unable to start the monitor helper.",
                         "Process-launch errors must remain in English")
        }
        try await runner.run(helper)
        precondition((try? String(contentsOf: record, encoding: .utf8)) == "xxxx",
                     "Process-launch failure must release the busy state")
        print("Cycle runner checks passed: duplicate suppression, later clicks, exit and launch failure recovery")
    }
}
