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
        // Check the monitor in the action so cached controls stay usable after reconnection.
        StaticControlConfiguration(kind: "local.eyesaver.next") {
            ControlWidgetButton(action: NextEyeSaverIntent()) {
                Label("Eye Saver", systemImage: "eye")
                    .accessibilityHint("Advance to the next Eye Saver mode.")
            }
        }
        .displayName("Eye Saver")
        .description("Advance the monitor's Eye Saver mode: Off → Low → High.")
    }
}
