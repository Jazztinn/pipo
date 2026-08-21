import AppKit
import PipoAppCore
import PipoUI
import Sparkle
import SwiftUI

@main
struct PipoApp: App {
    @NSApplicationDelegateAdaptor(PipoAppDelegate.self) private var appDelegate
    @State private var model = PipoModel.live()
    private let updater = PipoUpdater()

    var body: some Scene {
        MenuBarExtra("Pipo", systemImage: "flag.fill") {
            PipoRootView(
                model: model,
                configuration: PipoUIConfiguration(
                    model: model,
                    installUpdate: updater.isConfigured ? updater.checkForUpdates : nil
                )
            )
                .frame(width: 420, height: 620)
                .task {
                    await model.start()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            PipoSettingsView(model: model) {
                Task { @MainActor in
                    await model.signOut()
                }
            }
                .frame(width: 460, height: 420)
        }
    }
}

@MainActor
final class PipoUpdater {
    let isConfigured: Bool
    private let controller: SPUStandardUpdaterController

    init(bundle: Bundle = .main) {
        isConfigured = !(bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "").isEmpty
        controller = SPUStandardUpdaterController(
            startingUpdater: isConfigured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        controller.checkForUpdates(nil)
    }
}

final class PipoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
