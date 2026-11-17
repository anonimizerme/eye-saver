import AppIntents
import Foundation
import WidgetKit

struct NextEyeSaverIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Eye Saver mode"
    static let description = IntentDescription("Cycle the Samsung monitor's Eye Saver mode: Off, Low, High.")
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult {
        defer { ControlCenter.shared.reloadControls(ofKind: "local.eyesaver.next") }
        guard let helper = Bundle.main.url(forAuxiliaryExecutable: "ddc-key") else {
            throw NSError(domain: "EyeSaver", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The monitor helper is missing from the app."])
        }
        let availability = MonitorSupport.availability()
        guard availability.isAvailable else {
            throw NSError(domain: "EyeSaver", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: availability.message])
        }
        try await CycleRunner.shared.run(helper)
        return .result()
    }
}
