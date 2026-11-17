import CoreGraphics
import Foundation

enum MonitorAvailability: Equatable {
    case available, notConnected, ambiguous, unreadable, missingDDCService, unsupportedPlatform

    var isAvailable: Bool { self == .available }

    var message: String {
        switch self {
        case .available: return "Samsung S27B80P is connected."
        case .notConnected: return "Connect a Samsung S27B80P to use Eye Saver."
        case .ambiguous: return "More than one Samsung S27B80P is connected. Connect only one."
        case .unreadable: return "Unable to read the connected displays."
        case .missingDDCService: return "Samsung S27B80P has no external DDC service. Check the connection."
        case .unsupportedPlatform: return "Eye Saver requires an Apple Silicon Mac."
        }
    }
}

struct DisplayIdentity {
    let vendor: UInt32
    let model: UInt32
    let isBuiltin: Bool
}

struct DDCMonitor {
    let manufacturer: String
    let name: String
    let hasExternalService: Bool
}

enum MonitorSupport {
    // Verified against the EDID exposed by the supported S27B80P.
    static let vendor: UInt32 = 0x4C2D
    static let model: UInt32 = 0x71F7

    static func availability() -> MonitorAvailability {
        #if !arch(arm64)
        return .unsupportedPlatform
        #else
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return .unreadable }
        if count == 0 { return .notConnected }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return .unreadable }
        return availability(displays: displays.prefix(Int(count)).map {
            DisplayIdentity(vendor: CGDisplayVendorNumber($0), model: CGDisplayModelNumber($0),
                            isBuiltin: CGDisplayIsBuiltin($0) != 0)
        })
        #endif
    }

    static func availability(displays: [DisplayIdentity]) -> MonitorAvailability {
        let matches = displays.filter { !$0.isBuiltin && $0.vendor == vendor && $0.model == model }
        switch matches.count {
        case 0: return .notConnected
        case 1: return .available
        default: return .ambiguous
        }
    }

    static func selectDDC(_ monitors: [DDCMonitor]) throws -> Int {
        let matches = monitors.indices.filter {
            monitors[$0].manufacturer == "SAM" && monitors[$0].name == "S27B80P"
        }
        guard !matches.isEmpty else { throw error(.notConnected) }
        guard matches.count == 1 else { throw error(.ambiguous) }
        let index = matches[0]
        guard monitors[index].hasExternalService else { throw error(.missingDDCService) }
        return index
    }

    static func error(_ availability: MonitorAvailability) -> NSError {
        NSError(domain: "EyeSaver.MonitorSupport", code: 1,
                userInfo: [NSLocalizedDescriptionKey: availability.message])
    }
}
