import Foundation

@main
struct MonitorSupportChecks {
    static func main() throws {
        let supported = DisplayIdentity(vendor: 0x4C2D, model: 0x71F7, isBuiltin: false)
        precondition(MonitorSupport.availability(displays: []) == .notConnected)
        precondition(MonitorSupport.availability(displays: [supported]) == .available)
        precondition(MonitorSupport.availability(displays: [supported, supported]) == .ambiguous)
        for display in [DisplayIdentity(vendor: 0x4C2D, model: 1, isBuiltin: false),
                        DisplayIdentity(vendor: 1, model: 0x71F7, isBuiltin: false),
                        DisplayIdentity(vendor: 0x4C2D, model: 0x71F7, isBuiltin: true)] {
            precondition(MonitorSupport.availability(displays: [display]) == .notConnected)
        }

        let target = DDCMonitor(manufacturer: "SAM", name: "S27B80P", hasExternalService: true)
        let wrongSamsung = DDCMonitor(manufacturer: "SAM", name: "Other Samsung", hasExternalService: true)
        let wrongVendor = DDCMonitor(manufacturer: "DEL", name: "S27B80P", hasExternalService: true)
        let noService = DDCMonitor(manufacturer: "SAM", name: "S27B80P", hasExternalService: false)
        let values: [UInt16] = [0x0A01, 0x2A05, 0x2A06, 0x2A05, 0x2A04, 0x2A05]
        for monitors in [[], [wrongSamsung], [wrongVendor], [noService], [target, target], [target, noService]] {
            var writes = 0
            do {
                try DDCSequence.send(values, monitors: monitors, write: { _, _ in writes += 1; return true }, pause: { _ in })
                preconditionFailure("Unsupported or ambiguous monitors must be rejected")
            } catch {
                precondition(writes == 0, "Rejected configurations must never receive a DDC write")
            }
        }
        // An earlier UI check cannot authorize a later sequence after unplugging.
        precondition(MonitorSupport.availability(displays: [supported]).isAvailable)
        var writesAfterUnplug = 0
        do {
            try DDCSequence.send(values, monitors: [], write: { _, _ in writesAfterUnplug += 1; return true }, pause: { _ in })
            preconditionFailure("Disconnected monitor must fail final validation")
        } catch { precondition(writesAfterUnplug == 0) }

        var written: [UInt16] = []
        var pauses: [UInt32] = []
        try DDCSequence.send(values, monitors: [wrongVendor, target], write: { index, value in
            precondition(index == 1, "Only the selected monitor may receive writes")
            written.append(value)
            return true
        }, pause: { pauses.append($0) })
        precondition(written == values && pauses == Array(repeating: 300_000, count: 5))
        // Serial numbers are intentionally absent from the model-based selector.
        let selected = try MonitorSupport.selectDDC([target])
        precondition(selected == 0)
        var attempts = 0
        do {
            try DDCSequence.send(values, monitors: [target], write: { index, _ in
                precondition(index == 0)
                attempts += 1
                return attempts < 3
            }, pause: { _ in })
            preconditionFailure("A failed write must stop the sequence")
        } catch { precondition(attempts == 3, "Never retry or redirect after disconnect") }
        print("Monitor checks passed: model selection, ambiguity, no writes on rejection, disconnect and timing")
    }
}
