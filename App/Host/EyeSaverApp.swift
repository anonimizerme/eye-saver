import AppKit
import SwiftUI
import WidgetKit

@main
struct EyeSaverApp: App {
    var body: some Scene {
        Window("Eye Saver", id: "main") {
            EyeSaverView()
        }
        .windowResizability(.contentSize)
    }
}

private struct EyeSaverView: View {
    @State private var running = false
    @State private var availability = MonitorSupport.availability()
    @State private var message: String?

    private var status: String {
        availability.isAvailable ? (message ?? "Off → Low → High → Off") : availability.message
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "eye.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.teal)
                .accessibilityHidden(true)
            Text("Eye Saver").font(.largeTitle.bold())
            Text("Samsung S27B80P").foregroundStyle(.secondary)
            Button(running ? "Switching…" : "Next mode") {
                Task { @MainActor in
                    running = true
                    message = nil
                    defer {
                        running = false
                        availability = MonitorSupport.availability()
                    }
                    do {
                        _ = try await NextEyeSaverIntent().perform()
                        message = "Command sent."
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(running || !availability.isAvailable)
            Text(status).font(.callout).multilineTextAlignment(.center)
                .accessibilityLabel("Status: \(status)")
            Divider()
            Text("Add Eye Saver to Control Center using Edit Controls.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Close the monitor's menu before switching modes.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 350)
        .onAppear(perform: refreshAvailability)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refreshAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAvailability()
        }
    }

    private func refreshAvailability() {
        let current = MonitorSupport.availability()
        if current != availability {
            availability = current
            message = nil
        }
        ControlCenter.shared.reloadControls(ofKind: "local.eyesaver.next")
    }
}
