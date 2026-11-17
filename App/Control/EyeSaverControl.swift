import AppIntents
import Foundation
import SwiftUI
import WidgetKit

@main
struct EyeSaverControls: WidgetBundle {
    var body: some Widget {
        EyeSaverControl()
    }
}

struct EyeSaverControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "local.eyesaver.next", provider: MonitorAvailabilityProvider()) { availability in
            ControlWidgetButton(action: NextEyeSaverIntent()) {
                Label("Eye Saver", systemImage: "eye")
                    .accessibilityHint(availability.isAvailable ? "Advance to the next Eye Saver mode." : availability.message)
            }
            .disabled(!availability.isAvailable)
        }
        .displayName("Eye Saver")
        .description("Advance the monitor's Eye Saver mode: Off → Low → High.")
    }
}

private struct MonitorAvailabilityProvider: ControlValueProvider {
    var previewValue: MonitorAvailability { .available }

    func currentValue() async throws -> MonitorAvailability {
        let availability = MonitorSupport.availability()
        NSLog("EyeSaver control availability: %@", availability.message)
        return availability
    }
}
