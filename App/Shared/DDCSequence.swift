import Foundation

enum DDCSequence {
    static func send(_ values: [UInt16], monitors: [DDCMonitor],
                     write: (Int, UInt16) -> Bool, pause: (UInt32) -> Void) throws {
        let target = try MonitorSupport.selectDDC(monitors)
        for (index, value) in values.enumerated() {
            if index > 0 { pause(300_000) }
            guard write(target, value) else {
                throw NSError(domain: "EyeSaver.DDC", code: 1,
                              userInfo: [NSLocalizedDescriptionKey:
                                "DDC write failed. The sequence stopped without retrying. Check the monitor connection."])
            }
        }
    }
}
