import Foundation

@main
struct DDCKey {
    static func values(for args: [String]) -> [UInt16]? {
        if args == ["enable"] { return [0x0A01] }
        let keys: [String]
        if args.isEmpty || args == ["next"] {
            keys = ["5", "6", "5", "4", "5"]
        } else {
            keys = args == ["center"] ? ["5"] : args
        }
        let commands: [String: UInt16] = [
            "2": 0x2A02, "4": 0x2A04, "5": 0x2A05, "6": 0x2A06, "8": 0x2A08,
        ]
        let values = keys.compactMap { commands[$0] }
        guard !keys.isEmpty && values.count == keys.count else { return nil }
        return [0x0A01] + values
    }

    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("Eye Saver: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--self-test"] {
            precondition(values(for: ["enable"]) == [0x0A01])
            precondition(values(for: ["center"]) == [0x0A01, 0x2A05])
            precondition(values(for: ["5", "6"]) == [0x0A01, 0x2A05, 0x2A06])
            precondition(values(for: ["2"]) == [0x0A01, 0x2A02])
            let cycle: [UInt16] = [0x0A01, 0x2A05, 0x2A06, 0x2A05, 0x2A04, 0x2A05]
            precondition(values(for: []) == cycle && values(for: ["next"]) == cycle)
            precondition(values(for: ["0A"]) == nil && values(for: ["next", "2"]) == nil)
            precondition(values(for: ["5", "reset"]) == nil)
            print("Virtual-key command checks passed; no monitor access")
            return
        }
        guard args == ["--check"] || values(for: args) != nil else {
            throw error("Usage: ddc-key [--check|--self-test|next|center|enable|KEY...] (keys: 2 4 5 6 8)")
        }
        let availability = MonitorSupport.availability()
        guard availability.isAvailable else { throw MonitorSupport.error(availability) }
        let displays = AppleSiliconDDC.getIoregServicesForMatching()
        let monitors = displays.map {
            DDCMonitor(manufacturer: $0.manufacturerID, name: $0.productName,
                       hasExternalService: $0.location == "External" && $0.service != nil)
        }
        if args == ["--check"] {
            _ = try MonitorSupport.selectDDC(monitors)
            print("Samsung S27B80P is available. No DDC commands were sent.")
            return
        }
        // Keep the selected service for the whole sequence; never fall back to another display.
        try DDCSequence.send(values(for: args)!, monitors: monitors, write: { target, value in
            print(String(format: "Sending VCP E7=%04X once, without GET verification", value))
            fflush(stdout)
            return AppleSiliconDDC.write(service: displays[target].service, command: 0xE7, value: value,
                                        numOfWriteCycles: 1, numOfRetryAttemps: 0)
        }, pause: { usleep($0) })
        if args.isEmpty || args == ["next"] {
            // Let the closing click finish before a following invocation opens the menu again.
            usleep(700000)
        }
        print("I2C write accepted; confirm the monitor's response visually")
    }

    static func error(_ message: String) -> NSError {
        NSError(domain: "EyeSaverVirtualKey", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
